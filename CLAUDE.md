# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Current status and the task queue live in [ROADMAP.md](ROADMAP.md).** Read it
before planning work, and update it when work lands. See [AGENTS.md](AGENTS.md)
for agent working agreements.

## Project Overview

Text Adventure is a Rails 8 application that creates AI-powered text-based adventure games: a world generates itself as the player explores it, and what it generates is kept. It uses the RubyLLM gem to reach models through OpenRouter (`mistralai/mistral-medium-3.1`, falling back to `minimax/minimax-m3`) or a local ollama; `BaseAgent` picks between them. It has a plain ERB browser interface on Hotwire with zero build step
(`propshaft` + `importmap-rails` + `turbo-rails`, no Node and no
`package.json`) — see the browser section in [AGENTS.md](AGENTS.md).

## Development Environment

- **Ruby**: 3.4.10 (managed by asdf/mise, see `.tool-versions`)
- **Rails**: 8.1
- **Database**: SQLite3 for development and production

## Key Dependencies

- **ruby_llm**: AI chat completion framework with OpenRouter integration
- **open_router** (~> 0.3.3): OpenRouter API client for accessing AI models
- **solid_cache/solid_queue/solid_cable**: Rails 8 solid adapters

## Common Commands

### Development
```bash
# Install dependencies
bundle install

# Generate a world, then list what exists
rake 'game:new[a debt collector in a city built on a dead god]'
rake game:list

# Generate runs across the three seeded worlds, score them, print a board with
# its own noise floor. Generation spends money; scoring is free. See EVALUATION.md.
rake eval:run                       # ~$0.22 at the defaults; prints an estimate first
rake eval:score SET=main            # offline, no key, no network
rake eval:compare BEFORE=a AFTER=b  # REAL / NOISE / INCONCLUSIVE, per check

# The classifier's own bench: 300 hand-labelled typed lines replayed through
# Playthrough::Classifier. Accuracy, closed-set misses, also_named precision and
# recall, refusal agreement AND latency, per model, each with its band.
rake eval:classifier                       # ~$0.39 at the defaults; prints an estimate first
rake eval:classifier MODELS=ollama:qwen3:8b SET=local-qwen8b   # a local model: free, and slow
rake eval:classifier MODELS=ollama:qwen3:4b+nothink            # ...and 48x faster with the reasoning off
rake eval:classifier_offline               # the same corpus with no model at all -- free, in CI
rake eval:classifier_omission              # the also_named omission rate alone
rake eval:classifier_compare BEFORE=a AFTER=b   # including two DIFFERENT models
rake eval:classifier_board                 # the checked-in 2026-09-04 baseline as one table;
                                           # no key, no network, no database. SETS=a,b for others

# The narrator's own bench: 90 single-turn cases with fixed facts, one prose call
# each, scored by the deterministic checks -- per model AND per prompt version.
# The first gate a prompt-shaped change passes; eval:run confirms it.
rake eval:prompt                    # ~$0.20 at the defaults; prints an estimate first
rake eval:prompt_score SET=prompt-2026-09-05   # score a stored set again -- offline, free
rake eval:prompt_compare BEFORE=a AFTER=b      # REAL / NOISE per check, off the files alone
rake eval:prompt_board              # every stored set as one table; no key, no database

# Bring a checkout up to date after a pull: fast-forward, bundle, migrate, then
# everything the new code needs done to the database you already have. Offline,
# idempotent, no model call. lib/update.rb is the list of steps.
# It also re-seeds when a file under db/seeds/worlds moved in the range it
# pulled -- a world outlives its seed FILE the way it outlives its schema.
bin/update                          # --dry-run writes nothing at all; --skip-pull to only apply
bin/update --seed                   # force the re-seed (--skip-pull has no range to read)
rake game:update                    # the steps alone; DRY_RUN=1, ONLY=<step>, VERBOSE=1
rake game:reseed                    # re-assert the checked-in world files alone. Offline

# Check the stories in the database, fix what can be fixed, delete what cannot
rake game:doctor                    # or rake 'game:doctor[3]' for one story
rake game:audit                     # where narration contradicts the records; VERBOSE=1 for unjudged checks
rake game:backfill_transitions      # label old turns with what they did, from the stored
                                    # classifier answers. Offline; DRY_RUN=1 to see it first
rake game:backfill_whereabouts      # place characters who have none, from the arrival casts
                                    # still on disk. Offline; refuses to guess; DRY_RUN=1
rake game:backfill_items            # split one shared set of items into the world's own rows and
                                    # each playthrough's copies. Offline; refuses to guess; DRY_RUN=1
rake game:backfill_stat_blocks      # roll a body for everybody written before characters.level and
                                    # characters.hit_die existed. Offline, deterministic; DRY_RUN=1
rake game:score                     # the scoreboard: a rate per check, the movement since the
                                    # baseline, and every flagged turn with what was typed and
                                    # the passage. SAVE=1 to re-baseline; CORPUS=corpus or
                                    # CORPUS=transitions for one frozen corpus alone
rake 'game:repair[3]'               # safe repairs; GENERATE=1 to allow model calls
rake 'game:delete[3]'               # prints what would go; DRY_RUN=1 or CONFIRM='<title>'

# Walk the engine with the NARRATION off and nothing else off: the classifier
# still reads what you type and the world still generates as you walk into it.
rake 'game:mechanics[The Unrecorded Hour]'   # or by id; PLAYTHROUGH=<id> to attach
NO_MODEL=1 rake 'game:mechanics[2]'          # offline fallback: fixed grammar, no generation

# Walk stored scripts through the engine with no model at all and assert the
# records after every typed line. Free, deterministic, and it runs in CI.
rake game:sweep                              # every script in lib/engine_sweep/scripts
rake game:sweep SCRIPT=the-salt-assizes-grammar

# Play it in the browser. `bin/dev` starts both processes a turn needs -- the
# web server and the job worker -- under foreman. `PORT=3142 bin/dev` to move off
# 3000. `bin/rails server` alone still works, and is what to use when debugging.
bin/rails db:prepare   # the app's database, Solid Queue's, and Solid Cable's
bin/dev                # then open http://localhost:3000

# Rails console
rails console
```

### Testing
```bash
# Run all tests
rails test

# Run specific test
rails test test/models/universe_test.rb

# Verify autoloading (app/agents/ uses PascalCase filenames)
rails zeitwerk:check
```

### Code Quality
```bash
# Run rubocop (Rails omakase style)
bundle exec rubocop

# Run security scanner
bundle exec brakeman
```

## Architecture

### Core Components

1. **`BaseAgent`** (`app/agents/BaseAgent.rb`):
   - Every LLM call in the app goes through it. Do not build a bare
     `RubyLLM::Chat` in new code.
   - Selects a model and rotates to the next one when a call fails — except on
     a rejected key, which raises `BaseAgent::UnauthorizedProviderError`.
   - Rejects a response that ignored its schema, so a prose answer fails the
     call instead of corrupting a record.
   - Rejects a response that **refused** the prompt, so a refusal is a failed
     call and the rotation reaches a model that will write it
     (`BaseAgent::Refusal`, measured and pinned by
     `BaseAgent::RefusalPrecisionTest`). Unschema'd calls only.
   - **Intercepts** a response that answered with real-world crisis resources:
     `BaseAgent::CrisisResponseError`, deliberately NOT a rotation. The model's
     version is suppressed and never persisted; `NarrationJob` shows
     `Playthrough::SafetyNotice` outside the fiction instead. See AGENTS.md →
     *Talking to models*.

2. **The turn loop** (`Playthrough::Turn`):
   - **A SLASHED line is read by `Playthrough::Grammar` first and by the model
     second** — the captain's ruling of 2026-09-04, evening: *"support a slash
     prefix autocomplete in the text box, and resolve those and verb-prefixed
     lines offline then fallback to the model"*, narrowed by his ruling of
     2026-09-05: ***"I think we should only auto accept the slash commands."***
     A line carrying a `/` is matched against the SAME closed set the classifier
     would have been offered, for no model call; a noun the grammar cannot place
     falls through to the classifier exactly as before, and **a line with no
     slash is not claimed at all, whatever it begins with** — a leading verb is
     a coincidence of English (`Playthrough::Grammar::MEANS_SOMETHING_ELSE` has
     the four measured wrong answers it produced).
     `Playthrough::Turn#read_line` is the decision, `scenes.resolved_by` is
     which reader answered, and `Playthrough::SlashMenu` is what the browser box
     completes on.
   - `Playthrough::Classifier` reads what the player typed against a closed
     enum of the room's exits, its cast, what is lying in it and what the player
     carries, and the turn branches on the answer: `Scene::Generator` for
     arriving somewhere, `InteractionAgent` for talking to somebody, an app-owned
     `Item` transfer for `take` and `drop`, `Scene::Narrator` for `examine` and
     `other`. **ONE LINE, ONE ACT: a line that is not one is refused whole** —
     `Playthrough::Refusal`, the captain's ruling of 2026-09-04. Two acts on one
     line, a reach the closed sets cannot answer, or a classifier answer outside
     the intent table that still named a record: the turn stops in front of the
     dispatch, writes nothing, calls no narrator, and answers with the engine's
     own sentence. The `Playthrough::Drift` / `Playthrough::Overreach` row is
     still written. `Playthrough::Moment` is the one builder of what the prose
     and the character are told about the moment: room, exits, cast, inventory,
     last turn, recap. Add a fact there, not to a caller.
   - It runs in `NarrationJob`, which broadcasts what the player reads as Turbo
     Streams over Action Cable — so a turn outlives the tab and holds no Puma
     thread. The loop takes a block and knows nothing about the consumer.
   - [README.md](README.md#how-a-turn-works) has the diagram.

3. **AI Configuration**:
   - RubyLLM configuration in `config/initializers/ruby_llm.rb`
   - `OPENROUTER_API_KEY` in a gitignored `.env` (loaded by `dotenv-rails`) or
     `.envrc` (direnv). Model order lives in `BaseAgent::REMOTE_MODEL_IDS`.
   - The `models` table **is** the RubyLLM registry since the `acts_as`
     migration; `rails db:seed` fills it, and nothing resolves without it.

### System Architecture

- **A Rails app with a deliberately minimal ERB frontend** — no Node, no build
  step, no Turbo. `config.api_only = false`.
- **AI-driven narrative generation** with rule-based constraints
- **Database models** for Chat, Message, and ToolCall to store conversation history

### Configuration Notes

- OpenRouter API key must be set as environment variable: `OPENROUTER_API_KEY=your_token`
- Neo4j integration is currently commented out in `config/application.rb` but gems are installed

### Development Workflow

Worlds are built from rake tasks (`rake game:new`, `rake game:export`) and
played in the browser (`rails server`). There is no `rake game:play` and there
is not meant to be — the loop lives in `Playthrough::Turn`, so a rake front end
would be a second UI to maintain for no new capability.

### Model updates
- whenever a model is updated, check the model tests and factories and make the appropriate updates in those as well

### Testing Requirements

#### Model Coverage
- **Every model MUST have a corresponding test file** in `test/models/`
- **Every model MUST have a factory** in `test/factories/`
- Test files should cover all validations, associations, scopes, and public methods
- Use descriptive test names that explain the expected behavior

#### Factory Requirements
- Factories should provide valid default attributes for all required fields
- Use traits for common variations (e.g. `:rivendell` location, `:elrond` character)
- Ensure factories create valid objects that pass all model validations
- Keep factories minimal but complete - only specify what's necessary for a valid object

#### Database Schema
The current database includes the following story-related models with proper associations:
- **Story** → **Characters**, **Locations**, **Scenes**
- **Scene** → belongs to **Location**, has many **Characters** through join table
- **Interaction** → belongs to **Character**, **Scene**, and **Location**
- **Location** → tracks `last_protagonist_visit`, a moment on **story** time (not
  the wall clock), updated via Scene callbacks
  (with one deliberate exception: a `Scene` marked `is_opening` is world data
  written before anybody plays, so it does not stamp the visit —
  `PlaythroughsController#create` does when a player arrives)
- **Story** → `has_one :opening_scene`, the narrated arrival the world carries
  and every playthrough of that story starts on
- **Story** → `#clock`, what time it is in the fiction, derived from
  `scenes.story_timestamp`. Never use `Time.current` for story time; see
  `AGENTS.md` → *Story time, and a world that moves on its own*
- **Playthrough::Refusal** → **THE ONE AUTHOR OF WHAT THE ENGINE SAYS WHEN IT
  WILL NOT PLAY A LINE**, read by `Playthrough::Turn` and
  `Playthrough::Mechanics` alike so the two modes cannot disagree about a line.
  Three kinds, told apart because they are different facts:
  `named_more_than_one` (two things the records both have — counted by
  `Playthrough::Overreach`), `unresolved` (a reach the closed sets cannot answer
  — counted by `Playthrough::Drift`) and `unreadable` (an intent outside
  `Playthrough::IntentSchema::INTENTS` that still named a record — counted by
  nothing, because it is a defect on our side, and logged). `#reason` for the
  consumer that prints the records underneath, `#text` for the one that does
  not. **A refusal is not a `Scene`** and must not become one: `#description` is
  read as narration by `Story::Audit`, `Eval::Richness` and both frozen corpora,
  and a refusal has no moment in it to move the clock with. Read the header
  before changing a word of what the player is shown, and
  `Playthrough::Classifier::Intent#refused?` before changing which lines land
  there — a coherent `other` and an `examine` that landed on nothing are
  deliberately NOT refused, and an `examine` that named TWO things is (a
  readable thing named alongside another thing is one line asking for two acts,
  like any other)
- **Playthrough::Mechanics** → the game with the prose taken out, and nothing
  else taken out with it (`rake game:mechanics`). The classifier still reads the
  command and prints what it resolved to; the world still generates itself, so a
  move is `Playthrough::Turn#move_to` whole. Only `Scene::Narrator` and
  `InteractionAgent` are dropped, `talk` is refused as prose, and an `examine`
  prints `Item#inscription` out of the records when there is one to print —
  a record, so no model — and is refused as prose when there is not. The
  ruling's refusals come from `Playthrough::Refusal` and not from a second copy
  here — the mode's old `also named:` note is gone with the half-played turn it
  reported. `stats` prints the world's five numbers beside the game's condition
  (the layer split on the screen) and `check <ability> [penalty]` throws one d20
  through `Playthrough::Turn#check` and **writes nothing at all** — the one verb
  in `ENGINE_VIEW` a player might plausibly mean in the fiction, so with a model
  available `check` is the engine's own only when the next word is one of the
  three abilities and otherwise goes to the classifier. `model: false` (`NO_MODEL=1`) is the offline fallback — a fixed
  grammar, no generation, no model call at all — and it is the mode the
  engine-direct tests run in. See `AGENTS.md` → *The mechanics on their own,
  with the narration off*
- **Item** → **TWO LAYERS, ONE TABLE**, and `items.playthrough_id` is which
  layer a row is in — the captain's ruling of 2026-09-04, *"each play through
  should have its own copy of items"*. NIL is one of **the world's own rows** (a
  TEMPLATE): what a room or a person was seeded or generated with, lying in a
  room or held by one of the world's people (`Item::PLACES`, exactly one of the
  two), written by `WorldSeed::Loader` and `Item::Registry`, exported by the
  exporter, counted by the caps, and never touched by anybody playing. SET is
  **one game's own copy** (an INSTANCE): `location_id` (lying in a room, in that
  game), `character_id` (in that person's hands, in that game) or NEITHER, which
  is the party's own hands. `items.template_id` is the durable link.
  **Play reads the playthrough layer and nothing else**, through three readers
  and only three — `Playthrough#carried`, `#items_lying_in`, `#items_held_by` —
  and writes it only through `Playthrough::Turn#carry!` / `#put_down!`.
  `Item.in_story` is the one place the "every row in this world" query lives;
  narrow it with `.templates` to mean the world. The ROOMS THEMSELVES stay
  shared — geometry, descriptions, cast — and it is what is LYING in them that
  each game copies; pinned by `the-unrecorded-hour-two-players.yml` (independence),
  `the-unrecorded-hour-first-contact.yml` (timing) and
  `EngineSweep::Invariants#world_items_unmoved`
- **Item::Snapshot** → **THE INITIAL SNAPSHOT ANY PLAYTHROUGH USES**, and the
  only thing in the app that creates a row in the playthrough layer. LAZY, AT
  FIRST CONTACT: a room and the people standing in it are copied when the party
  arrives (`Playthrough::Turn#move_to`, *after* the room is realized) and at the
  top of every turn on the room they are in; `Playthrough::Mechanics` calls the
  same two. **The guard is per TEMPLATE, not per room** — "this room is done"
  would refurnish a room the party had just emptied, once per return trip, for
  ever. A copy carries every column but where it is and whose it is
  (`Item::NOT_COPIED`), so the next column added to `items` comes along by
  itself. A template held by the PROTAGONIST is the one stated exception to
  "a copy lands where its template is": it lands in the party's own hands
- **Story** → `#starting_inventory`, WHAT THE PLAYER STARTS OUT HOLDING: the
  seed file's `characters[].items` under the protagonist, held by the
  protagonist row **in the world layer** (`.templates` is the whole guard). The
  inventory's counterpart of `#opening_location`, and the one thing every
  playthrough of a world begins from — `Item::Snapshot#of_the_party!` gives each
  new playthrough its own COPY, in the party's hands. Only `WorldSeed::Loader`
  ever writes one — a generated protagonist is given nothing — so a generated
  world's is legitimately empty
- **Item::LayerBackfill** → `rake game:backfill_items` and one of `bin/update`'s
  steps: split an older database's one shared layer in two. Four outcomes told
  apart — the world's own (left exactly where it stands), attributed (the row
  becomes the copy of the player whose chain took it, and one of the world's own
  rows goes back to the room the take happened in, out of `scenes.location_id`),
  **ambiguous** (two chains' takes at one story moment: nothing is written and
  it is named), and unrecoverable (a copy nothing accounts for: LEFT where it
  is, in that player's hands, and named). Then every existing game is handed its
  copy of the rooms it has walked through. Offline, idempotent, `DRY_RUN=1`
  first — and the dry run counts what the REAL run would copy, which is not what
  today's rows say. It SUPERSEDES `Item::InventoryBackfill`: whose hands a thing
  is in is one case of which layer it belongs in. The checked-in world file is
  authority for exactly one question — whether a protagonist-held row is the
  story's starting kit — because a pre-PR-111 take wrote that same row and the
  turn log therefore cannot answer
- **Character** → `location`, WHERE THEY ARE: one place at a time, the `Item`
  shape applied to people, and `Character.present_in(location)` is the closed
  set `talk` resolves against exactly as `Item.lying_in` is the one `take`
  resolves against. Nullable, because nowhere is a real state. Written by the
  seed file (`characters[].location`), by `Character::Registry`, by the explicit
  `Character#move_to!` and by `rake game:backfill_whereabouts` — and **by no
  prose, ever**. The PARTY is the deliberate exception and stays derived: the
  protagonist and anyone `is_companion` are wherever the *playthrough* is, since
  two people playing one world stand in two rooms at once
- **Character::Registry** → the people half of the noun registry, and the only
  thing in the app that creates a `Character` outside `rake game:new`. Two
  jobs, and the first is the Tide Post defect written down: it places somebody
  who is nowhere and **never moves somebody who is not**. The second is the
  captain's *"rooms should be born with people in them sometimes"* — 0–2 people
  written as records when a room is realized, out of the same call that
  describes it (`Location::DetailSchema`'s optional `people`), exactly the way
  `Item::Registry` writes the furniture. **Who they are the engine decides**:
  race, age and sex are rolled by `#slots` and stated in the prompt before the
  model answers, so one instance per realization or the room is described
  around one person and written around another. Three bounds read back from
  the records — `MAX_PER_CALL` (2), `MAX_PER_ROOM` (3), `MAX_PER_STORY` (12),
  the last two reported by `rake game:doctor`. It refuses a name a character,
  an item or a place already has, and **a sheet the provider cut off**: a
  truncated field is a failed call everywhere else, and here it must not be,
  because the call it would fail is the room's description, already saved
- **Item** → `readable` and `inscription`, **what is written on a thing that has
  writing on it**. A note, a letter, a sign, a label: the words are a record the
  engine owns, so what a note says cannot drift between two readings. It is
  orthogonal to WHERE it is and WHICH LAYER it is in — a note lying in a room,
  one in an NPC's hands and one a party is carrying all keep their text, and
  every copy `Item::Snapshot` makes copies the words with it.
  `readable` is the whole gate — nothing generates text for an item the world
  did not mark readable, and `Item` refuses an inscription on one that is not.
  Written in two places only: `Item::Registry` at room realization, out of the
  same answer that named the thing (`Location::DetailSchema`), and a seed file.
  `Item::Inscriber` is the third and it fills a gap rather than opening one —
  **one structured call, on the first read of a readable thing that arrived with
  no words, once and never again**. `Playthrough::Classifier` gives `examine` a
  resolved target against what is lying here PLUS what the party carries (the
  only action that reads both sets), and `Playthrough::Turn#read_item` hands the
  narrator the words verbatim and quoted
- **Item::Registry** → how items come to *exist*, and the only thing in the app
  that creates one: 0–3 things written as records when a room is realized, out
  of the same call that describes it (`Location::DetailSchema`'s optional
  `items`). Not a narrator tool and not a scan of prose — the engine owns what
  exists and `Playthrough::Moment` tells the narrator. Capped per room and per
  world, and it refuses a name a person, a place or another item already has
- **Scene** → `characters`, a DERIVED SNAPSHOT of who the records put in the
  room, written on every branch by `Playthrough::Turn#play` out of
  `Character.present_in`. Kept rather than dropped because it answers a
  different question from the whereabouts column — where somebody WAS, which a
  column with no history cannot reconstruct, and which `Eval::Richness`, the
  `still_run` check and both frozen corpora read. Only its direction changed:
  184 of the 480 baseline turns had no cast at all, because only an arrival and
  a talk ever wrote one
- **Scene** → `typed`, what the player typed to cause the turn, written on every
  branch by `Playthrough::Turn#play`. Nil only on an opening arrival
- **Scene** → `resolved_action` and `acted_on` (polymorphic), **what the turn
  DID and to which record** — the move's destination, the person spoken to, the
  item taken or dropped. Written beside `typed`, in the same one place that has
  the command and the scene on every branch, and by `Playthrough::Mechanics` on
  the one branch that mode writes a Scene from. Both nullable: an opening
  arrival did nothing, a turn played before the columns existed recorded
  nothing, and an action with no record is a reach that resolved to nothing.
  `Scene#took?` / `#dropped?` / `#moved_to?` need BOTH halves, which is what
  makes them seams a check can trust. `rake game:backfill_transitions` labels
  old turns from the stored classifier answers and **refuses to guess**; read
  `Scene::TransitionBackfill`'s header before changing it. Read the columns
  through `#recorded_action` / `#acted_on_record`: a `Scene` also comes out of
  an `rake eval:run` database whose table predates them
- **Character** → `hostile`, and **Race** → `monstrous`, and **Location** →
  `danger`: **A WORLD CAN CONTAIN AN ENEMY, AND NOTHING FIGHTS YET.** The
  captain's ruling of 2026-09-04 — *"a universe should be able to have monsters
  as well as characters"* — answered with three columns on `hit_die`'s side of
  the layer split: rolled or derived by the engine, written by the seed loader,
  and **by no model, ever** (no schema field, no prompt, no prose scan). A
  monster is an ordinary `Character` with `hostile` set — `locations.mobile`'s
  argument one table over — and **the nine required fields are NOT relaxed for
  one**, because a monster you can talk to is a feature. `races.monstrous` makes
  a universe's bestiary the monstrous half of its own race list; `Race.monstrous`
  and `Race.peoples` are the two pools a GENERATED person is drawn from, and
  which one is a room's own `danger` (`Location::DANGERS`, a closed-set key whose
  value is faces of `DANGER_DIE` — the `DISTANCES` shape). `Location::Danger`
  rolls a room's danger when it is BORN (`Location::Generator#create_stub!`,
  never the opening room) and rolls one die per slot at realization
  (`Character::Registry#slots`); `deadly` is a seed file's word the engine never
  rolls. **Hostility is DERIVED in one line** for everybody the engine writes —
  `Character.hostile_by_default?`, the captain's seventh ruling — and a seed file
  says `hostile:` outright. `Playthrough#foes_in(location)` is the ONE reader:
  hostile, present, and alive **in this playthrough**, `id`-ordered like
  `Character.present_in`. **Captain call C4, his explicit word:** monstrous races
  DO reach `Universe#race_names` in both the `:place` and `:dialogue` audiences —
  no prompt template changed, only what the list contains.
  `EngineSweep::Invariants#hostility_unmoved` is `stat_blocks_unmoved`'s
  statement for all three columns (its own check, because two of them are not on
  a character), and `rake game:doctor` reports
  `hostile_without_a_stat_block` (safe), `monstrous_race_with_no_monsters` and
  `location_with_an_unknown_danger` (both **no repair**, stated).
  `lib/engine_sweep/scripts/a-monster-in-a-room.yml` walks it. There is no
  per-playthrough mark about hostility and no wandering; both are later slices
- **Character** → `level` and `hit_die`, **THE STAT BLOCK, AND IT IS THE
  WORLD'S**. `hit_die` (one of `Character::HIT_DICE`) is how tough the body is,
  and `level` is **stored and inert** — nothing reads it for behaviour, nothing
  advances it, and `#advance!` is the explicit call deliberately invoked from
  nowhere, exactly as `#move_to!` was when it landed. `#max_hp` is DERIVED and
  never stored: `hit_die + (level - 1) * (hit_die / 2 + 1)`, with **no ability
  term** — it gained none when the three abilities landed, because none of them
  is a constitution, `will` is nerve rather than stamina and the body's capacity
  is `hit_die`; said in the class header so the question is not reopened. Both
  columns are nullable: a character written before them has no stat block, which
  `rake game:doctor` REPORTS rather than anything inventing a value, and half a
  block is refused. Written by a seed file (`characters[].stats`), by
  `Character::Registry`, by `Character::Generator` and by
  `rake game:backfill_stat_blocks` — and **by no model, ever**:
  `Character::StatBlock` rolls it through `Roll`, and nothing in any schema or
  prompt asks for a number
- **Character** → `strength`, `dexterity` and `will`, **THE THREE ABILITIES, AND
  THERE ARE EXACTLY THREE**. The captain's ruling of 2026-09-04, evening —
  *"let's go with the 3 abilities"* — which corrects the earlier *"no
  abilities"*, a misunderstanding of the word. `Character::ABILITIES` is the
  closed list every reader iterates and **its order is load-bearing**:
  `Character::StatBlock` draws the hit die and then the three from ONE
  `Roll.generator` in that order, so a body is re-derivable for ever.
  `Character::ABILITY_RANGE` is 3..18 — 3d6's own bounds (`Roll.pool`), so a
  number outside it came from somewhere that is not the engine. Nullable, whole
  or nothing, and **`Character#abilities?` is its own predicate that must NOT be
  folded into `#stat_block?`**: that one gates `#max_hp` and through it every
  `playthrough_vitals` row, so widening it would nil every existing maximum
  between a migration and the backfill. Written by a seed file, by
  `Character::Registry`, by `Character::Generator`, by `Story::Repair` and by
  `rake game:backfill_stat_blocks` — and **by no model, ever**
- **Character** → `#check`, **ONE d20 UNDER THE ABILITY, AND THERE IS ONE
  KERNEL**. `Roll.die(20, rng:) <= score - penalty`: the penalty comes off the
  TARGET rather than onto the die, so the difficulty is a parameter on the thing
  being tried (`LocationConnection::DISTANCES`'s shape) instead of a second
  table. `Character::Check` is the record it answers — printable as
  `check strength -> d20(7) <= 12 PASS`, which is what `rake game:mechanics`'s
  `check <ability> [penalty]` prints and `rake game:sweep` asserts. **At a
  target of zero or less NO DIE IS THROWN**: the pass rate there is zero for
  ever, the answer is refusal-shaped, and the generator is left untouched so
  asking the impossible does not consume somebody else's roll.
  `Playthrough::Turn#check` builds the seed, beside `#harm!` and `#mend!` and
  for the same reason. There is no ability modifier, no DC ladder, no
  advantage and no skill
- **Roll** → the dice, and the one place a seed is built. Plain integer
  arithmetic over `(story, playthrough, story clock, sequence)` — **never
  `String#hash`**, which Ruby salts per process, the trap
  `WorldMechanic::ShuffleConnections`'s header already names. Determinism is
  what lets `DRY_RUN=1` print the numbers the real run writes
- **Playthrough::Vitals** → **HOW MUCH IS LEFT OF ONE BODY IN ONE GAME**, one
  row per `(playthrough, character)`: the `Item` layer split applied to people.
  **AN ABSENT ROW MEANS UNHURT**, which is the ordinary state of almost
  everybody in every world. `Playthrough#vitals_for` is the ONE reader — it
  answers a `Condition` value and never the record — and
  `Playthrough::Turn#harm!` / `#mend!` are the ONLY writers: no prose touches a
  number, and there is no narrator tool for damage. Created lazily at first
  contact by `Playthrough::Vitals::Snapshot`, called beside `Item::Snapshot`
  through the one seam `Playthrough::Snapshot`, so a room's things and its
  people are copied together or not at all. `hp_current` is the whole state and
  `#dead?` reads it, because two columns saying one thing can disagree
- **Playthrough** → `ended_at`, **THE GAME IS OVER, AND IT IS OVER FOR EXACTLY
  ONE REASON**. The captain's ruling of 2026-09-04: *"zero hit points means
  death. Playthrough is over and you can't do anything else. You have to start a
  new playthrough."* Written by `Playthrough::Turn#harm!` in the same
  transaction as the last hit point, on STORY time. `Playthrough::Turn#play` and
  `Playthrough::Mechanics#run` refuse every line while it is set, **in front of
  the classifier**, so a line typed into a finished game costs no model call and
  writes nothing at all; `Playthrough::Refusal.dead` is the refusal and
  `Playthrough::DeathNotice` the one author of the words the player reads. No
  death saves, no unconscious state, no scars, no revival, no
  restore-from-save — every one of those is deferred, and copy that hinted at
  one would promise a thing the app does not have
- **Playthrough** → **Playthrough::Drifts**: one row per turn on which a reach
  resolved to nothing. The drift counter; never pruned
- **Playthrough::Feedback** → the player's verdict on one turn (`good` / `weak`
  / `bad`, one per playthrough per **Scene**, amendable), with an optional note
  and the turn's **provenance frozen onto the row** — which model wrote the
  prose, **which version of the prose instructions it wrote under**
  (`prose_prompt_digest`, out of `Playthrough::PromptVersion` — the ROADMAP's
  `ta-prompt-bench` ask, and the same digest `rake eval:prompt` records so a set
  and a verdict group by one version), the prose attempt chain, every model that
  answered, the token counts.
  Frozen rather than referenced because `Playthrough#prune_conversations!`
  destroys the receipts wherever `TA_CHAT_KEEP_TURNS` opts into a cap (the
  default keeps them, so this is belt and braces); the `Scene` itself stays a
  reference
- **Character** → `#interaction_instructions`, the prompt every conversational
  turn is built on. Its voice rules are scoped per register — first person
  inside the quotes, named and pronouned outside them — and
  `#addressee_section` tells an NPC who is in front of it using only what
  meeting somebody would tell them, and `InteractionAgent#character_prompt` adds
  the moment (`Playthrough::Moment#character_context`) and names the speaker;
  no talk prompt says "the user". `#pronoun_forms` is for a prompt that builds a
  sentence, `#pronouns` for one that states a rule. The protagonist's `backstory`,
  `personality`, `likes`, `dislikes` and `fears` are deliberately withheld; see
  `AGENTS.md` → *Talking to models*
- **WorldMechanic** → **WorldEvents**: the world changing itself on the story's
  clock. `kind` and `cadence` are keys into fixed tables in code, so a seeded or
  generated world supplies parameters (`locations.mobile`, the cadence) and
  never behaviour
- **WorldSeed::Loader** → **RE-SEEDING A WORLD SOMEBODY HAS PLAYED**, which is
  what the loader's rules are about: it is how a file change reaches the
  database the captain plays. It *reconciles what the file can prove, says out
  loud what it cannot, and deletes nothing*. A room or an item the file renamed
  is the same row renamed, on `WorldSeed.natural_key` (case, whitespace and a
  leading article are not part of a name — and nothing wider, because folding
  two different rooms into one would destroy play); a doorway
  `WorldMechanic::ShuffleConnections` has moved is left where the world put it
  rather than written back as a second one; a rename no normalized name
  recognizes is created and named in `#warnings`. `#validate!` refuses a file
  whose own rooms or items are one name to a re-seed, and a
  `shuffle_connections` whose edges all hang off ONE mobile room (PR 85's
  authoring note, made a rule). `rake game:doctor` names the shapes an older
  database already carries — `duplicate_locations`, `duplicate_items`,
  `mobile_doorway_re_asserted` — each with a `safe` fold in `Story::Repair`,
  the only repairs there that remove a row: what is on the row a re-seed
  created is moved onto the row with the history first, and a row anybody has
  touched is refused. `lib/engine_sweep/scripts/reseed-a-played-world.yml`
  walks it offline

- **Playthrough::Grammar** → **THE FIXED GRAMMAR, AND IT IS ONE COPY**: a closed
  verb table and a name matched against `Playthrough::Classifier#offered_for`,
  making no model call and writing nothing. It was `Playthrough::Mechanics`'s
  private half until the captain's ruling of 2026-09-04, evening, and is now the
  FIRST reader of a SLASHED browser line too. `#reading_first` is what a caller
  with a model behind it asks — it claims a line beginning with `/` **and
  nothing else** (the ruling of 2026-09-05), answers only when it RESOLVED a
  record, and defers everything else; `#parse` is what `model: false` and
  `Eval::Classifier::Offline` reach, and it always answers, slash or no slash.
  `JOINING_WORDS` is the one guard that lives on the first and not the second:
  a resolved line still carrying `and`, `then` or a comma once the matched name
  is cut out of it goes to the classifier instead, because a fixed grammar has
  no `also_named` and playing half a line would break the one-line-one-act
  ruling. Measured on the classifier bench's 300 labelled lines: 59 of 300
  resolve offline in slash form, none of them wrongly — and **0 of 300 without a
  slash**, which is the ruling of 2026-09-05 stated as a number
- **Scene** → `resolved_by`, **WHICH READER ANSWERED THE LINE**, one of
  `Playthrough::Grammar::PATHS`. Nullable by history and stamped `model` on older
  turns by `Update::Steps::StampResolvedBy`; nil for ever on an opening arrival.
  `Scene::TURN_READERS` is the narrower list a turn can honestly carry and
  `rake game:doctor` names a row outside it (`scene_with_an_unknown_reader`). It
  exists because a grammar-resolved turn calls no classifier and so writes no
  `Playthrough::Drift` or `Playthrough::Overreach` row
- **Playthrough::SlashMenu** → what the play box completes on, rendered into the
  form as a data attribute on every turn and fetched from nowhere: the five verbs
  of `Playthrough::Grammar::RESOLVING` and, per verb, the closed set
  `Playthrough::Classifier#offered_for` gives that action. One Stimulus
  controller reads it (`slash_controller.js`, scoped INSIDE `#turn_log` so the
  end-of-turn replace renews it), and with no JavaScript the box is a plain text
  field

- All interactions with AI LLMs should use a structured output with RubyLLM::Schema

### When a world outlives its seed file
- A world here outlives its seed FILE as well as its schema: The Salt Assizes
  was seeded one evening and the file gave the tide-slate its words the next
  morning, and nothing the captain ran after pulling looked at seed files.
  **`bin/update` re-seeds when a file under `db/seeds/worlds` moved in the range
  it pulled** — `Update::SeedFiles` is the decision, `rake game:reseed` the act,
  `--seed` forces it where there is no range. A re-seed **re-asserts the file's
  values over the world's own rows, seeded stats included**; it adds and
  updates, deletes nothing, and writes the world layer only.
- **Item::TemplateRefresh** → the other half, because a re-seed must not reach
  into a game in progress: a playthrough's copy made before the edit still
  carries what the world used to say. `rake game:doctor` reports
  `copy_lags_its_template` for a copy **no turn has acted on** (`safe`; the
  repair takes the text off the template) and `touched_copy_lags_its_template`
  for one a take or a drop has handled (`manual`, left alone). `TEXT` is the
  whole of what moves — where a thing is and whose hands it is in are the
  player's, which is `Item::NOT_COPIED`'s line drawn from the other side

### Applying a change to a database that already exists
- **`bin/update` is the one command after a pull**, and `Update::REGISTRY`
  (`lib/update.rb`) is the repo-owned list of what it then does to the rows
  already there — three backfills, the safe half of `Story::Repair` for every
  story, then `Story::Doctor`. A PR that needs a post-update action **adds a
  step to that registry and says so in its body**; it does not add a hand list
  of commands to the description. See `AGENTS.md` → *A PR that needs a
  post-update action adds a step, not a sentence*.
- A step is a subclass of `Update::Step`: a key, a one-line reason, and a `#call`
  that honours `dry_run`. Three rules, pinned by `Update::RegistryTest` —
  idempotent, quiet when it has nothing to do, offline. A refusal the step can
  never resolve (`ambiguous`, `unrecoverable`) is a `note`, never a change.
- **No step may make a model call.** `Update::Step.model_calls?` is the gate,
  built before anything needed it and asserted empty, because this runs
  unattended against the captain's primary development database.
- `Update::Runner` asks every step what it WOULD do before asking it to do it,
  stops on the first failure and names the step. `bin/update --dry-run` writes
  nothing at all, not even the pull.

### When a model will not write the turn
- A refusal is a 200 OK, so it used to be saved as the `Scene` the player reads.
  `BaseAgent::Refusal` is the detector and `BaseAgent#verify_not_refused!` makes
  it a failed call, so the existing rotation gets a second try at the turn.
- `mistralai/mistral-medium-3.1` — which refused nothing in the measured sweep —
  is now **first** in `REMOTE_MODEL_IDS` rather than the model rotation falls to,
  so a refusal-triggered rotation lands on `minimax/minimax-m3`, the model that
  refuses. Acceptable on the measurement, but the net no longer has a
  known-compliant model behind it. The note on the constant states the trade.
- **Precision over recall, decided by measurement**, exactly like `Story::Audit`:
  127 real prose responses in `test/fixtures/files/refusal_corpus.skeleton.json`,
  pinned by `BaseAgent::RefusalPrecisionTest` at recall 11/11 and zero false
  positives. Do not replace the structural rule with a word list; that was
  measured and it fails in both directions.
- The corpus ships **reduced**, because the repo is public and the responses are
  what models said when asked for explicit content: every letter is `x` except a
  capital `I` and the literal crisis strings. `RefusalCorpusSkeleton` is the
  reduction, and it preserves every offset, so the detector reads exactly what it
  read before — 207 records compared raw against reduced, 0 mismatches. Do not
  replace it with a smaller corpus of refusals only: ordinary narration stresses
  none of the three rules, which was measured too.
- A **truncated field** is a failed call on the same side of the line, and it
  reaches the rotation through `BaseAgent#ask`'s `verify:` seam rather than by
  living in `BaseAgent`: the caps are `Interaction::Schema`'s and the rule is
  `SanitizesGeneratedText`'s, so only the raise moved inside the attempt loop.
  Calling a sanitizer on a response `#ask` has already returned puts the raise
  outside the rotation, which is what it did before. See AGENTS.md.
- A **failed turn** shows `Playthrough::TurnFailureNotice`, never `e.message`.
  The real error goes to the log.
- A **crisis response** is a separate path with a separate outcome: intercepted,
  never persisted, answered by `Playthrough::SafetyNotice` out of band. The two
  never collapse into one branch. Read `Playthrough::SafetyNotice`'s header
  before changing a word of what the player is shown.

### Keeping the conversation audit trail
- `Chat::KEEP_TURNS` is **nil by default: nothing is pruned.** Measured at
  ~4 KB a turn on disk (4 MB per 1,000 turns) against a `models` registry that
  ships at 912 KB, the old 25-turn ceiling was never justified by the file size
  it was defending. `TA_CHAT_KEEP_TURNS` survives as an opt-in cap and
  `Playthrough#prune_conversations!` is kept to apply it. See the constant's
  comment for the figures and `AGENTS.md` → *Bounds*.

### Recording what the player thought of a turn
- `Playthrough::Feedback` is an **evaluation instrument**, not a feature: one
  click under any turn on the play page, reviewed on the debug page, gated on
  the same `Playthrough::Debug.enabled?`.
- **The provenance is frozen on create and never re-snapshotted.** That is the
  rule the whole thing stands on — see `AGENTS.md` → *The captain's verdict on a
  turn* for why, and `Playthrough::FeedbackTest` for the test that proves it
  survives the pruner.

### Auditing narration against the records
- `Story::Audit` (`rake game:audit`) is the offline, deterministic sweep: no
  model call, no network. **Precision over recall, decided by measurement** —
  see its header comment and `Story::AuditPrecisionTest`, which pins the exact
  flags 24 real narrations earn. Do not add a check that scans prose for a name;
  that was measured and it does not work.
- It carries **twelve checks in five categories that are never merged**:
  contradictions (`unreachable_transition`, `item_not_held`,
  `unrecorded_departure`, `unrecorded_arrival`, `take_denied`,
  `pickup_invented`, `inscription_misquoted`), defects (`truncated_prose`, `third_person_protagonist`),
  drift (`reached_for_nothing`), limits (`named_more_than_one` — the loop's
  limit, not a defect; both of these count REFUSED turns since the ruling, and
  `Story::Audit#judgeable_for`'s note says what that did to the denominator)
  and pacing (`still_run` — evidence about pacing,
  explicitly *not* a defect). `Story::Audit::Prose` holds the text predicates as
  pure functions so the live database and the frozen corpora read them through
  the same code.
- **`take_denied` and `pickup_invented` read a CHANGE, not a state**, and they
  are the only two that can. Every other check reads one scene against the world
  as it stands; these read a narration against `Scene#resolved_action` and
  `Scene#acted_on` — what the turn DID. On a turn recorded as a `take` the item
  was demonstrably not the player's a moment earlier, so prose saying it already
  was denies the pickup the app made; on a `drop` it was, so prose lifting it
  off a floor invents one. Measured at **28 of 32 takes and 4 of 32 drops** on
  the 480-turn baseline of 2026-09-03, with zero flags on all three existing
  corpora. `Story::Audit::TransitionTest` pins it and states both misses. The
  prose fix is a separate task; this is the instrument that measures it.
- `inscription_misquoted` reads prose that QUOTES what is written on a thing
  whose words the records hold, and quotes it differently. Measured on all 367
  real passages in the four corpora — 92 of them quote somebody, 177 spans, and
  it flags **none** — with the captain's own narration (playthrough 15, scene 77)
  as the positive case. Two candidate widenings were measured and killed: `says`
  as a cue (7 flags, all dialogue) and the item's own name (3 flags, all
  dialogue). Its recall on real read prose is LOW and stated: three live read
  narrations, two quoting the record, and it detected neither. See
  `Story::Audit::InscriptionTest`
- `Playthrough::Drift` is the classifier drift counter: one row per turn on which
  a `move`, `talk`, `take` or `drop` resolved to nothing. Never pruned.
- `Playthrough::Overreach` is the other counter and never the same one: one row
  per turn on which the typed line named **two things the records really have**,
  which since 2026-09-04 is refused whole rather than half-played. Drift is a
  reach that found nothing; this is a reach that found more than a turn can
  answer. Adding them together would produce a number that is neither. Read
  `acted` as what the line RESOLVED to, not as what was done to it. Never
  pruned. Both are
  **unavailable to a scripted `rake eval:run`** — a script types a fixed line,
  so either figure would measure the yml file (`Eval::UNAVAILABLE_TO_A_SCRIPT`).
- `Playthrough::IntentSchema#also_named` is how the loop knows the line asked
  for two things: one more name out of the **same closed set** as `target`,
  resolved by the same matcher against the same list the action reads. It is
  what the whole refusal hangs on, and it is deliberately narrow — a second name
  in a DIFFERENT set ("take the stamp and go to the hallway") is invisible to
  it, in both modes, because a second and looser way into the records is what a
  closed set exists to prevent; pinned as a gap in
  `lib/engine_sweep/scripts/one-act-per-line.yml`. One name and not a list,
  because an empty required array reads as an omitted field to
  `BaseAgent#missing_schema_keys` — see the constant's comment before changing
  its shape.
- `Item` is in exactly one place — lying in a location, held by one of the
  world's own characters, or carried by a playthrough's party. `take` and `drop`
  are both app-owned: the row moves first, the narrator is told afterwards.
- **`character_not_present` was measured and NOT shipped**, and `Story::Audit`'s
  finding 5 has the numbers. The whereabouts record made the check conceivable —
  the records are authoritative about presence now — and the corpora still
  cannot support it: 104 of 248 passages are judgeable (36 before one seeded
  world gained a monster, and the numerator did not move), exactly one names
  somebody recorded elsewhere, and moving one seeded character one door makes
  real, correct prose ("Grenn's voice rises from somewhere below") read as a
  violation. The gap stays covered by the engine instead: a player cannot SPEAK
  to somebody who is not there, whatever the prose says about them.

### When the engine will not play a line
- **One line, one act.** The captain's ruling of 2026-09-04: two acts on one
  line are refused and the player is asked to pick one; a line the engine cannot
  resolve is refused and the player is asked for clarification. Both stay in the
  mechanics — no narrator, no model call beyond the classifier that had already
  run. `Playthrough::Refusal` is the one author of the sentence and
  `Playthrough::Classifier::Intent#refused?` the one decision.
- **A refused line writes nothing**: no row moves, no `Scene` exists,
  `Location#last_protagonist_visit` is untouched, `Story#clock` does not advance
  and the playthrough stays where it was. In the browser it arrives through
  `NarrationJob`'s ordinary end-of-turn `#turn_log` replace, with the typed line
  echoed and the input back under it.
- **The counters are untouched by the ruling.** `Playthrough::Overreach` and
  `Playthrough::Drift` are written from inside
  `Playthrough::Classifier#classify`, before the loop asks whether it will play
  the line. It changed what a turn does, not what is measured; `rake game:score`
  is byte-identical across it.
- **What is NOT refused**: `examine`, and `other` with nothing failing to
  resolve. "look at the sky", "wait", a remark to nobody — the classifier placed
  them and they reach for no record by design. And two acts across two different
  closed sets, which `#also_named` cannot see; that gap is pinned as a gap in
  `lib/engine_sweep/scripts/one-act-per-line.yml`.
- `Playthrough::Turn#reach_fact` is **gone**, with the branch that narrated a
  failed reach. `take` and `drop` still use `Scene::Narrator#narrate(fact:)` for
  what they DID; only the reach case left that seam.

### When the player is dead
- **Zero hit points means death and death ends the playthrough.** The captain's
  ruling of 2026-09-04. `Playthrough::Turn#harm!` writes the last hit point and
  `playthroughs.ended_at` in one transaction; `Playthrough::Turn#play` and
  `Playthrough::Mechanics#run` then refuse every typed line **before the world
  catches up, before the snapshot and before the classifier**, so a line typed
  into a finished game costs no model call and writes nothing.
- **The refusal is engine output, never narration.**
  `Playthrough::Refusal.dead` is the fourth shape and `Playthrough::DeathNotice`
  is the ONE author of both the refused-line sentence and the standing statement
  the play page shows where the input used to be. Read its header first.
- **What is NOT built, and it is deferred rather than missing**: death saves, an
  unconscious state, scars, revival, restore-from-save, and any level
  advancement rule. There is also no attack ROLL, no AC, no initiative, no rest,
  no skill, no spell, no number on an `Item`, and no `Story::Audit` prose check
  reading HP against narration. There ARE three ability scores since the evening
  of 2026-09-04 (see `Character`), and nothing connects a wound to a check: a
  hurt body rolls against the same number. **A FIGHT DOES RESOLVE** since
  2026-09-05 (`Playthrough::Riposte`, `Playthrough::Fight`, `attack <name>`), and
  a blow can take the last hit point — which is what makes this section reachable
  from play rather than only from `harm 5`.
- `lib/engine_sweep/scripts/death-ends-a-playthrough.yml` walks it: harm to
  zero, then every kind of line refused with nothing written.
  `the-unrecorded-hour-two-bodies.yml` walks the other half — one game ending is
  one game ending.

### When a fight resolves
- **A blow always connects and deals one die of the attacker's `hit_die`** — the
  captain's call C2, measured in `data/ta-combat-scout` §7.2. No to-hit, no
  armour, no critical, no initiative and no ability term.
  `Playthrough::Turn#damage_for` is the rule and `#strike!` is the ONE writer of
  `playthrough_blows`.
- **A ROUND IS THE TURN** (call C5). `Playthrough::Riposte#run!` is step 7 of
  `Playthrough::Turn#play` and of `Playthrough::Mechanics#run`: every live foe in
  the room the turn BEGAN in acts, in `id` order. It runs on every line the
  engine PLAYED — a look, a read, a move — and on no line it refused, because *a
  refused line writes nothing*. On a move, the foes in the room you LEFT act
  before you go; the fight is over the moment you are somewhere else, which is
  call C1 (*a fight is always escapable by leaving the room*) with a price on it.
- **`attack <name>` resolves against the FULL present-people set** — the
  captain's sixth ruling of 2026-09-05, *"anyone can be attacked"*. It is in
  `Playthrough::Grammar::VERBS`, `ENGINE_VIEW` and `RESOLVING`, so it makes no
  model call in either mode, and it is NOT in
  `Playthrough::IntentSchema::INTENTS`, `Drift::ACTIONS` or `Overreach::ACTIONS`
  — the seventh intent is a measured slice of its own. Being attacked marks the
  victim **provoked for this playthrough** (`playthrough_vitals.provoked_at`,
  one writer: `Playthrough::Turn#provoke!`), and a provoked person strikes back
  from the next turn. `characters.hostile` is the world's and never moves.
- **Playthrough::Blow** → the exchange, one durable row per blow, and
  **Playthrough::Fight** → ONE `Scene` when the fight ENDS. A Scene per round
  would put engine copy in the column `Story::Audit` and `Eval::Richness` read as
  narration once per round; writing none at all would stop `Story#clock`. So the
  rounds are rows and the closing Scene carries `resolved_action: "attack"`, the
  foe in `acted_on`, `Scene::TURN_MINUTES["action"]` per round of story time, and
  the ENGINE's own sentence in `description` — no model call, in either mode. A
  fight ends for exactly three reasons and `Fight#over?` is where they are
  written: no live foe present, the party left the room, or the player is dead.
- **`Scene#engine_authored?` keeps the audit honest.** `Story::Audit#scenes` and
  `Eval::Richness` skip those rows and `rake game:score` prints
  `Story::Scoreboard#excluded`, so a smaller denominator can never read as a
  better rate. **No combat prose check ships**; the corpora cannot answer one
  (`data/ta-combat-scout` §11.2 measured it).
- **Playthrough#cast_in** → WHO THIS GAME CAN SPEAK TO OR SWING AT, the
  playthrough-level reader that subtracts this game's dead, with the four readers
  repointed at it. `Character.present_in` stays the world's answer.
  `Playthrough::Turn#spill!` puts a dead body's own copies on the floor of the
  room it stands in, in the same transaction as the last hit point; the world's
  rows never move. `#harm!` ends the GAME only for the protagonist.
- **The player's body is level 3 with a d8 (18 hit points) in the seeded worlds**
  — call C1. `Character::StatBlock::STARTING_LEVEL` stays 1 for a generated
  person. It reaches an existing database through `bin/update`'s re-seed and
  does not touch `playthrough_vitals`.
- **A sweep script may not assert a die.** `Roll`'s seed is built out of row ids,
  so `EngineSweep::Expectation`'s `blows:` and `hp_of:` are the die-independent
  instruments; `a-fight-the-player-wins.yml` and
  `a-fight-that-kills-the-player.yml` walk both outcomes and each says in its
  header why its ending is fixed whatever the dice say
- **Playthrough::Battle** → **THE FIGHT IN THE BROWSER, AND IT IS THE RECORDS
  RENDERED.** The captain's call C9 of 2026-09-05 — *"go with buttons for now"* —
  which is the combat scout's §12 shape (a): a `.sheet.battle` panel inside
  `#turn_log` (`playthroughs/_battle`), rendered when
  `Playthrough#foes_in(current_location)` answers with somebody. **DERIVED, WITH
  NO BATTLE FLAG ANYWHERE**: it arrives the turn a foe is in front of the party
  and is gone the turn the last one dies or they walk out, and there is nothing
  to reconcile either way because the fight wrote through the records the prose
  loop writes through. This class is the ONE author of what the panel says, for
  `Playthrough::Refusal`'s reason, and it WRITES NOTHING and calls no model.
  **ONE UI**: every button is `turns#create` with a fixed command string, and the
  string is SLASHED (`/attack Marek Sollen`), so `Playthrough::Grammar` reads it
  and the classifier never runs — **a round costs zero model calls**, measured in
  the browser (three chats for two `/go` moves, none for two rounds). The
  free-text box stays under the panel: this is a shortcut into the one loop and
  not a mode. **Condition lines and never bars** (`9 of 18`), because the reading
  experience is `ta-api-iface`'s stage — scout §15.6. `#throws` is the slice 5
  seam and answers `[]` until `throw` reaches `Playthrough::Grammar::RESOLVING`;
  its comment says what fills it. No prose per round: that is shape (b) and it
  needs `ta-prompt-bench`

### Sweeping the engine with stored scripts
- `rake game:sweep` (`EngineSweep`) walks YAML scripts of typed lines through
  `Playthrough::Mechanics` with `model: false` and asserts the records after
  each one: location, exits (with detail level), what is lying here, what is
  carried, **who is standing here** (`present:`), **which of them is a foe**
  (`foes:`), refusals and their offered
  alternatives. **Offline, deterministic, free, and run by `bin/rails test`** — the engine half of the game, which
  `rake eval:run` cannot see and which nobody was testing without a keyboard.
- **No model is a guard, not an intention:** `BaseAgent.new` is replaced for the
  length of a run and raises `EngineSweep::ModelCalled`. Each walk loads its own
  copy of the seeded world under a title of its own inside a rolled-back
  transaction, so it is safe against a database mid-game.
- `hostility_unmoved` is the same statement about an ENEMY: no typed line may
  write `characters.hostile`, `races.monstrous` or `locations.danger`. Its own
  check rather than three more keys on the one below, because two of the three
  are not columns on a character and an invariant reporting a moved race under
  the heading "stat blocks" would send a reader to the wrong table.
- `stat_blocks_unmoved` is the same statement about a BODY: no typed line may
  write `characters.level`, `characters.hit_die` or any of the three abilities,
  because a sheet is the world's — `check strength` throws a die and writes
  nothing at all, which is what
  `lib/engine_sweep/scripts/a-check-against-an-ability.yml` walks. What a walk DOES write is `playthrough_vitals`, on the other side of
  the layer split, so `harm 5` walks the whole engine without this moving.
- `EngineSweep::Expectation::KEYS` is **closed** — an unknown key raises rather
  than passing quietly. `EngineSweep::Invariants` checks the whole world after
  every walk, because an invented door and an over-full room are things
  `Location::Generator` writes and no typed line can. `cast_unmoved` is the same
  statement about people: nothing a player types may write a whereabouts, and it
  is stated as *unmoved* rather than *nobody is nowhere* because nowhere is a
  state two of the three checked-in worlds deliberately hold.
- A step may be a **`reseed:`** rather than a typed line: it re-loads the world
  file over the copy the walk is playing, so every expectation under it says
  what a re-seed did and did not disturb. It may name what that load renames
  (`locations:` / `items:`), which is the only way a walk reaches a rename — a
  rename is what the SECOND version of a file says.
  `reseed-a-played-world.yml` is that script, and the invariants after it read
  the file **as last loaded**.
- A step may carry `player:`, and **a distinct name is a second `Playthrough` of
  the same loaded copy of the world**. It is the one thing a single walk cannot
  see: with the inventory on the story's protagonist row both games read the
  same hands, so no one-player script could tell a story-level inventory from a
  playthrough-level one. `the-unrecorded-hour-two-players.yml` is that script,
  and it also pins what rooms still share.
- What an offline walk cannot see is written into the scripts themselves; see
  `lib/engine_sweep/scripts/regressions-2026-09-03.yml`.

### Generating runs and judging a change against them
- `rake eval:run` is the whole automated loop: play three seeded worlds through
  the real turn loop, keep every row, score them, print a board with its own
  noise floor. **[EVALUATION.md](EVALUATION.md) is the protocol.**
- **Generated runs are model output and two identical runs disagree.** One
  unchanged configuration produced 1 to 8 `third_person_protagonist` flags on the
  same eleven turns. Judge a change with `rake eval:compare BEFORE= AFTER=`,
  which answers REAL / NOISE / INCONCLUSIVE from an exact rank test; four runs a
  side is the arithmetic minimum for any verdict.
- **Generation costs money and never runs in CI**; scoring is offline and free.
- **`Eval::Richness` is printed beside the defect counts and never folded in** —
  prose that says less cannot contradict the records, so it is the check on the
  checks.
- `The Salt Assizes` is the held-out world. Tune on the other two.

### The prompt bench: one turn, fixed facts, per prompt version
- `rake eval:prompt` is the narrator's own instrument and the FIRST GATE a
  prompt-shaped change passes; `rake eval:run` confirms it. 90 hand-verified
  single-turn cases (`test/fixtures/files/prompt_corpus.yml`) played through the
  real `Playthrough::Turn#play` with **the classifier stood in for** — so the
  branch, the row that moves and the fact sentence are the app's — and ONE prose
  call a case.
- **Eight of `Story::Scoreboard`'s twelve checks are scored and the other four
  are UNAVAILABLE, never clean**: `Eval::Prompt::UNAVAILABLE_TO_A_CASE` states
  the reason for each. Beside them and never folded in: `Eval::Richness`,
  refusals, omitted schema fields, cap hits, tokens, warm latency and spend.
- **Two prompt digests, covering different amounts.**
  `Playthrough::PromptVersion` is the instruction block — the same digest
  `Playthrough::Feedback` freezes as `prose_prompt_digest`, so his verdicts
  group by prompt version as well as by model. `Eval::Prompt::Version`'s
  `prompt_digest` is the whole prompt of one designated case per shape, so it
  also covers `Playthrough::Turn#taken_fact` and everything
  `Playthrough::Moment` builds.
- `rake eval:prompt_compare` gives REAL/NOISE per check on `Eval::Noise` and
  says whether the MODEL or the PROMPT moved — refusing to be read when both
  did. A `talk` is deliberately not measured; see EVALUATION.md.

### The evaluation loop
- `Story::Scoreboard` (`rake game:score`) is the one command: a rate per check,
  the movement since a checked-in baseline (`db/eval_baseline.json`, rewritten
  only under `SAVE=1`), the agreement with `Playthrough::Feedback` verdicts, and
  **every flagged turn with what the player typed and the offending passage** —
  so the captain's attention goes only to what a check caught.
- **Three corpora, reported separately and never pooled**: the local database
  (his own playthroughs, true but small and drifting),
  `test/fixtures/files/eval_corpus.json` (92 real passages, frozen,
  reproducible with no database) and `test/fixtures/files/transition_corpus.json`
  (119 real take and drop turns with the transition each one made frozen beside
  the prose — the only corpus that can answer a check about a change). A check a
  corpus cannot answer is reported **unavailable**, never as zero.
- **No prose score, no judge model, no aggregate quality number.** Every check
  counts an error that is objectively present or absent, each measured for false
  positives on real prose before it shipped. `Story::Scoreboard::CorpusTest`
  pins 19 flags over 92 passages with zero false positives and zero flags on the
  24 lab narrations; the three turns the captain judged are caught by three
  different checks.
- **The small sample is stated, not hidden.** Below
  `Story::Scoreboard::MIN_VERDICTS` verdicts the report prints CORRELATION
  UNESTABLISHED and shows counts; the figure recomputes as he labels more.