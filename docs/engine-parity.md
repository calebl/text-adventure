# Engine parity

`test/engine_parity/` holds what the Rust engine does, step by step, when it
plays every sweep script in `lib/engine_sweep/scripts/`: one golden file per
script, and beside it what the doctor and the audit say about the database
the walk left (`<script>.checks.json`). An engine that plays the same scripts
over the same SQLite schema is at parity when it writes the same dumps.

## Who owns them

**The goldens are the engine's.** Its repository,
[renderedstep/engine](https://github.com/renderedstep/engine), writes them
with its parity binary and keeps them in `parity/goldens/`; this repository
vendors them at the commit the extension is pinned to, byte for byte, and
`bin/rails engine:vendored` fails when a copy here is not that commit's. The
Ruby turn loop wrote them until the engine took them over; the commit tagged
`ruby-reference-final` is where every turn moved to Rust, and every golden it
holds was unchanged when the engine took them over. No gate plays the Ruby
loop now.

**The checks files are this repository's.** The doctor and the audit are
Ruby, and they judge the rows the engine wrote; nothing in them asks the
engine what it thinks it did. Each file was first written from the Ruby loop,
where the Rust walk and the Ruby walk were judged alike on every script, and
changes only as a reviewed diff: `bin/rails engine:checks` rewrites them from
the Rust walk.

**Two readers of one set of rows.** A golden is the engine's own reading of
the rows it wrote (its `parity` module). `bin/rails engine:rust_gates` reads
the same rows with Ruby (`EngineSweep::Dump` over `Playthrough::Mechanics#state`)
and requires the two to agree, so a golden is never only the engine's word.

## The dump

One JSON object per step: `EngineSweep::Dump`. Its keys are exactly
`EngineSweep::Expectation::KEYS`, in that order, less `exits_include` and
`exits_exclude` (which only ask questions of `exits`). So a dump answers every
question a script could have asserted, whether or not this script asked it.

- A room is `{id, name, detail}`; a thing and a person are `{id, name}`
  (a person's `name` is the full name). Every set is sorted by name, then id.
- Ids are the walk's pinned ids (`EngineSweep::Walk::ID_BASE`): every table's
  counter starts there, so the same script gets the same ids on any database.
- `inscription` lists every thing in reach that is readable or written on,
  with `text` null when it is blank. `hp_of` maps each person present who has
  a stat block to their hit points. `quest` maps a beat's position (a string)
  to `unbound`, `bound` or `reached`; `ending` is `none` until one is reached.
- `drifts`, `blows`, `hazards`, `volitions`, `acts` and `elapsed_minutes` are
  what that one step added. `shown` is null unless the step rendered in a
  browser. A `reseed:` step is dumped as the read-out after the load.

A golden file is `{script, story, steps: [{step, player, typed, dump}]}`,
written with `JSON.pretty_generate` and a trailing newline.

## The engine contract

An engine answers `play(script)` with one dump per script step, in order.
`EngineSweep::Parity::InProcess` is the engine this app plays (below);
`EngineSweep::Parity::Ruby`, `EngineSweep::Walk` with a listener, is the Ruby
reference loop, kept for asking by hand where the two loops part.

Any other engine is a command. It is run with the script's path as its last
argument and prints one dump per step, one JSON object per line, on stdout,
exiting zero. It is started with `OPENROUTER_API_KEY` and `TYPESAFE_API_KEY`
removed from its environment, and it must make no model call: it plays the
keyless game the sweep plays (`EngineSweep.without_a_model`). It loads the
script's world as `EngineSweep::Walk` does, under the title with
`EngineSweep::Walk::TITLE_SUFFIX` and ids from `ID_BASE`, and leaves the
database as it found it.

## The shared-database contract

A second, optional way to run a command engine, where the runner owns the
database. It is on when `ENGINE_DATABASE` is set (to anything but empty); the
whole-script contract above is unchanged and stays the default.

- The runner copies the database it is connected to into a scratch file, in
  a temporary directory it deletes when the script is done. The engine never
  sees the database the copy came from. On that file the runner prepares the
  world exactly as `EngineSweep::Walk` does: ids pinned at `ID_BASE`, the
  world loaded under the title with `TITLE_SUFFIX`, and it commits.
- For each typed step it runs
  `<command> --database <file> --player <name> <script>` with
  `ENGINE_STEP=<n>`, where `n` is the step's number as its label gives it
  (from 1), and without the provider keys, as above. The engine plays that
  one step on that file, leaves what it wrote there, prints that step's one
  dump on one line and exits zero. A nonzero exit fails the step.
- A player's playthrough is found on the file: players get playthroughs in
  the order they first appear in the script, so the n-th player's is the
  story's n-th playthrough by id, and a player not seen before gets the next
  one, created as the walk creates it. The counts in the dump (`drifts`,
  `blows` and the rest) are what the one step added.
- The runner plays every `reseed:` step itself, on the same file, with
  `WorldSeed::Loader`, and dumps it with the Ruby read-out, as `Walk` does.
- The engine prints `shown: null`. For a browser step whose expectation
  asserts `shown`, the runner fills it by rendering the playthrough's turn log
  from the same file.
- A `browser:` step's `replies` are the engine's to consume, in order,
  whichever provider asks. It exits nonzero when a call's purpose is out of
  order, when a reply is left over, or on a `prompt_includes` or
  `prompt_excludes` miss, as `EngineSweep::BrowserTurn` raises.

`test/support/per_step_engine.rb` is an engine of this shape made of the Rust
engine's extension, and `test/lib/engine_parity_test.rb` plays every script
through it. The engine's own parity binary is the other: its repository plays
it through this runner (`parity/runner.sh`).

## In process

`EngineSweep::Parity::InProcess` runs the shared-database contract without a
subprocess: this side prepares the file and plays the re-seeds as above, and
each typed step is `EngineSweep::Walk#play_step` on the file, played by the
Rust engine through its extension (`Playthrough::RustEngine`), which plays a
typed step with `EngineSweep::RustMechanics` and a browser step through
`Playthrough::Session`, answering its providers from the step's `replies`. A
step the engine could not play fails. The dump is built by Ruby from the rows
the engine wrote.

It is how the sweep walks: `rake game:sweep` (`EngineSweep.run`) checks every
step's expectation as it is played and the invariants over the file after the
walk. `bin/rails engine:rust_gates` (`EngineSweep::RustGates`) plays every
script the same way and holds it to its golden, the invariants, and its checks
file.

## Commands

```bash
bin/rails engine:parity                         # write the goldens from the Rust walk here
GOLDENS=<engine>/parity/goldens bin/rails engine:parity   # ... into a checkout of the engine
ENGINE="<command>" bin/rails engine:parity_diff # play every script through it and diff
ENGINE_DATABASE=1 ENGINE="<command>" bin/rails engine:parity_diff # one call per step, shared database
bin/rails engine:checks                         # rewrite the checks files from the Rust walk
bin/rails engine:vendored                       # the goldens, scripts and engine-owned vectors are the pin's
GOLDENS=<dir> bin/rails engine:rust_gates       # the gates, against another directory of goldens
```

`engine:parity_diff` prints the first divergence per script: the step, the
line typed, and the first key (in dump order) on which the two disagree, with
both values. `SCRIPT=<name>` narrows any of them to one script, and `GOLDENS=`
points `engine:parity`, `engine:parity_diff` and `engine:rust_gates` at another
directory of goldens. `engine:parity` also takes `ENGINE=` (and
`ENGINE_DATABASE=1`) to write what a command engine plays; the engine's
`parity/runner.sh --write` uses that for the scripts only this runner can play.
None of them calls a model; run them in a shell with neither provider key set.

## Changing behaviour

A rule change is made in the engine and carried here by the pin.

1. **In renderedstep/engine**: the rule and its tests; the sweep script, new
   or changed, stored as the engine stores scripts (less comments and `why:`
   notes); the goldens rewritten by `parity --write` (and `parity/runner.sh
   --write` for the scripts it plays through this runner), and any vector
   portion the engine owns blessed. Every changed key is a reviewed diff. Its
   CI plays the scripts against its own goldens, and runs this repository's
   `engine:rust_gates` against them with the extension built from the change,
   so a golden, an invariant or a doctor or audit finding that moved fails
   there first.
2. **Here**, once that merges: the pin (`ext/renderedstep/Cargo.toml` and its
   `Cargo.lock`), the script with its `why:` notes, the goldens and the
   engine-owned vector portions copied from the pinned commit, and the checks
   files rewritten by `bin/rails engine:checks` where a judge now says
   something else, with the reason in the PR. A migration, seed-loader keys,
   new doctor or audit findings and an `Update::REGISTRY` step come with it
   where the change needs them.
3. **A migration to a table the engine touches goes in lockstep.** The engine
   refuses a database whose tables changed shape, and there is no fallback, so
   the pin that knows the new shape lands with the migration, never after it.
