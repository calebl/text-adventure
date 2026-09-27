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

## Commands

```bash
bin/rails engine:parity                         # rewrite the goldens from the Ruby engine
ENGINE="<command>" bin/rails engine:parity_diff # play every script through it and diff
```

`engine:parity_diff` prints the first divergence per script: the step, the
line typed, and the first key (in dump order) on which the two disagree, with
both values. `SCRIPT=<name>` narrows it to one script.

`test/lib/engine_parity_test.rb` regenerates every golden and fails on any
drift. Neither command calls a model; run them in a shell with neither
provider key set.
