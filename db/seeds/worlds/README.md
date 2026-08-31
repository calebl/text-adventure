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

| key           | what it holds                                                          |
| ------------- | ---------------------------------------------------------------------- |
| `format`      | bumped when the format changes; the loader refuses one it cannot read   |
| `universe`    | the nine prompt fields, plus `races` (name and description)             |
| `story`       | title, genre, `start_time`, preface, summary                           |
| `characters`  | one entry each, `race` by name, optional `items`                       |
| `locations`   | every location, realized or stub; exactly one marked `opening: true`    |
| `connections` | one entry per edge, as an unordered `between: [a, b]` pair              |

Prose is stored in a `|-` block scalar: one paragraph is one physical line, so
editing a sentence is a one-line diff and what you type is what gets stored.

### Rules the loader enforces

- Exactly one location is `opening: true`, and it must be `realized` — a story
  whose first location is a stub cannot be started in the browser.
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

`Scene`s, `Playthrough`s and `last_protagonist_visit`: those are somebody's
progress through a world, not the world. `rake game:export` says out loud how
many it left behind, so nothing is dropped silently.

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

`test/lib/seeded_worlds_test.rb` asserts that at least one seeded world still
has a realized location with exactly one exit. Keep it that way.
