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

### The standing constraint

**Nothing may depend on the narrator obeying its prompt.** Prompt it with the
world's rules — that is cheap and it raises the odds — but never let a
guarantee rest on its compliance. *Gate the state, inform the prose, audit the
difference.* Where a model must be involved, do not ask it what should happen:
ask it to pick from a set the app closed, then have the app act on the record,
never on the label. The README's turn diagram states it in colours
([README.md](README.md#how-a-turn-works)); `ROADMAP.md` → *The standing
constraint* has the captain's wording and where the full audit lives.

### Talking to models

- All LLM calls go through `BaseAgent` (`app/agents/BaseAgent.rb`). It handles
  model selection and rotates to the next model when a call fails. Do not build
  a bare `RubyLLM::Chat` in new code.
- **A 401 does not rotate.** `RubyLLM::UnauthorizedError` is re-raised as
  `BaseAgent::UnauthorizedProviderError` instead, because a rejected key is
  fixed by a key and not by a different model — and the local ollama models are
  at the bottom of the same list, so rotating past a 401 answers from a 4k CPU
  model with nothing saying the remote call was refused. Keep any new failure
  class on the same side of that line: rotate on "this model failed", raise on
  "our setup is wrong".
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
  makes it 285 tokens instead of 628, and `:dialogue` takes race *names* only
  because the character sheet below it already carries the speaker's own race
  in full — which took it from 930 tokens to 606.
- **Every generated string goes through `sanitize_string`**
  (`SanitizesGeneratedText`). It is the one seam every model-written value
  crosses, so guards against model output belong there and not beside the field
  that first showed the problem — it strips emoji, and it strips the JSON
  envelope debris (`…”}`) a response cut at a `max_length` boundary leaves
  inside the value. Pass `max_length:` and it also **raises** when the value
  arrived at that cap, because a value at exactly its cap was cut off rather
  than finished. That reading is only safe while the cap is real headroom over
  the shape the description asks for, so the two go together: see
  `Interaction::Schema`, where the caps are the requested shape doubled and each
  description states its own budget. A field the guard rejects fails the turn
  rather than being trimmed — a fragment is not a shorter answer, it is an
  answer whose end is missing.
- **Sanitize where the consumers meet, not at each one.**
  `InteractionAgent#reaction_fields` builds both the narrator prompt and the
  `Interaction` row, so sanitizing there is what makes them agree. Checking the
  record alone would still have let a fragment shape the prose — and the
  narrator's whole job is to write fluently over whatever it is handed, which is
  why a bad field has to be caught before that pass runs.
- **Prefer a fixed table to a prompt** where the value is one of a known set.
  `LocationConnection::DISTANCES` and `::TRAVEL_METHODS` are enums the schema
  reads directly, and `time_to_travel` is derived from them rather than asked
  for. Free prose in a small `max_length` box truncates mid-word, and a
  directional phrase is wrong on the way back.
- Seed prompts with randomized "predetermined details" so repeated runs diverge
  (`Universe::Generator::TONES`, `Character::Generator::BIRTH_PLACES`).

### Conversations are kept, and bounded

Every `BaseAgent` writes a `Chat` and its `Message`s: the prompt, the answer,
the token counts and the model that actually replied. It is lazy — an agent
nobody asks anything leaves no row — and the granularity is **one chat per
agent conversation**, because a chat's messages have to be a list you could
send again: one system instruction, one schema, one model.

- **Which turn a message belongs to is on the MESSAGE** (`messages.scene_id`),
  not on the chat, because a durable conversation spans many turns. Whoever
  creates the `Scene` calls `BaseAgent#attribute_to!`; without it a turn's cost
  cannot be totalled and the debug view shows the turn as unrecorded.
- **A failed attempt is rolled back before the retry.** RubyLLM persists the
  prompt before it sends it, so without the rewind a rotation re-asks on top of
  the failed attempt and hands the replacement model the rejected answer. If you
  add a failure path to `#ask`, rewind on it.
- **`messages.content_raw` is load-bearing.** A schema'd answer is a Hash, and
  RubyLLM stores it there with `content` left nil. Drop the column and every
  schema'd call in this app persists an empty assistant message.
- **One conversation is picked up again rather than started fresh**: talking to
  somebody, keyed `(playthrough, character)` by `Chat.conversation_with`. It is
  the only one where last turn's words are worth replaying, and it is bounded by
  `Chat::HISTORY_EXCHANGES` because `Character#interaction_instructions` inlines
  the whole universe (4,705 characters on the seeded worlds) and the local
  models run in a 4,096-token window. Trimming means **deleting**: `Chat#to_llm`
  rebuilds the request from every persisted message, so history you keep is
  history you send. Nothing is lost — every exchange is an `Interaction` row.
- **The audit trail is pruned as the game runs** (`Chat::KEEP_TURNS`,
  `Playthrough#prune_conversations!`, called at the end of every turn). This is a
  SQLite file on a laptop; the game reads none of it back. Durable conversations
  are never pruned this way.
- **`Playthrough#recap` is how a long game stays inside the window.** It spends
  `scenes.summary` — written by `Scene::Generator` on every arrival, and for
  exactly this — under a fixed character budget, so the narrator sees several
  turns of memory for about what one more full description would have cost. It
  asks no model anything. A narrated turn has no summary and contributes its own
  first sentence; do not "fix" that with a second call per turn.
- **Conversation history is progress, not world**, so `WorldSeed::Exporter`
  leaves it out and says so. See `db/seeds/worlds/README.md`.

### Generating the world

- `Location` is generated in two steps and carries `detail_level`: a **stub** is
  a name plus a one-line `teaser`, a **realized** location has the description
  and lore the player reads. `description` / `lore` are validated only when
  realized, so a stub saves. `Location::Generator#realize!` fills a stub in and
  stubs out its exits; it returns an already-realized location untouched.
  Generation happens once per place — do not add a code path that regenerates one.
- `Scene::Generator.opening(story)` narrates the story's opening arrival once,
  at world-building time, and marks it `is_opening`. `rake game:new` calls it so
  a generated world and a seeded one are the same shape; without it the first
  thing a player reads would depend on how the world was made.
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
- **A world carries its own opening arrival**, as `opening_scene`. It is the one
  `Scene` that is world rather than progress, which is a line the exporter
  otherwise holds hard; `db/seeds/worlds/README.md` has the ruling and the two
  defects it closes. Its natural key is `scenes.is_opening`, it takes its
  `story_timestamp` from the story's `start_time`, and it deliberately does NOT
  stamp `Location#last_protagonist_visit` — a world built months ago is not
  somebody standing in a room. Do not "fix" that skip.
- `rake 'game:export[story_id]'` writes a generated world into that format.
  Rebuild the files with it after a schema change; the format, the rules the
  loader enforces and what is deliberately not exported are in
  `db/seeds/worlds/README.md`.
- The files are **authored artifacts**: edit them by hand. Re-export keeps the
  leading comment block and loses every comment below it.
- **Seeded worlds are not a substitute for generating one.**
  `test/lib/seeded_worlds_test.rb` is the only test that reads them; generator
  tests keep running against `FakeAgent`.

### Story time, and a world that moves on its own

- **`Story#clock` is what time it is in the fiction**, derived from
  `scenes.story_timestamp`, never stored and never the wall clock. A turn's
  scene is the previous scene plus what the turn cost:
  `LocationConnection.travel_minutes` for a journey, `Scene::TURN_MINUTES` for
  everything else. `Location#last_protagonist_visit` holds a story moment too.
  **Do not reach for `Time.current` anywhere on that path** — that was the
  defect, and a player could read it.
- **`WorldMechanic` is the world changing itself on that clock.** `kind` and
  `cadence` are keys into fixed tables in code, each naming a Ruby operation
  over records; a generated or hand-seeded world supplies parameters (which
  locations are `mobile`, how often, the in-fiction reason) and never behaviour.
  Same shape as `LocationConnection::DISTANCES`, and for the same reason. Adding
  a mechanic means adding a class under `app/models/world_mechanic/`, not a
  field somebody can fill in.
- `last_run_at` is a column in story time, so catching up is arithmetic on two
  datetimes: no timer, no job, nothing in memory, and a process that was down
  for a week pays the nights it owes on the next turn.
  `Playthrough::Turn#play` drives it. **It must stay free of model calls** —
  that is the whole claim, and `test/models/world_mechanic_test.rb` asserts it.
- **A mechanic that reports movement it did not perform is the failure mode this
  whole line of work exists to prevent.** So a rearrangement is judged on the
  **adjacency it induces** — the set of unordered pairs of places that end up
  joined — and never edge by edge or on array order: a permutation confined to
  one `mobile` location's own edges passes every per-edge check while leaving
  the graph identical. `ShuffleConnections#valid?` and `#settle` carry the
  argument. If you add a mechanic, the canonical form of the graph is what you
  compare; a night that changes nothing writes nothing.
- A `WorldEvent` is an audit trail, **not a narration source.** Two nights can
  return a place to the same neighbour, so replaying the log announces a change
  the player never experienced. Narration comes from a diff of what they were
  actually shown.
- `db/seeds/worlds/README.md` has the `mechanics` / `mobile` seed format and
  what `shuffle_connections` does to a graph.

### Playing the world

**[README.md](README.md#how-a-turn-works) has the diagram** — every branch of a
turn, and which boxes are model calls versus decisions from records. Read it
before changing the loop; the rules below are what it does not fit.

- **The loop is `Playthrough::Turn`, and its consumer's whole share of it is a
  string and a block.** `NarrationJob` broadcasts the chunks the block is
  yielded; it does not know which branch the turn took. Keep it that way — that
  block is what let SSE be swapped for Turbo Streams over Action Cable without
  touching a line of how prose is generated or persisted.
- The block is yielded **text**, not RubyLLM chunk objects. `Scene::Narrator`
  and `InteractionAgent` both unwrap before yielding; a schema'd branch yields
  its finished paragraph in one piece because it cannot stream at all.
- **`Playthrough::Classifier` resolves names back to records itself**, next to
  the candidate list it is the inverse of. It offers the model a closed enum of
  the room's exits, its cast, what is lying in it and what the player is
  carrying, so an answer either names a record that exists or names `nothing`.
  Do not move resolution into the loop and do not open the enum to free text: a
  fuzzy matcher on this seam guesses about where the player is standing and what
  they are holding.
- A classification the loop cannot act on falls through to `Scene::Narrator`,
  which narrates the attempt. Being unable to do a thing is part of the game;
  silently doing a different thing is not. **And it is counted**: an unresolved
  `move`, `talk`, `take` or `drop` writes a `Playthrough::Drift` row — see
  *Auditing the difference* below.
- **`take` and `drop` are the app moving a row, in that order: the record first,
  the sentence after.** `Item` is in exactly one place — held by a character or
  lying in a location — and the closed set each action resolves against is that
  distinction (`Item.lying_in`, `Item.for_character`). The narrator is then told
  what already happened, via `Scene::Narrator#narrate(command, fact:)`, and has
  no say in whether it is true. **Both directions or neither**: an app that owns
  picking up while the narrator asserts putting down has records that go stale
  the first time a player sets something on a table.
- **Nothing in the app creates an `Item`.** Seeds and tests do. The lazy
  stub-then-realize registry is `ta-item-registry`, and generating a per-room
  inventory ahead of time is explicitly ruled out.
- **What the player typed is `Scene#typed`**, written once in
  `Playthrough::Turn#play` rather than in each branch, so a branch added later
  cannot forget it. Do not go back to reconstructing it from the classifier's
  stored prompt: that is pruned at `Chat::KEEP_TURNS`, which is how it used to
  disappear from older turns.
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

### Auditing the difference

The third clause of the standing constraint, and `rake game:audit` is where it
lives. `Story::Audit` walks stored `Scene`s and reports where the prose and the
records disagree. **Offline, deterministic, no model call, ~20 ms per scene** —
so it can be run over every scene ever written. The debug view shows the same
two tables for one playthrough.

- **Contradictions are proved; drift is witnessed.** They are counted separately
  and must stay that way. A contradiction is the graph or an item record saying
  the narration is wrong. Drift is `Playthrough::Drift`: the player reached for
  something the closed sets do not have, which is how an invented exit becomes
  observable — by its consequences, not by scanning prose for a door.
- **PRECISION, NOT RECALL, and this is not a preference — it was measured.** A
  spike that asked "which known names appear in this prose" raised four flags on
  24 real narrations and all four were false positives: prose refers to places
  through windows and people in memory, so a mention is not a claim. There is
  therefore **no place check and no person check**, and adding one back needs a
  measurement, not an argument. `Story::Audit`'s header comment has the full
  reasoning for each check kept and each cut.
- **`test/fixtures/files/narration_corpus.json` is 24 narrations two remote
  models really wrote**, and `Story::AuditPrecisionTest` pins the exact set of
  flags they earn — currently 8, all true positives, zero false positives.
  Widening a pattern until it flags "There is no revolver, no pistol, no weapon
  of any kind on your person" fails the build, which is the point. If the set
  changes, read every new flag and sign for it before touching `EXPECTED`.
- **A check that cannot be run honestly is recorded as UNJUDGED, not guessed
  at.** A shuffled graph (`WorldMechanic` repoints edges, so today's graph is
  not the one the player walked), a scene with no story time, an item row
  touched after the scene was written. Keep that habit when adding a check.
- `Playthrough::Drift` is deliberately **not** pruned with the conversations. A
  chat is an audit trail nothing reads back; this is the measurement, and a
  measurement that expires cannot be watched over time.

### When a world outlives the schema

A story is written once and then sits in the database while features land
around it, so a database holds stories of several vintages and the play path is
where the difference surfaces. **`rake game:doctor` is where it should surface
instead** — it asks the preconditions the play path asks, ahead of the play
path, and answers in sentences.

- `Story::Doctor` reports and never writes. Every check names, in its comment,
  the code that would otherwise be the first to notice — `PlaythroughsController`
  refusing a story with no realized location, `Story#clock` needing a
  `start_time`, `realize!` returning an exitless room untouched. **When that
  code changes, change the check with it**; a doctor reporting on a precondition
  the game no longer has is worse than none.
- `Story::Repair` acts only on what the doctor marked `:safe` (derivable from
  records already on file) or, with `generate: true`, `:generate` (worth a model
  call — a room, its exits, the opening arrival, and it says how many calls
  before it makes them). **It never invents data to make a validation pass.**
  Anything else is reported as `:manual` and left exactly as it was; for most
  such stories the honest answer is `rake game:delete`.
- `Story::Deletion` prints a manifest, requires the story's **title** typed back
  (an id is precisely what gets mistyped), and destroys the universe only when
  no other story is built on it. `Story::DeletionTest` counts every table before
  and after rather than trusting the `dependent:` options — some are `nullify`,
  `Race`'s is `restrict_with_error`, and an edge's join rows are cleared by two
  separate HABTM declarations on `Location`.
- A dev server caches each table's columns on first use and a migration always
  runs in another process, so a server that was up before `db:migrate` serves
  models built from the old schema — which is `undefined method 'is_opening?'`
  for a column that exists. `StaleSchemaGuard` (development middleware) catches
  that and says restart; see the ROADMAP's *Known issues* for why it reports
  rather than repairs.

### Testing

- Generator tests **must not hit a model.** Use `FakeAgent`
  (`test/support/fake_agent.rb`) with `BaseAgent.stub(:new, agent)`. It records
  the prompts and schemas it was given, so assert on those.
- **`FakeAgent` writes no rows**, which is right for a test about what a
  generator does with an answer and wrong for a test about persistence. For
  that, use `OfflineExchange` (`test/support/offline_exchange.rb`): it stubs
  only `Chat#ask`, so the real `BaseAgent`, real `Chat` and `Message` rows, real
  token counts and real replay are all under test and only the HTTP call is not.
  `test/models/chat_persistence_test.rb` and
  `test/models/playthrough/turn_conversations_test.rb` are the two that use it.
  (`FakeChat` stood in for `RubyLLM::Chat.new`, which nothing constructs any
  more; it is gone.)
- The suite must run with **no API key and no ollama**, and that is now
  enforced rather than hoped for: `test_helper.rb` deletes
  `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `TA_DEBUG_VIEW`,
  `TA_CHAT_KEEP_TURNS` and `TA_CHAT_HISTORY_EXCHANGES`. All five change how the
  app behaves and all five are things you legitimately keep in `.env`. It takes
  **two passes** — once before `config/environment` is required, for the two
  that are frozen into `Chat` constants at class-load time, and once after,
  because `dotenv-rails` loads `.env` during that require and declines to
  override only the keys it finds already set, so the first pass hands it the
  opening to put them straight back. `RubyLLM.config.openrouter_api_key` is
  cleared too, since the initializer took its copy during the same require.
  Anything that needs one sets it inside the test and puts it back
  (`BaseAgentTest#with_env`), never reads it from the environment.
- **Factories must not roll dice.** A random default turns every test that
  reads the value into a lottery, and the failure lands on whoever runs the
  suite next rather than on whoever wrote the test. `location_connections`
  did this and cost a 1-in-35 flake that survived nine full runs and a re-run
  of its own seed — see **Known issues** in `ROADMAP.md` for why parallel
  workers made it unreproducible. Ask for a variation by trait, and pin the
  values a test actually asserts against in the test itself.
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
- `OPENROUTER_API_KEY` (kept in a gitignored `.env`, loaded by `dotenv-rails`,
  or `.envrc` for direnv users — both are gitignored) is strongly preferred
  for interactive work — local models take minutes per structured call, and on
  this machine run on CPU. `BaseAgent` uses remote models automatically when the
  key is set, working down `BaseAgent::REMOTE_MODEL_IDS` — `minimax/minimax-m3`,
  then `mistralai/mistral-medium-3.1` as a fallback. `OPENROUTER_MODEL` overrides
  the front of that list.

## Try it

```bash
rake 'game:new[a debt collector in a city built on a dead god]'
rake game:list
rake game:doctor   # what is wrong with each story, and what can be done about it
rake game:audit    # where the narration and the records disagree -- offline, no model call
bin/rails server   # then open http://localhost:3000 and play it
```

The rake tasks build worlds; the browser only plays them. There is no
`rake game:play` and there is not meant to be — the loop lives in
`Playthrough::Turn`, so a rake front end would be a second UI to maintain for
no new capability.

## The browser interface

Hotwire, and **genuinely zero build**: `propshaft` + `importmap-rails` +
`turbo-rails`, no Node, no `package.json`, no bundler step, no watch process.
That is a hard constraint from the captain, not an accident — `jsbundling-rails`,
`cssbundling-rails`, esbuild, Vite and any npm dependency are explicitly
refused. **If something appears to need one, that is a reason to reconsider the
something; stop and ask rather than adding a build step.**

Views are ERB with an inline `<style>` in the layout. Restyling is
`ta-api-iface`, a stage of its own — do not do it in passing.

- `ApplicationController < ActionController::Base` and `config.api_only = false`.
  That turns on `protect_from_forgery`, so every form goes through `form_with`.
- A browser session is bound to a `Playthrough` by its unguessable `token` in
  `session[:playthrough_token]`. There is no auth, no user model, and the
  captain does not want any: this is a single-player localhost app.
- **A turn is a job, and the play page is one Turbo Stream target.**
  `TurnsController#create` enqueues `NarrationJob` and answers immediately with
  a `replace` of `#turn_log`; the job broadcasts batched prose into `#stream`
  and then replaces `#turn_log` again with the finished turn, the location line
  and the input. There is no end-of-turn reload and no redirect carrying a
  `?command=` — both were consequences of streaming from the request.
  **Start with `bin/dev`** -- foreman, `Procfile.dev`, a `web` and a `jobs` line.
  A web process alone accepts a command and then narrates nothing, because the
  turn is sitting in the queue. Development also runs **`solid_cable`, not
  `async`** -- the turn is broadcast from the worker process and read by a
  WebSocket held in Puma, and `async` broadcasts only within one process. Three
  SQLite databases in development as a result; `bin/rails db:prepare` makes all
  three. Foreman is deliberately **not** in the Gemfile (it conflicts in a
  bundle); `bin/dev` installs it on demand, the way Rails' own generated one
  does. It is a process runner, not a build step.
- **Do not bind port 3000.** The captain runs his own long-lived server there.
  `PORT=3142 bin/dev` moves the whole formation; check a port is free before
  taking it, and never kill anything to free one.
- `turbo_stream_from` lives **outside** `#turn_log`. Inside it, the
  subscription would be torn down and rebuilt at the end of every turn and the
  next turn's tail would go to a channel nobody was listening on.
- The turn log's dimming rule is `.log:not(.streaming) > .turn:last-of-type`.
  Both halves are load-bearing: `streaming` on the wrapper says the newest turn
  is the `#stream` div outside the log, and `:last-of-type` is the marker with
  no class per entry. `PlaythroughsControllerTest`, `TurnsControllerTest` and
  `NarrationJobTest` all assert against those selectors.
- The only JavaScript is **one Stimulus controller**,
  `app/javascript/controllers/play_controller.js`: follow the narration down
  while the player is at the bottom, and put focus back in the input when a turn
  lands. Its scope is the wrapper on `playthroughs/show` and **not `#turn_log`**,
  which a Turbo Stream replaces at the end of every turn -- a controller there
  would be torn down by the very thing it exists to hook. Both its events are
  bound with `@window` / `@document` because neither reaches that element on its
  own.
- **Two things in that controller were found in a browser and will not fail a
  test if you break them.** It must WRAP `event.detail.render` rather than merely
  listen for `turbo:before-stream-render` -- Turbo awaits a repaint before it
  mutates, so the bare event measures stale layout and the follow drifts, 480px
  over one narration -- and it must focus with `preventScroll`. Arming happens in
  `connect()` **and** on `turbo:load`, which is not belt-and-braces: on a full
  page load `turbo:load` fires before Stimulus attaches and never arrives, and on
  a Turbo Drive visit `connect()` runs before Turbo applies the scroll. Each
  covers the case the other gets wrong.

### The debug view

`/playthroughs/:id/debug` — everything one playthrough generated and decided
behind the prose (`Playthrough::Debug`, `DebugController`, `app/views/debug/`).
Three rules govern it, and each exists because breaking it is easy:

- **Read, never write.** It must not generate, mutate a record or advance a
  playthrough — in particular it must never call `Story#catch_up_world!`,
  because looking at a world must not move it. Both tests snapshot every
  table's row count and newest `updated_at` across a full read, and the model
  test reads *every* public method, so an addition that writes fails a test
  that already exists.
- **Its own layout.** It shares no CSS with the game, which is what lets it be
  as dense as it likes while the reading experience stays deferred
  (`ta-api-iface`). Its whole mark on the game is one link on the play page.
- **Gated in the controller**, on `Playthrough::Debug.enabled?` — local by
  default, `TA_DEBUG_VIEW` overrides either way. Not only on the link: there is
  no auth, so a playthrough URL is the whole of a player's credentials.

It shows the branch each turn took **derived from the records that branch left
behind** rather than from a label, because there is no stored label — the
classifier's intent lives in memory inside `Playthrough::Turn#play`. Alongside
it, every prompt sent and every answer that came back, with the token counts and
the model that actually replied, out of `chats` / `messages`. What it still
cannot show — anything older than `Chat::KEEP_TURNS` turns, and the typed
command as a column — it names rather than hiding, and anything new it cannot
show should be added to that list.

**It overlaps `Story::Doctor` and must never be the quieter of the two.** Both
read the same rows: a one-way connection, two directions of one edge that
disagree, a distance or method outside the fixed tables. The division is scope —
the doctor reads every row of every story and is the one to trust; this reads
the room the player is standing in, and says so and links to `rake game:doctor`.
If you add a check to one and the same records are visible on the other, add it
to both or the project has two answers.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
