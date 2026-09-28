# Engine golden vectors

`test/engine_vectors/` holds the engine's pure rules written down as data:
for each portion (the dice, a stat block, a spot in a room, a population, a
room's danger, a building's parameters, box geometry, an interior's layout,
a shuffle of doorways, a world mechanic's boundaries, a deadline's anchor, the
seeded cast draws, the reading of a typed line, and the requests built for a
model) a list of cases, each with named inputs and the exact output this Ruby
code gives for them.

## The line-reading portions

Six portions pin how a typed line is read and refused, all of it offline:

| Portion | What it records |
| --- | --- |
| `grammar` | `Playthrough::Grammar`: `unslashed`, `word_for`, `line_for`, and every line's `#claims?`, `#reading_first`, `#parse` and `#engine_view_reading` with and without a model -- every line the grammar's model test reads, and every verb swept over every name a room answers to |
| `grammar_corpus` | the grammar over every line of the labelled classifier corpus (the input of `rake eval:classifier_offline`), in the room the line was labelled against: both readings and the refusal sentence the player gets |
| `slash_menu` | `Playthrough::SlashMenu#to_h`: the words offered after a slash and what each completes to |
| `classifier_intent` | `Playthrough::Classifier#build_intent`: a model's intent, target, `also_named` and a throw's `thrown_at` resolved against the room's closed sets, and the refusal that follows |
| `cascade` | the System One cascade (`Playthrough::Classifier::Cascade` when it was written, the engine's `cascade` now): the request a line would send System One, and recorded answers composed into an intent or escalated to the model call. The engine's own |
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
carries are the engine's `data/playthrough/classifier/request.yml`, and the
`cascade` portion records only each question's id, type and options.

## The request-building portions

Nine portions pin what the engine hands a model, byte for byte, still without
calling one:

| Portion | What it records |
| --- | --- |
| `classifier_request` | the whole System One request for a typed line, every instruction and criterion as sent, in the rooms the line-reading portions stand in -- including the position `test/fixtures/files/scored_classifier_request.json` was sent for. The engine's own |
| `volition_request` | the typed volition request: the room written in `test/fixtures/files/volition_system_one_request.json`, reproduced exactly, and rooms of sweep scripts. The engine's own |
| `moment` | the narration context (with and without the floor plan and the arc, with a thing just taken or dropped, with each of the story's endings) and every other person's character context. The engine's own |
| `ledger` | what one person saw happen in one game, for everybody in games inside and past both of its bounds. The engine's own |
| `memory` | which earlier exchanges come back into a prompt, each one's resolution and recollection, and the moment's conclusions and recollections built on them. The engine's own |
| `plan` | `Location::Plan` for every room of built worlds and laid-out places |
| `request_identity` | RubyLLM's `to_json_schema` output for every schema a request carries, and `Eval::RequestIdentity`'s canonical form and 16-hex digest -- including the classifier and prompt sets `rake eval:classifier_digest` and `rake eval:prompt_digest` identify |
| `kept_requests` | literal requests stored in kept evaluation sets under `db/eval/` (arrival, realization), rebuilt by today's builders |
| `dialogue_requests` | the dialogue bench's literal kept requests, both passes. The engine's own |

These builders read many tables at once, so their cases do not describe a
room field by field. A case builds its records, runs the builder, and writes
down every row the database then holds as its `records` input: a second
implementation loads those rows into the same schema and must give the same
output. `lib/engine_vectors/records.rb` documents the shape. Where a moment is
worth recording, the game reaches it itself: a sweep script is played offline
through the engine and stopped after a chosen step
(`lib/engine_vectors/walked.rb`), so the blows, tolls and acts in it were
written by the engine's own statements.

The prompt text in these outputs is the engine's `data/`, which this game
reads through its extension (`EngineData`); the vectors record what the
builders make of it. The export stops if a kept request is no longer
reproduced.

## What they are for

A second implementation of the same rules, such as a port of the engine to
another language, is tested by reading these files and reproducing every
output exactly. The vectors are the contract between the two: if the port
agrees with every case, it rolls the same dice, lays out the same buildings and
picks the same anchor as the Ruby engine for the same seed.

They also pin the Ruby side. `test/lib/engine_vectors_test.rb` regenerates
every file Ruby writes in memory and compares it byte for byte with the
committed one, so any change to a rule they cover fails the suite until the
vectors are updated.

## The engine's own portions

A portion whose Ruby code nothing runs any more but the Ruby turn loop, which
no player plays, belongs to the engine: `EngineVectors::ENGINE_OWNED`, which
must equal the engine's `vectors/ENGINE_OWNED`. The engine blesses its file
(recomputes every case's output and the constants from its own code) as a
reviewed diff in its repository, and this repository vendors it at the pinned
commit: `bin/rails engine:vendored` fails when the copy here is not that
commit's, byte for byte. `bin/rails engine:vectors` leaves it alone, and a
Ruby builder stays where the Ruby loop still runs its rule, so that loop can
still be asked what it would have answered.

`shuffle_connections` joined it that way, and so did the five line-reading
portions `grammar`, `grammar_corpus`, `slash_menu`, `classifier_intent` and
`refusal` once the panels, the verbs a player may use and the slash menu were
read off the engine (`Playthrough::RustEngine.glance`). Two of those have no
Ruby builder left: the menu and the grammar's slash words and use lines were
only ever read for the panels. `physics` (falls) was written in the engine and
never had a Ruby builder, so it is the engine's from the start. Nor do the
request builders (`cascade`, `classifier_request`, `volition_request`,
`moment`, `ledger`, `memory`, `dialogue_requests`) have one: every request the
benches and the Ruby loop send is the engine's own, asked for through the
extension (`Playthrough::Requests`). Any other portion joins the list only once
its Ruby code runs nowhere else: `world_mechanic` stays Ruby's while the debug
view reads a mechanic's boundaries, the arrival and room writer's
`kept_requests` while world creation writes rooms and opening arrivals, and the
dice and geometry for as long as world creation, seeding, repair and the doctor
run them.

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
behaviour change you did not intend. A rule in a portion the engine owns is
changed in the engine, blessed there, and copied here with the pin that
carries it.

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
A case whose input is `records` holds rows as `lib/engine_vectors/records.rb`
writes them; a case that shares another's rows names it in `records_of`.

Adding a portion means a module under `lib/engine_vectors/` with `SOURCES`,
`NOTES`, `.constants_table` and `.cases` (or `.contents`, answering both at
once, where they come out of one piece of work), and an entry in
`EngineVectors::PORTIONS`.
