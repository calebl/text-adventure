//! THE RUST ENGINE AS A RUBY EXTENSION, and nothing more than the crossing.
//!
//! `Playthrough::RustEngine` (app/models/playthrough/rust_engine.rb) is the
//! only caller. It hands over a whole turn -- the database file, the game, the
//! line, its request token, where model calls go, and a block for prose -- and
//! gets back one JSON document: what the turn left, or the error it ended in.
//! Every rule, every write and every model call is the engine's
//! (`renderedstep_engine::engine::Engine`); every decision about what the
//! player is told, and whether the Ruby engine plays the line instead, is
//! Ruby's. This file only carries values across.
//!
//! THREE THINGS NEVER CROSS:
//!
//! - A PANIC. The engine catches its own (`Error::Panicked`), and every entry
//!   point here runs inside `catch_unwind` as well, so a bug in this file is
//!   an error document too. A Rust panic that reached Ruby would arrive as a
//!   `fatal`, which nothing can rescue.
//! - A RUBY EXCEPTION THROUGH RUST FRAMES. The prose block is called through
//!   magnus, which protects the call; an exception it raises is kept, no more
//!   prose is delivered, and it is raised again once the engine has returned.
//! - A CREDENTIAL. A key arrives inside the models document and becomes a
//!   `model::Secret` at once, which has no `Display` and a redacted `Debug`;
//!   no error document quotes the request.
//!
//! THE TURN RUNS WITHOUT THE GVL. A turn waits on model calls for seconds, and
//! a worker process runs several jobs on threads of one interpreter: holding
//! the lock that long would stop every other thread in it, the queue's
//! heartbeat included. So `submit` and `play` release it for the engine's
//! work, and take it back only to hand the block a chunk of prose. Nothing
//! that runs without it touches a Ruby object. It registers no unblocking
//! function, so a signal or `Thread#raise` waits for the turn to finish rather
//! than stopping it halfway through a write.

use magnus::value::BoxValue;
use magnus::{block::Proc, function, prelude::*, Error as RubyError, Ruby};
use renderedstep_engine::engine::{self, Engine};
use renderedstep_engine::model::system_one::SystemOne;
use renderedstep_engine::model::{Failure, Live, Replay, Reply, Route, Secret};
use renderedstep_engine::outcome::{Outcome, State};
use renderedstep_engine::store::SCHEMA_VERSION;
use renderedstep_engine::turn::{Report, Turned};
use serde_json::{json, Map, Value};
use std::ffi::c_void;
use std::panic::{self, AssertUnwindSafe};
use std::path::Path;
use std::ptr;

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), RubyError> {
    let module = ruby.define_module("RenderedStep")?;
    module.const_set("SCHEMA_VERSION", SCHEMA_VERSION)?;
    module.define_module_function("submit", function!(submit, 5))?;
    module.define_module_function("play", function!(play, 4))?;
    Ok(())
}

/// `RenderedStep.submit(database, playthrough_id, line, request_token,
/// models_json) { |chunk| ... }`: one submitted line, played the way every
/// front end plays it (`Engine::submit`). Answers a JSON document, never
/// raises for anything the engine did.
fn submit(
    ruby: &Ruby,
    database: String,
    playthrough: i64,
    line: String,
    token: String,
    models: String,
) -> Result<String, RubyError> {
    let block = if ruby.block_given() {
        Some(BoxValue::new(ruby.block_proc()?))
    } else {
        None
    };
    let mut raised: Option<RubyError> = None;
    let answer = without_gvl(|| {
        let mut deliver = |chunk: &str| {
            if raised.is_some() {
                return;
            }
            if let Some(block) = &block {
                if let Err(error) = with_gvl(|| call_block(block, chunk)) {
                    raised = Some(error);
                }
            }
        };
        submitted(&database, playthrough, &line, &token, &models, &mut deliver)
    });
    if let Some(error) = raised {
        return Err(error);
    }
    Ok(answer.to_string())
}

/// `RenderedStep.play(database, playthrough_id, line, decision)`: one line
/// played with no model at all (`Engine::play`, or `Engine::play_deciding`
/// when `decision` stands in for the answer a person would give), in one
/// transaction. The engine sweep plays its typed steps this way.
fn play(
    database: String,
    playthrough: i64,
    line: String,
    decision: Option<String>,
) -> Result<String, RubyError> {
    let answer = without_gvl(|| {
        let mut engine = match Engine::open(Path::new(&database)) {
            Ok(engine) => engine,
            Err(error) => return failed(&error),
        };
        let played = match &decision {
            Some(decision) => engine.play_deciding(playthrough, &line, decision, &mut |_| {}),
            None => engine.play(playthrough, &line, &mut |_| {}),
        };
        match played {
            Ok(outcome) => outcome_json(&outcome),
            Err(error) => failed(&error),
        }
    });
    Ok(answer.to_string())
}

fn submitted(
    database: &str,
    playthrough: i64,
    line: &str,
    token: &str,
    models: &str,
    deliver: &mut dyn FnMut(&str),
) -> Value {
    let config: Value = match serde_json::from_str(models) {
        Ok(config) => config,
        Err(_) => return glue_error("the models document is not JSON"),
    };
    let mut engine = match Engine::open(Path::new(database)) {
        Ok(engine) => engine,
        Err(error) => return failed(&error),
    };
    let stop_after = config["stop_after"].as_str();
    match config.get("replay") {
        Some(replies) => {
            let replies = match replies.as_array().map(|replies| {
                replies
                    .iter()
                    .map(Reply::from_value)
                    .collect::<Result<Vec<_>, _>>()
            }) {
                Some(Ok(replies)) => replies,
                Some(Err(message)) => return glue_error(&message),
                None => return glue_error("replay is a list of replies"),
            };
            let mut replay = Replay::new(replies);
            let played =
                engine.submit_stopping(playthrough, line, token, &mut replay, deliver, stop_after);
            let replayed = json!({
                "calls": replay.calls(),
                "unfinished": replay.finish().err(),
            });
            answered(played, Some(replayed))
        }
        None => {
            let mut live = live(&config);
            let played =
                engine.submit_stopping(playthrough, line, token, &mut live, deliver, stop_after);
            answered(played, None)
        }
    }
}

/// Where the live calls go, as the Ruby side read it off the environment
/// (`Playthrough::RustEngine.models`).
fn live(config: &Value) -> Live {
    let secret = |key: &str| {
        config[key]
            .as_str()
            .map(Secret::new)
            .filter(|secret| !secret.is_blank())
    };
    let route = match (config["route"].as_str(), secret("key")) {
        (Some("direct"), Some(key)) => Route::Direct { key },
        _ => Route::None,
    };
    let system_one = match (config["system_one"].as_str(), secret("typesafe_key")) {
        (Some("typesafe"), Some(key)) => SystemOne::TypeSafe { key },
        (Some("decisions"), _) if !route.is_none() => SystemOne::Decisions,
        _ => SystemOne::Off,
    };
    let live = Live::new(route).with_system_one(system_one);
    match config["model"].as_str() {
        Some(first) => live.with_model(first),
        None => live,
    }
}

fn answered(played: Result<engine::Submitted, engine::Error>, replayed: Option<Value>) -> Value {
    let mut answer = match played {
        Ok(submitted) => json!({
            "turned": turned_json(&submitted.turned),
            "state": state_json(&submitted.state),
        }),
        Err(error) => failed(&error),
    };
    if let (Some(replayed), Some(map)) = (replayed, answer.as_object_mut()) {
        map.insert("replay".into(), replayed);
    }
    answer
}

// --- Ruby, carefully -----------------------------------------------------

fn call_block(block: &BoxValue<Proc>, chunk: &str) -> Result<(), RubyError> {
    let ruby = unsafe { Ruby::get_unchecked() };
    block
        .call::<_, magnus::Value>((ruby.str_new(chunk),))
        .map(|_| ())
}

/// Runs `work` with the GVL released, and answers what it answered; a panic
/// in it becomes an error document here rather than unwinding into C.
fn without_gvl<W: FnOnce() -> Value>(work: W) -> Value {
    struct Call<F> {
        work: Option<F>,
        answer: Option<Value>,
    }
    unsafe extern "C" fn run<F: FnOnce() -> Value>(data: *mut c_void) -> *mut c_void {
        let call = unsafe { &mut *(data as *mut Call<F>) };
        let work = call.work.take();
        call.answer = Some(
            panic::catch_unwind(AssertUnwindSafe(|| work.map_or(Value::Null, |work| work())))
                .unwrap_or_else(|_| glue_error("the extension panicked")),
        );
        ptr::null_mut()
    }
    let mut call = Call {
        work: Some(work),
        answer: None,
    };
    unsafe {
        rb_sys::rb_thread_call_without_gvl(
            Some(run::<W>),
            &mut call as *mut Call<W> as *mut c_void,
            None,
            ptr::null_mut(),
        );
    }
    call.answer
        .unwrap_or_else(|| glue_error("the engine did not answer"))
}

/// Runs `work` holding the GVL again, from inside [`without_gvl`].
fn with_gvl<T, W: FnOnce() -> Result<T, RubyError>>(work: W) -> Result<T, RubyError> {
    struct Call<F, T> {
        work: Option<F>,
        answer: Option<Result<T, RubyError>>,
        panicked: bool,
    }
    unsafe extern "C" fn run<F: FnOnce() -> Result<T, RubyError>, T>(
        data: *mut c_void,
    ) -> *mut c_void {
        let call = unsafe { &mut *(data as *mut Call<F, T>) };
        if let Some(work) = call.work.take() {
            match panic::catch_unwind(AssertUnwindSafe(work)) {
                Ok(answer) => call.answer = Some(answer),
                Err(_) => call.panicked = true,
            }
        }
        ptr::null_mut()
    }
    let mut call = Call {
        work: Some(work),
        answer: None,
        panicked: false,
    };
    unsafe {
        rb_sys::rb_thread_call_with_gvl(
            Some(run::<W, T>),
            &mut call as *mut Call<W, T> as *mut c_void,
        );
    }
    if call.panicked {
        panic!("delivering prose panicked");
    }
    call.answer.expect("the block was called")
}

// --- the documents -------------------------------------------------------

/// An engine error as the Ruby side sorts it: `kind` names the variant, and
/// `failure` the kind of model failure for `model`.
fn failed(error: &engine::Error) -> Value {
    use engine::Error::*;
    let (kind, failure) = match error {
        SchemaMismatch { .. } => ("schema_mismatch", None),
        SchemaChanged { .. } => ("schema_changed", None),
        NoSuchPlaythrough(_) => ("no_such_playthrough", None),
        NoSuchStory(_) => ("no_such_story", None),
        Database(_) => ("database", None),
        Unsupported(_) => ("unsupported", None),
        Panicked(_) => ("panicked", None),
        Model(failure) => ("model", Some(failure_kind(failure))),
        Interrupted => ("interrupted", None),
        PreviouslyFailed => ("previously_failed", None),
        Stopped(_) => ("stopped", None),
    };
    json!({ "error": { "kind": kind, "failure": failure, "message": error.to_string() } })
}

fn failure_kind(failure: &Failure) -> &'static str {
    match failure {
        Failure::NoModel => "no_model",
        Failure::Unauthorized(_) => "unauthorized",
        Failure::Crisis(_) => "crisis",
        Failure::Refused(_) => "refused",
        Failure::SchemaIgnored(_) => "schema_ignored",
        Failure::Rejected(_) => "rejected",
        Failure::Provider(_) => "provider",
        Failure::Unavailable(_) => "unavailable",
        Failure::Unexpected(_) => "unexpected",
    }
}

/// A failure of this file rather than of the engine; the Ruby side plays
/// the line itself, as it does for a panic.
fn glue_error(message: &str) -> Value {
    json!({ "error": { "kind": "panicked", "failure": null, "message": message } })
}

fn turned_json(turned: &Turned) -> Value {
    json!({
        "scene": turned.scene,
        "refusal": turned.refusal.as_ref().map(|refusal| json!({
            "kind": refusal.kind,
            "typed": refusal.typed,
            "fact": refusal.fact,
            "offer": refusal.offer,
            "text": refusal.text(),
        })),
        "safety_notice": turned.safety_notice,
        "setup": turned.setup,
    })
}

fn outcome_json(outcome: &Outcome) -> Value {
    json!({ "report": report_json(&outcome.report), "state": state_json(&outcome.state) })
}

fn report_json(report: &Report) -> Value {
    json!({
        "understood": report.understood,
        "change": report.change,
        "refusal": report.refusal,
        "note": report.note,
        "resolved_by": report.resolved_by,
    })
}

fn state_json(state: &State) -> Value {
    let room = |room: &renderedstep_engine::outcome::Room| json!({ "id": room.id, "name": room.name, "detail": room.detail, "storey": room.storey });
    let named = |rows: &[renderedstep_engine::outcome::Named]| -> Value {
        rows.iter()
            .map(|row| json!({ "id": row.id, "name": row.name }))
            .collect()
    };
    let pairs = |pairs: Vec<(String, Value)>| -> Value {
        Value::Object(pairs.into_iter().collect::<Map<_, _>>())
    };
    json!({
        "location": state.location.as_ref().map(room),
        "exits": state.exits.iter().map(room).collect::<Vec<_>>(),
        "here": named(&state.here),
        "carrying": named(&state.carrying),
        "present": named(&state.present),
        "foes": named(&state.foes),
        "inscription": state.inscription.iter()
            .map(|row| json!({ "id": row.id, "name": row.name, "text": row.text }))
            .collect::<Vec<_>>(),
        "hp": state.hp,
        "hp_of": pairs(state.hp_of.iter().map(|(name, hp)| (name.clone(), json!(hp))).collect()),
        "abilities": state.abilities.as_ref().map(|abilities| {
            pairs(abilities.iter().map(|(name, score)| (name.clone(), json!(score))).collect())
        }),
        "dead": state.dead,
        "quest": pairs(state.quest.iter().map(|(position, beat)| (position.to_string(), json!(beat))).collect()),
        "ending": state.ending,
        "ending_words": state.ending_words,
        "scheduled": state.scheduled,
        "fired": state.fired,
    })
}
