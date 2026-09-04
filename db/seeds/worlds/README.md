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
| `characters`    | one entry each, `race` by name, optional `location` (or `absent`) and `items` |
| `locations`     | every location, realized or stub; one marked `opening: true`; `items`   |
| `connections`   | one entry per edge, as an unordered `between: [a, b]` pair              |
| `mechanics`     | optional — the world's own laws, on the story's clock; see below        |

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

### `mechanics`, and the `mobile` flag they read

A world can change itself, on its own clock, with no model call and nothing in
memory. Two keys carry it:

```yaml
locations:
- name: Mournwell Lane
  detail_level: stub
  mobile: true            # this place travels
  teaser: |-
    Step out and eavesdrop on the lane while you still know where it runs.

mechanics:
- name: The nightly rearrangement
  kind: shuffle_connections
  cadence: nightly
  description: |-
    At midnight Nocturna floods the city and the Larkspur Quarter travels...
```

- `kind` is a key into **`WorldMechanic::KINDS`** and `cadence` a key into
  **`WorldMechanic::CADENCES`** — fixed tables in code, each naming a Ruby
  operation. This is the `LocationConnection::DISTANCES` precedent, and the
  reason it is that shape rather than a rule language: **the file supplies
  parameters, never behaviour.** A mechanic holds whether or not any narrator
  remembers it, survives a restart, and costs nothing per turn.
- `name` is the natural key, so re-seeding updates a mechanic rather than
  duplicating it, and a world can carry more than one.
- `description` is the in-fiction reason, for prompts. It is prose, not logic.
- There is **no `last_run_at`**. How far a mechanic has got through a story is
  progress, not world; seeding one would tell a fresh database that nights
  nobody has played had already happened.
- `mobile` is omitted rather than written `false`, like `opening`: the file says
  which places move and stays quiet about the ones that do not.

**What `shuffle_connections` actually does**, because the shape of the graph you
author decides what a night looks like: it takes every connection joining a
`mobile` location to one that is **not**, and permutes the fixed endpoints among
them. Permuting rather than choosing is what keeps the world whole — every
location keeps exactly the number of ways in and out it had — and an arrangement
that would still split the graph in two is rejected before it is applied.

An arrangement is judged on the **adjacency it induces** — which places end up
joined — rather than edge by edge, so a permutation that shuffles endpoints
around without changing who opens onto whom is a no-op and is refused. **What
that means for the graph you author:** two shufflable edges are not enough if
they both hang off the *same* `mobile` location. Swapping a lane's own two
exits leaves the lane opening onto exactly the two places it already did, so
such a world loads, validates, plays — and never moves. Spread the edges over
at least two `mobile` locations. **The loader refuses a file that does not** —
it counts the mobile rooms the shufflable edges hang off as well as the edges
themselves, so this is a rule rather than advice.

The consequence worth designing around: **an edge with two `mobile` ends is
never touched.** So a building whose rooms are all marked `mobile` travels as
one piece with its own doors intact, and only its edges out into the fixed city
are repointed. That is exactly how `the-lunar-cartographer.yml` is authored, and
it is why walking out of Room 3 always offers the same three ways — the house
holds together; what changes is which part of Nocturnis the quarter has come to
rest against. Whether that reads better than moving whole districts is a
question for actual play, not for this file.

The permutation comes from a `Random` seeded from the story id and the
story-time boundary, so the same night shuffles the same way in any process,
after any restart.

**Re-seeding a world whose nights have run does not re-assert the doorways the
mechanic has moved.** It used to: the loader wrote the file's own pair back on
top of the arrangement the world had moved to, so every mobile room ended up
with two ways into the fixed city and a later night reported one of them as
having moved when a player standing there saw no such thing. The loader now
leaves a shufflable doorway where the world put it wherever the mobile room
already leads every way out the file gives it, and says so on the way past.
Which anchored place a mobile room has come to rest against is *progress*, like
`last_run_at` — the file was never meant to carry it. See **Re-seeding a world
somebody has played** below.

### `items`, and the two places a thing can be

An `items:` list hangs off a **character** — something they are holding — or off
a **location** — something lying in the room, which is what makes it takeable.
Never both: `Item` is in exactly one place, and the loader writes the other
column nil.

```yaml
locations:
- name: Ward Office 12
  detail_level: realized
  opening: true
  # ...
  items:
  - name: ward stamp
    description: |-
      Her own ward stamp, lying beside the open daybook where she set it down.
    properties: '{"registered": true, "ward": 12}'
```

Items under a location are what a hand-written world carries so that anything in
it is takeable. A generated room furnishes itself now (`Item::Registry`, written
when the room is realized), but a seeded room is realized by this file rather
than by a model call, so what is lying in one is whatever the file says and
nothing else — the registry leaves it alone. `rake game:mechanics` is the
fastest way to see this half of the world work; see the README.

`properties` is a JSON string, stored verbatim and read back by
`Item#properties_hash`. Entries are exported sorted by name, so keep them that
way in the file or a re-export will reorder them.

#### `readable` and `inscription`: what is written on a thing

A note, a letter, a sign, a docket, a label. **What is written on it is a
record**, so the file carries the words and a player reading the same note twice
reads the same words:

```yaml
  items:
  - name: Perrin's private index
    description: |-
      A slim index in a hand that is not hers: two columns, dates on the left...
    readable: true
    inscription: |-
      11 Frost — 0714/12 — closed, no query raised
      19 Thaw — 1188/12 — QUERY RAISED (O.V.) — still open
```

- `readable` is **omitted rather than written `false`**, like `opening` and
  `mobile`: the file says which things have writing on them and stays quiet
  about the ones that do not. It is the whole gate — nothing in the app ever
  generates text for a thing that is not marked readable.
- `inscription` is **the words themselves**, as a player would read them off the
  object, not a description of it — that is what `description` already holds.
  Bounded at `Item::INSCRIPTION_LIMIT` (400 characters).
- An `inscription` without `readable: true` is **refused by the loader**, naming
  the file and the item. `Item` validates the same pair, so such a file would
  not load either way; the loader's message is the one worth reading.
- `readable: true` with no `inscription` is legal and means *nobody has written
  the words down yet*. `Item::Inscriber` writes them on the **first read**, once
  and never again, in one structured call. Spelling them out in the file is
  better where the words matter: it costs no call and it is the version somebody
  hand-edited.
- It works on **either side** of `Item::PLACES`, and on the starting inventory
  in particular. `Playthrough#take_up_the_starting_inventory` copies the
  protagonist's items into each new playthrough's hands and copies the words
  with them, so a seeded daybook says the same thing to every player. Writing
  belongs to the note, not to the shelf.
- Three seeded things carry words today: the **Ward Office 12 daybook** and
  **Perrin's private index** in `the-unrecorded-hour.yml`, and the **Assize
  tide-slate** in `the-salt-assizes.yml`. `the-lunar-cartographer.yml` carries
  no items at all and deliberately keeps none —
  `lib/engine_sweep/scripts/the-lunar-cartographer.yml` is the script about the
  graph alone, and its whole premise is a world with nothing in it.

### `characters[].location`, and where a person stands

A character carries **where they are**, by location name:

```yaml
characters:
- fullname: Neb Halloran
  race: Shorefolk
  location: The Tide Post
  nickname: Neb
```

That column — `characters.location_id` — is the closed set `talk` resolves
against (`Character.present_in`), the same way `Item.lying_in` is the closed set
`take` resolves against. It is what makes a seeded cast reachable at all. Before
it existed, who was standing in a room was reconstructed on every arrival from
the last scene there that happened to record anybody, so **a room nobody had
walked into had nobody in it** however central the person standing in it was:
arriving at The Tide Post recorded the protagonist alone on all three runs
checked, in a world whose whole premise is that Neb Halloran is chained to that
post.

Two rules about the key, and both are deliberate:

- **The protagonist does not carry one.** Where the player is standing belongs to
  the playthrough (`playthroughs.current_location_id`), because two people
  playing one seeded world stand in two different rooms at the same time and a
  story-level column cannot hold both answers. The story says where it *opens*
  with `opening: true` on a location. Anyone `is_companion` is derived the same
  way, for the same reason: they travel with the party.
- **The key is optional, and leaving it out means nowhere.** Nowhere is a real
  state and it is left alone rather than guessed at — `rake game:doctor` reports
  a character nobody can speak to.

### `characters[].absent`, and nowhere on purpose

```yaml
characters:
- fullname: Perrin Lasco
  race: Marginalia
  absent: true
```

An omitted `location` means *nobody has said where they are*, and the doctor
reports it. `absent: true` means *nowhere, and that is the story*, and the doctor
says nothing at all. `the-unrecorded-hour.yml` is the world that needs it: its
whole premise is that Perrin Lasco has been removed from Ambry, so the honest
record is no whereabouts — and for as long as the file had no word for it, the
doctor reported that world as one warning short of healthy on every run, which is
how a person learns to stop reading warnings.

It writes `characters.deliberately_absent`, a column rather than a run-time read
of this directory: only three stories in the database have a file here at all, so
a caller that answered "is this deliberate" by reading YAML would have no answer
for a generated world.

- **The two keys are mutually exclusive** and `validate!` refuses a file carrying
  both: `absent` asserts that nobody may be offered this person to talk to and
  `location` asserts that they are in that room's closed set.
- **Re-seeding re-asserts it in both directions**, like every other placement:
  `absent: true` writes the marker over a played world, and deleting the key
  takes it off the record.
- **`Character::Registry` never places a marked character** — the second half of
  its "never move somebody who is not nowhere" rule, so a realization cannot
  undo a world's premise as a side effect of describing a room.
- **`Character#move_to!` clears the marker.** An engine mechanic that brings
  Perrin back is the story's business, and a person standing in a room is not
  absent from the world. `Character#absent!` is the call that puts them back.
- A database seeded before the column existed carries an unmarked row, and
  `rake game:repair` writes the marker from this file — a `safe` repair, because
  the answer is checked in.

A `location` naming a room the file does not declare is refused by `validate!`,
because that mistake is otherwise silent — the character loads standing nowhere
and the room they were meant to be in is empty.

Nothing but this file, `Character::Registry` (which places somebody who is
nowhere, never moves somebody who is not, and never places somebody who is
absent on purpose), `Character#move_to!`, `Character#absent!` and
`rake game:backfill_whereabouts` ever writes it. **No narration moves anybody.**

### Rules the loader enforces

- Exactly one location is `opening: true`, and it must be `realized` — a story
  whose first location is a stub cannot be started in the browser.
- An `opening_scene` is **required**, it must be in the location marked
  `opening: true`, and it must have a `description`. Required rather than
  optional on purpose: a key that is usually there closes neither of the two
  defects above. Its `characters` must all be characters the file declares.
- Location names are unique within the file, on `WorldSeed.natural_key` — so
  `The Closet` and `Closet` are one name and the pair is refused, because a
  re-seed matches a room on that key and could not tell which one you renamed.
- Every `between` pair names two locations the file declares.
- Every character's `race` is one of this universe's races.
- A character carries `location` or `absent: true`, never both — one says which
  room's closed set they are in and the other says nobody may be offered them.
- A character's `location`, when the file gives one, names a location the file
  declares. Absent is legal and means nowhere; wrong is refused.
- `distance` and `travel_method` come from `LocationConnection::DISTANCES` and
  `::TRAVEL_METHODS`. `time_to_travel` is derived from those two and is
  deliberately absent from the file.
- Item names are unique within the file on `WorldSeed.natural_key`, on both
  sides — an item is matched on `(story, name)` and then on that key, so two of
  a name are one item.
- An item with an `inscription` is marked `readable: true`. Words on a thing
  with no writing on it is the one shape `Item` refuses outright.
- A `mechanics` entry has a `name`, unique within the file, a `kind` in
  `WorldMechanic::KINDS` and a `cadence` in `WorldMechanic::CADENCES`.
- A `shuffle_connections` mechanic needs **at least two connections** joining a
  `mobile: true` location to one that is not, **hanging off at least two
  different `mobile` locations** — otherwise the world says it rearranges itself
  every night and nothing can move, which loads and plays and silently never
  happens. Both counted from the file, so a hand edit is caught before it
  reaches the database.
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

`Playthrough`s, `last_protagonist_visit`, `WorldEvent`s, a mechanic's
`last_run_at`, **conversation history** (`chats` / `messages`), and every
`Scene` **but the opening arrival**: those are somebody's progress through a
world, not the world. `rake game:export` says out loud how many it left behind,
so nothing is dropped silently — and it warns loudly when a story has *no*
opening arrival, because the loader refuses such a file rather than producing a
world that opens on a room description.

Conversation history is on that list **deliberately, not by omission**. A
`Chat` is what one player said to one character on one playthrough, plus the
prompts and token counts that went with it. Seeding it would put half of
somebody else's conversation into a world nobody has played yet — and it would
hand a character memories of a player who does not exist. It gets no exception
the way the opening arrival does, and for the mirror-image reason: the opening
is the same for everyone who ever plays, and a conversation is the same for
nobody. What a character remembers of you is yours, and it starts empty.

## Idempotency

Loading is matched on natural keys, never on `id` — ids differ on every load.
Story `title` is a world's identity, so **keep titles unique across these
files**. Races match on `(universe, name)`, characters on `(story, fullname)`,
locations on `(story, name)`, connections on their endpoint pair, items on
`(story, name)` — **not** on their owner, because an item is the one thing in
these files that moves. `take` and `drop` write `items.character_id` and
`items.location_id`, so a file that looked for the daybook in the hands it
declares would miss the one the player left on a shelf and seed a second
daybook. Keying on the story finds it and puts it back, which is the same
"the file re-asserts itself over a played world" rule the connections follow.
Item names are therefore unique within a file, and the loader checks it.

## Re-seeding a world somebody has played

This is the case the rules above are actually about. Re-seeding is how you pick
up a file change on a database you have been playing for days, so it has to be
safe against a world in progress — and for a long time it was not. It **added
and never reconciled**, which left three shapes behind:

| what you edited | what used to happen |
| --- | --- |
| a location's name | a second room, with the office opening onto both |
| an item's name (a capital letter is enough) | a second item, and the classifier resolving a take by an ordering accident |
| nothing at all, on a world whose nights had run | a second doorway off every mobile room, and a phantom "now opens onto X instead of Y" on the next night |

The loader now **reconciles what the file can prove, says out loud what it
cannot, and still deletes nothing**:

- **A renamed row is the same row.** Identity is `WorldSeed.natural_key` — one
  step wider than the written name: case, runs of whitespace and a leading
  article are not part of it. So `Supply Closet` → `The Supply Closet` renames
  the row that exists, which keeps its id and therefore its doorways, its
  scenes, its `last_protagonist_visit` and anybody standing in it. It goes no
  wider than that on purpose: punctuation, possessives and plurals stay
  significant, because folding two genuinely different rooms into one would
  destroy play rather than duplicate it. **Two names in one file that are one
  name to a re-seed are refused** by `validate!`, so a rename never has two
  candidates.
- **A moved doorway has not gone missing** — the paragraph under `mechanics`
  above.
- **A rename no normalized name recognizes** — `The Supply Closet` edited to
  `The Broom Cupboard` — is, to any loader, a room that does not exist yet.
  Nothing in the file says which room it replaced. So the row is created and the
  load prints a `WARNING:` naming it, on a world that has been played; the old
  room is still there and `rake game:doctor` reports the pair whenever it can
  recognize one.

What still happens on every re-seed, and is the rule rather than a defect: **the
file re-asserts itself.** An item the file puts on a shelf goes back on the
shelf out of whoever's hands it was in, a character goes back where the file
places them, `absent: true` is written and deleting it is taken off. A seed file
is the authority on the world, not a suggestion. The party's own copy of the
starting inventory is untouched — the loader searches the world's own rows
before any playthrough's.

**What `rake game:doctor` reports about a database that already has one of these
shapes**, each with a `safe` repair where the answer is derivable from the file
(`rake 'game:repair[<id>]'`, no model call):

| finding | what it means | when it is `safe` |
| --- | --- | --- |
| `duplicate_locations` | two rows that are one room to a re-seed | the file declares one of the names and only one row has anybody's history in it — the fold moves the other row's items, cast and doorways over and removes what is left |
| `duplicate_items` | two rows that are one item | the file names one of them and nothing refers to the others |
| `mobile_doorway_re_asserted` | the file's own doorway is back on record after a night had moved it | closing it leaves the mobile room the arity the file gives it and strands nothing |

For a clean rebuild rather than a reconciliation, `rake 'game:delete[<id>]'`
then `bin/rails db:seed`, or drop the database.

`lib/engine_sweep/scripts/reseed-a-played-world.yml` walks all of this offline:
it plays a few turns, re-seeds mid-game, re-seeds again with the closet renamed,
and asserts the records after each one.

## The worlds

### Format versions

- **2** — a world carries its own `opening_scene`. A format 1 file has none.
- **1** — the original.

The optional `mechanics` key and `locations[].mobile` were added to format 2
rather than bumping it to 3, which is the rule `WorldSeed::FORMAT` states:
the number moves when a loader **cannot absorb** an older file. Both keys are
optional and both default to "this world does not move", so every format 2 file
written before they existed — `the-unrecorded-hour.yml` included — still loads
and still means exactly what it meant. A required key, as `opening_scene` was,
is what bumps the number.

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

**It is also the world that moves.** Its universe has claimed since it was
generated that Nocturnis rearranges itself every night; the hand-written
`mechanics` block is that claim made true in the records rather than in prose.
The four Larkspur Quarter locations — Room 3, the hallway, the lane and the
rooftops — are `mobile: true` and travel as one piece, and three fixed landmarks
the universe's own prose already names were added as stubs for them to come to
rest against: the Celestial Spire (*"a tower that remains static despite the
city's rearrangements"*), the Sovereign's Circle, and the bell tower of Saint
Aravel from the preface. The three connections out of the quarter are the edges
a night repoints.

One thing in this file predates the mechanic and is worth knowing about: Room 3's
`description` ends on *"the shuttered face of a clothier's shop has migrated
closer to your window"*. A description is written once and never regenerated, so
a sentence about a neighbour goes wrong the moment the graph moves it. That
sentence is safe as authored — Room 3's own exits never shuffle — and
`Location::DetailSchema` now tells the generator to describe the place and not
what is across the way, so the next one will not be written at all.

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
