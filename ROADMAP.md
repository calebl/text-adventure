# Roadmap

Working status for Text Adventure. Update this file as work lands — it is the
single place that records what is built, what is next, and why. The queue
itself lives in firstmate (`tasks-axi list --state queued`); this file says
what each queued item *is* and why it sits where it does.

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

## The standing constraint

The captain's ruling, and it now governs design decisions across the project:

> *"I would rather not depend on the narrator doing what we tell it to do. We
> should prompt it with rules if that makes it more likely that it will follow
> them though and save on tokens. But I think we ultimately need a verification
> process."*

Both halves, not one: **inform and verify.** Prompt the narrator with the
world's laws — it is cheap and it raises the odds — but never let a guarantee
rest on its compliance. *Gate the state, inform the prose, audit the
difference.* An unenforced narration rule costs a sentence; an unenforced state
rule costs the game.

The README's turn diagram already states it best, in the colours: purple is a
model call, teal is the app deciding from records it holds, and every branch is
taken on a record rather than on a label a model wrote — see
[README.md](README.md#how-a-turn-works). The pattern to copy: *do not ask a
model what should happen; ask it to pick from a set the app closed, then have
the app act.* `Playthrough::Classifier` is the worked example — it is a model
call, so it can be **wrong**, but its answer is a closed enum built from the
room's real exits and cast, so it cannot be **out of bounds**.

The full audit of every planned piece of work against this constraint is in
`data/ta-direction/report.md` §0.1 (firstmate repo).

## Status

### Done

- **`mistralai/mistral-medium-3.1` is the default hosted model**, with
  `minimax/minimax-m3` second. The captain's ruling on recommendation 2 of the
  refusal sweep: mistral refused 0 of 52 charged cases against minimax's 8 of 51
  (16%), is 3–4× faster (median 2.4s against 8.8s), and dropped no required
  `Interaction::Schema` field where minimax dropped them on 29% of talk turns.
  The accepted cost is thinner prose — about 60% of minimax's length narrating
  and under a third on the interaction path. The order also costs the safety
  net: a `RefusalError` rotation now falls to minimax, the model that refuses,
  rather than to a model known to comply. Stated on the constant, not buried.

- Rails 8 app, SQLite, 976 tests green. No longer API-only: `api_only` is off
  and `ApplicationController < ActionController::Base` so it can render ERB.
- Full schema: `Universe` → `Story` → `Location` / `Character` / `Scene` /
  `Interaction` / `Item`, plus the `location_connections` graph and the
  `world_mechanics` / `world_events` pair that moves it.
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
  `:dialogue` for a character speaking (606), `:scene` for arriving in a room
  already built (285). The whole record used to go to all of them.
  `:dialogue` was 930 until the race list came out of it: the speaker's own
  race sits in the character sheet directly below, and that block is re-sent on
  every turn of every conversation. It took a whole talk turn from 2,431 input
  tokens across three calls to 2,107.
- **`LocationConnection` distances and travel methods come from fixed tables**
  (`DISTANCES`, `TRAVEL_METHODS`), and `time_to_travel` is derived from the two
  rather than generated. The values are direction-neutral because connections
  are written both ways from one answer.
- `BaseAgent` — RubyLLM wrapper with model fallback on failure. A rejected key
  is the one failure it does NOT rotate past: it raises
  `BaseAgent::UnauthorizedProviderError` naming the environment variable,
  because rotating a 401 down to the local models answered from ollama with
  nothing saying the remote call had been refused.
- `rake game:new[premise]` / `rake game:list` — generate and inspect worlds.
  `game:new` now also generates and realizes the story's opening location.
- `InteractionAgent` — two-pass character-then-narrator dialogue.
- `ruby_llm` 1.16 + `ruby_llm-schema` 0.4, on RubyLLM's association-based
  `acts_as` API. The `models` table is the model registry now; seed it with
  `bin/rails db:seed`, or nothing resolves.
- AI-layer test coverage: `InteractionAgent`, the three schema
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
- **A browser you can play in.** `bin/dev`, open `localhost:3000`, pick a story,
  start a playthrough, read the preface, type an action and watch the narration
  arrive; reload and the log is still there. Deliberately ugly and deliberately
  small: two routes, five ERB templates, an inline `<style>`, and one Stimulus
  controller.
- **Jobs, Turbo Streams over Action Cable, and durability.** A turn is a
  `NarrationJob`, not a request. `TurnsController#create` enqueues it and
  answers immediately with the command echoed back; the job broadcasts prose in
  ~20-character batches into `#stream` and then replaces the whole `#turn_log`
  with the finished turn, the location line and the input. Four things that
  fixes: **the reload at the end of every turn** is gone, and with it the scroll
  position it threw away; **one Puma thread per open stream** is gone, because
  WebSockets do not consume request threads; and **a turn no longer dies with
  its connection** — close the tab mid-narration and it lands anyway, and is
  broadcast to whoever reopens the page. `propshaft` + `importmap-rails` +
  `turbo-rails` and still **zero build**: no Node, no `package.json`, no watch
  process. Solid Queue and Solid Cable both run in development, each against its
  own SQLite database — `async` cable would broadcast the turn into the worker
  process and nobody would ever see it.
- **`bin/dev` starts the whole development environment.** `Procfile.dev` with a
  `web` and a `jobs` line under foreman, both logs interleaved, Ctrl-C stopping
  both. Foreman is deliberately outside the Gemfile and installed on demand, the
  way Rails' own generated `bin/dev` does it: a process runner, not a build step.
  `PORT=3142 bin/dev` moves the formation off 3000.
- **One Stimulus controller**, `play_controller`, scoped to a wrapper that no
  Turbo Stream replaces — the log's own `#turn_log` is replaced every turn, and
  the controller's whole job is to hook that replacement. It follows the
  narration down while the player is at the foot of the log and puts focus back
  in the input when a turn lands. Three of its properties were established in a
  browser rather than by a test and are commented as such.
- `Scene::Narrator` — one unschema'd `BaseAgent` call that streams prose to a
  block and persists the finished text as a `Scene` in an `ensure`. It takes a
  block precisely so swapping SSE for Turbo Streams touched nothing but the
  consumer, and that is exactly how the swap went: `NarrationJob` replaced the
  SSE controller and not one line of this class moved.
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
  into the browser through two routes: `NarrationJob` hands the command to
  `Playthrough::Turn` and broadcasts the chunks it yields.
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

- **`.env` loads.** `dotenv` was in `Gemfile.lock` only transitively via kamal,
  so a key placed in `.env` was silently ignored by `bin/rails` and `rake`, and
  the docs pointed only at `.envrc`. `dotenv-rails` is a direct dependency now;
  both files work.
- **A conversation's structured fields are sanitized, and a truncated one
  fails the turn.** The talk path was the one generated-string path in the app
  that never crossed `sanitize_string`, so the guard below covered every field
  the app writes except the six a conversation writes every turn. Found by
  reading the debug view against a real conversation: one stored `pre_feeling`
  was exactly its 60-character cap ending `"hopeful for a (v"`, its
  `pre_thought` exactly the 200-character cap, another `pre_thought` ending
  `"so as not to r"` — and the narrator pass, handed the fragment by string
  key, wrote fluent prose over it, so the player could not tell. Two fixes:
  `Interaction::Schema`'s caps are now headroom over the shape asked for rather
  than the shape itself (a sentence 320, two sentences 480, three
  comma-separated words 120, each stated in the field's own description), and
  `InteractionAgent#reaction_fields` — the one seam the narrator prompt and the
  `Interaction` row share — sanitizes every field against its own cap. Arriving
  AT the cap now raises `SanitizesGeneratedText::TruncatedTextError` rather than
  being written: with caps this wide a finished answer lands nowhere near the
  ceiling, so landing on it means the provider cut the answer off. It is caught
  before the narrator pass runs, so no prose is ever paid for or read over a
  fragment. The scene's own prose is untouched, for the same reason
  `Scene::Narrator`'s is: it is unschema'd streaming text, so there is no cap
  for it to be cut at.
- **Generated text is guarded against `max_length` truncation.** A response cut
  at a schema boundary leaves the JSON envelope inside the value — a `summary`
  came back at exactly its 200-character cap ending in a smart quote and a
  closing brace, persisted as narrative content. `SanitizesGeneratedText` now
  strips a trailing run of quote/brace/bracket punctuation, and because it is
  the one seam every generated string crosses, that covers every schema in the
  app rather than the field it was first seen on.
- **The dead `Narrator` is gone.** `app/models/narrator.rb` predated the schema,
  read no database record at all, described `get_scene_details` /
  `get_universe_rules` tools that were never implemented, and named a model id
  that does not resolve — so `Narrator.new` raised. It went with
  `rake narrator:interact` and its test. `Scene::Narrator`, the live narration
  path, is unrelated and untouched. The stale `CLAUDE.md` sections that
  described it as the primary AI interaction class and the main development
  interface are corrected.
- **The world moves on its own clock.** The first slice of the rules-engine
  direction, and the purest expression of the standing constraint above: no
  model is involved anywhere in it. `Story#clock` is what time it is in the
  fiction, derived from `scenes.story_timestamp` rather than stored, and every
  `Scene` now costs story time — an arrival pays
  `LocationConnection.travel_minutes` for the edge actually walked, every other
  turn pays `Scene::TURN_MINUTES`. `Time.current` is gone from that whole path.
  `WorldMechanic` is a fixed catalogue of Ruby operations over records on a
  story-time schedule: `kind` and `cadence` are keys into tables in code, so a
  world supplies parameters and never behaviour, and `last_run_at` is a column
  in story time so catching up is arithmetic — no timer, no job, nothing in
  memory, and a process that was down for a week pays the nights it owes on the
  next turn. `Story#catch_up_world!` runs first thing in `Playthrough::Turn#play`
  at ~90 µs and **0 tokens** when nothing is due. The one `kind` is
  `WorldMechanic::ShuffleConnections`, which permutes rather than chooses so
  every location keeps its degree, checks connectivity and that the induced
  adjacency actually changed before applying, and is
  deterministic per (story, night); it is hand-written into
  `the-lunar-cartographer.yml`, whose universe has claimed since it was
  generated that Nocturnis rearranges itself nightly. `WorldEvent` is the audit
  trail and deliberately **not** a narration source — over two nights a shuffle
  can return a place to the same neighbour, so replaying the log would announce
  a change the player never experienced.
- **The story doctor** — `rake game:doctor`, `rake game:repair`,
  `rake game:delete`. A world outlives the schema that generated it, so a story
  written in August sits next to one written in September and the difference
  only shows up as a stack trace mid-turn. `Story::Doctor` asks the questions
  the play path asks, ahead of it, and answers in sentences a person can act on;
  `Story::Repair` fixes only what is derivable from records, keeps model-call
  repairs behind `GENERATE=1`, and **never invents data to make a validation
  pass**; `Story::Deletion` prints what will go, requires the story's own title
  back before it goes, and takes the universe only when no other story is built
  on it. See `AGENTS.md` → *When a world outlives the schema*.
- **The debug view** (`ta-debug-view`, PR #81). One page per playthrough
  showing what the game decided and generated behind the prose, organised
  around the turn just taken: the branch it took **derived from the records
  that branch left behind** and the evidence for it, the story-time cost
  checked against the fixed tables that were supposed to decide it, the scene
  and the place with stub-versus-realized called out, the exits in both
  directions, the closed set `Playthrough::Classifier` will accept next turn
  with the prompt it would build, `Story#clock` against the playthrough's own
  moment, every mechanic with when it fires next, the `WorldEvent` audit trail,
  and the durable background behind `<details>`. Its own route, controller and
  layout, so it shares no CSS with the game and cannot change how the story
  reads. Gated in the controller on `Playthrough::Debug.enabled?` — local by
  default, `TA_DEBUG_VIEW` overrides — because this app has no auth and a
  playthrough URL is the whole of a player's credentials. **Read, never write,
  asserted rather than intended:** both tests snapshot every table's row count
  and newest `updated_at` across a full read. It deliberately does not call
  `catch_up_world!`; a mechanic with nights owed is reported, not run.
  Built over existing records only, at the time — and `ta-chat-persist` has
  since given it the capture it was waiting for.
- **Conversations are kept** (`ta-chat-persist`). Every `BaseAgent` writes a
  `Chat` and its `Message`s: the prompt, the answer, the token counts and the
  model that actually replied. One chat per agent conversation, because a chat's
  messages have to be a list you could send again; which TURN a message belongs
  to is on the message, because one conversation spans many turns. Three things
  come out of it:
  - **The debug view stopped naming an absence.** Per-turn cost, per-playthrough
    cost, the answering model — and a rotation past a failed model is visible as
    two models on one turn.
  - **One conversation is picked up rather than started fresh:** talking to
    somebody, keyed `(playthrough, character)`. A character remembers what you
    said last turn, across a server restart. It is bounded to
    `Chat::HISTORY_EXCHANGES` because `Character#interaction_instructions`
    inlines the whole universe (4,705 characters) and the local models run in a
    4,096-token window; what falls off the chat is on `Interaction`, in full,
    forever.
  - **`Playthrough#recap`** deepens the narrator's memory from one turn to
    several, by spending the summaries every arrival already writes. Measured on
    `gemma3:12b`: +70 to +91 input tokens on the narration call, ~7% of a turn,
    against 2,264 characters of prose it replaces with 343.
  Bounded at both ends on purpose: the one-shot audit trail is pruned to
  `Chat::KEEP_TURNS` at the end of every turn, because this is a SQLite file on
  a laptop and the game reads none of it back.
- **Auditing the difference — `rake game:audit`, `Playthrough::Drift`, and
  app-owned `take` / `drop`** (step 2 of `data/ta-direction/report.md` §11).
  The third clause of the standing constraint, and the biggest single reduction
  in what there is to drift about, shipped together so the instrument's first
  reading is taken against the world we actually intend to have.
  - **`Story::Audit`** walks stored `Scene`s and reports where the prose and the
    records disagree. Offline, deterministic, no model call, no network,
    ~20 ms per scene, so it can be run over every scene ever written.
    **Contradictions** (a transition the graph forbids; the player told they
    carry something the records give to somebody else) are counted separately
    from **drift**, because one is proved and the other only witnessed. A check
    that cannot be run honestly is reported as *unjudged* rather than guessed at.
  - **PRECISION OVER RECALL, and it was measured rather than asserted.** The
    scout's spike raised 4 flags on 24 real narrations and all four were false
    positives, because a mention is not a claim: prose refers to places through
    windows and people in memory. So the vocabulary check is gone, and so is the
    person check the report expected to keep — every quotation in the corpus is
    attributed by pronoun, so a name-based speaker check would never have fired
    at all. What remains reads prose in exactly one place, possession, and only
    in the grammar of a claim about the player.
    `test/fixtures/files/narration_corpus.json` checks those 24 narrations in and
    `Story::AuditPrecisionTest` pins the flags they earn: **8 flags, 8 true
    positives, 0 false positives**, against 15 narrations that name one of the
    items. About half the real possession claims are missed, on purpose.
  - **`Playthrough::Drift`** is the drift counter: one row when a `move`, `talk`,
    `take` or `drop` resolves to nothing, keeping what the player typed, what was
    on offer, and the narration they had just read. That is how an invented exit
    becomes observable — not by scanning prose for a door, which is impossible,
    but by noticing the player walk at one. Never pruned: a measurement that
    expires cannot be watched over time.
  - **`Item` is in exactly one place**, held by a character or lying in a
    location, and `take` and `drop` are both the app moving that row out of a
    closed set before any prose exists. The narrator is told what happened. Both
    directions, because an app that owns picking up while the narrator asserts
    putting down has records that go stale the first time a player sets
    something down. This is what unblocks the arc's `hold_item` trigger.
  - **`Scene#typed`** is what the player typed, on every branch, written once in
    `Playthrough::Turn#play`. It replaces scraping the classifier's stored
    prompt, which the conversation pruner threw away — so older turns no longer
    lose the player's own words.
  - The debug view carries both tables for the playthrough being looked at.

- **A refusal is a failed call, and a crisis response is intercepted.**
  `BaseAgent` read every unschema'd response for two things it must not keep.
  A refusal — a decline, or a menu of alternatives — raises
  `BaseAgent::RefusalError` and rotates, which is what the app was missing:
  measured over 51 charged narrator prompts, `minimax/minimax-m3` refused 8
  (16%) and `mistralai/mistral-medium-3.1`, then second in
  `REMOTE_MODEL_IDS`, refused **none of them**. The app had the model it needed
  and could not reach it, because a refusal is a 200 OK. The detector is
  STRUCTURAL rather than a word list — an unquoted first-person opening, or a
  list — because a word list misses the refusals that decide things ("I'm not
  going to narrate that. Threatening to harm a child isn't something I'll
  roleplay" contains no phrase any such list carries) and fires on every
  character who says "I". Measured at recall 11/11 with **zero false
  positives** on 127 real prose responses, checked in as
  `test/fixtures/files/refusal_corpus.skeleton.json` and pinned by
  `BaseAgent::RefusalPrecisionTest` the way `Story::AuditPrecisionTest` pins the
  audit sweep. The repo is public, so the corpus ships reduced by
  `RefusalCorpusSkeleton` — every letter `x`, offsets intact, 0 mismatches
  against the raw responses. Every refusal is logged under `[refusal]`, because "the repo has
  no record of a refusal" meant nothing while nothing would have recorded one.
  A **crisis response** — a real-world suicide line, twice in 207 responses,
  both times in an NPC's mouth in a world with no telephones — is the second
  thing, and it takes the opposite path: `BaseAgent::CrisisResponseError` does
  NOT rotate, because rotating would be the app routing around a safety
  response. Captain-decided: suppress the model's version so it never becomes a
  `Scene`, and show `Playthrough::SafetyNotice` outside the fiction, in the
  app's own voice, naming no phone number it would have to guess at. The two
  checks are ordered and never merged — one response can be both.
  (`ta-refusal-range`; `data/ta-refusal-range/report.md` is the sweep.)

### Not built yet

Everything left is in **Next up** below. The loop moves, talks and narrates,
the world moves on its own clock underneath it, a turn runs in a job and
survives the tab closing, and every exchange it has with a model is written down
and bounded. Stage 5 of the browser plan is therefore complete. What it does not
yet do is look like anything -- stage 6, visual style.

The third clause of the standing constraint is now built: `rake game:audit`
verifies stored narration against the records, offline and deterministically,
and `take` / `drop` are state changes the app owns. What is not built is doing
anything with what the sweep finds -- a violation becoming a consequence -- and
the laws digest that would lower the violation rate in the first place.

## Next up

**The queue is authoritative, not this file.** `tasks-axi list --state queued`
in the firstmate repo is the list; each item below names its task id. The
ordering and the measured reasoning behind it are in
`data/ta-direction/report.md` §11 — 1,200 lines of argument that is
deliberately *not* copied here. §12 of the same report says what must
explicitly **not** be built, which is worth reading before proposing anything
in this area.

Steps 1 and 2 of that plan have landed (see **Done**). The rest, in order:

3. **The laws digest in the narrator prompt** (`ta-laws-digest`) — a short list
   of named one-line laws on the universe, in the one prompt that today sends
   zero universe context. ~100 input tokens, no extra round trip, and the live
   A/B halved violations on remote models. **Ship it as odds and prose quality,
   never as mechanics.** Blocked by (2).
4. **The arrival diff** (`ta-arrival-diff`) — record the exit names the player
   was actually shown on `Scene`, and diff them on arrival. ~25 tokens, and it
   is what makes the moving-buildings mechanic *felt* rather than merely true;
   a city that rearranges itself is worth nothing to a player who cannot notice
   it happened.
5. **A violation becomes a consequence** (`ta-violation-consequence`) — when
   verification catches a violation, the world responds to it in a later beat
   rather than the app quietly correcting the past. A scheduled consequence
   `WorldMechanic` applies. This is why the mechanics engine is load-bearing
   rather than merely elegant: the same engine that moves buildings bills for
   violations. Blocked by (2).
6. **The forward flag** (`ta-forward-flag`) — ~20 tokens per violation, to stop
   drift compounding between turns while (5) is being designed. A cheap holding
   measure, and named as one.
7. **The arc** (`ta-story-arc`) — quests, steps, and `Story#conclusion`. Two
   tables and four predicates the app evaluates from records: no model call per
   turn, no narrator tool calls, no plot generated up front. `reach_location`
   and `speak_to` work today, `time_passed` unblocked at (1) and `hold_item`
   unblocked at (2) — `Item#character` is now a real record the app writes — so
   all four triggers exist. The captain has already
   ruled: add `Story#conclusion`, one sentence, keep the preface open — decided,
   not to be re-litigated when this is built.
8. **The offline model-read compliance sweep** (`ta-compliance-sweep`) —
   quantifies compliance at scale by reading the stored prose with a model,
   which is why it can only ever run offline. A per-turn plausibility call is
   ruled out in both directions: 257–289 input tokens *and* a 2.4–7.3 s round
   trip, to answer "allowed" nearly every time.
9. **The item registry** (`ta-item-registry`) — how items come to *exist*, as
   opposed to app-owned `take` at (2) which makes taking a real state change for
   items that already do. Lazy, stub-then-realize — the shape `Location` already
   has — populated when the narrator names something. A generated per-room
   inventory is explicitly ruled out.

### Alongside those, the older queued work

- **`ta-scene-facts-prose`** — split `Scene::Generator` and `Scene::Narrator` by
  facts versus prose. Promoted by the standing constraint from "worth doing" to
  the structural expression of it: if the generator establishes facts and the
  narrator only renders them, non-compliance corrupts prose but never facts.
  **Land it before the laws digest** — everything prompt-shaped should wait for
  this split. Detail in **4. Persistence and history** is unaffected by it.
- **`ta-narrator-memory`** — a cast list and memory beyond one turn; the people
  half of the noun registry, and the same stub-then-realize shape (9) needs.
  Carries a live tension worth naming: its tool-call character creation is
  itself a narrator-compliance dependency.
- ~~**`ta-chat-persist`**~~ — **landed.** Conversations are kept, bounded and
  visible: see **Done** and **4** below. The arc's dependency on scene
  summarisation is discharged — `Playthrough#recap` is there and costs no call.
- **`ta-api-iface`** — the reading experience, stage 6. See **5** below.

## The detail, by area

The checklists below are the granular version of the same work: what is
actually done in each area, and what is not. Where an unchecked item is now a
queued task, the task id is named.

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

- [x] Classify player input: move / talk / examine / take / drop / other, in one
      schema'd `BaseAgent` call. `Playthrough::IntentSchema` is a factory rather
      than a declared schema because `target` is an enum built per turn from the
      room's exits, its cast, what is lying in it and what the player carries:
      the loop has to turn the answer back into a `Location`, a `Character` or an
      `Item`, and "north" resolves to nothing. Closing the
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
- [x] **`take` and `drop` are state changes the app owns.** `Item` is in exactly
      one place — held by a character or lying in a location — and each action
      resolves against that distinction as a closed set, moves the row, and only
      then hands the narrator the fact to write a sentence about. So a narration
      that says the player pocketed something cannot make it so, and one that
      forgets the compass cannot take it away. Both directions on purpose: an app
      that owns picking up while the narrator asserts putting down has records
      that go stale the first time a player sets something down.
- [ ] `examine` is told apart and then handed to `Scene::Narrator` like anything
      else. It is classified so the branch exists when there is something for it
      to do.
- [ ] **Nothing creates an `Item`.** Only a seed file or a test puts one in a
      world, so `take` and `drop` are real over a set that is usually empty.
      `ta-item-registry` is how items come to exist — lazy, stub-then-realize,
      populated when the narrator names something. A generated per-room inventory
      is explicitly ruled out.

### 4. Persistence and history

`ta-chat-persist`, landed. The prose summary is in **Done**; this is the
checklist.

- [x] **The `chats` / `messages` tables are wired up.** Every `BaseAgent` writes
      a `Chat` and its `Message`s — the prompt, the answer, the token counts and
      the model that actually replied — lazily, so an agent nobody asks anything
      leaves no row. One chat per agent CONVERSATION, because a chat's messages
      have to be a list you could send again: one system instruction, one
      schema, one model.
      Which turn a message belongs to is on the **message** (`messages.scene_id`),
      not on the chat, because a durable conversation spans many turns and a
      turn's cost has to come out exactly.
      `messages.content_raw` was added and is load-bearing: RubyLLM stores a
      schema'd answer there with `content` nil, so without it every schema'd
      call in the app persisted an empty assistant message.
- [x] **The debug view gained all of it**, which is what it was built to do:
      prompts, raw responses, token counts and the answering model, per turn and
      per playthrough. Two of the three gaps it named close with it — the
      classifier's exchange holds both the raw typed command and the intent
      label the loop decided in memory.
- [x] **`tool_calls` is wired but unexercised**, and that is honest rather than
      missing: `acts_as_tool_call` is in place and RubyLLM writes the rows when a
      call happens, and nothing in this app gives a model a tool yet. That is
      `ta-narrator-memory`, and it will find the table already there.
- [x] **Persist an `Interaction` at all.** `InteractionAgent#ask` returns the
      structured reaction alongside the prose now, and `Playthrough::Turn#talk_to`
      writes the row.
- [x] `Interaction#inner_resolution` is a **sixth field on `Interaction::Schema`**
      rather than the second call the note used to imagine — no extra round trip,
      ~30 tokens on a call that already happens — so `#completed?` is finally
      capable of being true. `#summary` is derived on create from what was
      already paid for. `inner_resolution` is deliberately NOT interpolated into
      the narrator pass: what a character decided is about what they will do
      next, and handing it to the prose invites narrating that instead.
- [x] Summarize old scenes so long playthroughs stay inside the context window.
      `Playthrough#recap` spends `scenes.summary` — written on every arrival, for
      exactly this — under a fixed character budget, and asks no model anything.
      Measured against `gemma3:12b` on the seeded world, the same commands played
      twice: the narration prompt went 711 → 781 and 684 → 775 input tokens
      (+70 / +91, about 7% of a turn) while its memory went from one turn to
      three. Carrying those three in full prose instead would have been 2,264
      characters against the recap's 343. README has the table.
- [ ] **Nothing summarises a narrated turn.** Only an arrival is schema'd, so
      only an arrival has a `summary`; the recap contributes such a turn's own
      first sentence instead. Truncation is honest and free, and the alternative
      is a second model call on every turn — but a real summary is better prose
      in the prompt. Worth revisiting only alongside `ta-scene-facts-prose`,
      which is where the narrator stops being the only thing that writes a turn.

### 4a. The world's own mechanics

Step 1 of the direction plan, landed as PR #77. The prose summary is in
**Done**; this is the checklist.

- [x] **`Story#clock`** — what time it is in the fiction, derived from
      `scenes.story_timestamp` rather than stored. A story nobody has played is
      at its own `start_time`.
- [x] **Story time on every `Scene`.** An arrival is the previous scene plus
      `LocationConnection.travel_minutes` for the edge actually walked; every
      other turn costs what `Scene::TURN_MINUTES` says. `Time.current` is gone
      from that whole path, which closed the wall-clock defect that used to be
      the first entry under **Known issues**: `Location#last_protagonist_visit`
      now holds a story moment, so `#time_since_last_visit` — the value
      `Scene::Generator` turns into "you were last here about an hour ago" — is
      measured in the fiction. Fixed in the one place the issue asked for.
- [x] **`WorldMechanic`** — a fixed catalogue of Ruby operations over records,
      on a story-time schedule. `kind` and `cadence` are keys into tables in
      code; a world supplies parameters (`locations.mobile`, the cadence, the
      in-fiction reason) and never behaviour. `last_run_at` is a column in story
      time, so catching up is arithmetic: no timer, no job, nothing in memory,
      and a process that was down for a week pays the nights it owes on the next
      turn. Driven from `Playthrough::Turn#play`; ~90 µs and **0 tokens** on a
      turn where nothing is due.
- [x] **`WorldMechanic::ShuffleConnections`** — repoints one endpoint of every
      edge joining a `mobile` location to a fixed one, permuting rather than
      choosing so every location keeps its degree, with an explicit connectivity
      check before an arrangement is applied. Deterministic per (story, night).
      Hand-written into `the-lunar-cartographer.yml`, whose universe has claimed
      since it was generated that Nocturnis rearranges itself nightly.
      An arrangement is judged on the **induced adjacency** — the set of
      unordered pairs of places that end up joined — and not edge by edge, so a
      permutation confined to one mobile location's own edges is a no-op and is
      refused. `settle` first rewrites every candidate into the one form that
      says what it means: within a location's own edges, an endpoint it keeps
      stays on the edge that already had it. Reordering endpoints among one
      location's edges cannot change the graph, so `valid?` judges exactly what
      gets written — and every sentence the log writes is then true of the
      graph, not merely of an edge. (`ta-shuffle-noop`.)
- [x] **`WorldEvent`** — the audit trail, in story time, with the locations it
      touched. Deliberately NOT a narration source: over two nights a shuffle
      can return a place to the same neighbour, so replaying the log would
      announce a change the player never experienced.
- [ ] **The arrival diff — "what changed while you were gone".** Record the exit
      names the player was actually shown on `Scene` and diff them on arrival.
      That is what makes the mechanic *felt* rather than merely true, and it is
      the honest version of the previous point. ~25 tokens. `ta-arrival-diff`,
      step 4 of the order above.
- [ ] **Judge the edge shuffle in play.** Captain-decided: build the simple
      version, play ten turns, and only then decide whether whole districts
      should travel as units instead. The districts variant is neither adopted
      nor rejected.
      **First nine turns played** (`ta-debug-view`, against the local models).
      The mechanic fired on schedule off the story's own clock and cost nothing,
      but the one arrangement it drew was a transposition within a single mobile
      location's own edges, so the graph did not actually change and the event
      said it did. That was a broken guarantee and is **fixed**
      (`ta-shuffle-noop`) — such an arrangement is now refused and the night
      writes nothing. Note what it implies for the districts variant, which the
      fix does not settle either way: a district travelling as a unit cannot
      produce a no-op of this shape, because its edges out have distinct mobile
      ends. The edge shuffle now has to reach for a valid arrangement where the
      districts variant would not, which on a sparse world is a real cost in
      nights that do nothing — one data point, recorded as one. **Still nine
      turns played, not ten, and none since the fix**: the judgement wants a
      night that visibly moved something.
- [ ] Generating a mechanic from a model at world-creation time. Deliberately
      not built: the parameters are hand-authored first, so the mechanic that
      exists is one somebody chose.
- [ ] A second `kind`. `WorldMechanic::KINDS` has one entry, and the next one is
      an operation in Ruby rather than a field in a file — including the one the
      direction wants for violation-becomes-consequence
      (`ta-violation-consequence`, step 5).

### 5. Interface

`ta-api-iface`. The first playable browser interface has landed (see **Done**).
What it still owes, roughly in order:

- [ ] Echo past commands in the turn log. **The column has landed** —
      `Scene#typed`, written on every branch by `Playthrough::Turn#play`, with a
      migration that backfills from `Interaction#user_input` and from whatever
      classifier prompts were still kept. The debug view reads it. What is left
      is presentation: the play page's turn log is still narration only, so a
      reloaded transcript reads as answers without questions.
- [x] **Jobs, Turbo Streams over Action Cable, and durability.** Landed — see
      **Done**. `NarrationJob` replaced `NarrationsController`, `propshaft` +
      `importmap-rails` + `turbo-rails` are in, and there is still no Node and
      no `package.json`. The conversation-persistence half of the same stage
      (`ta-chat-persist`) has landed too, so stage 5 is complete.
- [ ] Re-join a turn already in flight. Reopen the page mid-narration and the
      log is what was persisted; the prose written so far lives in the job's
      buffer and nowhere else. The finished turn still arrives over the cable
      when it lands, so nothing is lost — only the live view of the middle.
- [ ] Visual style. Deferred on purpose until there is a real loop to look at.
      The debug view (`ta-debug-view`) is **not** an exception to this and does
      not pre-empt it: it has its own layout and shares no CSS with the game, so
      the two can be styled independently and neither constrains the other. Its
      whole mark on the game is one link on the play page, absent when the view
      is off.
- [x] **The page stays where the story is.** Submitting a turn used to land at
      the top of the document while the answer streamed in below the fold: the
      streaming render emits no form, so the `autofocus` that had been pulling
      the viewport down was missing at exactly that moment. A `#bottom` anchor
      at the foot of `playthroughs/show` — which a plain reload and the index's
      Resume link aim at — does the landing with no script, and
      `app/javascript/play.js` follows the narration down only while the player
      is already at the bottom, so scrolling up to re-read is not overridden.
      The redirect anchors went away with SSE, as predicted; the follow was
      ported. With no end-of-turn reload, `stick` is honoured throughout: a
      player who had scrolled up is no longer dragged to the bottom when the
      turn lands.
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
      narrates, which was the honest limit of it — closed by the next item.
- [x] **Where the opening arrival comes from.** It comes from the world now —
      `Scene::Generator.opening` at `rake game:new` time, `opening_scene` in the
      seed file, loaded with everything else. See **Status → Done**. The ruling
      on the "progress rather than world" line, and the natural key a `Scene`
      did not have, are both written up in `db/seeds/worlds/README.md`.
- [x] A story generated before opening locations existed has nowhere to start,
      so the index lists it without a Play button and `create` refuses it. That
      branch stays, but it is no longer the only thing that says so:
      `rake game:doctor` names such a story and every other way one can be
      unplayable, and says whether it can be repaired or should be deleted.
      Measured on the captain's own database: of five stories, two were
      unplayable with no locations at all, one was playable with nine warnings,
      and two were healthy.

## Known issues

- **Three findings from the refusal sweep, measured and deliberately not acted
  on** (`data/ta-refusal-range/report.md`). None is a refusal problem, and each
  is its own piece of work: (1) **`mistral-medium-3.1` refused nothing and is
  3–4× faster**, but its prose is markedly thinner — *decided: it is now the
  default, and the thinner prose is the accepted trade. See Done.* (2) **The talk path
  hangs.** Three calls in ~150 stalled indefinitely, all on the unschema'd
  streaming pass inside `InteractionAgent`, and `RubyLLM`'s `request_timeout`
  demonstrably did not bound them — one ran 21 minutes with it set to 150s.
  `NarrationJob` has no timeout of its own, so a stalled talk turn holds a Solid
  Queue worker with the player watching a dead cursor. (3) **minimax drops
  required `Interaction::Schema` fields on ~29% of talk turns** (12 of 41; 0 of
  14 on mistral), each one a silent wasted call that `verify_schema_honored!`
  recovers from. The rate is *higher* on benign input than on charged input, so
  it is flakiness rather than steering.
- **The suppressed prose is still streamed before it is suppressed.** Both
  checks read the finished response, so a refusal or a crisis line has already
  been broadcast into `#stream` chunk by chunk by the time it is caught. It is
  never persisted and the end-of-turn `#turn_log` replace takes it off the page
  — the log renders persisted scenes — but a player watching closely saw it
  arrive. Catching it mid-stream is a different design on partial text, and the
  detector was measured on whole responses.
- **The story clock is the story's, not a playthrough's.** `Story#clock` is a
  `MAX` over every scene in the story, because `WorldMechanic` is story-level:
  the world moves for everybody. So two playthroughs of one world share a world
  clock, and the further-along player pulls the other's nights forward. Each
  playthrough's own next turn is still measured from its own last scene
  (`Playthrough#story_now`), so nobody's timestamps go backwards — but a second
  player can walk into a city that rearranged itself while they personally did
  nothing. Irrelevant for one player; the fix, if it matters, is a per-world
  clock rather than a per-story one.
- **Re-seeding a played world re-asserts the graph the file declares.** The
  loader adds and updates and never deletes, so seeding on top of a world whose
  mechanic has moved edges leaves both the seeded edge and the moved one. Drop
  the database for a clean rebuild — the same caveat as renaming a location.
- **A failed arrival leaves a realized room nobody has stood in**, which is the
  designed behaviour working and is worth knowing how to read. Observed in the
  same run: the move's `Scene::Generator` call rotated to `qwen3:8b`, which
  omitted `summary`, so `BaseAgent` raised `SchemaIgnoredError` and the turn
  failed. `Location::Generator#realize!` had already committed, so Mournwell
  Lane is realized with its exits stubbed out, and `Playthrough::Turn#move_to`
  correctly did not move the player — exactly as its comment promises. On the
  debug view it reads as a realized place with `last visit (never)` and nobody
  in it, which is the signature of a half-finished move and is not otherwise
  visible anywhere.
- **The play page does not show what the player typed.** The column exists now
  -- `Scene#typed`, written on every branch, and the debug view reads it -- but
  the turn log is still narration only, so a reloaded transcript reads as
  answers without questions. That is presentation, not plumbing.
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
- **Solid Queue's worker count is the new ceiling on concurrent turns.** The
  Puma-thread problem is genuinely gone — WebSockets consume no request threads,
  and the turn runs outside the request entirely — but it has a successor:
  `config/queue.yml` gives one worker process 3 threads, so a fourth
  simultaneous turn queues rather than starting. That is a much better failure
  than the old one — the site stays responsive and nobody loses a turn — and
  `JOB_CONCURRENCY` raises it. `deploy.yml` sets `SOLID_QUEUE_IN_PUMA: true`, so
  in production those threads share the web container.
- **A development server keeps the columns it booted with.** ActiveRecord caches
  each table's columns the first time a model touches it, and a migration is
  always run in another process — so a server that was up before `db:migrate`
  goes on serving a class built from the old schema, and a column that is right
  there in the database raises `undefined method`. That is what
  `NoMethodError: undefined method 'is_opening?' for an instance of Scene` was:
  not bad data and not a pending migration, an eleven-hour-old process.
  `StaleSchemaGuard` (development only) now compares the schema version on every
  request against the one the process first saw, and says *restart the server*
  rather than letting the first attribute the code reaches for fail. It reports
  and does not repair: resetting column information in place leaves the
  connection's prepared statements still selecting the old columns, so a new
  process is the honest answer. **`bin/jobs` is a second long-lived process with
  the same hazard**, and no guard: it serves no requests, so restart it after a
  migration too.
- **`Scene::Narrator`'s `ensure` cannot cover a `Scene` that will not save.**
  Closing the tab no longer costs anything — the turn is a job and nobody has to
  be watching — but that was only ever half of what the `ensure` was for. When
  the captain lost 82 seconds of a turn to the stale process above, the `ensure`
  ran exactly as designed and the `Scene.create!` inside it was what raised;
  there is nowhere to put prose when the model cannot be written at all. On a
  **move** most of that time was in fact kept: `Location::Generator` saves the
  room before it asks for the exits, so both of those calls had already landed
  and only the arrival narration was lost. The narration branch is the one that
  loses everything, and what fixes it is a process that is not stale rather than
  another `ensure`.
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
- **A factory that rolled dice made one view test fail 1 run in 35, and
  parallel workers were the reason nobody could reproduce it.**
  `DebugControllerTest#test_show_flags_a_one-way_edge...` failed a full-suite
  run with `Expected at least 1 element matching ".warn", found 0`, then
  survived nine further full runs including a re-run of the failing seed and
  every run of the file alone. Cause: `test/factories/location_connections.rb`
  picked `distance` and `travel_method` with `.sample` off the two fixed tables.
  The test wrote the *return* edge with a hard-coded `("a long journey",
  "riding")` and left the *outbound* edge to the factory, so 1 time in 35 (5
  distances × 7 methods) the two rows matched, `Playthrough::Debug::Exit#directions_disagree?`
  correctly answered false, the cell rendered `yes`, and the page carried no
  `.warn` at all — which is why the count was zero rather than merely
  unmatched. **Parallelism was the exposing condition, not the cause.** Minitest
  `srand`s the global RNG once from the run seed, so the sequence is fixed, but
  the *position* it has reached when a given test's factories fire depends on
  how many earlier `rand` calls landed in that forked worker — and work is
  handed to the 16 workers as they come free. Same seed, different schedule,
  different dice: that is the whole of why the seed did not reproduce it, and
  it is the same shape as the registry issue above, one layer down.
  **Proven rather than argued:** a record-level probe predicted the 10 global
  seeds in 0...300 that collide, and all 10 fail the old test through the real
  request path while 5 predicted-clean seeds pass. **Fixed twice over:** the
  factory's two values are now fixed (`across the district` / `walking`, chosen
  so its 20 minutes collides with neither entry in `Scene::TURN_MINUTES`), and
  the test writes both directions of the edge itself, because a disagreement is
  a relationship between two rows and a test that pins one and leaves the other
  to a factory is asserting against a value it does not know. The `.warn`
  assertions now match whole phrases, and the agreeing case — the state the
  flake actually rendered — has a test of its own. `test/factories/characters.rb`
  still uses `rand`/`.sample` for `age` and `sex`; nothing pins those today, so
  it is a latent instance of the same shape rather than a live one.
- **The suite used to read behaviour out of whoever's shell started it.** Found
  while confirming the above: three tests failed for a worker who had
  `OPENROUTER_API_KEY` set in their environment — `BaseAgent.default_model_options`
  puts the hosted models ahead of the local ones when the key is present, so two
  tests pinning the answering model to `gemma3:12b` got `minimax/minimax-m3`, and
  `ChatTest#test_resolving_a_model_name_needs_the_provider_configured` got no
  exception because the initializer had configured the provider from the same
  key. Worse and unnoticed: `TA_DEBUG_VIEW=0` in a shell turned
  `Playthrough::Debug.enabled?` off and took 11 of `DebugControllerTest`'s 13
  tests with it, and `TA_CHAT_KEEP_TURNS` / `TA_CHAT_HISTORY_EXCHANGES` are read
  into `Chat` constants at class-load time. Every one of the five is something a
  person working on this app legitimately keeps in `.env` or `.envrc`, and the
  ROADMAP tells them to. `test_helper.rb` now deletes all five, so the suite
  boots in a declared environment; a test that wants one sets it itself and puts
  it back, which `BaseAgentTest#with_env` and `Playthrough::DebugTest#with_env`
  already did. **It needs two passes, and finding out why cost a second round**:
  deleting them *before* `config/environment` is required is necessary for the
  two frozen into `Chat` constants at class-load time, but `dotenv-rails` loads
  `.env` during that same require and declines to override only the keys it
  finds already set — so the first pass is precisely what gives it the opening,
  and with that pass alone both `ENV["OPENROUTER_API_KEY"]` and
  `RubyLLM.config.openrouter_api_key` are populated again by the time the first
  test runs. Measured on a checkout with a `.env`, which is every checkout
  anybody plays the game from.
- **`sanitize_string` used to delete every digit a model wrote.** Its regex was
  `\p{Emoji}`, a property that matches the ASCII digits, `#` and `*` because
  those are the bases of the keycap emoji — so "80 meters" was stored as
  "meters". It now matches `\p{Extended_Pictographic}` instead. Any text
  generated before this fix has silently lost its numbers.
- **The move path does not work on local models, and rotation cannot reach the
  one that does.** Measured on a real playthrough: `gemma3:12b`, `gpt-oss:20b`
  and `qwen3:8b` all return `Scene::Schema` with `description` and no
  `summary`, so `verify_schema_honored!` rejects all three and the turn ends with
  the reason broadcast back and the player left where they were. `qwen3:4b` returns both
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
- **A talk turn is not durable, where a narrated turn is.** `Scene::Narrator`
  persists partial prose in an `ensure`, so closing the tab mid-stream keeps
  what was written. `Playthrough::Turn#talk_to` has no equivalent: the
  character pass has already been paid for and the narration is streaming, and
  a disconnect loses both calls with nothing recorded. Deliberately not fixed
  with a second bespoke `ensure` -- the job-and-cable stage deletes that shape
  for the narrator too, and should cover both paths at once.
- The migration to the new `acts_as` API left `chats.model_id_string` and
  `messages.model_id_string` behind — dead columns the generator's `down` step
  needs. Drop them if the migration is ever squashed.
- The `async` gem is still in the `Gemfile` but no longer used after
  `Character::Generator` was made synchronous.
