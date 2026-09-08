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

The worlds here have been edited after export. `the-unrecorded-hour.yml` was
written by hand outright, to get a shape the generator cannot produce (below).

`WorldSeed::Exporter` has a second reader now, and it never writes here:
`Story::Snapshot` keeps its document on the story's own row so a world can be
played again from its beginning (`rake game:fork`). A snapshot must not become a
file in this directory — `bin/rails db:seed` and `rake game:reseed` load every
`*.yml` in it, so one keyed by the same title as its original would re-assert
itself over the story it was taken from.

Two things to know before re-exporting over a file:

- The **leading comment block is preserved**. Put anything worth keeping there.
- Comments **further down the file are not** — YAML comments do not survive the
  parser. Long-lived notes belong in this README.

## The format

One file is one universe and one story. Keys are written in this order:

| key             | what it holds                                                          |
| --------------- | ---------------------------------------------------------------------- |
| `format`        | bumped when the format changes; the loader refuses one it cannot read   |
| `universe`      | the nine prompt fields, plus `races` (name, description, optional `monstrous`) |
| `story`         | title, genre, `start_time`, preface, summary                            |
| `opening_scene` | the narrated moment the story starts in — see below                     |
| `characters`    | one entry each, `race` by name, optional `location` (or `absent`) + a position in it (`x`, `y`), optional `hostile`, optional `stats`, and `items` |
| `locations`     | every location, realized or stub; one marked `opening: true`; optional `danger`; optional `population`; optional `hazard` + `hazard_die`; optional `parent` + a box (`x`, `y`, `z`, `width`, `depth`); `items`, each with an optional position (`x`, `y`) |
| `connections`   | one entry per edge, as an unordered `between: [a, b]` pair; optional `hazard` + `hazard_die` + `hazard_from` |
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
  fiction, that they had been gone that long — the wall-clock defect story time
  was built to close, amplified into something a player reads.
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

### `schedule`, and a thing this world has already decided will happen

The captain's Call 8, 2026-09-06: *"some events will need to happen at a
particular time, like if we have story where a bomb is going to go off or a
volcano is going to explode 1 week in the future."* A `schedule:` block is that,
as world data:

```yaml
schedule:
- summary: |-
    Grenn Ollivar comes for the overdue rent, and the table and the instruments
    go out into Mournwell Lane.
  after_minutes: 480
```

- Two keys and no others. `summary` is the sentence, and it is also the row's
  **natural key** — a scheduled event has no name and no position, so re-seeding
  matches on what it says.
- `after_minutes` is counted from the story's own `start_time`, never from
  whenever the file was loaded, so re-seeding a world a month later leaves the
  bomb at the same hour.
- **The engine fires it**, on the story's own clock, in the same call that
  catches the `mechanics:` up (`Story#catch_up_world!`). A world nobody has
  played has not reached its own midnight; a scheduled row is due when
  `Story#clock` reaches it and not when the wall clock does.
- **Nothing narrates it.** Firing a row writes `fired_at` and nothing else —
  the narrator is told a scheduled event only when it happens, and today that
  means not at all, because `WorldEvent` is an audit trail and never a narration
  source. Telling a model about a bomb a week out invites it to foreshadow an
  explosion the engine has not recorded.
- A **future catastrophe is an ordinary scheduled row**. There is no volcano
  table and no bomb mechanic. `rake game:doctor` reports a row whose hour has
  passed with nothing fired (`scheduled_event_never_fired`), because a schedule
  nothing reads is worse than no schedule.
- What is **not** here is the log of what has already happened. That is
  progress, is never exported, and is not the file's to write — see **What is
  not exported**.

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

An item lying in a room whose file gives that room a box may also say WHERE in
it — see the `x` and `y` section further down.

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
- It works **wherever the thing is and whichever layer it is in**, and on the
  starting inventory in particular. `Item::Snapshot` copies the world's own rows
  into each playthrough's own game -- the protagonist's items into the party's
  hands, a room's contents onto that game's floor -- and copies the words with
  them, so a seeded daybook says the same thing to every player. Writing belongs
  to the note, not to the shelf.
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

### `characters[].stats`, and the body the engine works from

```yaml
characters:
- fullname: Halkett Rowe
  race: Ledger-Kept
  location: Ward Office 12
  stats:
    level: 1
    hit_die: 8
    strength: 11
    dexterity: 9
    will: 13
```

Five numbers, and they are the whole of a sheet:

- `hit_die` is **how tough this body is** — one of 6, 8 or 10, the three the
  engine itself rolls from.
- `level` is **stored and inert**: nothing in the app reads it for behaviour and
  nothing advances it.
- `strength`, `dexterity` and `will` are **what a body can do** — 3..18, which is
  what 3d6 rolls. Exactly these three, and there is no fourth: the captain's
  ruling of 2026-09-04, evening, *"let's go with the 3 abilities"*.

`Character#max_hp` is derived from the level and the die, and from **nothing
else**:

```
max_hp = hit_die + (level - 1) * (hit_die / 2 + 1)
```

**No ability term, and that is a decision rather than an oversight.** None of the
three is a constitution, `will` is nerve rather than stamina, and the body's
capacity is `hit_die`. An ability term would give one column two jobs and let a
re-seed editing `will` silently move every playthrough's ceiling.

**A check is one d20 under the ability**, with the difficulty subtracted from the
target rather than added to the die — `Character#check(:strength, penalty: 4)`,
and `rake game:mechanics` walks it with `check strength 4`. At a target of zero
or less the engine says the thing cannot be done instead of rolling a die it
cannot win. One kernel: no modifier, no DC ladder, no skill, no spell.

A hand-authored world **is** the decision, which is why the key exists at all.
Everywhere else the engine rolls it — `Character::StatBlock`, seeded through
`Roll` — because a model may not set anybody's numbers (the captain's ruling of
2026-09-04). Nothing in any schema or prompt asks for one.

- **The key is optional, and leaving it out means no sheet at all.** Nothing is
  rolled on load: a file that says nothing about a body leaves the columns
  exactly as they are, so a re-seed cannot quietly rewrite a world because
  somebody edited a different part of the file. `rake game:doctor` reports the
  gaps (`character_without_a_stat_block`, `character_without_abilities`) and
  `rake game:backfill_stat_blocks` rolls whatever is missing.
- **All five keys or none.** `validate!` refuses a partial mapping: a `stats:`
  carrying some of them is a key that looks as though it said something and did
  not. `level` is 1..20, `hit_die` is one of 6, 8, 10, and an ability is 3..18.
- **Re-seeding re-asserts it**, like every other placement. Lowering somebody's
  hit die under a game in progress is legitimate and leaves that game's
  condition row above its new maximum, which the doctor reports
  (`hp_above_maximum`) with a safe repair. Editing an ability disturbs nothing at
  all — no playthrough row is derived from one.
- **What is NOT in the file is how much is left of anybody.** That is
  `playthrough_vitals`, one row per (playthrough, character) — the captain's
  ruling that the world owns the template and each playthrough owns the
  instance, the same split the items are under. A seed file describes a world;
  what has happened to somebody in one game is that player's progress.

### Monsters: `races[].monstrous`, `characters[].hostile` and `locations[].danger`

The captain's ruling of 2026-09-04: *"a universe should be able to have monsters
as well as characters."* Three keys, and all three are on the **world's** side of
the layer split — `hit_die`'s side. No model sets any of them, no schema has a
field for one, and `EngineSweep::Invariants#hostility_unmoved` asserts that no
typed line moves one.

```yaml
universe:
  races:
  - name: Nocturna-Blighted
    monstrous: true
    description: |-
      What is left when somebody stands too long under Nocturna's glow.

characters:
- fullname: Marek Sollen
  race: Nocturna-Blighted
  location: The Bell of Saint Aravel
  hostile: true
  stats: { level: 1, hit_die: 10, strength: 14, dexterity: 8, will: 3 }
  # ... and the same nine fields everybody else has

locations:
- name: The Bell of Saint Aravel
  detail_level: realized
  danger: dangerous
```

- **`monstrous` makes a race one of the world's monsters** rather than one of its
  peoples. A universe's bestiary is the monstrous half of its own race list —
  there is no second catalogue — and `Race.monstrous` / `Race.peoples` are the
  two pools a GENERATED person is drawn from.
- **Monstrous races still reach the prompts.** Captain call C4, 2026-09-04, his
  explicit word: they are in `Universe#race_names` for room realization and for
  every turn of every conversation, so a room can be described knowing what
  lives out past the levee and a person in it can warn you about one.
- **`hostile` says this person attacks the party.** A monster is an ordinary
  character with this one column set, and **none of the nine required fields is
  relaxed for one**: a monster has a backstory, a personality and something it is
  afraid of, because a monster you can talk to is a feature. The file is the
  decision, so it may also hold a *tame* beast of a monstrous race, or a hostile
  person of a people.
- **A hostile character needs `stats`.** The loader refuses one without: a fight
  is arithmetic over `Character#max_hp`, and a foe with no body can be neither
  hurt nor hurt back. `rake game:doctor` reports one an older database carries
  (`hostile_without_a_stat_block`) with a safe repair.
- **`danger` is how likely a room is to be BORN with the world's monsters in
  it** — one of `safe`, `uneasy`, `dangerous`, `deadly` (`Location::DANGERS`),
  the shape `distance` and `travel_method` have. The value is faces of a d6, so
  `uneasy` is one inhabitant in six and `dangerous` is one in two. It affects
  people the ENGINE writes when a room is realized; a character the file places
  is placed exactly as the file says, whatever the room's danger is.
- **`deadly` is a file's word and the engine never rolls it.** A generated
  world's rooms are rolled at birth out of `Location::Danger::ROLLED`, which is
  `safe`/`uneasy`/`dangerous` only.
- **A generated character of a monstrous race is hostile by default** — the
  captain's seventh ruling, one derived line. The `hostile` key is what a file
  says instead.
- All three are **omitted rather than written out** on export, like `opening`,
  `mobile`, `absent` and `readable`, and all three are **re-asserted in both
  directions** on load: deleting `hostile: true` from a file and re-seeding
  disarms the monster.
- `rake game:doctor` also reports **a monstrous race this world has nobody of**
  (`monstrous_race_with_no_monsters`) and **a danger key the engine has no table
  for** (`location_with_an_unknown_danger`). Neither can be repaired: writing a
  monster is world data, and there is no record of which of the four words a
  fifth one meant.

### How populated a place is: `locations[].population`

```yaml
locations:
- name: The Fish Market
  population: a crowd
- name: The Bonded Cellar
  population: nobody
```

- **`population` is how many people a room is BORN with** — one of `nobody`, `a
  person or two`, `a crowd` (`Location::Population::BANDS`), the shape `danger`
  and `distance` have. The word is the band and the engine rolls the exact count
  inside it when the room is realized, so `a crowd` is two or three people and
  not a number a file can name. The captain's ruling of 2026-09-07 is why it is
  a word: *"The narrarator should get to decide how populated a room should
  be"*, from a closed list, with the engine keeping the arithmetic.
- **It affects people the ENGINE writes when a room is realized**, exactly as
  `danger` does — so a room your file ships *realized*, with a description and a
  cast, will never read it. Write it on the rooms you leave as **stubs**, which
  are the rooms a player will walk into and a model will write.
- **An absent key is not `nobody`.** Leaving it out means *nobody has picked a
  word for this room*, and the engine rolls one out of
  `Location::Population::ROLLED` — seeded on the room's own name, so a world
  exported and re-seeded keeps every word it had. Writing `nobody` is your file
  saying the place is empty, and the engine honours it.
- **Your own cast wins either way.** A room you put three characters in has no
  places left (`Character::Registry::MAX_PER_ROOM`), so the engine asks for
  nobody however busy the word is. Nothing ever removes somebody your file
  placed.
- Like `danger`, it is **omitted rather than written out** on export when nobody
  picked a word, and **re-asserted in both directions** on load: deleting the key
  from a file and re-seeding hands the room back to the engine.
- The loader refuses **a word the engine has no band for**, naming the file and
  the room, exactly as it does for a fifth `danger`.

### Hazards: `locations[].hazard` and a doorway's one-way `hazard_from`

**A place can cost you hit points, and so can the way you got there.** Two keys
on a room and three on a doorway, and every one of them is world data: a seed
file writes a hazard here and no typed line ever does. A model picks one **key**
for a whole generated building and never a die or a room (see the last bullet of
this section, and `Location::Parameters`).

```yaml
locations:
- name: The Tide Post
  detail_level: realized
  hazard: flooded
  hazard_die: 4

connections:
- between: [The Causeway Court, The Vestry Hulk]
  distance: adjacent
  travel_method: walking
  hazard: drop
  hazard_die: 4
  hazard_from: The Causeway Court
```

- **`hazard` on a room is a key into `Location::HAZARDS`** — `flooded`, `unlit`,
  `silent`, `airless` — and the table, not the file, says which ability saves
  against it and *when* it is paid. `flooded` and `unlit` are paid **on
  arrival**, once, by whoever walks in; `silent` and `airless` are paid **every
  turn**, on the room the turn began in, in the same step of the loop a foe
  strikes back in. So a room can charge you for coming in or for staying, and
  which of the two is a property of the hazard rather than of the room.
- **`hazard` on a connection is a key into `LocationConnection::HAZARDS`** —
  `drop`, `undertow` — and it is paid when that doorway is walked.
- **`hazard_die` is the parameter**: one of `Location::HAZARD_DICE` (4, 6, 8,
  10), thrown when the save is missed. A hazard is a key **and** a die, or it is
  neither; half of one is refused by the file and by the record.
- **`save` is one of the three abilities, or nothing.** `d20 <= the ability`
  through the same kernel `check strength` uses (`Character#check`). `airless`
  names no ability at all, which is a real hazard and not an omission: there is
  no dexterity against having nothing to breathe.
- **`hazard_from` is the one new shape in the whole design, and it is what makes
  a doorway's hazard one-way.** `location_connections` is two rows per door, so
  a hazard written on one of them costs in one direction only — the drop into
  the hulk hurts and the climb back out does not. `between:` is an unordered
  pair, so the file has to name the room you are **leaving** when it is paid,
  and the loader puts the key and the die on exactly that row and clears the
  other.

  **A one-way hazard is not a one-way exit.** Both rows are still written, the
  door still leads both ways, and `Location#exits` is unchanged; only the cost
  differs. One-way exits stay unsupported and deliberately deferred.
- Both are **omitted rather than written out** on export, like `opening`,
  `mobile` and `danger`, and both are **re-asserted in both directions** on
  load: deleting `hazard:` from a file and re-seeding takes it back off, so a
  room its author made safe stops costing anybody anything.
- **What a hazard took is not world data** and is never in a file:
  `playthrough_tolls` is one row per hazard paid, per game, exactly as
  `playthrough_vitals` is how much is left of one body in one game.
- `rake game:doctor` reports **a room hazard the engine has no table for**
  (`location_with_an_unknown_hazard`) and **a doorway one**
  (`connection_with_an_unknown_hazard`). Neither can be repaired: there are only
  a few words it could have been, nothing on record says which, and clearing the
  column is not a neutral guess — it is the answer that makes safe a room
  somebody meant to cost hit points.
- **`the-salt-assizes.yml` is the only world that carries any**, and its own
  header says why at length: its fiction is built out of exactly this (the stain
  band on the tide post, three men dead at it in the court's records), and it is
  the one seeded world with no `mechanics:` block — which matters for the
  DOORWAY half specifically, because `WorldMechanic::ShuffleConnections` rewrites
  an edge from `distance` and `travel_method` alone and in both directions, so a
  directed hazard on a shufflable edge would be destroyed the first night.
- **A GENERATED world gets hazards through a building and nowhere else**, on the
  captain's Call 1 of 2026-09-07. A model realizing a place picks ONE key out of
  `Location::HAZARDS` for the whole building — or `none`, which is the default —
  and the engine rolls it per ROOM at a share as the room is born, biased by the
  danger gradient, with the die drawn from `Location::HAZARD_DICE`.
  `Location::Parameters` is the vocabulary and the reason the pick is a rate and
  not an assignment: `silent` and `airless` are charged **every turn**, so a
  building every room of which carried one would end a playthrough by
  arithmetic. Nothing else in a generated world writes a hazard — an ordinary
  room, a doorway and every `hazard_from` are still a seed file's alone.

### `parent`, and the box — a place that has an inside

Since the captain's four rulings of 2026-09-06, a `Location` can be a **place**
with rooms inside it. `parent` names the containing place; the five integer
columns say where in it a room sits. The unit is the **pace**, one cell of
roughly 1.5 m, and `Location::Box` owns the whole design — read its header, not
this list.

```yaml
locations:
- name: The Taproom            # a ROOM inside the place below: all five numbers
  detail_level: realized       # and the opening row, so it LEADS the list
  opening: true
  parent: The Rusted Anchor
  x: 0
  y: 0
  z: 0
  width: 7
  depth: 8
- name: The Rusted Anchor      # a PLACE: an extent, and no position
  detail_level: stub
  width: 12
  depth: 8
- name: The Back Room          # beside the taproom, sharing the wall at x = 7
  detail_level: realized
  parent: The Rusted Anchor
  x: 7
  y: 0
  z: 0
  width: 5
  depth: 8
```

- **Containment imposes NO ordering — but the opening row still has to lead the
  list.** A `parent` may be named before or after the rooms inside it: the
  loader wires containment in a second pass precisely so a file need not be
  sorted. What is NOT free is where the opening room goes.
  `Story#opening_location` is the story's lowest-id location and the loader
  creates rows in file order, so the row marked `opening: true` must also be the
  FIRST row. Nothing refuses a file that breaks it — it loads, and then the
  story's opening room and the room the browser actually starts you in are two
  different places. The trap is specific to interiors: a reader's instinct is to
  write the building before the rooms in it, and that is the one order this rule
  forbids when the opening room is one of those rooms. The example above leads
  with the taproom for that reason, and so does
  `test/fixtures/files/a-world-with-an-interior.yml`.
- **Every one of these keys is optional and NONE of the three worlds here uses
  them.** The captain's fourth ruling leaves the seeded worlds flat, and
  interiors are opt-in per file: a footprint is still something only a file
  writes, so a generated world has no insides in it either — which generated
  stubs become places is a scoping decision nobody has made yet
  (`Location#place?`). The worked example above is
  `test/fixtures/files/a-world-with-an-interior.yml`, and
  `lib/engine_sweep/worlds/the-quay-house.yml` is a laid-out one the sweep
  walks; both are out of this directory rather than a fourth world in it,
  because `db/seeds.rb` loads everything here.
- **There are two whole shapes, not one.** An extent alone (`width` + `depth`)
  is a **footprint**: *this place has an inside, and it is this big*, which is
  what the outermost place of an interior carries. All five is a **box**: *and
  it sits here, on this storey of its parent*. Anything else — two of the three
  position keys, or a position with no extent — is refused.
- **Coordinates are local to a parent; there is no global space.** That is what
  lets the world graph stay non-planar (two cities are *days apart*, not
  *n paces apart*) while an interior is exact. So a box needs a `parent`; a
  footprint must not have one forced on it, or nothing could sit at the top.
- **`z` is a storey index, not a height.** 2.5D: each floor is its own plane and
  a stair is an ordinary connection with `travel_method: taking stairs`. The
  same rectangle on two storeys is a building with two floors, not an overlap.
  It is **signed**: `0` is the ground floor — the storey `Location::Interior`
  puts a place's way in on — `1` the floor above it and `-1` the cellar. A file
  may write a negative storey outright, and `Location::Interior` lays one out
  too — see `Location::Interior::BASEMENTS` for which places get one, and
  `lib/engine_sweep/worlds/the-quay-house.yml`'s bonded cellar for a laid-out
  place that spans both directions from its way in.
- **The intervals are half-open.** A room at `x: 0` `width: 7` occupies 0–6, so
  a room at `x: 7` shares its wall and does not overlap it.
- Both are **omitted rather than written out** on export, like `mobile` and
  `danger`, and both are **re-asserted in both directions** on load: deleting
  `parent:` and the box from a file and re-seeding takes the room back out of
  the building.
- **The loader refuses** a partial shape, a non-integer or a zero-width room, a
  box with no `parent`, a `parent` this file does not declare, a room that is
  its own parent, a containment cycle, a box inside a place with no footprint,
  and two boxes under one parent on one storey that overlap.
- `rake game:doctor` reports the same faults on a database that already carries
  them — `location_with_a_partial_box`,
  `location_with_an_impossible_extent`, `location_with_a_box_and_no_parent`,
  `location_with_a_box_outside_a_footprint`, `overlapping_sibling_locations`
  and `locations_containing_each_other`. **None can be repaired:** which of two
  overlapping rooms its author put in the wrong place is not on record, and
  clearing a box deletes a floor plan somebody laid out. `rake game:export`
  warns about every one of them too, naming the code, because a file carrying
  one will not load.
- **The doctor also reports faults the loader cannot refuse** — an interior with
  a room nothing reaches, stairs between rooms that do not stand over each
  other, a door between two rooms that share no wall, a place written out in
  full with not one room inside it. A file carrying one of those loads and
  plays; it is a floor plan that does not add up rather than a file that does
  not parse. `Story::Doctor`'s geometry group is the list, with what each one
  means.
- **A FOOTPRINT AND NO ROOMS MEANS THE ENGINE DRAWS THEM.** The first time
  somebody walks into a place carrying a footprint, `Location::Interior` lays
  out its whole inside — every room and every door, from one seeded roll and
  with no model call. It is skipped for a place that already has children, so a
  file that draws its own rooms keeps them exactly as written and a file that
  gives only a width and a depth is asking for a building it has not seen. Read
  `Location::Interior`'s header before writing either. **The rooms it draws are
  numbered, not named** — `The Custom House room 1` — until somebody walks into
  one, and `Location::RoomName` writes the name then; `rake game:export` dumps
  the numbers as it finds them, so what a re-seed does with one is under
  *Re-seeding a world somebody has played*.
- **No typed line may touch a box.** A box is the world's on exactly the terms a
  hit die and a hazard are; `EngineSweep::Invariants`' `geometry_unmoved` asserts
  across a whole scripted play that no coordinate and no `parent` moved.

### `x` and `y` on a thing and on a person — where in the room they are

Once a room carries a box, a file may say where in it something is. Two integer
keys, on an **item lying in that room** and on a **character standing in it**:

```yaml
characters:
- fullname: Nell Cawsand
  location: The Taproom
  x: 2
  y: 6
  # ...
locations:
- name: The Taproom
  parent: The Rusted Anchor
  x: 0
  y: 0
  z: 0
  width: 7
  depth: 8
  # ...
  items:
  - name: brass tap key
    description: |-
      A short brass key with a square bit, kept on the lintel.
    x: 5
    y: 1
```

`test/fixtures/files/a-world-with-an-interior.yml` is the worked example.
`Location::Spot` owns the design; the rules a FILE is held to:

- **Both keys or neither**, and integers. One of the two is half an answer and
  the loader refuses it.
- **Read in the same plane the room's own box is** — its parent's, not a frame
  of the room's own. The taproom above runs 0–6 along `x`, so a thing at `x: 9`
  is in the back room next door and not in the taproom, whatever room its
  `items:` list hangs off. Half-open again: `x: 7` there is the far wall.
- **There is no `z`.** A storey belongs to the room; a thing is in a room, so
  which floor the key is on is which floor the taproom is on.
- **A position needs a floor.** An item under a `characters:` entry is in a pair
  of hands and is in no room, and a character with no `location` is nowhere;
  neither may carry one. Nor may anything in a room with no box — there is no
  plane to read the numbers in.
- **Absent keys mean UNPLACED**, which every row of all three worlds below is
  and which is a perfectly ordinary state. Written in both directions, like the
  box: deleting them and re-seeding takes the thing out of that corner again.
- **The loader refuses** every one of those, naming the file and the row, and
  `rake game:doctor` reports the same faults on a database that already carries
  them — `thing_with_a_partial_position`,
  `thing_positioned_in_a_room_with_no_box` and
  `thing_outside_the_room_it_is_in`. **None can be repaired,** for the boxes'
  reason: when a row says it is somewhere its room is not, which of the two
  records is wrong is not on record. `rake game:export` warns about each of
  them, naming the code.
- **A room with a box places what is born into it, by itself.** `Item::Registry`
  and `Character::Registry` roll a cell for anything the engine writes into a
  boxed room (`Location::Placement`, one seeded roll, no model call), so a file
  only needs these keys for something it wants in a particular corner.
- **No typed line and no model may write one.** A position is the world's on the
  same terms a box is. What PLAY may move is one game's own copy of a thing: a
  take clears its position (it is in a hand) and a drop rolls a new one inside
  the room the party is standing in. `EngineSweep::Invariants`'
  `positions_in_bounds` asserts across a whole scripted play that nothing ended
  up outside the room it says it is in.

### Rules the loader enforces

- Exactly one location is `opening: true`, and it must be `realized` — a story
  whose opening location is a stub cannot be started in the browser. That row
  must also be the FIRST in the list, which the loader does not check: see
  the `parent` section above for why an interior makes it easy to get wrong.
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
- A character's `stats`, when the file gives one, carries exactly `level` and
  `hit_die`, in `Character::LEVELS` and `Character::HIT_DICE`. Absent is legal
  and means no stat block; half a block is refused.
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
- A `hostile: true` character carries a `stats` mapping. A foe with no body can
  neither be hurt nor hurt back.
- A location's `danger`, when the file gives one, is one of `safe`, `uneasy`,
  `dangerous`, `deadly` — `Location::DANGERS`, and an absent key means `safe`.
- A `hazard`, on a room or on a connection, is a key into that table's own
  catalogue (`Location::HAZARDS` / `LocationConnection::HAZARDS`) and comes with
  a `hazard_die` in `Location::HAZARD_DICE`. Half a hazard is refused: a key
  with no die is a file that looks as though it said something and did not.
- A connection with a `hazard` carries a `hazard_from`, and that name is one of
  the edge's **own two ends**. Without it there is no way to say which direction
  costs something; with the wrong name the edge would load with no hazard at all
  and no complaint.
- A `parent` and a box are held to the rules `WorldSeed::Loader#validate_boxes!`
  names — whole, integers, framed, footprint, declared, apart — which are not
  repeated here: see the `parent` section above.
- An `x` and a `y` on a thing or a person are held to the rules
  `WorldSeed::Loader#validate_positions!` names — whole, integers, on a floor,
  inside — which are not repeated here either: see the `x` and `y` section
  above.
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

`Playthrough`s, `last_protagonist_visit`, the `WorldEvent` **log**, a mechanic's
`last_run_at`, **conversation history** (`chats` / `messages`), and every
`Scene` **but the opening arrival**: those are somebody's progress through a
world, not the world. The one `WorldEvent` that IS exported is an unfired row a
world file **scheduled** (see `schedule` above) — a statement about what will
happen is a rule this world was written with, and a record of what already did
is not. `rake game:export` says out loud how many it left behind,
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
- **A room of a place is the same room at the same coordinates**, whatever it
  has come to be called — the one identity pass the written name cannot reach,
  and the reason it exists is that the ENGINE renames these rooms: a room of a
  laid-out place is named when somebody first walks into it, so a stub this file
  declares as `The Custom House room 1` is a row called `the counting room`
  afterwards, and no reading of the two strings could tell they are one room. So
  a room the file gives a `parent:` and a box is matched on that place and that
  box when both name passes miss. **Only where this file names that row nowhere else**,
  because a row some other declaration names is that declaration's — without
  that limit, which declaration got the played row came down to which one the
  document happened to list first. `WorldSeed.find_location` owns all three
  passes, and the loader, `Story::Doctor` and `Story::Repair` all read it, so
  what a re-seed loads, what the doctor reports and what a repair puts back
  cannot disagree about which row the file means.
- **A rename no normalized name recognizes** — `The Supply Closet` edited to
  `The Broom Cupboard` — is, to any loader, a room that does not exist yet.
  Nothing in the file says which room it replaced. So the row is created and the
  load prints a `WARNING:` naming it, on a world that has been played; the old
  room is still there and `rake game:doctor` reports the pair whenever it can
  recognize one. Two hand-written names for one room of a place are this shape
  too: the box pass above takes a rename across the provisional line and not a
  second deliberate name, which is a known limit left open on purpose.

What still happens on every re-seed, and is the rule rather than a defect: **the
file re-asserts itself over the world layer.** An item the file puts on a shelf
is back on the shelf when the load finishes, a character goes back where the
file places them, `absent: true` is written and deleting it is taken off. A seed
file is the authority on the world, not a suggestion.

**With one exception, and it is a number rather than a name.** A file still
carrying `The Custom House room 1` for a room somebody has since named is not
asserting a name: that string is the placeholder the engine wrote before anybody
walked in, and `rake game:export` dumps those numbers straight out, so a
round-tripped file is full of them. Loaded over a row that has a name of its own,
the row keeps it — the one place in this file where the document does not get the
last word. `WorldSeed.keeps_its_own_name?` carries what putting the number back
would cost: a room realized under its number is never offered a name again, so
the player would read *"You are in The Custom House room 1 of The Custom
House"* for the rest of the game. Write a real room name into the file and it
wins like everything else here.
`lib/engine_sweep/scripts/re-seeding-a-building-somebody-is-inside.yml` walks
both directions of that offline.

**And it reaches no game at all.** Since the ruling of 2026-09-04 the world's
own rows are the templates each playthrough copies at first contact, so what a
party is carrying — and what a party left lying in a room — is that party's, and
the loader does not touch it (`Item.templates` is the whole guard in
`WorldSeed::Loader#find_item`). One consequence is worth knowing: **a copy keeps
the text and the name it was copied with**, so editing a room's item reaches
every game that has not met the thing yet and no game that has.
`items.template_id` still ties the two together, which is how `rake game:doctor`
reads a copy of a renamed row as a copy rather than as a stray.
`lib/engine_sweep/scripts/reseed-a-played-world.yml` walks both halves: the
first player's stamp stays where they dropped it, and the second player — who
never moved anything — sees the world's own stamp back in the office.

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

`universe.races[].monstrous`, `characters[].hostile` and `locations[].danger`
were added to format 2 for the same reason, on the same rule: all three are
optional, all three default to a world with no monsters in it, and every file
written before they existed still loads and still means exactly what it meant.

`locations[].hazard` / `hazard_die` and `connections[].hazard` / `hazard_die` /
`hazard_from` were added to format 2 on that same rule: every one of them is
optional, all of them default to a world that does nothing to anybody for
walking around it, and the columns are nullable so no existing database needs a
backfill either.

The optional `mechanics` key and `locations[].mobile` were added to format 2
rather than bumping it to 3, which is the rule `WorldSeed::FORMAT` states:
the number moves when a loader **cannot absorb** an older file. Both keys are
optional and both default to "this world does not move", so every format 2 file
written before they existed — `the-unrecorded-hour.yml` included — still loads
and still means exactly what it meant. A required key, as `opening_scene` was,
is what bumps the number.

`locations[].parent` and the box (`x`, `y`, `z`, `width`, `depth`) were added to
format 2 on that same rule: all six are optional, all six default to a world
with no interiors in it — which is what every world here is, by the captain's
fourth ruling of 2026-09-06 — and the columns are nullable, so no existing
database needs a backfill either. See the `parent` section above.

`characters[].x` / `.y` and the same pair on an `items[]` entry were added to
format 2 on that rule too: both are optional, an absent pair means *unplaced* —
which every thing and every person in every world here is — and the columns are
nullable, so no existing database needs a backfill either. See the `x` and `y`
section above.

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

**It is the one seeded world with a monster in it**, and it is here rather than
in the other two on purpose. `The Salt Assizes` is the held-out world for
`rake eval:run`; `The Unrecorded Hour`'s own universe says physical violence is
rarely the instrument of choice. This world's physics have claimed since it was
generated that prolonged exposure to Nocturna causes disorientation and memory
loss, so `Nocturna-Blighted` is that claim followed to its end and marked
`monstrous: true`, and Marek Sollen — `hostile: true`, in the `dangerous` bell
chamber — is one of them. The Bell of Saint Aravel is realized for the reason the
supply closet in `The Unrecorded Hour` is: a stub has nothing in it to walk into.
`lib/engine_sweep/scripts/a-monster-in-a-room.yml` walks up to him offline.

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

### Worlds that are checked in and are not here

Two, and each one is out of this directory for a stated reason rather than by
oversight — `db/seeds.rb` loads everything in here, so a file here is a world
every fresh clone and every development database gains.

- `lib/engine_sweep/worlds/the-quay-house.yml` — two places with their insides
  laid out, one of them with storeys below its own way in, for the sweep
  scripts that walk them. `EngineSweep::WORLDS`.
- `lib/engine_sweep/worlds/the-iron-gate-descends.yml` — a **generated** world,
  exported with `rake game:export` and then repaired by hand until its own
  premise was reachable, and the first generated world with an offline test.
  `Eval::Realization::WORLD_ROOTS` refuses a generated world in this directory:
  the realization bench searches here first, so a copy here would quietly
  become the world that bench measures. The bench's own copy is the frozen
  export at `test/fixtures/files/worlds/the-iron-gate-descends.yml` — the graph
  as the generator left it — and it is deliberately not repaired.
