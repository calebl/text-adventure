# Roadmap

Working status and the task queue for Text Adventure. Update this file as work
lands — it is the single place that records what is built, what is next, and why.

**Core idea:** a text adventure that generates itself as you explore. The world
is generated on demand, and once generated it persists — walk back into a room
and it is the room you left.

## The persistence model

This is the load-bearing design decision, and the schema already encodes it:

- **`Location` is the durable world.** Name, description, `lore`, the
  `location_connections` graph (with `distance` / `time_to_travel` /
  `travel_method`), `parent_location` for containment. Generated once, then
  reused forever.
- **`Scene` is a moment in that world.** `belongs_to :location`, plus a
  `previous_scene` linked list and a `story_timestamp`.

So revisiting a place reuses the persisted `Location` while creating a new
`Scene`. The world stays fixed; time still moves. Generation happens at the
`Location` boundary, never twice for the same place.

## Status

### Done

- Rails 8 app, SQLite, 307 tests green. No longer API-only: `api_only` is off
  and `ApplicationController < ActionController::Base` so it can render ERB.
- Full schema: `Universe` → `Story` → `Location` / `Character` / `Scene` /
  `Interaction` / `Item`, plus the `location_connections` graph.
- `Universe::Generator`, `Story::Generator` — bootstrap a world from a premise.
- `Character::Generator` — one call, one `Character::Schema`. Race, age and sex
  are decided by the generator and stated in the prompt, not asked for: race
  comes from the universe's list so a character belongs to one of its peoples,
  age and sex are rolled so repeated runs diverge. A full name is unique within
  a story (validation plus a unique index on `story_id, LOWER(fullname)`), and
  the generator retries on the same conversation when the model reuses one.
- `Playthrough` model — a session's position in a story (protagonist,
  `current_location`, `current_scene`, session `token`), plus `is_protagonist`
  on `Character`. The browser interface reads and writes it.
- `Race` model — `Universe has_many :races`, `Character belongs_to :race`, with a
  validation that a character's race comes from its own story's universe.
- Explicit bounds on every schema field: a `max_length` plus a stated sentence
  count, or an enum where the value comes from a fixed table. Without them a
  strong model answered "Race of the character" with 2,382 characters of prose;
  the whole character sheet is now ~2,530 characters.
- **Audience-specific universe context.** `Universe#prompt_details(audience)`
  sends each caller the fields it can use — `:full` for story generation
  (1,584 tok), `:character` (1,238), `:place` for building a room (628),
  `:dialogue` for a character speaking (930), `:scene` for arriving in a room
  already built (285). The whole record used to go to all of them.
- **`LocationConnection` distances and travel methods come from fixed tables**
  (`DISTANCES`, `TRAVEL_METHODS`), and `time_to_travel` is derived from the two
  rather than generated. The values are direction-neutral because connections
  are written both ways from one answer.
- `BaseAgent` — RubyLLM wrapper with model fallback on failure.
- `rake game:new[premise]` / `rake game:list` — generate and inspect worlds.
  `game:new` now also generates and realizes the story's opening location.
- `InteractionAgent` — two-pass character-then-narrator dialogue.
- `ruby_llm` 1.16 + `ruby_llm-schema` 0.4, on RubyLLM's association-based
  `acts_as` API. The `models` table is the model registry now; seed it with
  `bin/rails db:seed`, or nothing resolves.
- AI-layer test coverage: `Narrator`, `InteractionAgent`, the three schema
  classes, and `Chat` / `Message` / `ToolCall` / `Model`, all stubbed at the
  RubyLLM boundary.
- **Location stubs and on-demand realization.** `Location#detail_level` is
  `stub` or `realized`; `description` and `lore` are required only once a
  location is realized, so a stub is a name plus a one-line `teaser` and
  nothing more. `Location::Generator#realize!` writes the description and lore,
  then creates a stub `Location` for each exit plus the `location_connections`
  rows — in **both** directions, so the way back exists before the far side is
  ever realized. It returns an already-realized location untouched: generation
  happens once per place, never twice. `Location::Generator.opening(story)`
  names the first location from the story's preface and realizes it.
  `Location#exits` is the exit list the game loop will resolve movement against.
- **A browser you can play in.** `bin/rails server`, open `localhost:3000`,
  pick a story, start a playthrough, read the preface, type an action and watch
  the narration stream in token by token; reload and the log is still there.
  Deliberately ugly and deliberately small: three routes, four ERB templates,
  an inline `<style>`, six lines of `EventSource`, and no gems at all — no
  Node, no importmap, no propshaft, no Turbo, no Action Cable.
- `Scene::Narrator` — one unschema'd `BaseAgent` call that streams prose to a
  block and persists the finished text as a `Scene` in an `ensure`, so a
  browser that closes mid-turn does not lose it. It takes a block precisely so
  swapping SSE for Turbo Streams later touches nothing but the consumer.
- `BaseAgent#ask` forwards a block to RubyLLM, which turns the call into a
  token stream.
- **`Scene::Generator`** — narrating arrival in a location, as one schema'd
  `BaseAgent` call (`Scene::Schema`: `description` + `summary`). It is the
  sibling of `Scene::Narrator`, not a copy of it: the narrator answers what the
  player *typed* and streams unschema'd, this writes the record of walking
  *into* a place and stays schema'd like everything else. Arrival reads as
  discovery or as coming back depending on `Location#last_protagonist_visit`,
  with the gap stated in words. `scene.characters` is decided from records —
  the protagonist, anyone `is_companion`, and whoever was in the last scene
  played in that location — never asked of the model. Measured against a real
  generated world: **1,302 input / ~200 output tokens** per arrival
  (system 67 + prompt 1,127 + schema 108), which is the whole cost of walking
  back into a room that already exists, and +37% input on top of realizing a
  new one. The per-turn path is untouched. It writes `scenes.summary`, which
  nothing had ever written.
- **Two playable worlds in the repo.** `bin/rails db:seed` loads every YAML file
  in `db/seeds/worlds` — offline, idempotent, matched on natural keys — so a
  fresh clone can be played immediately without minutes of live generation or an
  API key. `rake 'game:export[story_id]'` dumps a generated world into that
  format, which is what keeps the files from rotting at the first schema change;
  the files are authored artifacts after that and are meant to be hand-edited.
  `the-unrecorded-hour.yml` is shaped on purpose: its opening office has two
  ways out, one of them a *realized* supply closet whose only exit is back into
  the office. That is the dead end `Location::Generator` cannot produce on its
  own, since it leaves every neighbour a stub and a stub has no exits at all.
  See `db/seeds/worlds/README.md` for the format and
  `test/lib/seeded_worlds_test.rb` for the drift guard.
- **A world carries its own opening arrival.** `rake game:new` narrates it once
  with `Scene::Generator.opening`, the exporter writes it into the seed file as
  `opening_scene`, and the loader loads it — so starting a playthrough makes no
  model call at all and the first thing a new player reads is real narrated
  prose rather than the room's own description standing in for it. It is the
  ONE `Scene` that is world rather than progress, and the exporter and
  `db/seeds/worlds/README.md` both say why at length: nobody made it happen, it
  is identical for everyone who plays, and it is the answer to a question the
  world is supposed to know. `scenes.is_opening` is the marker and the loader's
  natural key both (a `Scene` has none of its own); the seed format is at 2.
  Three things fall out of it:
  * **A seeded world has somebody to talk to on turn one.** The cast is
    hand-authored in the file, `Scene::Generator.characters_present` reads the
    last scene that recorded anyone, so the `talk` branch is reachable in both
    checked-in worlds for the first time. Grenn is in the doorway of Room 3;
    Sub-Inspector Rowe is in the doorway of Ward Office 12, forty minutes early.
  * **An opening `Scene` deliberately does not stamp `last_protagonist_visit`.**
    It is created when the world is BUILT, which can be months before anybody
    plays; stamping then would narrate the first walk back into the opening room
    as a return after however long the file had been on disk.
    `PlaythroughsController#create` stamps it when a player actually arrives,
    which is why the explicit `mark_protagonist_visit!` #73 dropped is back.
  * **`Scene#next_scene` is now `#next_scenes`.** Every playthrough of a story
    starts on the same opening `Scene`, so the forward direction is a genuine
    branch point and a `has_one` over it was a wrong answer dressed as a right
    one. Walking backwards from `current_scene` was never affected, so the turn
    log did not move.
- **The game loop.** `Playthrough::Turn` is the whole of it: one schema'd
  classification call (`Playthrough::Classifier`, five intents from a fixed
  table plus a target enum built per turn from the room's exits and its cast),
  then move / talk / narrate. **Movement is the load-or-generate seam:**
  `Location::Generator#realize!` writes a stub out in full and returns an
  already-realized room untouched, so walking somewhere new generates it once
  and walking back reads what was written, then `Scene::Generator` narrates
  arriving and the playthrough moves only once both calls have landed. Wired
  into the browser through the same three routes: `NarrationsController` hands
  the command to `Playthrough::Turn` and forwards the chunks it yields.
  Movement costs ~415 input tokens for the classification (system 189 + prompt
  66 + schema 160) on top of whatever it leads to -- an arrival is 1,302, a
  narrated turn ~849 -- so the classifier is about a third of a narrated turn
  and a quarter of an arrival.
- **Talking to a character, kept.** The `talk` branch routes to
  `InteractionAgent`, which now goes through `BaseAgent` on both passes -- so
  the character pass inherits `verify_schema_honored!` and both inherit model
  fallback, and the unresolvable
  `cognitivecomputations/dolphin-mixtral-8x22b` it used to hardcode is gone.
  `#ask` returns an `Exchange` of the prose and the character's five structured
  fields instead of throwing the structured half away, so a talk turn keeps
  **two** records: the `Scene` the player reads (with `scene.characters` set to
  the protagonist and whoever they spoke to, which is what tells the next turn
  in that room who is standing in it), and the first `Interaction` row this app
  has ever written. The turn log names who was spoken to.

### Not built yet

Everything left is in **Next up** below. The loop moves, talks and narrates.
What it does not yet do is survive a closed tab, remember more than the last
scene, or look like anything -- stage 5 (jobs, Turbo over Action Cable,
conversation persistence) and stage 6 (visual style) of the browser plan.

## Next up

### 1. The protagonist

- [x] The player is a `Character` with `is_protagonist` set — at most one per
      story, enforced by validation and exposed as `Story#protagonist`.
- [x] Position lives on a separate `Playthrough` model (`story`, `character`,
      `current_location`, `current_scene`, unguessable unique `token`) rather
      than columns on `Story`. Same split the schema already makes between the
      durable `Location` and the momentary `Scene`: the world is not somebody's
      progress through it, and one generated world can be played twice. The
      `token` is what will bind a browser session to a playthrough.
- [x] `PlaythroughsController#create` creates the `Playthrough`, points it at
      `Story#protagonist` and at the story's first location, and binds the
      browser session to it with the playthrough's `token`. No auth, no user
      model — a single unguessable token in the cookie is the whole mechanism.
- [ ] `Character::Generator` still never sets `is_protagonist` (nor
      `is_companion`), so a generated story has no protagonist and the
      playthrough's `character` stays nil. Narration copes; it should not have to.

### 2. Scene generation

- [x] `Scene::Generator` — given a `Location` and the `previous_scene`, narrate
      arriving and persist the `Scene`. Reads differently on a first visit
      versus a return: `Location#last_protagonist_visit` decides which, and
      `#time_since_last_visit` puts the gap in the prompt in words. Both are
      read **before** `Scene.create!`, because `Scene`'s `after_create` stamps
      the visit — read them after and every return is "less than a minute ago".
- [x] Populate `scene.characters` from who is present.
- [x] It does not advance the `Playthrough` itself, by design: it returns the
      scene and lets the caller place the player, because moving the player is
      the game loop's decision and it also has to set `current_location`.
      `Playthrough::Turn#move_to` is that caller.
- [x] `#holdovers` read the plain latest scene in a location, so any turn that
      was not an arrival emptied the room -- only an arrival records a cast, and
      a `Scene::Narrator` turn writes a scene with nobody in it. It now reads
      the last scene that recorded anyone. Unreachable before movement existed.
- [x] `Scene::Generator.characters_present(location)` answers the same question
      without building an arrival, so `Playthrough::Classifier` offers exactly
      the people the arrival paragraph introduced.

### 3. The game loop

- [x] Classify player input: move / talk / examine / take / other, in one
      schema'd `BaseAgent` call. `Playthrough::IntentSchema` is a factory rather
      than a declared schema because `target` is an enum built per turn from the
      room's exits and its cast: the loop has to turn the answer back into a
      `Location` or a `Character`, and "north" resolves to nothing. Closing the
      set means the model names something that exists or names `nothing`, and
      there is no third answer to write a matcher for.
- [x] On **move**: resolve the target from `Location#exits`, realize it if it is
      a stub, narrate arriving, and point the playthrough at both. The
      load-or-generate seam, and there is no branch in it: `realize!` returns an
      already-realized location untouched, so the same four lines cover walking
      somewhere new and walking back.
- [x] On **talk**: `InteractionAgent`, through `BaseAgent`. The exchange keeps
      two records -- the `Scene` the player reads and the `Interaction` the
      character felt.
- ~~`rake game:play[story_id]`~~ -- skipped on purpose. The browser is the
      playable interface; the rake tasks build worlds and the browser plays
      them. Do not add a `game:play` task.
- [ ] **A move is 3 model calls and does not stream**, so the player watches a
      blinking cursor for as long as realizing a room takes. Nothing is wrong;
      it is just slow, and the job-and-cable stage below is where it is fixed.
      Do not "fix" it by schema-ing less -- `Scene::Generator` cannot stream.
- [ ] `examine` and `take` are told apart and then handed to `Scene::Narrator`
      like anything else. They are classified so the branch exists when items
      do; nothing acts on them yet.

### 4. Persistence and history

- [ ] Wire up the `chats` / `messages` / `tool_calls` tables. `Chat`, `Message`
      and `ToolCall` already call `acts_as_chat` and friends, but every agent
      builds a bare `RubyLLM::Chat`, so **nothing is ever persisted**. Quitting
      loses all conversation state.
- [x] **Persist an `Interaction` at all.** `InteractionAgent#ask` returns the
      structured reaction alongside the prose now, and `Playthrough::Turn#talk_to`
      writes the row.
- [ ] `Interaction#inner_resolution` and `#summary` are still never written, so
      `Interaction#completed?` is always false. `inner_resolution` is what a
      character decided as a result of the exchange, which is a second call
      nothing asks for yet.
- [ ] Summarize old scenes so long playthroughs stay inside the context window.

### 5. Interface

The first playable browser interface has landed (see **Done**). What it still
owes, roughly in order:

- [ ] Echo past commands in the turn log. A `Scene` has no column for the input
      that produced it, so a reloaded transcript is narration only. Needs a
      migration, so it waits for one.
- [ ] Jobs, Turbo Streams over Action Cable, and durability. SSE holds one Puma
      thread per open stream and loses the live view on reload; the persisted
      `Scene` is the only thing that survives today. Swap `NarrationsController`
      for a job broadcasting batched chunks (~20 chars) once the real token rate
      is known. `Scene::Narrator` already takes a block so only the consumer
      moves. That stage brings `propshaft`, `importmap-rails` and `turbo-rails`
      — do not install them before it.
- [ ] Visual style. Deferred on purpose until there is a real loop to look at.
- [x] A playthrough starts in the story's first **realized** location — the
      opening room `game:new` generates. Stubs are skipped: they are exits
      nobody has walked into, with a name and a teaser and nothing to read.
- [x] **The turn log starts where the story starts.** The opening room used to
      be read out *above* the log and only while the log was empty, so the
      first turn — the first thing to put a `Scene` in that log — made the
      opening text vanish from under the player. `PlaythroughsController#opening_scene`
      writes it as a `Scene` when the playthrough starts, so it stays where it
      was written. Two things fall out: `Scene`'s after_create stamps
      `last_protagonist_visit`, so the explicit `mark_protagonist_visit!` is
      gone, and the first move now gets a real `previous_scene` instead of
      `Scene::Generator` being told "this is where the story opens" one room
      too late. It is a room description standing in for an arrival nobody
      narrates, which is the honest limit of it — see **Next up** below.
- [x] **Where the opening arrival comes from.** It comes from the world now —
      `Scene::Generator.opening` at `rake game:new` time, `opening_scene` in the
      seed file, loaded with everything else. See **Status → Done**. The ruling
      on the "progress rather than world" line, and the natural key a `Scene`
      did not have, are both written up in `db/seeds/worlds/README.md`.
- [ ] A story generated before opening locations existed has nowhere to start,
      so the index lists it without a Play button and `create` refuses it. That
      whole branch can go once no such stories are left, or once realizing a
      location on demand is cheap enough to do inside a request.

## Known issues

- **"How long since you were last here" is wall-clock time, not story time.**
  `Location#time_since_last_visit` is `Time.current - last_protagonist_visit`,
  and `Scene::Generator` puts it into the arrival prompt in words. So a player
  who closes the tab and comes back a week later is told, in fiction, that they
  were gone a week. `Story#start_time` and `Scene#story_timestamp` exist to
  hold story time and nothing derives an in-fiction clock from them yet;
  `LocationConnection#time_to_travel` is the other half of that clock. Fix it
  in one place — the elapsed value `Scene::Generator#generate!` reads — rather
  than at each call site.
  The worst version of this — a seeded world dating the protagonist's presence
  to whenever the file was written, so the first walk back into the opening room
  reads as a return after however many months — is closed: an opening `Scene`
  does not stamp the visit, and `PlaythroughsController#create` does it when a
  player arrives. The wall-clock-within-a-session defect above is untouched.
- **Nothing records where a character stands.** `characters` has no location
  column, so `Scene::Generator#characters_present` answers from the three
  things the app can actually know: the protagonist, anyone `is_companion`,
  and whoever was in the last scene played in that location. A place nobody has
  visited and no companion follows you into is therefore empty. That is honest
  rather than correct, and it is what `ta-narrator-memory` — the narrator
  creating characters by tool call — plugs into.
  It used to mean you could not talk to anyone in a freshly seeded world at all.
  **That is fixed:** both checked-in worlds now ship an `opening_scene` with a
  hand-authored cast, so `characters_present` answers with somebody besides the
  protagonist and the `talk` branch is reachable from turn one. The underlying
  gap is unchanged — walk two rooms away and the world is empty again, because
  nothing records where a character stands. That is still `ta-narrator-memory`.
- **`ActionController::Live` costs one Puma thread per open stream.** Puma runs
  3 threads by default, so three people reading narration at once stalls the
  whole site for everyone else. Irrelevant for one player on localhost; raise
  `RAILS_MAX_THREADS` before that changes.
- **A turn dies with its connection.** Closing the tab mid-stream kills the
  generation. `Scene::Narrator` persists whatever it had in an `ensure`, so the
  player keeps the part that was written, but the rest is gone. Fixed properly
  by the job-and-cable stage.
- **RubyLLM's model registry is a process-wide memoized snapshot.**
  `RubyLLM::Models.instance` is built once, out of the `models` table, falling
  back to the registry JSON the gem ships only when that table is empty. It is
  never re-read. In tests that made model resolution depend on test order:
  registry rows are created inside transactions that roll back, so a snapshot
  taken by one test resolved the next test's model names against rows that no
  longer existed. `test_helper.rb` now drops the memo before every test. In
  development and production the same memoization means a `models` row added
  after boot is invisible until the process restarts or something calls
  `Model.refresh!`.
- **`sanitize_string` used to delete every digit a model wrote.** Its regex was
  `\p{Emoji}`, a property that matches the ASCII digits, `#` and `*` because
  those are the bases of the keycap emoji — so "80 meters" was stored as
  "meters". It now matches `\p{Extended_Pictographic}` instead. Any text
  generated before this fix has silently lost its numbers.
- **The move path does not work on local models, and rotation cannot reach the
  one that does.** Measured on a real playthrough: `gemma3:12b`, `gpt-oss:20b`
  and `qwen3:8b` all return `Scene::Schema` with `description` and no
  `summary`, so `verify_schema_honored!` rejects all three and the turn ends in
  an SSE `error` with the player left where they were. `qwen3:4b` returns both
  fields — but it is 4th in `LOCAL_MODEL_OPTIONS` and `BaseAgent::MAX_ATTEMPTS`
  is 3, so rotation stops one short of it. Raising the cap is not obviously
  right: four attempts at up to a 600s timeout is 40 minutes for one failed
  turn, and `qwen3:4b` took **490s** for that single arrival call. Set
  `OPENROUTER_API_KEY` to move. The classification call is not affected — it
  honored its schema on `gemma3:12b` first try, including the per-turn enum.
  This is also why the loop's **talk** path was verified end to end in a
  running browser session against ollama and the **move** path was not: the
  classification and the arrival call were each verified live and separately,
  but the composition of the two is covered by `test/models/playthrough/turn_test.rb`
  rather than by a live playthrough. A single local arrival is ~8 minutes of
  CPU. Anyone with a key should walk the loop once and delete this paragraph.
- **Local models are slow, and they run on CPU here.** `ollama ps` reports
  `size_vram: 0`, so nothing is GPU-accelerated on this machine. Measured on a
  small 3-field schema: `gemma3:12b` ≈ 39s, `qwen3:8b` ≈ 92s (it burns the budget
  on thinking tokens). Paragraph-length schemas like `Universe::PhysicalSchema`
  take *many* minutes and exceeded RubyLLM's 120s default request timeout, which
  surfaced as `Faraday::TimeoutError` and looked exactly like a broken model.
  `config.request_timeout` is now 600s, overridable via `LLM_REQUEST_TIMEOUT`.
  Set `OPENROUTER_API_KEY` for anything interactive; `BaseAgent` prefers remote
  models automatically when the key is present.
- **A model that ignores your schema is worse than one that fails.** OpenRouter's
  `:free` endpoints frequently accept a JSON schema and answer in prose anyway --
  `minimax/minimax-m3:free` does exactly this, while the paid `minimax/minimax-m3`
  honors it. Ruby's `String#[]` does substring matching, so `content["fullname"]`
  on a prose response returns `"fullname"` rather than raising, silently poisoning
  the record. `BaseAgent#verify_schema_honored!` now raises `SchemaIgnoredError`
  and rotates to the next model. It also rejects a Hash that came back missing
  required fields, which is the same failure one step further along.
  **Before adding any model, check it:**
  `curl -s https://openrouter.ai/api/v1/models | jq '.data[] | select(.id == "MODEL") | .supported_parameters'`
- **Watch the ollama context window.** `ollama ps` reports `context_length: 4096`
  for these models. The universe prompt plus ten paragraphs of output is already
  close to that, and `Story::Generator` still feeds the whole universe back in
  (`:full` is the right audience there). `Scene::Generator` fits — 1,302 input
  tokens on the `:scene` audience, measured — but it carries exactly one prior
  scene. A playthrough that wants more history than that has to summarize
  first; `scenes.summary` is now written on arrival for that purpose.
- **`Location::Generator#realize!` can leave a room with no way out.** The
  description is saved before the exits call so an exits failure does not throw
  away the more expensive of the two calls — but `realize!` then returns that
  realized room untouched on a retry, which is the "generate once per place"
  guarantee working against recovery. Finishing such a room means calling
  `Location::Generator#write_exits!` directly. Harmless until the game loop
  resolves movement against `Location#exits`; give it a real completeness
  marker before then.
- **`Location#parent_location` is never written.** Every stub is created from an
  exit, and an exit says where you can walk, not what is inside what. The dead
  `parent_context` branch in `Location::Generator` is gone; the association and
  column remain, so a caller has to write it before any prompt can read it.
- **`Narrator`** (`app/models/narrator.rb`) predates the schema and never reads
  a single database record — no `Scene`, no `Location`, no `Character`. It is a
  freestanding chat prompt whose system directive describes tools
  (`get_scene_details`, `get_universe_rules`) that do not exist. Either rewrite it
  as the narration layer over `Scene::Generator` or delete it; do not build on it.
- **A talk turn is not durable, where a narrated turn is.** `Scene::Narrator`
  persists partial prose in an `ensure`, so closing the tab mid-stream keeps
  what was written. `Playthrough::Turn#talk_to` has no equivalent: the
  character pass has already been paid for and the narration is streaming, and
  a disconnect loses both calls with nothing recorded. Deliberately not fixed
  with a second bespoke `ensure` -- the job-and-cable stage deletes that shape
  for the narrator too, and should cover both paths at once.
- **`Narrator::DEFAULT_MODEL` does not resolve.**
  `cognitivecomputations/dolphin-mixtral-8x22b` is in neither the bundled
  registry nor the seeded `models` table, so `Narrator.new` raises
  `RubyLLM::ModelNotFoundError`. Pre-existing — it failed on ruby_llm 1.8.2 too.
  `app/models/narrator.rb` is now the only place left holding that model id;
  `InteractionAgent` went through `BaseAgent` and stopped hardcoding it.
- The migration to the new `acts_as` API left `chats.model_id_string` and
  `messages.model_id_string` behind — dead columns the generator's `down` step
  needs. Drop them if the migration is ever squashed.
- The `async` gem is still in the `Gemfile` but no longer used after
  `Character::Generator` was made synchronous.
