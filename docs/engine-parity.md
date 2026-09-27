# Engine parity

`test/engine_parity/` holds what the Ruby engine does, step by step, when it
plays every sweep script in `lib/engine_sweep/scripts/`. A second engine that
plays the same scripts over the same SQLite schema is at parity when it
writes the same dumps.

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
`EngineSweep::Parity::Ruby` is the Ruby engine: `EngineSweep::Walk` with a
listener, playing exactly as `rake game:sweep` does.

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

`test/support/per_step_engine.rb` is an engine of this shape made of the Ruby
engine, and `test/lib/engine_parity_test.rb` plays every script through it.

## In process

`EngineSweep::Parity::InProcess` runs the shared-database contract without a
subprocess: this side prepares the file and plays the re-seeds as above, and
each typed step is `EngineSweep::Walk#play_step` on the file, played by the
engine it was built with. `:ruby` is the Ruby engine; `:rust` is the Rust
engine through its extension (`Playthrough::RustEngine`), which plays a typed
step with `EngineSweep::RustMechanics` and a browser step through
`Playthrough::Session` with the switch on, answering its providers from the
step's `replies`. A Rust step that fell back to Ruby fails. The dump is built
by Ruby from the rows the engine wrote. `bin/rails engine:rust_gates`
(`EngineSweep::RustGates`) plays every script both ways and holds the Rust
walk to the goldens, the invariants, and the doctor and audit of the Ruby walk.

## Commands

```bash
bin/rails engine:parity                         # rewrite the goldens from the Ruby engine
ENGINE="<command>" bin/rails engine:parity_diff # play every script through it and diff
ENGINE_DATABASE=1 ENGINE="<command>" bin/rails engine:parity_diff # one call per step, shared database
```

`engine:parity_diff` prints the first divergence per script: the step, the
line typed, and the first key (in dump order) on which the two disagree, with
both values. `SCRIPT=<name>` narrows it to one script.

`test/lib/engine_parity_test.rb` regenerates every golden and fails on any
drift. Neither command calls a model; run them in a shell with neither
provider key set.
