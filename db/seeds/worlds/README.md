# Seeded worlds

The playable worlds a fresh clone gets for free. `bin/rails db:seed` loads every
`*.yml` file in this directory — offline, with no model call, no API key and no
network — so `bin/rails server` has something to walk around in immediately.

Generating a world costs minutes of live model calls. These files are why you do
not have to.

```bash
bin/rails db:prepare && bin/rails db:seed   # loads the model registry, then these worlds
rake 'game:export[3]'                       # dump story #3 over the top of its file
```

## These files are authored, not dumps

`rake 'game:export[story_id]'` exists to bootstrap a world out of a real
generated one, and to rebuild these files when the schema changes. Everything
after that is hand editing, and that is the intended workflow: generate, export,
then edit the YAML until the world has the shape you want.

Both worlds here have been edited after export. `the-unrecorded-hour.yml` was
written by hand outright, to get a shape the generator cannot produce (below).

Two things to know before re-exporting over a file:

- The **leading comment block is preserved**. Put anything worth keeping there.
- Comments **further down the file are not** — YAML comments do not survive the
  parser. Long-lived notes belong in this README.

## The format

One file is one universe and one story. Keys are written in this order:

| key             | what it holds                                                          |
| --------------- | ---------------------------------------------------------------------- |
| `format`        | bumped when the format changes; the loader refuses one it cannot read   |
| `universe`      | the nine prompt fields, plus `races` (name and description)             |
| `story`         | title, genre, `start_time`, preface, summary                            |
| `opening_scene` | the narrated moment the story starts in — see below                     |
| `characters`    | one entry each, `race` by name, optional `items`                        |
| `locations`     | every location, realized or stub; exactly one marked `opening: true`    |
| `connections`   | one entry per edge, as an unordered `between: [a, b]` pair              |

Prose is stored in a `|-` block scalar: one paragraph is one physical line, so
editing a sentence is a one-line diff and what you type is what gets stored.

### `opening_scene`, and why one Scene crosses a line the others do not

```yaml
opening_scene:
  location: Ward Office 12
  characters: [Odile Vance, Halkett Rowe]
  description: |-
    The gap in your daybook is still under your hand when the sound in the hallway...
  summary: |-
    The story opens in Ward Office 12 with Sub-Inspector Rowe arriving forty minutes early...
```

**What is not exported** below says scenes are progress rather than world, and
that is still the rule. This is the one exception, and it is worth being explicit
about why, because the line is otherwise a good one.

Every other `Scene` exists because a player walked in. It belongs to their
linked list, it is a record of somebody having been somewhere, and seeding it
into a fresh database would be seeding a playthrough. The opening arrival is not
that. Nobody made it happen. It is the moment the story begins, identical for
everyone who ever plays it, and it is the answer to a question the world is
supposed to know: *what does it read like to be standing here at the start.*

Leaving it out had two visible costs:

- The opening room was **the one arrival in the game that was never narrated.**
  Every other room the player walks into goes through `Scene::Generator`; the
  opening room was read out as its own description, standing in for prose nobody
  wrote.
- **Nobody was in a freshly seeded world.** `Scene::Generator.characters_present`
  answers from the last scene in a location that recorded anyone, so with no
  scene at all it answered with the protagonist alone,
  `Playthrough::Classifier` offered an empty cast, and the `talk` branch could
  not be reached. A hand-authored `characters:` list here is what fixes that,
  and it is the strongest argument for the whole key.

Practicalities:

- It is written **directly after `story`** because it reads directly after the
  preface. Those two paragraphs are the first thing any player sees, so the file
  puts them where somebody editing them will find them. The loader loads it
  **last**, because it names a location and a cast by natural key and both have
  to exist first — key order and load order are not the same thing.
- A `Scene` has no natural key, so `scenes.is_opening` is both the marker and the
  key the loader matches on. A story has exactly one, which `Scene` validates.
- There is **no `story_timestamp`**. An opening arrival happens at the story's
  `start_time`, which the file already carries; restating it would be a second
  place to edit and a second place to drift.
- It **does not stamp `Location#last_protagonist_visit`**, and that is deliberate
  rather than an oversight. These files sit on disk for months. If seeding stamped
  the visit, the first player to walk back into the opening room would be told, in
  fiction, that they had been gone that long — the wall-clock defect in the
  ROADMAP's **Known issues**, amplified into something a player reads.
  `PlaythroughsController#create` stamps it when a player actually arrives.
- Every playthrough of a story starts on the **same** opening `Scene`. The turn
  log walks backwards from `current_scene`, so branching playthroughs still each
  read their own turns; `Scene#next_scenes` is plural because the forward
  direction stopped being single-valued when this landed.

### Rules the loader enforces

- Exactly one location is `opening: true`, and it must be `realized` — a story
  whose first location is a stub cannot be started in the browser.
- An `opening_scene` is **required**, it must be in the location marked
  `opening: true`, and it must have a `description`. Required rather than
  optional on purpose: a key that is usually there closes neither of the two
  defects above. Its `characters` must all be characters the file declares.
- Location names are unique within the file (case-insensitively).
- Every `between` pair names two locations the file declares.
- Every character's `race` is one of this universe's races.
- `distance` and `travel_method` come from `LocationConnection::DISTANCES` and
  `::TRAVEL_METHODS`. `time_to_travel` is derived from those two and is
  deliberately absent from the file.
- `sex` is a `Character.sexes` key: `male`, `female`, `non_binary`,
  `trans_woman`, `trans_man`. Not checked by `validate!` -- it is `Character`'s
  own `inclusion` validation that rejects a bad one, inside the same
  transaction, so a typo still fails the load rather than storing something the
  pronoun rules cannot answer for.

A file that breaks one of these raises `WorldSeed::Loader::InvalidWorld` naming
the file, rather than failing three records later.

### Connections are listed once, and written twice

`location_connections` rows are directional and always exist in pairs, both
carrying the same values — `LocationConnection`'s enums are direction-neutral
precisely so that holds, and `Location::Generator` writes both rows from one
answer. So a file lists each edge once and the loader writes both rows. Listing
both directions would double the hand editing and would let a hand edit produce
an asymmetric graph the model does not support.

If the database ever holds only one direction of an edge, `rake game:export`
says so in its warnings and loading the file writes the missing row.

### What is not exported

`Playthrough`s, `last_protagonist_visit`, and every `Scene` **but the opening
arrival**: those are somebody's progress through a world, not the world. `rake
game:export` says out loud how many it left behind, so nothing is dropped
silently — and it warns loudly when a story has *no* opening arrival, because
the loader refuses such a file rather than producing a world that opens on a
room description.

## Idempotency

Loading is matched on natural keys, never on `id` — ids differ on every load.
Story `title` is a world's identity, so **keep titles unique across these
files**. Races match on `(universe, name)`, characters on `(story, fullname)`,
locations on `(story, name)`, connections on their endpoint pair, items on
`(character, name)`.

The loader adds and updates; it never deletes rows a file no longer mentions.
Renaming a location and re-seeding therefore leaves the old one behind — drop
the database when you need a clean rebuild.

## The worlds

### Format versions

- **2** — a world carries its own `opening_scene`. A format 1 file has none.
- **1** — the original.

### `the-lunar-cartographer.yml`

Exported from a real generated world: Nocturnis, a city that rearranges itself
every night. The opening room has three ways out and all three are stubs, which
is exactly what `Location::Generator.opening` produces — the happy path, at the
size the generator actually makes it.

Edited after export: the three connections predated `DISTANCES` and
`TRAVEL_METHODS` being fixed tables and had free prose in them, three fields had
been cut off mid-sentence by the generator's length caps, and the story had no
characters at all, because `Story::Generator` does not make any and
`Character::Generator` never sets `is_protagonist`.

Its `opening_scene` is hand-written — this world predates `rake game:new`
narrating one — and its cast is the point: Grenn is in the doorway from the
first line, so the player has somebody to talk to on turn one.

### `the-unrecorded-hour.yml`

Hand-authored, and shaped on purpose: a ward office with two ways out, one of
which is a **realized dead end** — a supply closet whose only exit is back into
the office. It gives the single-exit behaviour permanent coverage in real data,
and keeps the two worlds off the same happy path.

The generator cannot produce this shape on its own.
`Location::Generator#realize!` realizes the opening location and leaves every
neighbour a stub, and a stub has no exits at all until somebody walks into it —
so a closet that is only a stub is not yet a dead end in the data. Realizing the
closet in the seed file is what makes its single connection back to the office
exist as data.

Its `opening_scene` is shaped on purpose too: Sub-Inspector Rowe is in the
doorway forty minutes early, so the player has somebody to talk to and something
to be afraid of while they decide whether to go into the closet.

`test/lib/seeded_worlds_test.rb` asserts that at least one seeded world still
has a realized location with exactly one exit, that every world opens with a
narrated arrival, and that every world has somebody other than the protagonist
standing in its opening room. Keep it that way.
