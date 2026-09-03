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

# Check the stories in the database, fix what can be fixed, delete what cannot
rake game:doctor                    # or rake 'game:doctor[3]' for one story
rake game:audit                     # where narration contradicts the records; VERBOSE=1 for unjudged checks
rake game:score                     # the scoreboard: a rate per check, the movement since the
                                    # baseline, and every flagged turn with what was typed and
                                    # the passage. SAVE=1 to re-baseline, CORPUS=corpus for the
                                    # frozen one alone
rake 'game:repair[3]'               # safe repairs; GENERATE=1 to allow model calls
rake 'game:delete[3]'               # prints what would go; DRY_RUN=1 or CONFIRM='<title>'

# Walk the engine with the NARRATION off and nothing else off: the classifier
# still reads what you type and the world still generates as you walk into it.
rake 'game:mechanics[The Unrecorded Hour]'   # or by id; PLAYTHROUGH=<id> to attach
NO_MODEL=1 rake 'game:mechanics[2]'          # offline fallback: fixed grammar, no generation

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
   - `Playthrough::Classifier` reads what the player typed against a closed
     enum of the room's exits, its cast, what is lying in it and what the player
     carries, and the turn branches on the answer: `Scene::Generator` for
     arriving somewhere, `InteractionAgent` for talking to somebody, an app-owned
     `Item` transfer for `take` and `drop`, `Scene::Narrator` for everything
     else. An unresolved reach writes a `Playthrough::Drift` row **and is stated
   to the narrator as a fact** (`Turn#reach_fact`). `Playthrough::Moment` is the
   one builder of what the prose and the character are told about the moment:
   room, exits, cast, inventory, last turn, recap. Add a fact there, not to a
   caller.
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
- **Playthrough::Mechanics** → the game with the prose taken out, and nothing
  else taken out with it (`rake game:mechanics`). The classifier still reads the
  command and prints what it resolved to; the world still generates itself, so a
  move is `Playthrough::Turn#move_to` whole. Only `Scene::Narrator` and
  `InteractionAgent` are dropped, and `talk` / `examine` are refused as prose.
  `model: false` (`NO_MODEL=1`) is the offline fallback — a fixed grammar, no
  generation, no model call at all — and it is the mode the engine-direct tests
  run in. See `AGENTS.md` → *The mechanics on their own, with the narration off*
- **Item** → belongs to **Character** *or* **Location**, exactly one of the two:
  held by somebody, or lying in a place. The second half is what makes `take`
  and `drop` app-owned state changes rather than prose
- **Scene** → `typed`, what the player typed to cause the turn, written on every
  branch by `Playthrough::Turn#play`. Nil only on an opening arrival
- **Playthrough** → **Playthrough::Drifts**: one row per turn on which a reach
  resolved to nothing. The drift counter; never pruned
- **Playthrough::Feedback** → the player's verdict on one turn (`good` / `weak`
  / `bad`, one per playthrough per **Scene**, amendable), with an optional note
  and the turn's **provenance frozen onto the row** — which model wrote the
  prose, the prose attempt chain, every model that answered, the token counts.
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

- All interactions with AI LLMs should use a structured output with RubyLLM::Schema

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
- It carries **seven checks in four categories that are never merged**:
  contradictions (`unreachable_transition`, `item_not_held`,
  `unrecorded_departure`), defects (`truncated_prose`,
  `third_person_protagonist`), drift (`reached_for_nothing`) and pacing
  (`still_run` — evidence about pacing, explicitly *not* a defect).
  `Story::Audit::Prose` holds the three text predicates as pure functions so the
  live database and the frozen corpus read them through the same code.
- `Playthrough::Drift` is the classifier drift counter: one row per turn on which
  a `move`, `talk`, `take` or `drop` resolved to nothing. Never pruned.
- `Item` is in exactly one place — held by a character or lying in a location.
  `take` and `drop` are both app-owned: the row moves first, the narrator is told
  afterwards.

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

### The evaluation loop
- `Story::Scoreboard` (`rake game:score`) is the one command: a rate per check,
  the movement since a checked-in baseline (`db/eval_baseline.json`, rewritten
  only under `SAVE=1`), the agreement with `Playthrough::Feedback` verdicts, and
  **every flagged turn with what the player typed and the offending passage** —
  so the captain's attention goes only to what a check caught.
- **Two corpora, reported separately and never pooled**: the local database (his
  own playthroughs, true but small and drifting) and
  `test/fixtures/files/eval_corpus.json` (92 real passages, frozen,
  reproducible with no database). A check the frozen corpus cannot answer is
  reported **unavailable**, never as zero.
- **No prose score, no judge model, no aggregate quality number.** Every check
  counts an error that is objectively present or absent, each measured for false
  positives on real prose before it shipped. `Story::Scoreboard::CorpusTest`
  pins 19 flags over 92 passages with zero false positives and zero flags on the
  24 lab narrations; the three turns the captain judged are caught by three
  different checks.
- **The small sample is stated, not hidden.** Below
  `Story::Scoreboard::MIN_VERDICTS` verdicts the report prints CORRELATION
  UNESTABLISHED and shows counts; the figure recomputes as he labels more.