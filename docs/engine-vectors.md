# Engine golden vectors

`test/engine_vectors/` holds the engine's pure rules written down as data:
for each portion (the dice, a stat block, a spot in a room, a population, a
room's danger, a building's parameters, box geometry, an interior's layout,
a shuffle of doorways, a world mechanic's boundaries, a deadline's anchor, the
seeded cast draws) a list of cases, each with named inputs and the exact output
this Ruby code gives for them.

## What they are for

A second implementation of the same rules, such as a port of the engine to
another language, is tested by reading these files and reproducing every
output exactly. The vectors are the contract between the two: if the port
agrees with every case, it rolls the same dice, lays out the same buildings and
picks the same anchor as the Ruby engine for the same seed.

They also pin the Ruby side. `test/lib/engine_vectors_test.rb` regenerates
every file in memory and compares it byte for byte with the committed one, so
any change to a rule they cover fails the suite until the vectors are updated.

## Regenerating them

```bash
bin/rails engine:vectors
```

The task is offline: it makes no model call and writes no database. Portions
that need rows build them with explicit ids in an in-memory SQLite database
loaded from `db/schema.rb`, inside a transaction that is rolled back. Running
it twice gives byte-identical files.

## Changing behaviour

**An intended behaviour change updates the vectors in the same PR.** Run the
task, read the diff (one case per line, so a changed rule shows as the cases it
changed) and commit it with the change. A diff you did not expect is a
behaviour change you did not intend.

## The format

Each file is one JSON object; `lib/engine_vectors.rb` documents it in full and
each file's `notes` field says how to read its own inputs and outputs. In
short:

| Field | Meaning |
| --- | --- |
| `format` | always `"engine-vectors"` |
| `version` | `EngineVectors::FORMAT_VERSION`; bumped when a file's shape changes |
| `portion` | the file name without `.json` |
| `sources` | the Ruby files whose behaviour the cases record |
| `notes` | how to read this portion's cases |
| `constants` | the tables the portion reads, as `[key, value]` pairs so key order is kept |
| `cases` | one per line: `{ "name", "input", "output" }` |

A seed that can exceed 2^53 (in `roll.json`) is a decimal string; every other
number is a JSON integer. A time is whole seconds since the Unix epoch, UTC.

Adding a portion means a module under `lib/engine_vectors/` with `SOURCES`,
`NOTES`, `.constants_table` and `.cases`, and an entry in
`EngineVectors::PORTIONS`.
