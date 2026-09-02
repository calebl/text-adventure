# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Current status and the task queue live in [ROADMAP.md](ROADMAP.md).** Read it
before planning work, and update it when work lands. See [AGENTS.md](AGENTS.md)
for agent working agreements.

## Project Overview

Text Adventure is a Rails 8 application that creates AI-powered text-based adventure games: a world generates itself as the player explores it, and what it generates is kept. It uses the RubyLLM gem to reach models through OpenRouter (`minimax/minimax-m3`, falling back to `mistralai/mistral-medium-3.1`) or a local ollama; `BaseAgent` picks between them. It has a plain ERB browser interface on Hotwire with zero build step
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

# Check the stories in the database, fix what can be fixed, delete what cannot
rake game:doctor                    # or rake 'game:doctor[3]' for one story
rake game:audit                     # where narration contradicts the records; VERBOSE=1 for unjudged checks
rake 'game:repair[3]'               # safe repairs; GENERATE=1 to allow model calls
rake 'game:delete[3]'               # prints what would go; DRY_RUN=1 or CONFIRM='<title>'

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
     else. An unresolved reach writes a `Playthrough::Drift` row.
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
- **Item** → belongs to **Character** *or* **Location**, exactly one of the two:
  held by somebody, or lying in a place. The second half is what makes `take`
  and `drop` app-owned state changes rather than prose
- **Scene** → `typed`, what the player typed to cause the turn, written on every
  branch by `Playthrough::Turn#play`. Nil only on an opening arrival
- **Playthrough** → **Playthrough::Drifts**: one row per turn on which a reach
  resolved to nothing. The drift counter; never pruned
- **WorldMechanic** → **WorldEvents**: the world changing itself on the story's
  clock. `kind` and `cadence` are keys into fixed tables in code, so a seeded or
  generated world supplies parameters (`locations.mobile`, the cadence) and
  never behaviour

- All interactions with AI LLMs should use a structured output with RubyLLM::Schema

### When a model will not write the turn
- A refusal is a 200 OK, so it used to be saved as the `Scene` the player reads.
  `BaseAgent::Refusal` is the detector, `BaseAgent#verify_not_refused!` makes it
  a failed call, and the existing rotation reaches
  `mistralai/mistral-medium-3.1`, which refused nothing in the measured sweep.
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
- A **crisis response** is a separate path with a separate outcome: intercepted,
  never persisted, answered by `Playthrough::SafetyNotice` out of band. The two
  never collapse into one branch. Read `Playthrough::SafetyNotice`'s header
  before changing a word of what the player is shown.

### Auditing narration against the records
- `Story::Audit` (`rake game:audit`) is the offline, deterministic sweep: no
  model call, no network. **Precision over recall, decided by measurement** —
  see its header comment and `Story::AuditPrecisionTest`, which pins the exact
  flags 24 real narrations earn. Do not add a check that scans prose for a name;
  that was measured and it does not work.
- `Playthrough::Drift` is the classifier drift counter: one row per turn on which
  a `move`, `talk`, `take` or `drop` resolved to nothing. Never pruned.
- `Item` is in exactly one place — held by a character or lying in a location.
  `take` and `drop` are both app-owned: the row moves first, the narrator is told
  afterwards.