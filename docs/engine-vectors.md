# Engine golden vectors

`test/engine_vectors/` holds the engine's pure rules written down as data:
for each portion (the dice, a stat block, a spot in a room, a population, a
room's danger, a building's parameters, box geometry, an interior's layout,
a shuffle of doorways, a world mechanic's boundaries, a deadline's anchor, the
seeded cast draws, and the reading of a typed line) a list of cases, each with
named inputs and the exact output this Ruby code gives for them.

## The line-reading portions

Six portions pin how a typed line is read and refused, all of it offline:

| Portion | What it records |
| --- | --- |
| `grammar` | `Playthrough::Grammar`: `unslashed`, `word_for`, `line_for`, and every line's `#claims?`, `#reading_first`, `#parse` and `#engine_view_reading` with and without a model -- every line the grammar's model test reads, and every verb swept over every name a room answers to |
| `grammar_corpus` | the grammar over every line of the labelled classifier corpus (the input of `rake eval:classifier_offline`), in the room the line was labelled against: both readings and the refusal sentence the player gets |
| `slash_menu` | `Playthrough::SlashMenu#to_h`: the words offered after a slash and what each completes to |
| `classifier_intent` | `Playthrough::Classifier#build_intent`: a model's intent, target, `also_named` and a throw's `thrown_at` resolved against the room's closed sets, and the refusal that follows |
| `cascade` | `Playthrough::Classifier::Cascade`: the request a line would send System One, and recorded answers composed into an intent or escalated to the model call -- every case in its model test, and a sweep |
| `refusal` | `Playthrough::Refusal` from each entry point, every case in its model test and a sweep |

They stand in rooms rather than on bare values: a line is read against the
ways out, the people, the floor and the hands of the room the player is in.
A room is a plain description with explicit ids, written once in the file's
`worlds` constant and named by each case; `lib/engine_vectors/room.rb`
documents its shape and builds it. A reading names a record by that id.
The corpus rooms are staged from their seed files the way the classifier bench
stages them, written down as room descriptions, and read in both forms; the
export stops if the two readings disagree.

No prompt text is copied into these files. The words a System One request
carries are `config/engine/playthrough/classifier/request.yml`, and the
`cascade` portion records only each question's id, type and options.

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

A seed that can exceed 2^53 (in `roll.json`) is a decimal string; a System
One reading (in `cascade.json`) is a JSON number between 0 and 1; every other
number is a JSON integer. A time is whole seconds since the Unix epoch, UTC.

Adding a portion means a module under `lib/engine_vectors/` with `SOURCES`,
`NOTES`, `.constants_table` and `.cases` (or `.contents`, answering both at
once, where they come out of one piece of work), and an entry in
`EngineVectors::PORTIONS`.
