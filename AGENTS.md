# AGENTS.md

Guidance for AI coding agents working in this repository. It is the only such
file: `CLAUDE.md` imports it, so the two cannot disagree.

## Start here

**The code is the source of truth for what is built.** A decision lives in the
header of the file it constrains — read that header before changing the thing it
governs. This file holds the approach and the rules that apply everywhere; it
deliberately holds no counts, no measured numbers and no enumeration presented as
complete, because those go stale silently and a reader cannot tell. Where you
need a number, the constant is named here and the number is read from it.

There is no status file and no roadmap in this repo: the code is the record of
what is built, and the task queue lives in firstmate.

*Where the decisions live* below is the index — question, then the file that owns
the answer.

## What this project is

A text adventure that generates itself as the player explores, and keeps what it
generates. Rails 8.1 on SQLite; every model call goes through `BaseAgent`.

**The persistence model is the load-bearing design decision, and the schema
encodes it.** `Location` is the durable world — name, description, `lore`, the
`location_connections` graph (with `distance` / `time_to_travel` /
`travel_method`), `parent_location` for containment — generated once and then
reused forever. `Scene` is a moment in that world: `belongs_to :location`, plus
a `previous_scene` linked list and a `story_timestamp`. So revisiting a place
reuses the persisted `Location` while creating a new `Scene`. The world stays
fixed; time still moves. Generation happens at the `Location` boundary, never
twice for the same place. That split is the whole design — do not touch either
model without it.

The second split is the same idea applied to a *game*: the world's own rows and
one playthrough's copies share a table, told apart by a nullable
`playthrough_id`. `Item` is the worked example, `Playthrough::Vitals` the same
shape for bodies. Play reads the playthrough layer; a seed file and a generator
write the world layer.

## The standing constraint: the game engine is the source of truth

The captain's ruling, and it governs design decisions across the whole project:

> *"I would rather not depend on the narrator doing what we tell it to do. We
> should prompt it with rules if that makes it more likely that it will follow
> them though and save on tokens. But I think we ultimately need a verification
> process."*

**Nothing may depend on the narrator obeying its prompt.** Both halves, not one:
**inform and verify.** Prompt the narrator with the world's laws — cheap, and it
raises the odds — but never let a guarantee rest on its compliance. *Gate the
state, inform the prose, audit the difference.* An unenforced narration rule
costs a sentence; an unenforced state rule costs the game.

The README's turn diagram states it in the colours: purple is a model call, teal
is the app deciding from records it holds, and every branch is taken on a record
rather than on a label a model wrote — see
[README.md](README.md#how-a-turn-works). The pattern to copy: *do not ask a
model what should happen; ask it to pick from a set the app closed, then have
the app act.* `Playthrough::Classifier` is the worked example — it is a model
call, so it can be **wrong**, but its answer is a closed enum built from the
room's real exits and cast, so it cannot be **out of bounds**.

The full audit of every planned piece of work against this constraint is in
`data/ta-direction/report.md` §0.1 (firstmate repo).

## A prompt is not changed without a baseline to judge it against

The captain's ruling of 2026-09-06, and it is the other rule that stands over
everything: **always have a baseline for evaluating a prompt before deciding to
change it.**

Generated prose is model output, and two identical runs disagree by more than
most claimed improvements — [EVALUATION.md](EVALUATION.md) opens with the
current spread and keeps it current; do not quote a spread from memory. So "it
reads better" is not evidence, and neither is a single run either side of an
edit. Before touching `Scene::Narrator::INSTRUCTIONS`,
`Character#interaction_instructions`, `Playthrough::Classifier::INSTRUCTIONS`,
`Location::Generator`'s people, items and exits instructions, or anything else a
model is handed:

1. **Have a stored baseline the change can be measured against.**
   `rake eval:prompt` (fixed single-turn cases, cents a run) is the cheap first
   gate; `rake eval:run` confirms it; `rake eval:classifier` is the classifier's
   own bench and `rake eval:realization` is `Location::Generator`'s. Baselines
   are checked in under `db/eval/` and `db/eval_baseline.json` and replay
   offline for free.
2. **Judge the after against the before with a verdict that can say *noise***
   — `rake eval:prompt_compare` / `rake eval:compare`, four runs a side minimum.
3. **Re-baseline only once the change is judged.**

[EVALUATION.md](EVALUATION.md) is the protocol, in full. A prompt change shipped
without a baseline is a change nobody can defend — and a plausible-sounding
prompt fix has more than once been measured moving the wrong number, which is the
whole reason this rule is a rule (`Scene::Narrator::INSTRUCTIONS` and
`Playthrough::Turn#taken_fact` carry one such finding between them).

## The rules that apply wherever you are working

- **All LLM calls go through `BaseAgent`** (`app/agents/BaseAgent.rb`). Do not
  build a bare `RubyLLM::Chat`. Every call uses a structured output with
  `RubyLLM::Schema` — `Scene::Narrator` is the one documented exception, because
  a schema and token streaming are mutually exclusive; its header says so and
  says not to "fix" it.
- **Genuinely zero build step.** `propshaft` + `importmap-rails` +
  `turbo-rails`; no Node, no `package.json`, no watch process. A hard constraint
  from the captain — `jsbundling-rails`, `cssbundling-rails`, esbuild, Vite and
  any npm dependency are explicitly refused. **If something appears to need one,
  that is a reason to reconsider the something; stop and ask.**
- **Do not bind port 3000.** The captain runs his own long-lived server there.
  `PORT=3142 bin/dev` moves the whole formation; check a port is free before
  taking it, and never kill anything to free one.
- **An engine change earns a sweep script, not only a unit test.** A unit test
  written after a bug pins the bug; a script in `lib/engine_sweep/scripts/`
  walks the game a player walks and would have caught it. Both.
- **Every model needs a test file in `test/models/` and a factory in
  `test/factories/`, and a factory must not roll dice.** A random default turns
  every test that reads the value into a lottery and lands the failure on
  whoever runs the suite next; ask for a variation by trait instead.
  `test/factories/location_connections.rb` carries the full diagnosis of the
  1-in-35 flake that established this.
- **A PR that needs a post-update action adds a step to `Update::REGISTRY`
  (`lib/update.rb`) and says so in its body** — never a hand list of commands in
  the description. `bin/update` is the one command after a pull. No step may
  make a model call; `Update::Step.model_calls?` is the gate.
- **A world supplies parameters, never behaviour.** A seed file may say which
  key and which die; what that key *does* is a table in code.
- **Restyling is `ta-api-iface`, a stage of its own** — do not do it in passing.
- **The rake tasks build worlds; the browser only plays them.** There is no
  `rake game:play` and there is not meant to be — the loop lives in
  `Playthrough::Turn`, so a rake front end would be a second UI for no new
  capability. `README.md` carries the command surface in full.

## Where the decisions live

Read the header of the file named, not a summary of it.

| The question | The file that owns the answer |
| --- | --- |
| How a turn is read, branched and written | `app/models/playthrough/turn.rb` |
| What the engine says when it will not play a line | `app/models/playthrough/refusal.rb` |
| Which reader answered a line, and the offline grammar | `app/models/playthrough/grammar.rb` |
| What the narrator and an NPC are told about the moment | `app/models/playthrough/moment.rb` |
| The game with the prose taken out | `app/models/playthrough/mechanics.rb` |
| A body, its abilities, and the one check kernel | `app/models/character.rb`, `character/stat_block.rb` |
| How much is left of one body in one game | `app/models/playthrough/vitals.rb` |
| A fight, a round, and who strikes back | `app/models/playthrough/fight.rb`, `riposte.rb`, `blow.rb` |
| A place or a doorway that costs hit points | `app/models/playthrough/hazards.rb`, `toll.rb` |
| Where a room is, how big it is, and what a storey is | `app/models/location/box.rb` |
| A thing thrown | `Playthrough::Turn#throw_item!`, `app/models/roll.rb` |
| The dice, and the one place a seed is built | `app/models/roll.rb` |
| The two item layers, and who may write each | `app/models/item.rb`, `item/snapshot.rb` |
| What is written on a thing that has writing on it | `app/models/item.rb`, `item/inscriber.rb` |
| How items and people come to exist in a room | `app/models/item/registry.rb`, `character/registry.rb` |
| What `rake game:new` builds, in what order | `app/models/story/first_screen.rb` |
| Story time, and a world that moves on its own | `app/models/story.rb`, `app/models/world_mechanic.rb` |
| Where narration contradicts the records | `app/models/story/audit.rb` |
| The scoreboard, its corpora and its baseline | `app/models/story/scoreboard.rb` |
| Re-seeding a world somebody has played | `lib/world_seed/loader.rb`, `item/template_refresh.rb` |
| A database that outlives its schema | `app/models/story/doctor.rb`, `story/repair.rb` |
| What a pull then does to the rows already there | `lib/update.rb` |
| What an offline walk asserts after every typed line | `lib/engine_sweep/` |
| Model selection, refusals, and a crisis response | `app/agents/BaseAgent.rb` |
| What the play page renders and how a turn streams | `app/views/layouts/application.html.erb`, `app/jobs/narration_job.rb` |

## Before you finish

```bash
bin/rails test          # includes rake game:sweep
bundle exec rubocop
bin/rails zeitwerk:check   # app/agents/ uses PascalCase filenames
```

## Environment

- Ruby 3.4.10 via asdf/mise (`.tool-versions`). Rails 8.1, SQLite.
- `bin/rails db:prepare && bin/rails db:seed` — the dev database is not checked
  in; the seed step fills the `models` table and loads `db/seeds/worlds`. Since
  the RubyLLM `acts_as` migration that table **is** the model registry — RubyLLM
  resolves names out of it and does not fall back to the one the gem ships with,
  so an empty table resolves nothing. Offline; no API key.
- **The local rotation is OFF by default and needs `TA_LOCAL_MODELS=1`.** The
  captain's ruling, 2026-09-03: *"if we are still falling back to local models,
  let's stop doing that for now."* A local fallback does not fail, it ANSWERS —
  slowly, from a small-context CPU model — and every measurement downstream
  quietly becomes about a different model. With no key and no opt-in there is no
  model at all, and `BaseAgent::NoModelConfiguredError` says so in a sentence
  naming both ways out.
- With `TA_LOCAL_MODELS=1`, `ollama serve` must run; keep
  `BaseAgent::LOCAL_MODEL_OPTIONS` matching what is actually pulled.
- `OPENROUTER_API_KEY` (in a gitignored `.env` via `dotenv-rails`, or `.envrc`
  for direnv) is strongly preferred for interactive work. `BaseAgent` works down
  `BaseAgent::REMOTE_MODEL_IDS`; `OPENROUTER_MODEL` overrides the front of it.
- **Start the app with `bin/dev`**, not `bin/rails server` alone: a turn is a
  job, so a web process on its own accepts a command and narrates nothing.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session.
**No counts, no measured numbers, no enumeration presented as complete** — name
the constant instead, so a reader who needs the number reads it from the code
that has it. Do not repeat what the codebase already shows; point to the
authoritative file or command. Prefer rewriting or pruning existing entries over
appending new ones — this file got to this length by deleting what its own
sources already said, and it gets back here the same way.

**A new entry has to earn residency.** Ask where the reader is when they need
it: if the answer is "editing one file", it belongs in that file's header; if
"running one command", in that command's own docs; if "reading about the
protocol", in `EVALUATION.md`. What is left — the rules that bind wherever you
are standing — is what this file is for.
