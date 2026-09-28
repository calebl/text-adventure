//! THE RUST ENGINE AS A RUBY EXTENSION, and nothing more than the crossing.
//!
//! `Playthrough::RustEngine` (app/models/playthrough/rust_engine.rb) hands
//! over a whole turn -- the database file, the game, the line, its request
//! token, where model calls go, and a block for prose -- and gets back one
//! JSON document: what the turn left, or the error it ended in.
//! `Playthrough::Requests` (app/models/playthrough/requests.rb) asks for the
//! engine's data and the requests it builds, for the benches and the Ruby
//! reference loop (see "the benches", below).
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
use renderedstep_engine::arrival::Arrival;
use renderedstep_engine::engine::{self, Engine};
use renderedstep_engine::glance::{self as glanced, Glance};
use renderedstep_engine::intent::Intent;
use renderedstep_engine::model::system_one::SystemOne;
use renderedstep_engine::model::{
    Agent, Answer, Book, Call, Failure, Filed, Live, Models, Replay, Reply, Route, Secret,
    Unavailable, Verify,
};
use renderedstep_engine::moment::{Direction, Handled, Moment};
use renderedstep_engine::outcome::{Outcome, State};
use renderedstep_engine::playthrough::Game;
use renderedstep_engine::records::Records;
use renderedstep_engine::room::{Record, Room};
use renderedstep_engine::store::SCHEMA_VERSION;
use renderedstep_engine::turn::room_of;
use renderedstep_engine::turn::{Fixed, Report, Turned};
use renderedstep_engine::{cascade, classifier, dialogue, memory, narration, volition};
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
    module.define_module_function("glance", function!(glance, 2))?;
    module.define_module_function("scaffold", function!(scaffold, 0))?;
    module.define_module_function("data", function!(data, 0))?;
    module.define_module_function("request", function!(request, 3))?;
    module.define_module_function("read_line", function!(read_line, 4))?;
    module.define_module_function("submit_fixed", function!(submit_fixed, 6))?;
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

/// `RenderedStep.glance(database, playthrough_id)`: what a front end's
/// panels show between turns and which verbs are open (`Engine::glance`), as
/// one JSON document. Reads only.
fn glance(database: String, playthrough: i64) -> Result<String, RubyError> {
    let answer = without_gvl(|| {
        let engine = match Engine::open(Path::new(&database)) {
            Ok(engine) => engine,
            Err(error) => return failed(&error),
        };
        match engine.glance(playthrough) {
            Ok(glance) => glance_json(&glance),
            Err(error) => failed(&error),
        }
    });
    Ok(answer.to_string())
}

/// `RenderedStep.scaffold`: the narration prompt's per-turn scaffold,
/// rendered against fixed placeholders, which the prompt version digests.
fn scaffold() -> String {
    renderedstep_engine::prompt_version::scaffold()
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

// --- the benches -------------------------------------------------------
//
// A bench measures what the game sends, so it builds its requests with the
// engine's own builders rather than a copy of them. These entries hold the
// GVL throughout: none of them waits on anything but the block, and the
// block releases the lock itself while it waits on a provider.

/// `RenderedStep.data`: every engine data file as `{name => text}`, the
/// bytes the engine plays with. The game reads its prompt data here and
/// keeps no copy of its own (`EngineData`).
fn data() -> String {
    let files: Map<String, Value> = renderedstep_engine::data::files()
        .iter()
        .map(|(name, text)| (name.to_string(), Value::from(*text)))
        .collect();
    Value::Object(files).to_string()
}

/// `RenderedStep.request(kind, records_json, args_json)`: one request the
/// engine would send, built from a staged position's rows
/// (`EngineVectors::Records`), with nothing played and nothing written.
/// Answers the request as JSON, or an error document.
fn request(kind: String, records: String, args: String) -> String {
    let answer = panic::catch_unwind(AssertUnwindSafe(|| {
        let records = match serde_json::from_str::<Value>(&records) {
            Ok(dump) => Records::from_json(&dump),
            Err(_) => return glue_error("the records are not JSON"),
        };
        let args: Value = match serde_json::from_str(&args) {
            Ok(args) => args,
            Err(_) => return glue_error("the arguments are not JSON"),
        };
        built(&kind, &records, &args).unwrap_or_else(|message| glue_error(&message))
    }))
    .unwrap_or_else(|_| glue_error("the extension panicked"));
    answer.to_string()
}

fn built(kind: &str, records: &Records, args: &Value) -> Result<Value, String> {
    let int = |key: &str| {
        args[key]
            .as_i64()
            .ok_or_else(|| format!("{kind} needs an integer {key}"))
    };
    let text = |key: &str| args[key].as_str();
    let game = || int("playthrough").map(|id| Game::new(records, id));
    let row = |table: &str, key: &str| -> Result<&renderedstep_engine::records::Row, String> {
        let id = int(key)?;
        records
            .find(table, id)
            .ok_or_else(|| format!("there is no {table} {id}"))
    };
    Ok(match kind {
        "narration" => {
            let handled = handled_of(&args["handled"])?;
            narration::call(
                game()?,
                text("command").unwrap_or_default(),
                text("fact"),
                text("doing"),
                handled,
            )
            .to_request()
        }
        "ending" => {
            let outcome = row("quest_outcomes", "outcome")?;
            narration::ending_call(game()?, outcome).to_request()
        }
        "narration_context" => {
            let handled = handled_of(&args["handled"])?;
            let ending = match args["ending"].as_i64() {
                Some(outcome) => Some(
                    records
                        .find("quest_outcomes", outcome)
                        .ok_or_else(|| format!("there is no quest_outcomes {outcome}"))?,
                ),
                None => None,
            };
            let moment = Moment {
                game: game()?,
                handled,
                ending,
            };
            Value::from(moment.narration_context(
                args["plan"].as_bool().unwrap_or(true),
                args["arc"].as_bool().unwrap_or(true),
            ))
        }
        "character_context" => {
            let character = row("characters", "character")?;
            let moment = Moment::new(game()?);
            let replayed = args["replayed"]
                .as_i64()
                .unwrap_or(dialogue::HISTORY_EXCHANGES);
            json!({
                "context": moment.character_context(character, replayed, text("query")),
                "personal_facts": moment.personal_facts(character),
            })
        }
        "memory" => {
            let game = game()?;
            let character = row("characters", "character")?;
            let replayed = args["replayed"]
                .as_i64()
                .unwrap_or(dialogue::HISTORY_EXCHANGES);
            let query = text("query");
            let recall: Vec<Value> = memory::recall(&game, character, query, replayed, memory::CONCLUSIONS)
                .into_iter()
                .map(|found| json!({ "id": renderedstep_engine::records::id(found), "resolution": memory::resolution(found) }))
                .collect();
            let recollection = match args["interaction"].as_i64() {
                Some(interaction) => {
                    let found = records
                        .find("interactions", interaction)
                        .ok_or_else(|| format!("there is no interactions {interaction}"))?;
                    Value::from(memory::recollection(&game, found))
                }
                None => Value::Null,
            };
            json!({
                "recall": recall,
                "recollection": recollection,
                "conclusions": renderedstep_engine::moment::conclusions(&game, character, replayed, query),
                "recollections": renderedstep_engine::moment::recollections(&game, character, replayed, query),
            })
        }
        "framing" => Value::from(renderedstep_engine::facts::framing(
            text("context").unwrap_or_default(),
            text("command").unwrap_or_default(),
            text("fact"),
            text("doing"),
        )),
        "handled_note" => Value::from(match text("direction") {
            Some("taken") => Direction::Taken.note(),
            Some("dropped") => Direction::Dropped.note(),
            _ => return Err("a direction is taken or dropped".into()),
        }),
        "character" => {
            let game = game()?;
            let character = row("characters", "character")?;
            dialogue::character_request_offering(
                &game,
                character,
                text("line").unwrap_or_default(),
                args["offered_item"].as_i64(),
            )
        }
        "interaction_narration" => {
            let game = game()?;
            let character = row("characters", "character")?;
            let reaction = args["reaction"].as_object().cloned().unwrap_or_default();
            dialogue::narrator_request(
                &game,
                character,
                text("line").unwrap_or_default(),
                &reaction,
                text("fact").unwrap_or_default(),
            )
        }
        "classifier" => {
            let room = room_of(records, int("playthrough")?);
            let call = classifier::call(records, &room, text("line").unwrap_or_default());
            let mut request = call.to_request();
            request["temperature"] = call.temperature.clone().unwrap_or(Value::Null);
            request
        }
        "cascade" => {
            let room = room_of(records, int("playthrough")?);
            let state = cascade::State::new(&room, text("line").unwrap_or_default());
            json!({ "state": state.to_json(), "questions": cascade::request(&state) })
        }
        "volition" => {
            let game = game()?;
            let characters = args["characters"]
                .as_array()
                .ok_or("volition needs its characters")?
                .iter()
                .map(|who| {
                    who.as_i64()
                        .map(|id| game.character(id))
                        .ok_or("a character is an id")
                })
                .collect::<Result<Vec<_>, _>>()?;
            let location = row("locations", "location")?;
            volition::request(&game, &characters, location, text("line"))
        }
        "speech_choices" => {
            let game = game()?;
            let character = row("characters", "character")?;
            let location = row("locations", "location")?;
            Value::Array(
                volition::speech_choices(&game, character, location)
                    .into_iter()
                    .map(|(token, fact)| json!({ "token": token, "fact": fact }))
                    .collect(),
            )
        }
        "arrival" => {
            let location = row("locations", "location")?;
            let game = args["playthrough"]
                .as_i64()
                .map(|id| Game::new(records, id));
            let previous_scene = match args["previous_scene"].as_i64() {
                Some(scene) => Some(
                    records
                        .find("scenes", scene)
                        .ok_or_else(|| format!("there is no scene {scene}"))?,
                ),
                None => None,
            };
            Arrival {
                records,
                location,
                previous_scene,
                game,
                opening: args["opening"].as_bool().unwrap_or(false),
            }
            .request()
        }
        "room" => room_json(&room_of(records, int("playthrough")?)),
        other => return Err(format!("no request builder called {other}")),
    })
}

/// The item a turn moved and which way, as `{item, direction}`, or none.
fn handled_of(handled: &Value) -> Result<Option<Handled>, String> {
    match (handled["item"].as_i64(), handled["direction"].as_str()) {
        (Some(item), Some("taken")) => Ok(Some(Handled {
            item,
            direction: Direction::Taken,
        })),
        (Some(item), Some("dropped")) => Ok(Some(Handled {
            item,
            direction: Direction::Dropped,
        })),
        (None, None) => Ok(None),
        _ => Err("handled is an item and taken or dropped".into()),
    }
}

/// A room's closed sets, by name, the way a caller offers them to a model.
fn room_json(room: &Room) -> Value {
    json!({
        "exits": room.exits.iter().map(|exit| exit.place.name.clone()).collect::<Vec<_>>(),
        "cast": room.cast.iter().map(|person| json!({ "fullname": person.fullname, "nickname": person.nickname })).collect::<Vec<_>>(),
        "lying": room.lying.iter().map(|thing| thing.name.clone()).collect::<Vec<_>>(),
        "carried": room.carried.iter().map(|thing| thing.name.clone()).collect::<Vec<_>>(),
        "physical": room.physical_actions().iter().map(|choice| json!({
            "token": choice.token(),
            "name": choice.name(),
            "kind": choice.kind,
            "binding": [
                choice.item.as_ref().map(|thing| thing.name.clone()),
                choice.recipient.as_ref().map(|person| person.fullname.clone()),
                choice.connection.as_ref().map(|exit| json!([room.here.as_ref().map(|here| here.name.clone()), exit.place.name])),
                choice.tool.as_ref().map(|thing| thing.name.clone()),
            ],
        })).collect::<Vec<_>>(),
    })
}

/// `RenderedStep.read_line(records_json, playthrough_id, line, system_one)
/// { |call| ... }`: the line read the way a turn reads it
/// (`classifier::read`), over a staged position's rows, with each call the
/// reading makes handed to the block (see [`Hosted`]). Writes nothing.
fn read_line(
    ruby: &Ruby,
    records: String,
    playthrough: i64,
    line: String,
    system_one: bool,
) -> Result<String, RubyError> {
    let block = ruby.block_proc()?;
    let mut host = Hosted::new(block, system_one);
    let answer = panic::catch_unwind(AssertUnwindSafe(|| {
        let records = match serde_json::from_str::<Value>(&records) {
            Ok(dump) => Records::from_json(&dump),
            Err(_) => return glue_error("the records are not JSON"),
        };
        let room = room_of(&records, playthrough);
        let call = classifier::call(&records, &room, &line);
        match classifier::read(&room, &call, &line, &mut host) {
            Ok(reading) => json!({
                "intent": intent_json(&reading.intent),
                "resolved_by": reading.path,
                "target_present": reading.target_present,
                "named_more_than_one": reading.named_more_than_one,
            }),
            Err(failure) => json!({ "error": { "kind": "model", "failure": failure_kind(&failure), "message": failure.to_string() } }),
        }
    }))
    .unwrap_or_else(|_| glue_error("the extension panicked"));
    host.finish(answer)
}

/// What a line was read as, with the name each record answers to.
fn intent_json(intent: &Intent) -> Value {
    let label = |record: Option<Record>| record.map(|record| record.label());
    let target = match &intent.physical {
        Some(choice) => Some(choice.name()),
        None => label(intent.subject()),
    };
    json!({
        "action": intent.action,
        "target": target,
        "token": intent.physical.as_ref().map(|choice| choice.token()),
        "also_named": label(intent.also_named.clone()),
        "thrown_at": label(intent.at.clone()),
        "unknown_action": intent.unknown_action,
        "refused": intent.refused(),
        "reached_for_nothing": intent.reached_for_nothing(),
        "named_more_than_one": intent.named_more_than_one(),
    })
}

/// `RenderedStep.submit_fixed(database, playthrough_id, line, token,
/// fixed_json, system_one) { |call| ... }`: one submitted line played on a
/// committed database the way every front end plays it, read as
/// `fixed_json` (`{action, target}`) says wherever the classifier would
/// have been asked (`Engine::submit_fixed`), with every other call handed to
/// the block. Answers what `submit` answers, plus `calls`: every request
/// the turn made, in order.
fn submit_fixed(
    ruby: &Ruby,
    database: String,
    playthrough: i64,
    line: String,
    token: String,
    fixed: String,
    system_one: bool,
) -> Result<String, RubyError> {
    let block = ruby.block_proc()?;
    let mut host = Hosted::new(block, system_one);
    let answer = panic::catch_unwind(AssertUnwindSafe(|| {
        let fixed: Value = match serde_json::from_str(&fixed) {
            Ok(fixed) => fixed,
            Err(_) => return glue_error("the fixed reading is not JSON"),
        };
        let Some(action) = fixed["action"].as_str() else {
            return glue_error("a fixed reading names its action");
        };
        let fixed = Fixed {
            action: action.to_string(),
            target: fixed["target"].as_str().map(str::to_string),
        };
        let mut engine = match Engine::open(Path::new(&database)) {
            Ok(engine) => engine,
            Err(error) => return failed(&error),
        };
        let played =
            engine.submit_fixed(playthrough, &line, &token, &fixed, &mut host, &mut |_| {});
        answered(played, None)
    }))
    .unwrap_or_else(|_| glue_error("the extension panicked"));
    host.finish(answer)
}

/// The models a bench turn asks: each call handed to a Ruby block as one
/// JSON document, and its answer read back from the JSON the block returns.
///
/// A chat call is `{kind: "chat", purpose, system, user, schema, history,
/// temperature, stream}`, answered with `{content, model}` or with
/// `{failure: {kind, message}}`; a System One call is `{kind: "system_one",
/// purpose, state, questions}`, answered with the provider's body or with
/// `{unavailable: message}`. Nothing is written here: the block keeps
/// whatever receipts it keeps. An exception the block raises is kept, the
/// call it answered fails, and it is raised again once the engine returns.
struct Hosted {
    block: Proc,
    system_one: bool,
    calls: Vec<Value>,
    raised: Option<RubyError>,
}

impl Hosted {
    fn new(block: Proc, system_one: bool) -> Hosted {
        Hosted {
            block,
            system_one,
            calls: Vec::new(),
            raised: None,
        }
    }

    /// Hands `request` to the block and parses what it returns.
    fn hand(&mut self, request: Value) -> Result<Value, String> {
        self.calls.push(request.clone());
        if self.raised.is_some() {
            return Err("an earlier call raised".into());
        }
        let ruby = unsafe { Ruby::get_unchecked() };
        let returned = self
            .block
            .call::<_, magnus::Value>((ruby.str_new(&request.to_string()),))
            .and_then(String::try_convert);
        match returned {
            Ok(text) => {
                serde_json::from_str(&text).map_err(|_| "the block did not answer JSON".to_string())
            }
            Err(error) => {
                self.raised = Some(error);
                Err("the block raised".into())
            }
        }
    }

    /// The answer document with the calls made, or the block's exception.
    fn finish(self, mut answer: Value) -> Result<String, RubyError> {
        if let Some(error) = self.raised {
            return Err(error);
        }
        if let Some(fields) = answer.as_object_mut() {
            fields.insert("calls".into(), Value::Array(self.calls));
        }
        Ok(answer.to_string())
    }
}

fn failure_of(document: &Value) -> Failure {
    let message = document["message"].as_str().unwrap_or_default().to_string();
    match document["kind"].as_str() {
        Some("no_model") => Failure::NoModel,
        Some("unauthorized") => Failure::Unauthorized(message),
        Some("crisis") => Failure::Crisis(message),
        Some("refused") => Failure::Refused(message),
        Some("schema_ignored") => Failure::SchemaIgnored(message),
        Some("rejected") => Failure::Rejected(message),
        Some("unavailable") => Failure::Unavailable(message),
        Some("provider") => Failure::Provider(message),
        _ => Failure::Unexpected(message),
    }
}

impl Hosted {
    fn chat(&mut self, purpose: &str, call: &Call, stream: bool) -> Result<Answer, Failure> {
        let mut request = call.to_request();
        request["kind"] = Value::from("chat");
        request["purpose"] = Value::from(purpose);
        request["temperature"] = call.temperature.clone().unwrap_or(Value::Null);
        request["stream"] = Value::from(stream);
        let answered = self.hand(request).map_err(Failure::Unexpected)?;
        if let Some(failure) = answered.get("failure") {
            return Err(failure_of(failure));
        }
        Ok(Answer {
            content: answered["content"].clone(),
            model: answered["model"].as_str().map(str::to_string),
        })
    }
}

impl Models for Hosted {
    fn ask(
        &mut self,
        _book: &mut Book,
        agent: &mut Agent,
        call: &Call,
        verify: Option<Verify>,
        on_chunk: Option<&mut (dyn FnMut(&str) + '_)>,
    ) -> Result<Answer, Failure> {
        let answer = self.chat(agent.purpose(), call, on_chunk.is_some())?;
        if let Some(verify) = verify {
            verify(&answer.content).map_err(Failure::Rejected)?;
        }
        if let Some(on_chunk) = on_chunk {
            on_chunk(answer.text());
        }
        Ok(answer)
    }

    fn system_one(&self) -> bool {
        self.system_one
    }

    fn ask_questions(
        &mut self,
        _book: &mut Book,
        filed: &Filed,
        state: &Value,
        questions: &Value,
    ) -> Result<Value, Unavailable> {
        let request = json!({ "kind": "system_one", "purpose": filed.purpose, "state": state, "questions": questions });
        let answered = self.hand(request).map_err(Unavailable)?;
        match answered.get("unavailable") {
            Some(reason) => Err(Unavailable(
                reason.as_str().unwrap_or("unavailable").to_string(),
            )),
            None => Ok(answered),
        }
    }
}

impl classifier::Reader for Hosted {
    fn system_one(&self) -> bool {
        self.system_one
    }

    fn questions(&mut self, state: &Value, questions: &Value) -> Result<Value, Unavailable> {
        let request = json!({ "kind": "system_one", "purpose": "classifier", "state": state, "questions": questions });
        let answered = self.hand(request).map_err(Unavailable)?;
        match answered.get("unavailable") {
            Some(reason) => Err(Unavailable(
                reason.as_str().unwrap_or("unavailable").to_string(),
            )),
            None => Ok(answered),
        }
    }

    fn classifier(&mut self, call: &Call) -> Result<Answer, Failure> {
        self.chat("classifier", call, false)
    }
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

fn glance_json(glance: &Glance) -> Value {
    let named = |id: i64, name: &str| json!({ "id": id, "name": name });
    let target = |target: &glanced::Target| match &target.token {
        Some(token) => json!({
            "name": target.name, "token": token, "kind": target.kind, "line": target.line,
        }),
        None => json!({ "id": target.id, "name": target.name }),
    };
    json!({
        "room": glance.here.as_ref().map(|here| json!({ "id": here.id, "name": here.name, "within": here.within })),
        "exits": glance.exits.iter()
            .map(|exit| json!({ "id": exit.id, "name": exit.name, "written": exit.written, "open": exit.open }))
            .collect::<Vec<_>>(),
        "people": glance.people.iter()
            .map(|person| json!({
                "id": person.id, "name": person.name, "condition": person.condition,
                "foe": person.foe, "provoked": person.provoked,
            }))
            .collect::<Vec<_>>(),
        "lying_here": glance.lying_here.iter().map(|thing| named(thing.id, &thing.name)).collect::<Vec<_>>(),
        "carrying": glance.carrying.iter().map(|thing| named(thing.id, &thing.name)).collect::<Vec<_>>(),
        "condition": glance.condition,
        "sheet": glance.sheet,
        "next_beat": glance.next_beat,
        "story_time": glance.story_time,
        "over": glance.over,
        "ended": glance.ended,
        "verbs": glance.verbs.iter()
            .map(|verb| json!({
                "name": verb.name,
                "available": verb.available(),
                "reason": verb.reason,
                "targets": verb.targets.iter().map(target).collect::<Vec<_>>(),
                "aims": verb.aims.as_ref().map(|aims| aims.iter().map(target).collect::<Vec<_>>()),
                "word": verb.word,
            }))
            .collect::<Vec<_>>(),
        "slash_menu": {
            "verbs": glance.slash_menu.verbs.iter()
                .map(|verb| json!({ "word": verb.word, "hint": verb.hint }))
                .collect::<Vec<_>>(),
            "targets": Value::Object(glance.slash_menu.targets.iter()
                .map(|(word, names)| (word.clone(), json!(names)))
                .collect::<Map<_, _>>()),
        },
        "state": state_json(&glance.state),
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
