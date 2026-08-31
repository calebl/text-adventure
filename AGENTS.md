# AGENTS.md

Guidance for AI coding agents working in this repository.

## Start here

**[ROADMAP.md](ROADMAP.md) is the source of truth for status and tasks.** Read it
before planning any work. It records what is built, what is next, the reasoning
behind the persistence model, and the known issues.

When you finish a piece of work, update `ROADMAP.md` in the same change: check
off what landed, move it into **Status → Done**, and add anything new you
discovered to **Next up** or **Known issues**. A task queue that drifts from the
code is worse than none.

`CLAUDE.md` holds the project conventions (testing requirements, factory rules,
architecture notes). This file and `CLAUDE.md` are complementary — conventions
there, status here.

## What this project is

A text adventure that generates itself as the player explores, and keeps what it
generates. `Location` is the durable world and is generated once; `Scene` is a
timestamped moment in a location. See the persistence model section in
`ROADMAP.md` before touching either model — that split is the whole design.

## Working agreements

### Talking to models

- All LLM calls go through `BaseAgent` (`app/agents/BaseAgent.rb`). It handles
  model selection and rotates to the next model when a call fails. Do not build
  a bare `RubyLLM::Chat` in new code.
- All LLM calls use structured output via `RubyLLM::Schema`. Schemas live
  alongside the model they populate (`app/models/universe/physical_schema.rb`),
  and are usually a declared class. `Playthrough::IntentSchema` is a factory
  instead, because its `target` is an enum over the exits and people in front
  of the player, which is only known per turn.
- **One documented exception, and the line is what the call PRODUCES, not which
  class makes it: prose the player watches arrive streams and stays
  unschema'd; anything that fills a record stays schema'd.** Structured output
  and token streaming are mutually exclusive here — with a schema attached the
  model emits JSON, so a player watching the stream sees
  `{\n  "description": "The doorway...` arrive a character at a time (and the
  call runs ~4x longer). Two calls are on the prose side of that line, and only
  two: `Scene::Narrator`, which answers what the player *typed*, and
  `InteractionAgent`'s second pass, which turns a character's reaction into
  prose. Note the shape of the second one — the same turn's *structured* half
  (`Interaction::Schema`, five fields) is a separate schema'd call, so nothing
  a record needs is left to prose. Do not "fix" either by giving it a schema,
  and do not add a third without that same split.
  **`Scene::Generator` is `Scene::Narrator`'s sibling, not a second copy of
  it.** It narrates walking *into* a place, which is a record rather than a
  turn, so it is schema'd like everything else and returns a `Scene` instead of
  streaming. If you find yourself giving one of them the other's job, the two
  classes have drifted — today the line is "answering a command" versus
  "writing a moment". A refactor to split them by *facts* versus *story*
  instead is filed as its own work item; until it lands, keep the current line.
- **Never let `ruby_llm-schema` resolve to 1.x.** Its 1.0.0 is a deprecation
  shim forwarding to the renamed `schematist` gem. `ruby_llm` itself still
  depends on `ruby_llm-schema ~> 0` and contains no reference to `schematist`,
  so its own constraint already rules the shim out — the `~> 0.2` in the
  `Gemfile` is belt-and-braces, not the thing doing the work. What matters is
  never *widening* past it: an unconstrained `gem "ruby_llm-schema"` lets the
  resolver take 1.0.0 and silently drags `ruby_llm` back to 1.8.2, the last
  release with no such dependency. That failure is silent twice over, because
  the shim and `ruby_llm` then disagree about what `to_json_schema` returns and
  `RubyLLM::Chat#with_schema` drops the schema with no error at all — every
  structured call goes out as prose.
  `test/models/ruby_llm_schema_envelope_test.rb` guards that seam all the way
  to the rendered request body; keep it passing.
- The explicit `Gemfile` entry stays even though `ruby_llm` would pull the gem
  in anyway: every schema class here subclasses `RubyLLM::Schema` directly, so
  it is a direct dependency. If `ruby_llm` 2.0 does switch to `schematist`, an implicit
  dependency would vanish and surface as a `NameError` rather than a
  resolution failure.
- **Never swallow a generation failure.** Generators raise. A rescue that
  returns a half-built record turns a missing model or a bad API key into
  "the AI gave me garbage," which is very hard to debug — this has already
  happened once in this codebase.
- **Verify a model supports structured outputs before adding it to
  `BaseAgent`.** Several OpenRouter `:free` endpoints accept a schema and answer
  in prose instead, which corrupts records silently rather than failing. Check
  with `curl -s https://openrouter.ai/api/v1/models | jq '.data[] | select(.id == "MODEL") | .supported_parameters'`
  and confirm `structured_outputs` is listed.
- Ask for a handful of fields per call, not twenty. Split large records across
  sequential calls on one agent, the way `Universe::Generator` does; the
  conversation carries context between calls. **A pass earns its round trip when
  its output is large enough to constrain the next one.** The universe's first
  pass produces ~584 tokens the second is told to stay consistent with, so it
  earns it. Two splits that did not — naming the opening location, and a
  character's identity before their background — produced 39 and 21 output
  tokens against ~2,300-token prompts, and were collapsed into the calls that
  already had the context.
- **Send each prompt only the context it can use.** `Universe#prompt_details`
  takes an audience (`:full`, `:character`, `:place`, `:dialogue`, `:scene`)
  because the whole record is 1,584 tokens and goes out again on every room and
  every turn of dialogue. Add a field to `Universe::AUDIENCE_FIELDS`, not to a
  caller. Before adding an audience, check that the prompt does not already
  carry the same facts in a more specific form: `:scene` is `:place` minus
  everything the location's own description and lore already say, which is what
  makes it 285 tokens instead of 628.
- **Prefer a fixed table to a prompt** where the value is one of a known set.
  `LocationConnection::DISTANCES` and `::TRAVEL_METHODS` are enums the schema
  reads directly, and `time_to_travel` is derived from them rather than asked
  for. Free prose in a small `max_length` box truncates mid-word, and a
  directional phrase is wrong on the way back.
- Seed prompts with randomized "predetermined details" so repeated runs diverge
  (`Universe::Generator::TONES`, `Character::Generator::BIRTH_PLACES`).

### Generating the world

- `Location` is generated in two steps and carries `detail_level`: a **stub** is
  a name plus a one-line `teaser`, a **realized** location has the description
  and lore the player reads. `description` / `lore` are validated only when
  realized, so a stub saves. `Location::Generator#realize!` fills a stub in and
  stubs out its exits; it returns an already-realized location untouched.
  Generation happens once per place — do not add a code path that regenerates one.
- The description is saved BEFORE the exits are asked for, so a failed exits
  call does not throw away the more expensive of the two. The cost is that a
  room can end up realized with no way out, and `realize!` will not finish it;
  `Location::Generator#write_exits!` is public for exactly that recovery.
- `LocationConnection` rows are written in both directions from one answer, so
  anything stored on them has to be true both ways. That is why the travel
  method is a direction-neutral enum and the travel time is derived.

### Seeded worlds

- `db/seeds/worlds/*.yml` are two checked-in playable worlds, loaded offline and
  idempotently by `db/seeds.rb`. `WorldSeed::Loader` matches on natural keys
  (story title, race name, character fullname, location name) — never on `id`.
- `rake 'game:export[story_id]'` writes a generated world into that format.
  Rebuild the files with it after a schema change; the format, the rules the
  loader enforces and what is deliberately not exported are in
  `db/seeds/worlds/README.md`.
- The files are **authored artifacts**: edit them by hand. Re-export keeps the
  leading comment block and loses every comment below it.
- **Seeded worlds are not a substitute for generating one.**
  `test/lib/seeded_worlds_test.rb` is the only test that reads them; generator
  tests keep running against `FakeAgent`.

### Playing the world

- **The loop is `Playthrough::Turn`, and the browser's whole share of it is a
  string and a block.** `NarrationsController` forwards the chunks the block is
  yielded; it does not know which branch the turn took. Keep it that way — the
  block is also the seam that makes the Turbo Streams swap touch only the
  consumer.
- The block is yielded **text**, not RubyLLM chunk objects. `Scene::Narrator`
  and `InteractionAgent` both unwrap before yielding; a schema'd branch yields
  its finished paragraph in one piece because it cannot stream at all.
- **`Playthrough::Classifier` resolves names back to records itself**, next to
  the candidate list it is the inverse of. It offers the model a closed enum of
  the room's exits and its cast, so an answer either names a record that exists
  or names `nothing`. Do not move resolution into the loop and do not open the
  enum to free text: a fuzzy matcher on this seam guesses about where the
  player is standing.
- A classification the loop cannot act on falls through to `Scene::Narrator`,
  which narrates the attempt. Being unable to do a thing is part of the game;
  silently doing a different thing is not.
- **Who is standing in a room is answered in one place**, `Scene::Generator.characters_present`,
  because the classifier must accept exactly the people the arrival paragraph
  introduced. It reads the last scene in that location that recorded *anyone* —
  only an arrival records a cast, so reading the plain latest scene emptied the
  room after any narrated turn.
- **Tools on the narrator were evaluated and rejected for movement** (see the
  ROADMAP): `gemma3:12b`, first in `LOCAL_MODEL_OPTIONS`, has no tool
  capability at all, and a model that cannot call tools does not fail — it
  narrates walking through a door and the player never moves. Tool support is
  slated to land with the narrator creating characters, where a missed call
  costs a record rather than the player's position.

### Testing

- Generator tests **must not hit a model.** Use `FakeAgent`
  (`test/support/fake_agent.rb`) with `BaseAgent.stub(:new, agent)`. It records
  the prompts and schemas it was given, so assert on those.
- For code that builds a `RubyLLM::Chat` directly rather than going through
  `BaseAgent`, use `FakeChat` (`test/support/fake_chat.rb`).
  `FakeChat.with_fake_chats(...)` replaces `RubyLLM::Chat.new` for a block and
  hands out queued responses, so a multi-pass agent's chats can be inspected in
  construction order.
- The suite must run with **no API key and no ollama**. Anything that needs a
  provider configured should set the key on `RubyLLM.config` inside the test and
  restore it, never read one from the environment.
- Per `CLAUDE.md`: every model needs a test file and a factory.
- `bin/rails test` runs in about a second. There is no reason to skip it.

### Before you finish

```bash
bin/rails test
bundle exec rubocop
bin/rails zeitwerk:check   # app/agents/ uses PascalCase filenames; verify autoloading
```

## Environment

- Ruby 3.4.10 via asdf/mise (`.tool-versions`).
- `bin/rails db:prepare && bin/rails db:seed` — the dev database is not checked
  in, and the seed step fills the `models` table and loads the two playable
  worlds in `db/seeds/worlds`. Since the RubyLLM v1.7 `acts_as` migration that
  table **is** the model registry: RubyLLM resolves model names out of it and
  does not fall back to the registry the gem ships with, so an empty table
  resolves nothing. Reading it is offline; no API key.
- `ollama serve` must be running for local generation. Installed models are
  listed in `BaseAgent::LOCAL_MODEL_OPTIONS`; keep that list matching what is
  actually pulled, or every call fails on a missing model.
- `OPENROUTER_API_KEY` (kept in the gitignored `.envrc`) is strongly preferred
  for interactive work — local models take minutes per structured call, and on
  this machine run on CPU. `BaseAgent` uses remote models automatically when the
  key is set, working down `BaseAgent::REMOTE_MODEL_IDS` — `minimax/minimax-m3`,
  then `mistralai/mistral-medium-3.1` as a fallback. `OPENROUTER_MODEL` overrides
  the front of that list.

## Try it

```bash
rake 'game:new[a debt collector in a city built on a dead god]'
rake game:list
bin/rails server   # then open http://localhost:3000 and play it
```

The rake tasks build worlds; the browser only plays them. There is no
`rake game:play` and there is not meant to be — the loop lives in
`Playthrough::Turn`, so a rake front end would be a second UI to maintain for
no new capability.

## The browser interface

Plain Rails, deliberately minimal: no Node, no `package.json`, no build step,
no importmap, no propshaft, no Turbo, no Action Cable. Views are ERB with an
inline `<style>` in the layout, and the only JavaScript is six lines of
`EventSource` in `app/views/playthroughs/show.html.erb`. Those gems belong to a
later stage — do not install them in passing.

- `ApplicationController < ActionController::Base` and `config.api_only = false`.
  That turns on `protect_from_forgery`, so every form goes through `form_with`.
- A browser session is bound to a `Playthrough` by its unguessable `token` in
  `session[:playthrough_token]`. There is no auth, no user model, and the
  captain does not want any: this is a single-player localhost app.
- `NarrationsController` streams over SSE with `ActionController::Live`, which
  holds one Puma thread per open stream. Fine for one player; raise
  `RAILS_MAX_THREADS` before two.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
