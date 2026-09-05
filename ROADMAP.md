# Roadmap

Working status for Text Adventure. Update this file as work lands — it is the
single place that records what is built, what is next, and why. The queue
itself lives in firstmate (`tasks-axi list --state queued`); this file says
what each queued item *is* and why it sits where it does.

**Core idea:** a text adventure that generates itself as you explore. The world
is generated on demand, and once generated it persists — walk back into a room
and it is the room you left.

## The persistence model

This is the load-bearing design decision, and the schema already encodes it:

- **`Location` is the durable world.** Name, description, `lore`, the
  `location_connections` graph (with `distance` / `time_to_travel` /
  `travel_method`), `parent_location` for containment. Generated once, then
  reused forever.
- **`Scene` is a moment in that world.** `belongs_to :location`, plus a
  `previous_scene` linked list and a `story_timestamp`.

So revisiting a place reuses the persisted `Location` while creating a new
`Scene`. The world stays fixed; time still moves. Generation happens at the
`Location` boundary, never twice for the same place.

## The standing constraint

The captain's ruling, and it now governs design decisions across the project:

> *"I would rather not depend on the narrator doing what we tell it to do. We
> should prompt it with rules if that makes it more likely that it will follow
> them though and save on tokens. But I think we ultimately need a verification
> process."*

Both halves, not one: **inform and verify.** Prompt the narrator with the
world's laws — it is cheap and it raises the odds — but never let a guarantee
rest on its compliance. *Gate the state, inform the prose, audit the
difference.* An unenforced narration rule costs a sentence; an unenforced state
rule costs the game.

The README's turn diagram already states it best, in the colours: purple is a
model call, teal is the app deciding from records it holds, and every branch is
taken on a record rather than on a label a model wrote — see
[README.md](README.md#how-a-turn-works). The pattern to copy: *do not ask a
model what should happen; ask it to pick from a set the app closed, then have
the app act.* `Playthrough::Classifier` is the worked example — it is a model
call, so it can be **wrong**, but its answer is a closed enum built from the
room's real exits and cast, so it cannot be **out of bounds**.

The full audit of every planned piece of work against this constraint is in
`data/ta-direction/report.md` §0.1 (firstmate repo).

## Status

### Done

- **The battle view in the browser** (`ta-combat-battle-view`, slice 7 of the
  combat build order). The captain's call C9, 2026-09-05: *"go with buttons for
  now."* He can now fight in a browser, and **this is the last slice that
  changes no prompt**.

  **What he sees.** A panel inside `#turn_log` — the room and the round, one
  condition line per body in the fight (`9 of 18`, marked `you` / `hostile` /
  `provoked`), the blows of the round just fought in the engine's own sentence,
  and a button per act: strike each live foe, leave by each exit. Condition
  lines and **not bars**: restyling is still `ta-api-iface`'s stage, and a
  hit-point bar would be that stage arriving early and unplanned.

  **A fight is entered and left by DERIVATION.** The panel is rendered when
  `Playthrough#foes_in(current_location)` answers with somebody — no battle
  flag, no mode, nothing to go stale. It is gone the turn the last foe dies or
  the party walks out, and the ordinary prose loop resumes with **nothing to
  reconcile**, because the fight wrote through the same records the prose loop
  writes through. A dead player has the death notice instead, exactly as before.

  **ONE UI, and this is the argument.** A battle button *is* `turns#create` with
  a fixed command string — the same route, the same `NarrationJob`, the same
  `Playthrough::Turn#play` the text box reaches, and the box stays under the
  panel. The strings carry a `/`, so `Playthrough::Grammar` reads them and the
  classifier never runs: **a round costs zero model calls**, measured in a real
  browser (three model conversations for the two `/go` moves that walked to the
  fight, and none at all for the two rounds fought).

  **Not built, and deferred rather than missing**: prose per round (shape (b),
  blocked on `ta-prompt-bench`), the seventh classifier intent (slice 8), throw
  buttons (`Playthrough::Battle#throws` is a marked seam answering `[]`; slice 5
  has since landed the verb, so what is left there is the button and not the
  grammar), hit-point bars, and the d3 scout's room
  sheet — `.sheet` is factored so that sheet can reuse the frame when it is
  ruled on.

- **Terrain and edges hurt** (`ta-combat-hazards`, slice 6 of the combat build
  order). The captain's request, second half: *"certain terrain or actions
  should also cause damage."* A room can cost you hit points for walking into it
  or for staying in it, and **a doorway can cost you in one direction and not
  the other** — the first mechanic that uses the directed edge for what it was
  kept for.

  **One writer, four sources, and no rule engine.** Every hit point in the app
  still comes off through `Playthrough::Turn#harm!`; what changed is that a
  fourth thing calls it. `Playthrough::Hazards` is two named branches in Ruby —
  `#on_arrival!` (the doorway that was walked, then the room), called from
  `Playthrough::Turn#move_to` after the room is realized and after the snapshot,
  and `#every_turn!`, called from step 7 beside `Playthrough::Riposte` on the
  room the turn BEGAN in. `data/ta-direction/report.md` §12's prohibition holds:
  the catalogues (`Location::HAZARDS`, `LocationConnection::HAZARDS`) are the
  branches' PARAMETERS, and §8.4's general "action carries a consequence" table
  is deliberately not built. A refused line pays nothing, an engine instrument
  pays nothing, and a game that is over pays nothing — the same three rules the
  riposte is under.

  **The save is the three abilities earning their keep**: `d20 <= the ability`
  through `Character#check`, the one kernel. `save: nil` is a real hazard and not
  an omission — there is no dexterity against having nothing to breathe — and a
  body with no abilities on record does not get one either.

  **Directed edges (the ruling of 2026-09-03) make it one-way by construction.**
  `location_connections` is two rows per door, so the hazard lives on one of
  them and nothing has to enforce the asymmetry. **A one-way HAZARD is not a
  one-way EXIT**: both rows are still written, the door still leads both ways,
  and only the cost differs; one-way exits stay unsupported and deliberately
  deferred. `hazard_from: <room name>` is the one new piece of seed-format shape
  the whole design needs, because `between:` is an unordered pair.

  **What it took is a record of its own and never a `Playthrough::Blow`.**
  `playthrough_tolls` — one row per hazard paid, per game — because a hazard has
  no attacker (`playthrough_blows.attacker_id` is NOT NULL) and because
  `Playthrough::Fight#open_blows` is *the fight that is still on*: a hazard in
  that table would open a fight nobody was in and close it on the same turn with
  a `Scene` saying so. `Playthrough::Moment` states the untold ones to the prose
  beside `#struck_fact` and never folded into it — somebody hit you and the world
  did are two different facts — and a SAVE is stated too, so the prose does not
  invent a wound for a turn the water missed.

  **All four columns are nullable and there is no `bin/update` step**, which is a
  different answer from `locations.danger`'s and the right one for a different
  question: a danger is a share of a die every room has, and a hazard is a thing
  almost no room does. NULL says exactly that, and there is nothing about an
  existing database that is wrong.

  **The instruments**: a `hazards:` sweep expectation (counting rows, never a
  die), `hazard` and `hazards out` lines in the mechanics read-out,
  `EngineSweep::Invariants#hazards_unmoved` (no typed line writes one), two
  doctor findings — `location_with_an_unknown_hazard` and
  `connection_with_an_unknown_hazard`, both manual and both stated — and
  `lib/engine_sweep/scripts/a-one-way-hazard-on-a-door.yml`, which walks the same
  door both ways.

  **`the-salt-assizes.yml` gains both**, and the file says why at length: its
  fiction is built out of exactly this, and it is the one seeded world with no
  `mechanics:` block — `WorldMechanic::ShuffleConnections` rewrites an edge from
  `distance` and `travel_method` alone and in both directions, so a directed
  hazard on a shufflable edge would be destroyed the first night.

  **Not built, and deferred rather than missing**: `items.hazard` (§8.4's third
  row — a `take` of something the world marks harmful), a provoking `talk`
  (captain call C7, which needs a model's answer to be authoritative about
  state), and **generated hazards** — nothing rolls a `hazard` the way
  `Location::Danger` rolls a `danger`, and whether a generated world should get
  one is a later question.

- **A thing can be thrown** (`ta-combat-throw`, slice 5 of the combat build
  order). The captain's request, answered: *"I want players to be able to pick up
  items and throw them based on a strength check."*

  **ONE ROLL, NOT TWO.** A d20 under the thrower's `strength` less what the thing
  weighs, through the one check kernel (`Character#check`) — and no second roll to
  see whether it hit. The lift IS the throw: if it leaves your hands it goes where
  you aimed it, which is *a blow always connects* said one act over.
  `Playthrough::Turn#throw_item!` is the whole of it and needs no new writer —
  `#put_down!` (which gained one keyword, `into:`) and `#harm!` in one
  transaction, and a hit is a `Playthrough::Blow` through `#strike!`'s new
  `damage:`, so the riposte answers a thrown chair and the fight-end rule sees it.

  **`items.bulk` is a closed key and never a number on the row.** `Item::BULK`
  maps it to the penalty — light 0, handy 2, heavy 5 — and `immovable` to nil,
  which is not a hard throw but the absence of one; `Item::THROWN_DAMAGE` is a
  second table on the same key: light d4, handy d6, heavy d8. `default: "handy",
  null: false`, so **no `bin/update` step exists and none is needed**: every row
  already written is handy, and a file that decides otherwise reaches a game in
  progress through `Item::TemplateRefresh`, whose list is now `bulk`'s home too.

  **C8, said out loud:** a thrown heavy thing kills an unhurt level-1 d6 body
  **37.3%** of the time, in either direction. It is the most lethal act in the
  game, survivable only because C1 put the seeded protagonists at 18 hit points.

  **Four outcomes and only one is a refusal.** A **fumble** is a turn the engine
  played — it costs story time, writes a `Scene` and is narrated as a fact, and
  nothing moved. **Immovable** is `Playthrough::Refusal`'s fifth shape: no die, no
  row, no clock. A **hit** lands the thing at their feet; a throw **through a
  doorway** leaves it lying in the next room.

  **`throw <thing> at <somebody|way out>` names TWO records**, the only line in
  the game that does — the thing out of what is carried PLUS what is lying here,
  the aim out of who is standing here and then the ways out. It is an engine-view
  verb in the fixed grammar (call C6), so it makes no model call in either mode
  and a slashed `/throw ...` resolves offline in the browser;
  `Playthrough::IntentSchema::INTENTS`, `Drift::ACTIONS` and `Overreach::ACTIONS`
  are untouched, because the classifier intent is slice 8.

  **The instruments**: `a-thing-can-be-thrown.yml` walks all four outcomes and
  says in its header why no script can pin one — `Roll`'s seed is built out of row
  ids and no bulk makes a pass certain (the best case is strength 18 against a
  light thing, `d20 <= 18`) — so it pins the refusals, the act, the target the d20
  was thrown at, and one throw whose records are the same either way.
  `Playthrough::TurnThrowTest` hands `#throw_item!` its own `rng:` and pins all
  four exactly. `Scene::ENGINE_AUTHORED` is a named list now rather than the gap
  between `ACTIONS` and `INTENTS`, because a throw's Scene is the narrator's prose
  and the derived definition would have hidden it from `Story::Audit`.

- **A fight resolves and can kill** (`ta-combat-fight`, slice 4 of the combat
  build order). The captain's word, 2026-09-05: *"continue through all of the
  combat slices."* **This is the slice the whole direction asked for**: he can
  walk a whole fight with `NO_MODEL=1 rake game:mechanics`, win one, die in one,
  and CI regression-tests both.

  **The rule, in one paragraph.** A blow always connects and deals one die of the
  attacker's `hit_die` — no to-hit, no armour, no critical, no initiative and no
  ability term (call C2, measured: with death terminal, a to-hit roll makes the
  *underdog* more likely to win). **A round IS the turn** (call C5): the player
  acts by typing, then every live foe in the room acts in `id` order
  (`Playthrough::Riposte`, step 7 of `Playthrough::Turn#play` and of
  `Playthrough::Mechanics#run`). It runs on every line the engine PLAYED and on
  no line it refused. On a move, the foes in the room you LEFT act before you go,
  and then the fight is over — call C1, *a fight is always escapable by leaving
  the room*, with a price on it.

  **`attack <name>` reads the FULL present-people set** — the captain's sixth
  ruling, ***"anyone can be attacked"***. It is an engine-view verb in the fixed
  grammar, so it makes no model call in either mode and a slashed `/attack Rowe`
  resolves offline in the browser too; `Playthrough::IntentSchema::INTENTS`,
  `Drift::ACTIONS` and `Overreach::ACTIONS` are untouched, because the seventh
  intent is a measured slice of its own (slice 8). Being attacked marks the
  victim **provoked for this playthrough** (`playthrough_vitals.provoked_at`),
  and a provoked person strikes back from the next turn. `characters.hostile` is
  the world's and never moves.

  **`playthrough_blows` is the exchange and ONE `Scene` closes the fight.** A
  Scene per round would put engine copy in the column `Story::Audit` and
  `Eval::Richness` read as narration once per round; none at all would stop
  `Story#clock` through a fight. `Playthrough::Fight` writes the closing Scene —
  `resolved_action: "attack"`, `Scene::TURN_MINUTES["action"]` per round, the
  ENGINE's own sentence in `description`, no model call — and `#over?` is the one
  place the fight-end rule lives: no live foe present, the party left the room,
  or the player is dead. `Scene#engine_authored?` keeps the audit honest and
  `rake game:score` prints the count it excluded.

  **Death of an NPC is this game's death.** `Playthrough#cast_in` subtracts this
  game's dead and the four readers come through it, so a corpse cannot be talked
  to or hit twice; `Character.present_in` stays the world's answer.
  `Playthrough::Turn#spill!` puts a dead body's own copies on the floor in the
  same transaction as the last hit point — loot — and the world's rows never
  move. Three doctor findings: `dead_body_holding_things` and
  `playthrough_dead_but_not_ended` (both safe, both repaired) and
  `provoked_without_a_meeting` (manual, stated: deleting the row would erase a
  fight).

  **The instruments**: `blows:` and `hp_of:` sweep expectations, a `foes` and a
  `provoked` line in the mechanics read-out, and two sweep scripts —
  `a-fight-the-player-wins.yml` and `a-fight-that-kills-the-player.yml`. **A
  script may not assert a die**: `Roll`'s seed is built out of row ids, so what a
  blow COST is not reproducible between two databases and what a turn DID is.
  Each script is arranged so its ending is fixed whatever the dice say, verified
  over 16 different row-id offsets.

  **The player's body starts at level 3 with a d8 — 18 hit points** — in the
  three seeded worlds (call C1); `STARTING_LEVEL` stays 1 for generated people.
  It reaches an existing database through `bin/update`'s re-seed and deliberately
  does not touch `playthrough_vitals`.

- **A monster can exist in a room and be seen** (`ta-combat-monsters`, slice 2 of
  the combat build order). The captain's ruling of 2026-09-04, verbatim:

  > *"a universe should be able to have monsters as well as characters."*

  And his seventh ruling the same evening, which is where they come from:

  > *"go with your rule for now. eventually I want the universe generator to
  > provide more input into this."*

  **Nothing fights.** What ships is that a world can CONTAIN an enemy, that
  `rake game:mechanics` shows it standing there, that `rake game:doctor` can
  vouch for it and that `rake game:sweep` asserts it offline.

  **Three columns, all on the WORLD's side of the layer split** — `hit_die`'s
  side. `races.monstrous` makes a race one of a universe's monsters rather than
  one of its peoples, so a bestiary is the monstrous half of the race list that
  already exists and there is no second catalogue. `characters.hostile` says
  this person attacks the party — a flag on the record rather than an STI
  subtype or a `monsters` table, which is `locations.mobile`'s own argument said
  one table over: every seam a fight needs (a body, a whereabouts, hands, a place
  in a room's cast, a per-playthrough condition, a seed entry, a doctor finding)
  already exists on `Character` and on nothing else. `locations.danger` is how
  likely a room is to be BORN with the world's monsters in it. All three are NOT
  NULL with a default, which is `items.readable`'s shape and why **no
  `bin/update` step was needed**: an existing world has no monsters and the
  defaults say so.

  **Hostility is DERIVED for everybody the engine writes**, in one line:
  `Character.hostile_by_default?` is true when the race is monstrous, read by
  `Character::Registry` and `Character::Generator` — the only two things in the
  app that create a character outside a seed file. No model input reaches it:
  no schema gained a field, no prompt mentions one, and nothing scans prose.
  A seed file may say `hostile:` outright, which is how a world holds a tame
  beast of a monstrous race.

  **Where monsters come from is a rolled per-room `danger`**, in the shape of
  `locations.mobile` and `location_connections.distance`: a closed-set key into
  `Location::DANGERS` (`safe` / `uneasy` / `dangerous` / `deadly`) whose value is
  faces of a d6. `Location::Danger.for_a_new_room` rolls it through the seeded
  `Roll` kernel when a room is BORN — `Location::Generator#create_stub!`, which
  is where a generated world's rooms come into existence — and
  `Character::Registry#slots` throws one die per slot at realization to decide
  whether that person is drawn from `Race.monstrous` or `Race.peoples`. `deadly`
  is a seed file's word and the engine never rolls it. **The opening room of a
  generated world is never rolled** and is therefore safe. Wandering on the story
  clock and universe-generator input to placement are later slices, by ruling.

  **`Playthrough#foes_in(location)` is the one reader**: the world says who is
  hostile, a GAME says who is still standing. It is `#items_lying_in`'s shape one
  table over and it is there for that method's reason — `Character.hostile`
  alone would offer a corpse a fight. There is no per-playthrough mark about
  hostility and that is deliberate: whether a foe has noticed you, whether you
  talked it down, whether it is still angry after you fled are all slice 4's.

  **Captain call C4, and it is the only model-facing piece.** His explicit word,
  overriding the combat scout's recommendation: *"monstrous races should reach
  the prompts."* So a monstrous race is in `Universe#race_names` for BOTH the
  `:place` and `:dialogue` audiences. **No prompt template changed** — only what
  the existing list contains once a world marks a race monstrous.

  **The instruments**: a `hostile` line in the mechanics engine-view read-out
  beside `present`, a `foes:` sweep expectation,
  `EngineSweep::Invariants#hostility_unmoved` (all three columns against the
  world file — the statement `stat_blocks_unmoved` makes about a body, and its
  own check because two of the three are not columns on a character), and three
  doctor findings: `hostile_without_a_stat_block` (safe, and the same roll
  `character_without_a_stat_block` already had),
  `monstrous_race_with_no_monsters` and `location_with_an_unknown_danger` (both
  explicitly **no repair** — writing a monster is world data, and nothing on
  record says which of the four words a fifth one meant).

  **One seeded world gained a monster.** `The Lunar Cartographer` — not the
  held-out `The Salt Assizes`, and not `The Unrecorded Hour`, whose own universe
  says physical violence is rarely the instrument of choice. Its physics have
  claimed since it was generated that prolonged exposure to Nocturna causes
  memory loss, so `Nocturna-Blighted` is that claim followed to its end, and
  Marek Sollen stands `hostile: true` in the `dangerous` bell chamber.
  `lib/engine_sweep/scripts/a-monster-in-a-room.yml` walks up to him with no
  model at all.

  **One pre-existing bug fell out of it**: `WorldSeed::Loader` never wrote a
  CHANGED race back. `has_many` without `autosave:` saves the new records in a
  collection and leaves the changed ones alone, so editing a race's description
  in a seed file and re-seeding did nothing. Races were the one table outside the
  loader's own "the file re-asserts itself over a played world" rule.
- **A pull re-applies a changed world file, and the doctor notices a copy that
  lags it** (`ta-update-reseeds`). A world outlives its seed FILE the way it
  outlives its schema: The Salt Assizes was seeded on the evening of 2026-09-03
  and the next morning's PR gave the protagonist's `Assize tide-slate`
  `readable: true` and an inscription — and nothing `bin/update` did looked at a
  seed file, so the world's own row stayed blank, every playthrough had already
  copied the blank row, and `read slate` was correctly refused for days.

  `bin/update` now asks `db/seeds/worlds` the same range question it already
  asks `Gemfile.lock`, after the migrations and the steps, and runs
  `rake game:reseed` (which is `WorldSeed::Loader`, whole) when a file moved.
  `Update::SeedFiles` is the decision, extracted so it can be asserted with no
  checkout and no network; `--seed` forces it where `--skip-pull` leaves no
  range to read. A re-seed **re-asserts the file's values over the world's own
  rows, seeded stats included** — the script says so — and, correctly, stops at
  the world layer.

  Which leaves the copies, so `Item::TemplateRefresh` is the other half:
  `rake game:doctor` reports `copy_lags_its_template` (`safe`) for a copy **no
  turn has acted on** and `touched_copy_lags_its_template` (`manual`) for one a
  take or a drop has handled. Only the text moves. Rehearsed on a copy of the
  captain's own database: the re-seed wrote the slate's words, the doctor named
  both lagging copies and three `hp_above_maximum` rows the seeded stats had
  just created, and `rake 'game:repair[6]'` cleared all five.

- **A slash in front of the line, and the grammar reads it first**
  (`ta-slash-input`). The captain's ruling of 2026-09-04, evening, verbatim:

  > *"support a slash prefix autocomplete in the text box, and resolve those and
  > verb-prefixed lines offline then fallback to the model."*

  **No prompt changed.** `Playthrough::Classifier::INSTRUCTIONS` and
  `Playthrough::IntentSchema` are byte-identical.

  **The slash is the whole of the claim**, which is his ruling of the following
  day. He objected first — *"i'm not sure that a line beginning with `move`
  should always go to the move action… a player might type: `move the lamp off
  the desk`"* — and then ruled:

  > *"I think we should only auto accept the slash commands."*

  He was right and it was worse than the example. Measured against a room with a
  `The Supply Closet` exit and a daybook in hand, four ordinary English lines
  were answered on a real record: `move the supply closet shelf aside` and `walk
  the supply closet perimeter` **walked the player in**, `leave the ward office`
  **put down the daybook**, and `take a look at the brass lamp` **took it**.
  `VERBS` is a command vocabulary, not English, and a leading verb is a
  coincidence. `Playthrough::Grammar::MEANS_SOMETHING_ELSE` keeps the four so the
  verb-prefixed claim cannot come back quietly.

  **One grammar, two readers, one vocabulary.** The fixed verb table that was
  `Playthrough::Mechanics`'s private half is `Playthrough::Grammar` now, and both
  the browser and the mechanics mode read a SLASHED line with it before spending
  a classifier call. It is matched against **the same closed set the model would
  have been offered** (`Playthrough::Classifier#offered_for`); only a reading
  that RESOLVED a record is taken, so a noun the grammar cannot place falls
  through and the turn costs exactly what it did before. The slash is input
  syntax and is stripped before the line is read, so `Scene#typed` and every
  corpus that reads it go on holding ordinary English. **Offline
  (`model: false`) nothing changed at all**: `#parse` has no slash rule, because
  there is no classifier behind it to defer to.

  **`scenes.resolved_by` is which reader answered**, because a grammar-resolved
  turn calls no classifier and therefore writes no `Playthrough::Drift` or
  `Playthrough::Overreach` row — and a miss attributed to a classifier that never
  saw the line would aim the next prompt change at the wrong thing.

  **One line, one act survived, and it took a measured guard.** A fixed grammar
  has no `also_named`, so a line naming two things out of one closed set would
  have resolved the first and PLAYED it. `Playthrough::Grammar::JOINING_WORDS`
  hands such a line to the classifier instead — which sees the second name,
  refuses the line and writes the counter. On the classifier bench's 300
  labelled lines:
  without the guard 6 wrong answers, all six that shape; with it **59 of 300
  resolve offline in slash form and none of them wrongly**, at a cost of 4 lines
  that were right and now cost one call each. Without a slash: **0 of 300**, and
  the other 300 cost exactly what they cost today.

- **The classifier bench** (`ta-classifier-bench`). The classifier had no
  instrument of its own. `Playthrough::Drift` and `Playthrough::Overreach` count
  its misses indirectly and **neither knows whether the answer was right** — a
  drift row is written whether the player reached for a door that is not there
  or the model failed to see a door that is. Since the ruling of 2026-09-04 that
  gap costs the player something they read, so it is worth measuring.

  **What it is.** `test/fixtures/files/classifier_corpus.yml` — 300 hand-labelled
  typed lines across 11 positions in the three seeded worlds, each with the
  expected intent, target, `also_named` and refusal kind — replayed through the
  real `Playthrough::Classifier` by `rake eval:classifier`. The board reports
  accuracy per intent, a confusion matrix, closed-set misses (right branch,
  wrong record), `also_named` precision and recall, refusal-kind agreement, and
  every figure as a band across repetitions, per model, on `EVALUATION.md`'s own
  noise discipline. `rake eval:classifier_compare` judges a later prompt change
  with the same exact rank test the prose loop uses.

  **The labels are verified mechanically, not asserted.**
  `Eval::Classifier::CorpusTest` runs offline in CI: every `target` and
  `also_named` is checked back against the closed set the action really reads at
  its position, and a stated `refusal:` is re-derived from the label and
  compared — two readings of one line have to agree. 55 of the 300 lines carry
  `also_accept` because their English admits two readings, and the headline rate
  excludes them.

  **The offline floor is the number that says what a call is buying.**
  `rake eval:classifier_offline` runs the same 300 lines through the fixed
  grammar with no model at all: **127 of 300 (0.423)**, and 156 of the 173
  failures are lines it refused that should have played. It gets every
  reach-that-finds-nothing right and none of the `other` or `examine-nothing`
  lines.

  **The baseline of 2026-09-04 is checked in**, under `db/eval/` as three
  summary sets — 12 KB rendering the same table as the 4.4 MB of runs they came
  from — so `rake eval:classifier_board` prints it on any machine with no key,
  no network and no database, and a later run gets a real REAL/NOISE verdict
  against it. Four hosted models and 4,800 calls:
  `mistralai/mistral-medium-3.1` strict accuracy **0.939..0.951**, **8..11**
  closed-set misses (median 9.5), 0.61s median / 0.88s p95, **0 failures of 1,200**;
  `minimax/minimax-m3` **0.905..0.938**, 11..18 misses, the fastest median of the
  four (0.44s) and the second-worst p95 (1.83s), 7 schema failures;
  `google/gemini-2.5-flash-lite` **0.898 flat over all four repetitions**, 11
  misses, the only arm whose p95 stays inside a second, 0 failures, $0.05 per
  1,000 calls; `mistralai/mistral-small-3.2-24b-instruct` **0.872..0.877** and
  **30 closed-set misses** — the cheapest arm at $0.03 per 1,000 and three times
  the wrong records. `also_named` is a precision/recall trade the four sit all
  over: 1.000/0.888, 0.788/0.897, 1.000/0.862 and **0.553**/0.948. The shipped
  first model gets the safe direction. The two cheaper models are **bench arms
  only** — `REMOTE_MODEL_IDS` is untouched.

  **Speed is one of the measured figures**, because the classifier runs in front
  of the turn and its latency is dead time on every line typed. Median and p95
  per arm, warm-cache with each arm's first call timed apart and excluded, and a
  failed call carries no latency at all. **The local models were not measured**:
  the captain stopped those runs on 2026-09-04 because the machine cannot carry
  them (19 GB, `size_vram: 0`, swapping with one 6 GB model resident). The arm
  selector and the default-off provider-params seam are in and green, so
  `MODELS=ollama:qwen3:4b+nothink REPS=4` is one command away on capable
  hardware.

  **PR 102's finding F4 is answered: the omission rate is 0.000.** Over 4,754
  answers on four models the required `also_named` field never came back absent
  or null. It is read off the provider's own JSON (`messages.content_raw`, kept
  since PR 97) rather than inferred from the resolved `Intent`, which cannot
  tell an omitted field from an answer of `nothing`.

  **No prompt changed.** The findings are in the PR body for the captain. See
  [EVALUATION.md](EVALUATION.md) → *The classifier bench*.
- **Three abilities, and a seeded check kernel** (`ta-ability-scores`). The
  captain's ruling of 2026-09-04, evening, verbatim:

  > *"let's go with the 3 abilities"*

  Strength, dexterity and will — Cairn's set, and **exactly three**. It corrects
  the *"No abilities for now"* below, which was a misunderstanding of the word:
  an ability here is a number a die is thrown against, not a special power.

  **The shape is the stat block's, one column-set wider.** `characters.strength`,
  `.dexterity` and `.will` are nullable integers in `Character::ABILITY_RANGE`
  (3..18, which is what 3d6 rolls), drawn by `Character::StatBlock` from **one
  generator in one fixed order** — the hit die, then `Character::ABILITIES` in
  its stated order — so a body stays re-derivable for ever and `DRY_RUN=1`
  prints the numbers the real run writes. `Roll.pool(3, 6, rng:)` is the one new
  die. Every number is the engine's: no schema and no prompt gained a field, and
  `EngineSweep::Invariants#stat_blocks_unmoved` now reads all five columns off
  the world file, so no typed line may write one.

  **`Character#stat_block?` was deliberately NOT widened.** It gates `#max_hp`
  and through it every `playthrough_vitals` row in the database; widening it
  would have made every existing maximum nil and every game's condition
  unreadable between the migration and the backfill. `#abilities?` is its own
  predicate, with its own whole-or-nothing validation, its own doctor findings
  (`character_without_abilities`, `ability_out_of_range`) and its own safe
  repairs.

  **`#max_hp` gains nothing, and that is stated in `Character`'s header so the
  question is not reopened**: there is no constitution among the three, `will` is
  nerve rather than stamina, and the body's capacity is `hit_die` and nothing
  else.

  **The check is one kernel: d20-under the ability**, with the penalty
  subtracted from the TARGET rather than added to the die — so difficulty is a
  parameter on the thing being tried, the shape `LocationConnection::DISTANCES`
  already has, and there is no modifier function and no DC ladder.
  `Character#check` is the arithmetic, `Character::Check` the record it answers,
  and `Playthrough::Turn#check` builds the seed beside `#harm!` and `#mend!`. At
  a target of zero or less **no die is thrown at all** — the pass rate there is
  zero for ever, so the engine says the thing cannot be done. `rake
  game:mechanics` walks it (`stats`, `check <ability> [penalty]`, printing
  `check strength -> d20(7) <= 12 PASS`) and
  `lib/engine_sweep/scripts/a-check-against-an-ability.yml` sweeps it offline.

  **Not built in THAT slice, and deferred rather than missing**: combat,
  monsters, hostility, throwing, terrain damage, a battle view, any prose check
  reading an ability, any classifier or prompt change, and any ability beyond
  the three. Monsters landed in `ta-combat-monsters`, the fight in
  `ta-combat-fight` and throwing in `ta-combat-throw` (the check kernel's first
  real caller); nothing connects a wound to a check even now — a hurt body rolls
  against the same number.

- **Hit points, death, and inert levels** (`ta-character-stats`). The captain's
  rulings of 2026-09-04, verbatim:

  > *"zero hit points means death. Playthrough is over and you can't do anything
  > else. You have to start a new playthrough. Eventually, we can add going back
  > to saved previous state."*
  >
  > *"No abilities for now. Levels are stored but inert in the first PR. A model
  > cannot set an NPC's numbers, the engine rolls them."*

  The first sentence was **withdrawn the same evening** — see
  `ta-ability-scores` above. The rest stands unchanged: levels are still stored
  and inert, and the engine is still the sole author of every number.

  **The shape is `ta-items-per-playthrough`'s, applied to people.** Who somebody
  IS is the world's (`characters.level`, `characters.hit_die`, nullable, rolled
  by `Character::StatBlock` through the seeded `Roll` kernel); how much is LEFT
  of them is one game's (`playthrough_vitals`, one row per playthrough and
  character, written lazily at first contact by
  `Playthrough::Vitals::Snapshot`). An absent row means unhurt.
  `Character#max_hp = hit_die + (level - 1) * (hit_die / 2 + 1)` — derived, never
  stored, and with no ability term in it. It gained none when the three
  abilities landed either: none of them is a constitution.

  **Death is terminal.** `Playthrough::Turn#harm!` writes the last hit point and
  `playthroughs.ended_at` in one transaction; `Playthrough::Turn#play` and
  `Playthrough::Mechanics#run` refuse every further line in front of the
  classifier, so a line typed into a finished game costs no model call and
  writes nothing. `Playthrough::Refusal`'s fourth shape (`:dead`) says it and
  `Playthrough::DeathNotice` is the one author of the words; the play page drops
  the input and offers a new playthrough.

  **No prose decides anything.** `Playthrough::Moment` gains ONE line — "X is
  badly hurt (4 of 11)." — and nothing else about the prompts changed. Nothing
  in any schema asks a model for a number, and
  `EngineSweep::Invariants#stat_blocks_unmoved` asserts that no typed line ever
  writes one.

- **The world is the template, the playthrough owns the instances**
  (`ta-items-per-playthrough`). The captain's ruling of 2026-09-04, verbatim:

  > *"each play through should have its own copy of items. If a location is
  > generated with items in it, that should become the initial snapshot that any
  > playthrough uses but what happens to the items after that should be managed
  > by the playthrough."*

  **What it closes.** `ta-inventory-per-playthrough` made the party's HANDS
  per-playthrough and deliberately left the ROOMS shared, which was written down
  under *Known issues* with two options. This is the first of those two: a room
  one party has emptied is furnished again for the next player.

  **The shape is one table and two layers.** `items.playthrough_id` stops
  meaning "the party is carrying this" and starts meaning WHICH LAYER: nil is
  one of the world's own rows (a *template*), set is one game's own copy (an
  *instance*), whose place is `location_id`, `character_id`, or neither — which
  is the party's own hands. `items.template_id` is the durable link, so the
  doctor can tell this playthrough's ward stamp from a fresh thing of the same
  name and a template written into a room nobody has visited still reaches every
  game that walks in later. The alternatives — a fourth column keeping
  `playthrough_id` as the hands, or a second table — are stated and rejected in
  `Item`'s header: both make a carried row name its playthrough twice, or fork
  `Item.in_story` and every query that reads it.

  **What it costs, stated.** The old rule was "exactly one of three places,
  never two and never none", and "none" was a real defect. For an instance
  "none" is now a place, so the never-none leg survives on templates only and a
  bug that nulled an instance's `location_id` reads as carried rather than as
  broken. `Item#in_exactly_one_place` says both halves and its header says why.

  **The copies are lazy and made exactly once.** `Item::Snapshot` copies a room
  — its floor and what the people standing on it hold — when the party arrives
  and at the top of every turn on the room they are in, guarded per TEMPLATE
  rather than per room: "this room is done" would refurnish a room the party had
  just emptied, once per return trip, for ever. The protagonist's seeded kit
  became an ordinary case of the same rule, replacing
  `Playthrough#take_up_the_starting_inventory`, with one stated exception —
  it lands in the party's hands rather than the protagonist's, because the
  protagonist is the player.

  **The instruments were rewritten per layer.** The caps, `duplicate_items`,
  `room_over_item_cap` and the name collisions ask about the world; two new
  findings ask about the copies (`playthrough_missing_a_copy`, `safe`;
  `instance_without_a_template`, a report and not a defect). `Item#whereabouts`
  names the layer, so no finding can be read against the wrong one.
  `Item::LayerBackfill` (`rake game:backfill_items`, an `Update::Step`)
  supersedes `Item::InventoryBackfill`: whose hands a thing is in is one case of
  which layer it belongs in, and two backfills deciding it are two answers
  waiting to disagree. On the captain's own database it answered 7 world rows
  left alone, 16 rows attributed with the world's row put back in the room the
  take happened in, 27 copies handed out, and **0 ambiguous and 0
  unrecoverable** — after which all three stories read healthy.

  **`Item::Inscriber` writes the words back onto the template** as well as onto
  the instance, and it is the one place a turn writes the world layer. A world
  whose note said one thing to the first player and something else to the second
  would be the drift the inscription mechanic exists to stop, one layer up.

- **One command after a pull** (`ta-bin-update`). The captain's request of
  2026-09-04, in his words:

  > *"I want a bin/update command I can run that will pull the latest from main
  > and run any fixes or doctor commands necessary to apply the latest changes."*

  **What it replaced.** A hand list at the bottom of every PR body — `git pull
  && bin/rails db:migrate`, then `DRY_RUN=1 rake game:backfill_whereabouts`,
  then `game:backfill_inventory`, then `game:backfill_transitions`, then
  `rake 'game:repair[<id>]'`, then `rake game:doctor`. PRs 105, 109, 110, 111
  and 113 each added one, so five merged descriptions were the only record of
  what an existing database still needed.

  **What is built.** `bin/update` (Ruby, in `bin/setup`'s style): pull the
  default branch fast-forward only, `bundle install` when the lockfile moved in
  that range, `bin/rails db:migrate`, then the post-update steps, then the
  doctor, then a summary and a *restart your dev server* notice. `--dry-run`
  fetches and says what would happen and writes nothing at all — not even the
  pull; `--skip-pull` applies to the tree as it stands. It refuses before it
  touches anything on a dirty tree, a branch that is not the default one, or a
  failed fetch, and it never stashes, resets, checks out, merges, rebases or
  forces anything (`Update::BinUpdateTest` asserts that against the script's own
  source, not just its header).

  **The list is in the repo, not in a PR body.** `Update::REGISTRY`
  (`lib/update.rb`) holds the steps in dependency order and its header is how
  the next PR adds one; `rake game:update` runs them without the git half
  (`DRY_RUN=1`, `ONLY=`, `VERBOSE=1`). Each step is asked what it WOULD do and
  only then asked to do it, so a step with nothing to do costs one line and no
  write, and `bin/update` is worth running after every pull. A step must be
  idempotent, quiet when it has nothing to do, and offline — the model-call gate
  (`Update::Step.model_calls?`) is built, nothing uses it, and
  `Update::RegistryTest` asserts nothing has. See `AGENTS.md` → *A PR that needs
  a post-update action adds a step, not a sentence*.

- **One line, one act — and a line that is not one is refused whole**
  (`ta-one-act-refusal`). The captain's ruling of 2026-09-04, in his words:

  > *"If someone tries to do two things or more at a time, we should refuse and
  > prompt the player to pick only 1 thing. Or if we can't determine what they
  > are trying to do, then we should refuse and ask for clarification. This can
  > all be in the mechanics and doesn't need to go through narration."*

  **What it replaced.** A two-act line did its first act and recorded the rest:
  the browser took the index, said nothing about the apron, and counted the
  apron as a `Playthrough::Overreach`; `rake game:mechanics` printed
  `also named: copy-room apron -- one line is one act, so this turn did not
  touch it`. And a reach that resolved to nothing was narrated with a fact
  saying so (`Playthrough::Turn#reach_fact`), which had a known cost of its own
  — a classifier miss on a real exit read as prose denying a door that is there.

  **What is built.** `Playthrough::Refusal` is the one author of what the engine
  says when it will not play a line, read by both front ends; the decision is
  `Playthrough::Classifier::Intent#refused?`, so the two modes cannot come to
  disagree about a line. Three shapes: **two acts on one line**, **a reach the
  closed sets cannot answer**, and **a classifier answer outside the intent
  table that still named a record** (which used to be coerced to `other`, which
  threw the record away and narrated the raw line). A refused line writes
  nothing at all — no row, no `Scene`, no visit stamp, no story time, no
  narrator call, and no tokens beyond the classifier that had already run. In
  the browser it arrives through `NarrationJob`'s ordinary end-of-turn
  `#turn_log` replace, in the app's own voice where the turn would have been,
  with the typed line echoed and the input back under it — the same place and
  the same `.notice` as `Playthrough::SafetyNotice`, because it is the same kind
  of thing.

  **A refusal is not a `Scene`,** and that is the load-bearing decision.
  `Scene#description` is read as NARRATION by `Story::Audit`, `Eval::Richness`
  and both frozen corpora, so a row of engine copy in that column would be
  audited as prose a model wrote; and a refusal has no moment in it, so writing
  one would move `Story#clock` and stamp
  `Location#last_protagonist_visit` on a turn whose whole point is that nothing
  happened. The durable record of a refused line is the counter row.

  **The counters are untouched.** `Playthrough::Overreach` and
  `Playthrough::Drift` rows are written from exactly where they were, inside
  `Playthrough::Classifier#classify`, before the loop asks whether it will play
  the line: the ruling changed what a turn does, not what is measured.
  `rake game:score` is byte-identical across the change. What did change is what
  the two reach rates *mean* going forward — a refused turn writes no `Scene`,
  so the denominator counts played turns; the note is on
  `Story::Audit#judgeable_for` and fixing it is its own measurable task.

  **The boundary, stated.** `other`, and an `examine` that landed on nothing,
  are NOT undeterminable and stay narrated — "look at the sky", "wait", a remark
  to nobody — or narrated play would refuse everything that is not one of the
  acts that move a row. An `examine` that named TWO things IS refused, like any
  other line asking for two acts: since `ta-item-inscriptions` a look resolves a
  record, and a readable thing named alongside another thing is one line asking
  twice. `Playthrough::Overreach::ACTIONS` gained `examine` for exactly that —
  it was an alias of `Playthrough::Drift::ACTIONS`, and the row would have
  failed its own validation and been logged away, so the refusal would have
  fired uncounted. The two lists are no longer identical and the model header
  says why: a look can overreach and it cannot drift. Two acts across two
  *different* closed sets ("take the stamp and go to the hallway") are still not
  refused, in either mode, because `#also_record` resolves the second name
  through the action's own closed set; widening that would change what
  `Playthrough::Overreach` counts, so it is pinned as a gap in
  `lib/engine_sweep/scripts/one-act-per-line.yml` rather than closed here.

- **What a note says is a record** (`ta-item-inscriptions`). *"when an item is a
  note or piece of paper, etc that has writing on it, we need to store that
  writing so it is permanently held in the game state."* Playthrough 15, scene
  77: he typed *"pickup the note. what does it say?"* and read back *"Midnight.
  The Bell. They know about the maps."* — invented on the spot, kept nowhere,
  and free to be something different the next time he unfolded it.

  `items.readable` says a thing has words on it and `items.inscription` holds
  them, bounded at 400 characters and validated as a pair: an inscription on a
  thing nobody marked readable is the one shape `Item` refuses. **`readable` is
  the whole gate** — nothing in the app ever generates text for an item the
  world did not mark readable, so a ward stamp stays a ward stamp forever.

  **The words are written in three places and only three.** `Item::Registry`
  writes them at room realization, out of the same answer that named the thing
  (`Location::DetailSchema` gained `readable` and an optional `inscription`, and
  the realization prompt now asks for the text — measured live, four
  realizations named three readable things and supplied words for none of them
  until it did). A seed file writes them by hand: the Ward Office 12 daybook,
  Perrin's private index and the Assize tide-slate all carry real text now. And
  `Item::Inscriber` writes them **once**, on the first read of a readable thing
  that arrived with none — one structured call, one field, before any prose
  exists, and never again.

  **Reading is a branch of the loop.** `Playthrough::Classifier` gives `examine`
  a resolved target against what is lying here *plus* what is carried — the only
  action that reads both sets, because looking at a thing does not move it — and
  `Playthrough::Turn#read_item` hands the narrator the recorded words verbatim
  and quoted, the way `take` hands it the pickup. A `take` of a thing whose words
  are already on record hands them over too, because the turn that produced the
  complaint was a take; it never generates them, because picking a thing up is
  not reading it. `Playthrough::Moment#character_context` tells somebody standing
  in the room what the player was reading and what it said, out of the same
  three columns. `rake game:mechanics` prints an inscription with no model at
  all, `NO_MODEL=1` gained `read` / `examine` / `x` / `look at`, and the engine
  sweep reads a seeded note twice offline and asserts the same words both times.

  **`inscription_misquoted` is the third clause**, and it is an honest one:
  precision measured at 0 flags over all 367 real passages in the four corpora —
  92 of which quote somebody — with the captain's own narration as the positive
  case, and two plausible widenings measured and killed (`says` as a cue, 7
  flags of dialogue; the item's own name, 3 flags of dialogue). Its recall is
  **low and stated**: three live read narrations, two quoting the record inside
  quote marks, and it detected neither, because both set the quotation on its
  own after a paragraph break with no cue near it. It catches the shape that
  produced the complaint — prose announcing text as written and then writing
  different text — and nothing here pretends it catches more.

  **What it costs.** The realization call carries +138 tokens of schema
  (measured at 0 tokens of provider-reported input difference on the same room
  and prompt) and one extra sentence of prompt; a room with nothing readable in
  it pays nothing more. A read turn adds ~116 tokens of stated fact to the
  narrator prompt. The one-off inscription call, measured live on a seeded note
  with no words, cost 1,058 input and 163 output tokens — once, for the life of
  the item. Every later reading is a database read.

- **A new playthrough starts with its own hands** (`ta-inventory-per-playthrough`).
  The captain's report: he started playthrough 17 of a story and the
  protagonist was already carrying things from a previous playthrough.

  **The defect.** The party's inventory was `items.character_id` pointing at
  `story.protagonist` — **one `Character` row per story** — and
  `PlaythroughsController#create`, `rake game:mechanics` and
  `EngineSweep::Walk` all create a playthrough with that same row. So every
  play of one world shared one pair of hands, and nothing on creation emptied
  them or put the things back. Reproduced offline in two commands before
  anything was changed, and that reproduction is now
  `PlaythroughsControllerTest` → *"a new playthrough does not open holding what
  an earlier one picked up"*.

  **The fix is the position shape**, and PR 109's argument word for word: where
  the player stands is `playthroughs.current_location_id` rather than a column
  on the protagonist, because two people playing one seeded world stand in two
  rooms at once — and they carry two different sets of things. So
  `items.playthrough_id`, and an `Item` is in exactly one of **three** places:
  lying in a room (`location_id`, story-level and shared), held by one of the
  world's own people (`character_id`), or **carried by the party of one
  playthrough** (`playthrough_id`). `Playthrough#carried` is the one reader and
  `Playthrough::Turn#carry!` / `#put_down!` the only writers; `Item.in_story` is
  the one place the three-leg "every item in this world" query lives.

  **The starting inventory is world data, and it is copied rather than handed
  over.** A seed file's `characters[].items` under the protagonist is
  `Story#starting_inventory`: held by the protagonist row, carried by nobody,
  exported by the exporter, and given to each new playthrough as its own copy
  (`Playthrough#take_up_the_starting_inventory`, an `after_create` so all three
  creators of a playthrough agree). Position needs no copy because a `Location`
  holds two parties at once; an `Item` does not, so handing the daybook over by
  reference would leave the second player empty-handed. Only
  `WorldSeed::Loader` ever writes a protagonist item — `rake game:new` gives a
  generated protagonist none — so a generated world's starting inventory is
  legitimately empty, which is why the captain's playthrough 17 of *The Lunar
  Cartographer* now opens with nothing at all.

  **The backfill, run against a copy of the captain's real database.**
  `rake game:backfill_inventory` (`Item::InventoryBackfill`) attributes what is
  still on a protagonist out of the takes recorded on `scenes.resolved_action` /
  `scenes.acted_on`, with four outcomes told apart: **attributed** (6 items),
  **the starting kit** (3, left on the protagonist and copied into the 7
  playthroughs owed one), **ambiguous** (two playthroughs' takes at one story
  moment — nothing written, named in the output) and **unrecoverable** (put
  down where the last party that could have held it stands, on
  `Playthrough::Turn#drop_item`'s own rule, and stated every time). It took the
  captain's three stories from 6 shared-inventory findings to 0 and left
  playthrough 15 holding the four things its own turn log records taking.
  `rake game:doctor`'s `protagonist_holds_a_taken_item` is the `safe` finding
  `rake game:repair` acts on, one item at a time.

  **What it deliberately does not do.** Rooms stay story-level and shared, on
  the captain's explicit ruling that he is thinking about that separately — so a
  room one party has emptied is empty for the other. That is not left as folklore:
  `lib/engine_sweep/scripts/the-unrecorded-hour-two-players.yml` asserts it, so a
  future change to it fails a test rather than surprising somebody. Items carried
  by the world's own NPCs stay on `items.character_id`, which is where they
  belong — nothing has ever read a companion's items as the player's. And no
  narrator prose rule changed, no narrator tool was added and no per-turn model
  check exists; this is engine and records only.

  **`player:` on a sweep step** is the one grammar extension, and it is what
  makes the defect regression-testable offline: a distinct name is a second
  `Playthrough` of the same loaded copy of the world. With the inventory on the
  story's protagonist row both games read the same hands, so no one-player
  script could tell a story-level inventory from a playthrough-level one.

- **Character whereabouts, and the Tide Post remembering who is chained to it**
  (`ta-character-whereabouts`). The captain's ruling was *"go with shape one"* —
  a whereabouts record of a character's own, the `Item` shape, over making the
  scene cast authoritative. `characters.location_id` is that record, and
  `Character.present_in(location)` is now the closed set `talk` resolves
  against, exactly as `Item.lying_in(location)` is the one `take` resolves
  against.

  **The defect it closes.** Who was in a room was worked out again on every
  arrival — the protagonist, anyone `is_companion`, and whoever was in the last
  scene played there that had recorded a cast — and only an arrival records one,
  so 184 of the 480 baseline turns had no record of who was present at all. A
  cast that is regenerated is a cast that forgets: arriving at **The Tide Post**
  recorded the protagonist alone, on all three runs checked, in a world whose
  whole premise is that Neb Halloran is chained to that post. It now records him,
  the arrival narration names him, `rake game:mechanics` lists him under
  `present`, and a `talk` to him resolves — while a `talk` to him from the court
  is refused with the cast that *is* there.

  **Why the protagonist does not carry one, and never will.** Where the player
  stands belongs to the playthrough (`playthroughs.current_location_id`),
  because two people playing one seeded world stand in two different rooms at
  the same time and a story-level column cannot hold both answers. The party —
  the protagonist and anyone `is_companion` — stays derived for that reason, and
  `Scene::Generator.characters_present` is the one place the party and the
  world's own people are added together.

  **Four writers, and prose is not one of them**: `characters[].location` in a
  world file, `Character::Registry` (which places somebody who is nowhere and
  **never moves somebody who is not** — that rule is the Tide Post defect
  written down), the explicit `Character#move_to!`, and
  `rake game:backfill_whereabouts` once, which refuses to guess when two rooms
  recorded somebody at the same moment. No narrator tool, no per-turn model
  check, no scan of prose for a name.

  **Nowhere on purpose is now said out loud** (`characters[].absent: true`,
  `characters.deliberately_absent`). The acceptance transcript for this item
  read *"playable, 1 warning"* on `The Unrecorded Hour` for exactly one reason:
  Perrin Lasco is nowhere because that world's premise is that he has been
  removed from it, and nothing distinguished that from the accidental nowhere
  the check exists for. All three checked-in worlds are HEALTHY now, and
  `test/lib/seeded_worlds_test.rb` keeps them that way.

  **The scene cast is kept and its direction reversed.** It is a derived
  snapshot now, written on every branch by `Playthrough::Turn#play` beside
  `typed` and `resolved_action`. Kept rather than dropped because it answers a
  different question — where somebody *was* — which a column with no history
  cannot reconstruct and which `Eval::Richness`, `still_run` and both frozen
  corpora read.

  **What it cost the prompts: nothing that matters, and it was measured.** Every
  prompt has the same shape and the same line per person; only the content of
  the list changed. Across every room of all three seeded worlds exactly one
  room's cast differs from what the old derivation produced — The Tide Post,
  gaining Neb Halloran — at **+7 tokens** on the arrival prompt (once per
  arrival), **−1** net on the per-turn classifier prompt (−5 on the cast list,
  +4 on the closed enum, because "Nobody. There is no one here to talk to." is
  longer than the line that replaced it) and **+9** on
  `Playthrough::Moment#narration_context`. Every other room: zero.

  **`character_not_present` was measured and NOT shipped**, which is the one
  deliverable that did not land and is stated rather than quietly dropped. The
  record removed the stated blocker — the records are authoritative about
  presence now — and the corpora still cannot support the check: 36 of 248
  frozen passages are judgeable, exactly ONE names somebody recorded elsewhere
  (a true positive, so there is a demonstrated positive case and no
  false-positive rate, because n = 1), and moving one seeded character one door
  turns real, correct prose — *"From somewhere below, Grenn's voice rises in a
  muffled, irritated shout"* — into a violation. `Story::Audit`'s finding 5 has
  the numbers and `Story::AuditPresenceTest` pins them. **What would settle it
  is now generatable for the first time**: presence is a record, so
  `rake eval:run` can produce runs in which people are demonstrably elsewhere.
  Meanwhile the gap is covered by the engine rather than by a check — a player
  cannot SPEAK to somebody who is not there whatever the prose says.

  **AND ROOMS ARE BORN WITH PEOPLE IN THEM, SOMETIMES** — the captain's scope
  addition, and it is built the way `ta-item-registry` built the furniture.
  `Location::DetailSchema` gains an optional, bounded `people` array (0–2, and
  the prompt makes *nobody* the ordinary answer) and `Character::Registry`
  turns the sheets into rows placed in the room it just described. Structured
  records out of the call that describes the room; **not a narrator tool call
  and not a scan of prose**, which is the standing constraint and is why this
  **supersedes `ta-narrator-memory`'s characters-by-tool-call for CREATION** —
  that item keeps the memory and cast-list half.

  *Who they are, the engine decides.* Race, age and sex are rolled per slot by
  `Character::Registry#slots` and stated in the prompt before the model answers,
  on `Character::Generator`'s rule that asking for a value the prompt just
  supplied is a decision bought twice — so one registry instance per
  realization, or the room is described around one person and written around
  another. Three bounds, each read back from the records rather than counted
  down: `MAX_PER_CALL` (2) on one answer, `MAX_PER_ROOM` (3) on the room and
  `MAX_PER_STORY` (12) on the world, the last two reported by
  `rake game:doctor`. It refuses a name a character, an item or a place already
  has, and it never moves somebody who already stands somewhere.

  **And it refuses a sheet the provider cut off**, which the first live
  realization under this schema found: `appearance` and `personality` came back
  severed mid-word at their caps — *"She is small and"*. So
  `Character::Registry::PERSON_LIMITS` is sized to a finished answer (the whole
  of how `SanitizesGeneratedText` tells truncation from a near miss) and a
  sheet that still arrives at one is dropped. A truncated field is a FAILED
  CALL everywhere else in the app; here it must not be, because the call it
  would fail is the room's own description — already saved, and the expensive
  half of the realization.

  **Cost, measured.** The realization prompt grows by exactly **+173 tokens**
  per room. On the same room of the same world the detail call came back at
  **789 output tokens with two complete people in it against 396 with `people`
  suppressed by the cap** — about 197 tokens a person, against a schema bound
  of ~400. Most rooms pay only the +173, because the prompt asks for nobody.

  **What it unlocks**, stated because it was the argument for doing it:
  `speak_to` as an arc trigger that means something, an interaction that can
  refuse to happen because the person is not in the room (regression-tested
  offline now — `rake game:sweep`, `present:`, and
  `lib/engine_sweep/scripts/the-salt-assizes-presence.yml`), and a
  `character_not_present` check the day a corpus can judge one.

- **The scripted offline engine sweep** (`ta-engine-sweep`). *"focus on the game
  engine and the classifier, with a reliable way of testing before more
  changes."* `rake game:sweep` walks stored scripts of typed lines through
  `Playthrough::Mechanics` in its no-model mode and asserts the records after
  every line: where the player stands, what leads out of there and whether it is
  written, what is lying here, what is carried, and what was refused. Free,
  deterministic, offline, and it runs in `bin/rails test` — so the half of the
  game that `rake eval:run` cannot see, and that nobody was testing without
  sitting at a keyboard, is now regression-tested on every build. 60 typed lines
  over six scripts and the three seeded worlds.

  **Three things make it repeatable, and one of them is a guard rather than an
  intention.** `BaseAgent.new` is replaced for the length of a run, so a model
  call from anywhere in the engine raises `EngineSweep::ModelCalled` instead of
  reaching a provider. Each script loads its own copy of the seeded world under a
  title of the sweep's own, inside a transaction that is rolled back — a sweep
  run against a half-played database changes neither it nor the game. And the
  world does not move underneath it: `WorldMechanic` runs on `Story#clock`, the
  clock only advances when a Scene is written, and an offline move writes none,
  so The Lunar Cartographer's nightly shuffle never comes due **without anything
  being switched off** to achieve that.

  **Four invariants are checked over the whole world after every walk**, because
  that is the shape the generator defects had: nobody typed a line that gave The
  Supply Closet a second door. No door opened or closed, no room over
  `Location::ExitsSchema::MAX_EXITS` ways out, every item in exactly one place,
  no room written.

  **What it cannot see is written down rather than left to be found.** With the
  classifier off, a defect in how a *model* read a line is out of reach:
  `lib/engine_sweep/scripts/regressions-2026-09-03.yml` walks the evening that
  produced the five engine defects and says, defect by defect, which two the walk
  catches, which two the invariants hold, and which one stays pinned by
  `Playthrough::ClassifierTest` alone.

  **Two matching defects fixed in the offline grammar on the way in.**
  `Playthrough::Mechanics#resolve` matched one way round only, so `drop the
  tide-slate` was refused underneath a refusal listing "Assize tide-slate" and
  `go to the Tide Post` was refused while offering "The Tide Post". A leading
  article or preposition is now dropped and a fragment is read in both
  directions — the second one on word boundaries, so a "key" is not found inside
  "monkey". Reverting the fix turns every script in the sweep red, which is what
  a script written the way a person types is worth.

- **The item registry** (`ta-item-registry`). How items come to *exist*, which
  was the last part of the possession mechanic still missing: `take` and `drop`
  have been app-owned state changes since step 2, but `Item` rows were created
  in exactly one place in the whole codebase — the seed loader — so a generated
  room was always empty and the mechanic was exercisable only in rooms a person
  had hand-written.

  **Items are born as structured records at the moment a room is realized,
  exactly the way exits are.** `Location::DetailSchema` asks for at most three
  portable things lying here alongside the description and lore, on the SAME
  call, and `Item::Registry` writes the rows. A realization still costs two
  model calls; nothing per turn was added.

  **This deviates on purpose from the direction plan's "populated when the
  narrator names something"** (§12). A narrator tool call, or a scan of
  narration prose, makes the record depend on a model complying with a prompt —
  the thing the captain has said he will not build mechanics on. The plan's real
  intent survives whole: nothing is generated ahead of time, a stub costs nothing
  until somebody walks into it, and the ontology stays bounded. Only the
  compliance dependency is dropped. `Playthrough::Moment` then *tells* the
  narrator what is lying here, out of the records.

  **The engine decides what exists.** `Item::Registry` refuses a name anything
  in the story already has, a name a person or a place has (two of the
  classifier's closed sets would answer to one word), and anything past
  `MAX_PER_ROOM` (3, on the **room** and read from the records, so a seeded room
  can already be at it) or `MAX_PER_STORY` (60, the ceiling on the ontology —
  three per room is three per room times however far the player walked). A
  refusal costs the room its furniture and never its description.

  Items are created **whole, not stubbed**: an item is a name and one line
  riding on a call already being made, so deferring it would save ~15 output
  tokens now and cost a whole round trip the first time somebody examined it.
  `Location`'s two-state shape is the model to copy if an item ever grows a
  field worth a call of its own.

  Nothing downstream changed. `Item.lying_in` is the closed set the classifier
  already resolves `take` against, so a generated thing is takeable on the next
  turn in the browser and in `rake game:mechanics` alike.
  `Playthrough::Moment#narration_context` gained the floor list — the one closed
  set the classifier computed every turn and the prose was never told about (PR
  98, F3). `rake game:doctor` reports the states the registry refuses but an
  older world can still be in: items nowhere, duplicate names, rooms and worlds
  over the caps, and an item named after a person or a place.

- **The automated half of the evaluation loop** (`ta-eval-pipeline`). *"I'm fine
  with the loop being manual initially. I just want more confidence that changes
  we are making are improving results."* `rake eval:run` generates runs across
  **three** seeded worlds through the app's own turn loop, keeps every row each
  turn wrote, scores them with `Story::Audit`, and prints a board. One command,
  offline scoring, and the generated corpus is what makes three previously
  dormant checks answerable at all — a frozen file of loose passages cannot be
  checked against records it does not carry.

  **THE HEADLINE IS THE NOISE FLOOR, and it is bad news reported as news.** 24
  runs of unchanged code over three worlds, twenty turns each: one configuration
  produced **1 to 13** `third_person_protagonist` flags on the same twenty turns
  of the same world (rate 0.050–0.650, median 0.475). That spread is wider than
  nearly any improvement anybody would claim, so a board that printed a count
  without it would invite exactly the false confidence the loop exists to
  prevent. **More turns did not reliably narrow it**: the same extension more
  than halved one tuning world's band (0.455 wide to 0.200) and widened the
  other's (to 0.600).
  `Eval::Noise` therefore reports min/median/max per check and
  `rake eval:compare` gives a verdict — REAL, NOISE or INCONCLUSIVE — from a
  two-sided exact rank test at p ≤ 0.05. **Four runs a side is the floor and it
  is arithmetic:** at three a side the smallest attainable p is 0.100, so no
  verdict is reachable however clean the separation. `rake eval:null` splits one
  set in half and checks the protocol cannot invent a difference; it passes.

  **The known bugs are visible and counted.** `ta-narration-third-person` fires
  159 times in 320 tuning turns (49.7%) — the arrival narrations put the player
  in the doorway watching themselves arrive. `ta-narrator-invents-exit` is caught
  by three checks, one of them new: `unrecorded_departure` (a door closing at the
  back of a player who never moved), `item_not_held` (fixed below, and it catches
  his *"losing the location of the ledger when it is put down and picked up"*
  on real transcripts), and `unrecorded_arrival` — new, the same defect from the
  front, where the prose names the room it walked the player into.

  **Two faults in `item_not_held` found by pointing it at 132 whole-run
  narrations and watching it flag nothing.** (1) `Item#name` is "Ward Office 12
  daybook" and every narration writes "daybook", so the check was live and
  permanently silent — head-noun aliases fix it, and they also add three signed
  true positives to `Story::AuditPrecisionTest` (8 → 11). (2) A bare possessive
  is ownership, not custody: "your daybook lies open on your desk" is true of a
  daybook lying on that desk. The possessive now needs the thing to be somewhere
  the player is not, which takes 8 flags on real transcripts (3 true, 5 false)
  down to 2 flags, both true, at a cost of one true positive that is pinned.

  **A richness counter-metric, reported beside the defects and never folded in.**
  The cheapest way to stop contradicting the records is to say less, so
  `Eval::Richness` counts what the prose committed to — rooms, exits, items and
  people the records know, named in the passage. Thinning all 132 real narrations
  to their first sentence drops it 46%. **Commitments per hundred words was
  measured and thrown out**: it rises when prose thins, which is backwards.
  A third finding contradicts the assumption it was commissioned under — **length
  is not commitment**: the two longest arms commit to *less* per turn than the two
  shortest.

  **A third seeded world, `The Salt Assizes`, held out by documented convention.**
  No check was measured against it; it has no mechanics, so
  `unreachable_transition` is fully live on it where the Lunar Cartographer's
  nightly shuffle makes it unjudgeable. It scores **9.4% against the tuning
  worlds' 49.7%** on the third-person bug — a world-dependence worth knowing
  about before anybody tries to fix it. At eleven turns it scored zero on 88
  turns and looked clean; twenty turns is what made it fire, which is the
  argument for the longer script standing on its own.

  Actual spend: **$0.4712 for 24 runs / 480 turns**, against a $0.63 estimate,
  and every one of those turns took the branch its script said it would.
  **Prompt caching was measured and is not the cost lever it looks like**: the
  minimum cacheable prompt is 2,048 tokens and these calls average 615, so
  eighteen real prompts replayed back to back read zero cached tokens — see
  `Eval::Cost`'s header and `script/cache_probe.rb`.
  The protocol, the verdict rule and the measurement manifest are in
  [EVALUATION.md](EVALUATION.md). **The agent skill is deliberately not built** —
  the captain's accuracy pass on these flags comes first.

- **The prose is told the moment, and the character is too.** Three prompts
  wrote about one moment and each assembled its own: the narrator knew the room
  and the last turn, the interaction narrator knew neither, the character knew
  the universe and its sheet and not which room it stood in. Meanwhile the
  classifier computed the room's exits, cast, floor and inventory every turn and
  threw them away. `Playthrough::Moment` builds it once from records:
  `#narration_context` (story, room, **ways out, who else is here, what the
  player carries**, last turn, recap) for both prose passes, and
  `#character_context` (room name, story hour, company, last turn's recap line,
  and the `inner_resolution`s on exchanges the chat no longer replays) for the
  character pass, in the user turn. A `move`/`talk`/`take`/`drop` that resolved
  to nothing now reaches the narrator as a **fact** through the `take`/`drop`
  seam (`Turn#reach_fact`) instead of as the bare command it used to walk the
  player through anyway; `examine` carries a label. The talk prompts stopped
  saying "the user" (the per-turn message and every `Interaction::Schema`
  description still did, undoing `#addressee_section`); the voice rule names one
  register per field; the interaction narrator's stale "do not recite the
  backstory" instruction (it has none) and fixed "her"/"The person" example are
  replaced by a rule confining it to the six lines and an example in the
  character's own name and pronouns (`Character#pronoun_forms`); both prose
  passes ask for the same length; the arrival cast list marks the protagonist as
  the player; the classifier asks at temperature 0. **None of this is measured
  yet** — it is facts the app already held, handed to prompts that lacked them
  — and the bench that would measure it is the next item in *Next up*.
- **The evaluation loop** (`ta-eval-loop`). *"It feels like we are flailing
  around a bit right now without being able to measurably improve the
  experience. Having me review everything manually is too slow and I start
  losing focus from reading variations on the same thing too many times."* The
  answer is not a prose score — this project has killed two prose heuristics on
  measurement already, and `data/ta-model-bench/report.md` §9 refuses to score
  prose on purpose. It is **the errors he actually named, each of them
  objectively checkable**, turned into a rate that moves.

  `Story::Audit` gains four checks and two categories: `truncated_prose` and
  `third_person_protagonist` (DEFECTS — one passage wrong on its own terms),
  `unrecorded_departure` (a CONTRADICTION: prose closes a door behind a player
  the records never moved) and `still_run` (PACING, explicitly *not* a defect:
  four turns of nothing with somebody in the room). `Story::Scoreboard`
  (`rake game:score`) runs them over a corpus and prints a rate per check, the
  movement since `db/eval_baseline.json`, the agreement with his own verdicts,
  and **every flag with the turn, what he typed and the passage** — so his
  attention goes only to what a check caught. Offline, free, 0.6 s for both
  corpora.

  **Measured before shipped, on the `BaseAgent::Refusal` precedent.** 92 real
  passages — every stored `Scene` description and `Interaction` action from the
  two worlds played, plus the 24 lab narrations — raise **19 flags, all true
  positives, zero false positives**, and **not one of the 24 lab narrations is
  flagged**. The three turns he judged are caught by three different checks:
  scene 59 `truncated_prose` (*"truncated"*), 63 `still_run` (*"this has stretch
  on too long… Why is Halkett not doing anything?"*), 64 `unrecorded_departure`
  (*"the narration says a door clicked behind me but I'm still in the Ward Office
  12"*). `Story::Scoreboard::CorpusTest` pins all of it, including the two real
  sentences that broke earlier versions of the rules.

  **The agreement with his labels is reported as unestablished, not dressed up.**
  Three verdicts is not a correlation; below `MIN_VERDICTS` the report says so in
  words and shows counts, and the figure recomputes as he labels more. It also
  names every turn he marked weak or bad that no check caught — which is where
  the next check comes from, and today that list is empty.

  **What it cannot measure**, stated rather than left to be discovered: whether
  the prose is any good; the invention of things that do not exist (that is
  `Playthrough::Drift`, by consequence); a `take` or `drop` turn, which moves a
  row but leaves nothing dated on the turn, so it reads as still; and, for the
  third-person check, an apposition with no pronoun and no possessive ("a figure
  — Isbet Marrow — watches you"), which needs a part-of-speech tagger. One miss
  in ten real violations, and the trade is the one this project takes everywhere.

- **The conversation audit trail is kept, not pruned** (`ta-keep-history`).
  `Chat::KEEP_TURNS` defaulted to 25 turns, so `Playthrough#prune_conversations!`
  destroyed every older turn's prompts, answers, token counts and models at the
  end of every turn. The argument for it — a SQLite file on a laptop, three or
  four chats a turn, an arrival prompt that inlines the universe, the audit
  trail as the biggest thing a long game accumulates — was true in every clause
  and never checked against a number. Measured over 500 real turns driven
  through the loop: 6 messages a turn, ~520 bytes of content each, **4.16 KB a
  turn on disk** — 0.41 MB per 100 turns, 4.1 MB per 1,000 — against the
  **912 KB `models` registry that ships with the app**. The trail being the
  largest thing the *game* writes is a statement about how little else it
  writes, not about the trail being large.

  The default is now nil, meaning keep everything, and `TA_CHAT_KEEP_TURNS`
  survives as an **opt-in** cap for anyone who wants a bounded file — the
  pruning path is kept for it rather than deleted. Growth was checked and not
  assumed: `Playthrough::Debug#preload` batches a playthrough's messages, so at
  500 turns the debug page issues an **identical** number of queries capped or
  uncapped (507 either way, one per scene from the `scene_chain` walk, which is
  linear in turns and unaffected by retention) and assembles in 278 ms. What
  this buys is the point — a flagged turn stays fully inspectable however long
  ago it was played, which is the evaluation record `Playthrough::Feedback`
  exists to build. Its frozen provenance stays correct and is now belt and
  braces. Two stale bullets in the debug page's *what is not recorded* panel
  went with it: the retention ceiling, and a claim that a `Scene` has no column
  for what the player typed when `scenes.typed` has existed since
  `ta-api-iface`'s migration landed.

- **A truncated character sheet rotates like any other failed call, and a
  failed turn shows the app's own copy.** Two fixes on the talk path. (1)
  `InteractionAgent#ask` called `#reaction_fields` — where a field that arrived
  at exactly its cap raises `SanitizesGeneratedText::TruncatedTextError` — on
  the response *after* `BaseAgent#ask` had returned, so the rotation never saw
  it: a model that ignored the schema got a second try and a model that
  truncated cost the player the turn, which nobody chose. It was where the raise
  happened. `BaseAgent#ask` takes a `verify:` check now and runs it inside the
  attempt loop, so the caller keeps the check (the caps are the schema's
  business, not `BaseAgent`'s) while the raise is a failed call that rewinds the
  attempt out of the character's durable conversation and asks the next model.
  Measured firing rate before the fix, on plain minimax: 15 of 16 attempted
  narrations, 1 of 18 turns completed at either reasoning setting
  (`data/ta-conversation-read/report.md` §4) — and the captain had that model
  pinned in his own `.envrc`. (2) `NarrationJob`'s general rescue passed
  `e.message` to the page, so the `.alert` read *"generated text arrived at its
  320-character cap…"* and quoted the fragment the app had just decided not to
  keep. It renders `Playthrough::TurnFailureNotice` instead, one line in the
  app's own voice; `Rails.logger.error` still has the class and the message in
  full. Also corrected the "accepted cost" note on `REMOTE_MODEL_IDS`: the 602
  it cited as minimax's interaction-path length was measured before this guard
  existed, over a five-field schema with a 200-character `pre_thought`, and 30
  of minimax's 39 character sheets in that sweep carried a field cut off
  mid-word at exactly 200. It is not a length minimax delivers.

- **`mistralai/mistral-medium-3.1` is the default hosted model**, with
  `minimax/minimax-m3` second. The captain's ruling on recommendation 2 of the
  refusal sweep: mistral refused 0 of 52 charged cases against minimax's 8 of 51
  (16%), is 3–4× faster (median 2.4s against 8.8s), and dropped no required
  `Interaction::Schema` field where minimax dropped them on 29% of talk turns.
  The accepted cost is thinner prose — about 60% of minimax's length narrating.
  (The interaction-path figure this entry used to quote is withdrawn; see the
  truncation entry above.) The order also costs the safety
  net: a `RefusalError` rotation now falls to minimax, the model that refuses,
  rather than to a model known to comply. Stated on the constant, not buried.

- **A verdict on any turn, recorded while playing** (`ta-turn-feedback`). Three
  buttons under each turn in the log, one click each, with an optional note once
  a verdict is there; amendable and clearable; a Turbo Stream replacing that one
  turn's footer, so nothing reloads and a turn in flight is untouched. Gated on
  `Playthrough::Debug.enabled?` — local by default — because it is the captain's
  instrument, not a feature for whoever was handed a playthrough link.

  **The provenance is FROZEN onto the row, and that is the whole design.**
  `Chat#answering_model_ids` knows which model answered, including after a
  rotation past one that failed, but `Playthrough#prune_conversations!` destroys
  the one-shot conversations whenever `TA_CHAT_KEEP_TURNS` sets a cap — so on an
  install that opts into a bounded file a reference would resolve to nothing on
  exactly the turns worth comparing. The default keeps them (`ta-keep-history`),
  which makes the copy belt and braces rather than unnecessary. `.record`
  copies the model that wrote the prose, the whole prose attempt chain, the
  purpose it was writing as, every model that answered the turn and the token
  counts, once, on create; amending a verdict never re-snapshots. The `Scene` is
  referenced rather than copied: its prose, its `typed` and its story time are
  never pruned, and a copy would be a second answer that could disagree.
  `Playthrough::FeedbackTest` proves the survival directly — record, prune,
  assert the provenance is still there and still correct.

  Read back in the debug view: verdict against frozen prose model as a
  cross-tab, and every verdict beside the turn, the words typed, the prose and
  the provenance. Counts only — what they prove is `ta-narrator-model` and
  `ta-talk-model`, and this is the instrument rather than the conclusion.
- **A character speaks in the first person and knows who it is talking to.**
  `Character#interaction_instructions` used to say "Refer to yourself in third
  person only" with no scope, two lines under the sentence establishing that
  quoted text is speech, and it named the player nowhere at all. Measured over
  30 real talk turns per arm per model: characters named themselves aloud on
  `google/gemini-2.5-flash` (4 of 27 spoken turns, 2 reaching the player) and on
  `mistralai/mistral-medium-3.1` (1 of 27), and invented a stand-in for the
  player — "the user", "the speaker", "the interlocutor" — on 13 of 30 mistral
  passes and 23 of 30 minimax. After: 0 self-naming on either model, 0 invented
  stand-ins, and the protagonist named on 11–28 of 30. The rule is now scoped to
  the register outside the quotes, and `Character#addressee_section` passes what
  meeting somebody tells you and withholds the protagonist's `backstory`,
  `personality`, `likes`, `dislikes` and `fears`.

- Rails 8 app, SQLite, 1,040 tests green. No longer API-only: `api_only` is off
  and `ApplicationController < ActionController::Base` so it can render ERB.
- Full schema: `Universe` → `Story` → `Location` / `Character` / `Scene` /
  `Interaction` / `Item`, plus the `location_connections` graph and the
  `world_mechanics` / `world_events` pair that moves it.
- `Universe::Generator`, `Story::Generator` — bootstrap a world from a premise.
- `Character::Generator` — one call, one `Character::Schema`. Race, age and sex
  are decided by the generator and stated in the prompt, not asked for: race
  comes from the universe's list so a character belongs to one of its peoples,
  age and sex are rolled so repeated runs diverge. A full name is unique within
  a story (validation plus a unique index on `story_id, LOWER(fullname)`), and
  the generator retries on the same conversation when the model reuses one.
- `Playthrough` model — a session's position in a story (protagonist,
  `current_location`, `current_scene`, session `token`), plus `is_protagonist`
  on `Character`. The browser interface reads and writes it.
- `Race` model — `Universe has_many :races`, `Character belongs_to :race`, with a
  validation that a character's race comes from its own story's universe.
- Explicit bounds on every schema field: a `max_length` plus a stated sentence
  count, or an enum where the value comes from a fixed table. Without them a
  strong model answered "Race of the character" with 2,382 characters of prose;
  the whole character sheet is now ~2,530 characters.
- **Audience-specific universe context.** `Universe#prompt_details(audience)`
  sends each caller the fields it can use — `:full` for story generation
  (1,584 tok), `:character` (1,238), `:place` for building a room (628),
  `:dialogue` for a character speaking (606), `:scene` for arriving in a room
  already built (285). The whole record used to go to all of them.
  `:dialogue` was 930 until the race list came out of it: the speaker's own
  race sits in the character sheet directly below, and that block is re-sent on
  every turn of every conversation. It took a whole talk turn from 2,431 input
  tokens across three calls to 2,107.
- **`LocationConnection` distances and travel methods come from fixed tables**
  (`DISTANCES`, `TRAVEL_METHODS`), and `time_to_travel` is derived from the two
  rather than generated. The values are direction-neutral because connections
  are written both ways from one answer.
- `BaseAgent` — RubyLLM wrapper with model fallback on failure. A rejected key
  is the one failure it does NOT rotate past: it raises
  `BaseAgent::UnauthorizedProviderError` naming the environment variable,
  because rotating a 401 down to the local models answered from ollama with
  nothing saying the remote call had been refused.
- `rake game:new[premise]` / `rake game:list` — generate and inspect worlds.
  `game:new` now also generates and realizes the story's opening location.
- `InteractionAgent` — two-pass character-then-narrator dialogue.
- `ruby_llm` 1.16 + `ruby_llm-schema` 0.4, on RubyLLM's association-based
  `acts_as` API. The `models` table is the model registry now; seed it with
  `bin/rails db:seed`, or nothing resolves.
- AI-layer test coverage: `InteractionAgent`, the three schema
  classes, and `Chat` / `Message` / `ToolCall` / `Model`, all stubbed at the
  RubyLLM boundary.
- **Location stubs and on-demand realization.** `Location#detail_level` is
  `stub` or `realized`; `description` and `lore` are required only once a
  location is realized, so a stub is a name plus a one-line `teaser` and
  nothing more. `Location::Generator#realize!` writes the description and lore,
  then creates a stub `Location` for each exit plus the `location_connections`
  rows — in **both** directions, so the way back exists before the far side is
  ever realized. It returns an already-realized location untouched: generation
  happens once per place, never twice. `Location::Generator.opening(story)`
  names the first location from the story's preface and realizes it.
  `Location#exits` is the exit list the game loop will resolve movement against.
- **A browser you can play in.** `bin/dev`, open `localhost:3000`, pick a story,
  start a playthrough, read the preface, type an action and watch the narration
  arrive; reload and the log is still there. Deliberately ugly and deliberately
  small: two routes, five ERB templates, an inline `<style>`, and one Stimulus
  controller.
- **Jobs, Turbo Streams over Action Cable, and durability.** A turn is a
  `NarrationJob`, not a request. `TurnsController#create` enqueues it and
  answers immediately with the command echoed back; the job broadcasts prose in
  ~20-character batches into `#stream` and then replaces the whole `#turn_log`
  with the finished turn, the location line and the input. Four things that
  fixes: **the reload at the end of every turn** is gone, and with it the scroll
  position it threw away; **one Puma thread per open stream** is gone, because
  WebSockets do not consume request threads; and **a turn no longer dies with
  its connection** — close the tab mid-narration and it lands anyway, and is
  broadcast to whoever reopens the page. `propshaft` + `importmap-rails` +
  `turbo-rails` and still **zero build**: no Node, no `package.json`, no watch
  process. Solid Queue and Solid Cable both run in development, each against its
  own SQLite database — `async` cable would broadcast the turn into the worker
  process and nobody would ever see it.
- **`bin/dev` starts the whole development environment.** `Procfile.dev` with a
  `web` and a `jobs` line under foreman, both logs interleaved, Ctrl-C stopping
  both. Foreman is deliberately outside the Gemfile and installed on demand, the
  way Rails' own generated `bin/dev` does it: a process runner, not a build step.
  `PORT=3142 bin/dev` moves the formation off 3000.
- **One Stimulus controller**, `play_controller`, scoped to a wrapper that no
  Turbo Stream replaces — the log's own `#turn_log` is replaced every turn, and
  the controller's whole job is to hook that replacement. It follows the
  narration down while the player is at the foot of the log and puts focus back
  in the input when a turn lands. Three of its properties were established in a
  browser rather than by a test and are commented as such.
- `Scene::Narrator` — one unschema'd `BaseAgent` call that streams prose to a
  block and persists the finished text as a `Scene` in an `ensure`. It takes a
  block precisely so swapping SSE for Turbo Streams touched nothing but the
  consumer, and that is exactly how the swap went: `NarrationJob` replaced the
  SSE controller and not one line of this class moved.
- `BaseAgent#ask` forwards a block to RubyLLM, which turns the call into a
  token stream.
- **`Scene::Generator`** — narrating arrival in a location, as one schema'd
  `BaseAgent` call (`Scene::Schema`: `description` + `summary`). It is the
  sibling of `Scene::Narrator`, not a copy of it: the narrator answers what the
  player *typed* and streams unschema'd, this writes the record of walking
  *into* a place and stays schema'd like everything else. Arrival reads as
  discovery or as coming back depending on `Location#last_protagonist_visit`,
  with the gap stated in words. `scene.characters` is decided from records —
  the protagonist, anyone `is_companion`, and whoever was in the last scene
  played in that location — never asked of the model. Measured against a real
  generated world: **1,302 input / ~200 output tokens** per arrival
  (system 67 + prompt 1,127 + schema 108), which is the whole cost of walking
  back into a room that already exists, and +37% input on top of realizing a
  new one. The per-turn path is untouched. It writes `scenes.summary`, which
  nothing had ever written.
- **Two playable worlds in the repo.** `bin/rails db:seed` loads every YAML file
  in `db/seeds/worlds` — offline, idempotent, matched on natural keys — so a
  fresh clone can be played immediately without minutes of live generation or an
  API key. `rake 'game:export[story_id]'` dumps a generated world into that
  format, which is what keeps the files from rotting at the first schema change;
  the files are authored artifacts after that and are meant to be hand-edited.
  `the-unrecorded-hour.yml` is shaped on purpose: its opening office has two
  ways out, one of them a *realized* supply closet whose only exit is back into
  the office. That is the dead end `Location::Generator` cannot produce on its
  own, since it leaves every neighbour a stub and a stub has no exits at all.
  See `db/seeds/worlds/README.md` for the format and
  `test/lib/seeded_worlds_test.rb` for the drift guard.
- **A world carries its own opening arrival.** `rake game:new` narrates it once
  with `Scene::Generator.opening`, the exporter writes it into the seed file as
  `opening_scene`, and the loader loads it — so starting a playthrough makes no
  model call at all and the first thing a new player reads is real narrated
  prose rather than the room's own description standing in for it. It is the
  ONE `Scene` that is world rather than progress, and the exporter and
  `db/seeds/worlds/README.md` both say why at length: nobody made it happen, it
  is identical for everyone who plays, and it is the answer to a question the
  world is supposed to know. `scenes.is_opening` is the marker and the loader's
  natural key both (a `Scene` has none of its own); the seed format is at 2.
  Three things fall out of it:
  * **A seeded world has somebody to talk to on turn one.** The cast is
    hand-authored in the file, `Scene::Generator.characters_present` reads the
    last scene that recorded anyone, so the `talk` branch is reachable in both
    checked-in worlds for the first time. Grenn is in the doorway of Room 3;
    Sub-Inspector Rowe is in the doorway of Ward Office 12, forty minutes early.
  * **An opening `Scene` deliberately does not stamp `last_protagonist_visit`.**
    It is created when the world is BUILT, which can be months before anybody
    plays; stamping then would narrate the first walk back into the opening room
    as a return after however long the file had been on disk.
    `PlaythroughsController#create` stamps it when a player actually arrives,
    which is why the explicit `mark_protagonist_visit!` #73 dropped is back.
  * **`Scene#next_scene` is now `#next_scenes`.** Every playthrough of a story
    starts on the same opening `Scene`, so the forward direction is a genuine
    branch point and a `has_one` over it was a wrong answer dressed as a right
    one. Walking backwards from `current_scene` was never affected, so the turn
    log did not move.
- **The game loop.** `Playthrough::Turn` is the whole of it: one schema'd
  classification call (`Playthrough::Classifier`, five intents from a fixed
  table plus a target enum built per turn from the room's exits and its cast),
  then move / talk / narrate. **Movement is the load-or-generate seam:**
  `Location::Generator#realize!` writes a stub out in full and returns an
  already-realized room untouched, so walking somewhere new generates it once
  and walking back reads what was written, then `Scene::Generator` narrates
  arriving and the playthrough moves only once both calls have landed. Wired
  into the browser through two routes: `NarrationJob` hands the command to
  `Playthrough::Turn` and broadcasts the chunks it yields.
  Movement costs ~415 input tokens for the classification (system 189 + prompt
  66 + schema 160) on top of whatever it leads to -- an arrival is 1,302, a
  narrated turn ~849 -- so the classifier is about a third of a narrated turn
  and a quarter of an arrival.
- **Talking to a character, kept.** The `talk` branch routes to
  `InteractionAgent`, which now goes through `BaseAgent` on both passes -- so
  the character pass inherits `verify_schema_honored!` and both inherit model
  fallback, and the unresolvable
  `cognitivecomputations/dolphin-mixtral-8x22b` it used to hardcode is gone.
  `#ask` returns an `Exchange` of the prose and the character's five structured
  fields instead of throwing the structured half away, so a talk turn keeps
  **two** records: the `Scene` the player reads (with `scene.characters` set to
  the protagonist and whoever they spoke to, which is what tells the next turn
  in that room who is standing in it), and the first `Interaction` row this app
  has ever written. The turn log names who was spoken to.

- **`.env` loads.** `dotenv` was in `Gemfile.lock` only transitively via kamal,
  so a key placed in `.env` was silently ignored by `bin/rails` and `rake`, and
  the docs pointed only at `.envrc`. `dotenv-rails` is a direct dependency now;
  both files work.
- **A conversation's structured fields are sanitized, and a truncated one
  fails the turn.** The talk path was the one generated-string path in the app
  that never crossed `sanitize_string`, so the guard below covered every field
  the app writes except the six a conversation writes every turn. Found by
  reading the debug view against a real conversation: one stored `pre_feeling`
  was exactly its 60-character cap ending `"hopeful for a (v"`, its
  `pre_thought` exactly the 200-character cap, another `pre_thought` ending
  `"so as not to r"` — and the narrator pass, handed the fragment by string
  key, wrote fluent prose over it, so the player could not tell. Two fixes:
  `Interaction::Schema`'s caps are now headroom over the shape asked for rather
  than the shape itself (a sentence 320, two sentences 480, three
  comma-separated words 120, each stated in the field's own description), and
  `InteractionAgent#reaction_fields` — the one seam the narrator prompt and the
  `Interaction` row share — sanitizes every field against its own cap. Arriving
  AT the cap now raises `SanitizesGeneratedText::TruncatedTextError` rather than
  being written: with caps this wide a finished answer lands nowhere near the
  ceiling, so landing on it means the provider cut the answer off. It is caught
  before the narrator pass runs, so no prose is ever paid for or read over a
  fragment. The scene's own prose is untouched, for the same reason
  `Scene::Narrator`'s is: it is unschema'd streaming text, so there is no cap
  for it to be cut at.
- **Generated text is guarded against `max_length` truncation.** A response cut
  at a schema boundary leaves the JSON envelope inside the value — a `summary`
  came back at exactly its 200-character cap ending in a smart quote and a
  closing brace, persisted as narrative content. `SanitizesGeneratedText` now
  strips a trailing run of quote/brace/bracket punctuation, and because it is
  the one seam every generated string crosses, that covers every schema in the
  app rather than the field it was first seen on.
- **The dead `Narrator` is gone.** `app/models/narrator.rb` predated the schema,
  read no database record at all, described `get_scene_details` /
  `get_universe_rules` tools that were never implemented, and named a model id
  that does not resolve — so `Narrator.new` raised. It went with
  `rake narrator:interact` and its test. `Scene::Narrator`, the live narration
  path, is unrelated and untouched. The stale `CLAUDE.md` sections that
  described it as the primary AI interaction class and the main development
  interface are corrected.
- **The world moves on its own clock.** The first slice of the rules-engine
  direction, and the purest expression of the standing constraint above: no
  model is involved anywhere in it. `Story#clock` is what time it is in the
  fiction, derived from `scenes.story_timestamp` rather than stored, and every
  `Scene` now costs story time — an arrival pays
  `LocationConnection.travel_minutes` for the edge actually walked, every other
  turn pays `Scene::TURN_MINUTES`. `Time.current` is gone from that whole path.
  `WorldMechanic` is a fixed catalogue of Ruby operations over records on a
  story-time schedule: `kind` and `cadence` are keys into tables in code, so a
  world supplies parameters and never behaviour, and `last_run_at` is a column
  in story time so catching up is arithmetic — no timer, no job, nothing in
  memory, and a process that was down for a week pays the nights it owes on the
  next turn. `Story#catch_up_world!` runs first thing in `Playthrough::Turn#play`
  at ~90 µs and **0 tokens** when nothing is due. The one `kind` is
  `WorldMechanic::ShuffleConnections`, which permutes rather than chooses so
  every location keeps its degree, checks connectivity and that the induced
  adjacency actually changed before applying, and is
  deterministic per (story, night); it is hand-written into
  `the-lunar-cartographer.yml`, whose universe has claimed since it was
  generated that Nocturnis rearranges itself nightly. `WorldEvent` is the audit
  trail and deliberately **not** a narration source — over two nights a shuffle
  can return a place to the same neighbour, so replaying the log would announce
  a change the player never experienced.
- **The story doctor** — `rake game:doctor`, `rake game:repair`,
  `rake game:delete`. A world outlives the schema that generated it, so a story
  written in August sits next to one written in September and the difference
  only shows up as a stack trace mid-turn. `Story::Doctor` asks the questions
  the play path asks, ahead of it, and answers in sentences a person can act on;
  `Story::Repair` fixes only what is derivable from records, keeps model-call
  repairs behind `GENERATE=1`, and **never invents data to make a validation
  pass**; `Story::Deletion` prints what will go, requires the story's own title
  back before it goes, and takes the universe only when no other story is built
  on it. See `AGENTS.md` → *When a world outlives the schema*.
- **The debug view** (`ta-debug-view`, PR #81). One page per playthrough
  showing what the game decided and generated behind the prose, organised
  around the turn just taken: the branch it took **derived from the records
  that branch left behind** and the evidence for it, the story-time cost
  checked against the fixed tables that were supposed to decide it, the scene
  and the place with stub-versus-realized called out, the exits in both
  directions, the closed set `Playthrough::Classifier` will accept next turn
  with the prompt it would build, `Story#clock` against the playthrough's own
  moment, every mechanic with when it fires next, the `WorldEvent` audit trail,
  and the durable background behind `<details>`. Its own route, controller and
  layout, so it shares no CSS with the game and cannot change how the story
  reads. Gated in the controller on `Playthrough::Debug.enabled?` — local by
  default, `TA_DEBUG_VIEW` overrides — because this app has no auth and a
  playthrough URL is the whole of a player's credentials. **Read, never write,
  asserted rather than intended:** both tests snapshot every table's row count
  and newest `updated_at` across a full read. It deliberately does not call
  `catch_up_world!`; a mechanic with nights owed is reported, not run.
  Built over existing records only, at the time — and `ta-chat-persist` has
  since given it the capture it was waiting for.
- **Conversations are kept** (`ta-chat-persist`). Every `BaseAgent` writes a
  `Chat` and its `Message`s: the prompt, the answer, the token counts and the
  model that actually replied. One chat per agent conversation, because a chat's
  messages have to be a list you could send again; which TURN a message belongs
  to is on the message, because one conversation spans many turns. Three things
  come out of it:
  - **The debug view stopped naming an absence.** Per-turn cost, per-playthrough
    cost, the answering model — and a rotation past a failed model is visible as
    two models on one turn.
  - **One conversation is picked up rather than started fresh:** talking to
    somebody, keyed `(playthrough, character)`. A character remembers what you
    said last turn, across a server restart. It is bounded to
    `Chat::HISTORY_EXCHANGES` because `Character#interaction_instructions`
    inlines the whole universe (4,705 characters) and the local models run in a
    4,096-token window; what falls off the chat is on `Interaction`, in full,
    forever.
  - **`Playthrough#recap`** deepens the narrator's memory from one turn to
    several, by spending the summaries every arrival already writes. Measured on
    `gemma3:12b`: +70 to +91 input tokens on the narration call, ~7% of a turn,
    against 2,264 characters of prose it replaces with 343.
  Bounded where the context window demands it and *not* where it does not: the
  replay ceiling and the recap budget are arithmetic against a 4,096-token
  window, whereas the one-shot audit trail is now kept in full by default
  (`ta-keep-history`) because 4 KB a turn never justified the ceiling it had.
- **Auditing the difference — `rake game:audit`, `Playthrough::Drift`, and
  app-owned `take` / `drop`** (step 2 of `data/ta-direction/report.md` §11).
  The third clause of the standing constraint, and the biggest single reduction
  in what there is to drift about, shipped together so the instrument's first
  reading is taken against the world we actually intend to have.
  - **`Story::Audit`** walks stored `Scene`s and reports where the prose and the
    records disagree. Offline, deterministic, no model call, no network,
    ~20 ms per scene, so it can be run over every scene ever written.
    **Contradictions** (a transition the graph forbids; the player told they
    carry something the records give to somebody else) are counted separately
    from **drift**, because one is proved and the other only witnessed. A check
    that cannot be run honestly is reported as *unjudged* rather than guessed at.
  - **PRECISION OVER RECALL, and it was measured rather than asserted.** The
    scout's spike raised 4 flags on 24 real narrations and all four were false
    positives, because a mention is not a claim: prose refers to places through
    windows and people in memory. So the vocabulary check is gone, and so is the
    person check the report expected to keep — every quotation in the corpus is
    attributed by pronoun, so a name-based speaker check would never have fired
    at all. What remains reads prose in exactly one place, possession, and only
    in the grammar of a claim about the player.
    `test/fixtures/files/narration_corpus.json` checks those 24 narrations in and
    `Story::AuditPrecisionTest` pins the flags they earn: **8 flags, 8 true
    positives, 0 false positives**, against 15 narrations that name one of the
    items. About half the real possession claims are missed, on purpose.
  - **`Playthrough::Drift`** is the drift counter: one row when a `move`, `talk`,
    `take` or `drop` resolves to nothing, keeping what the player typed, what was
    on offer, and the narration they had just read. That is how an invented exit
    becomes observable — not by scanning prose for a door, which is impossible,
    but by noticing the player walk at one. Never pruned: a measurement that
    expires cannot be watched over time.
  - **`Item` is in exactly one place**, held by a character or lying in a
    location, and `take` and `drop` are both the app moving that row out of a
    closed set before any prose exists. The narrator is told what happened. Both
    directions, because an app that owns picking up while the narrator asserts
    putting down has records that go stale the first time a player sets
    something down. This is what unblocks the arc's `hold_item` trigger.
  - **`Scene#typed`** is what the player typed, on every branch, written once in
    `Playthrough::Turn#play`. It replaces scraping the classifier's stored
    prompt, which the conversation pruner threw away — so older turns no longer
    lose the player's own words.
  - The debug view carries both tables for the playthrough being looked at.

- **A refusal is a failed call, and a crisis response is intercepted.**
  `BaseAgent` read every unschema'd response for two things it must not keep.
  A refusal — a decline, or a menu of alternatives — raises
  `BaseAgent::RefusalError` and rotates, which is what the app was missing:
  measured over 51 charged narrator prompts, `minimax/minimax-m3` refused 8
  (16%) and `mistralai/mistral-medium-3.1`, then second in
  `REMOTE_MODEL_IDS`, refused **none of them**. The app had the model it needed
  and could not reach it, because a refusal is a 200 OK. The detector is
  STRUCTURAL rather than a word list — an unquoted first-person opening, or a
  list — because a word list misses the refusals that decide things ("I'm not
  going to narrate that. Threatening to harm a child isn't something I'll
  roleplay" contains no phrase any such list carries) and fires on every
  character who says "I". Measured at recall 11/11 with **zero false
  positives** on 127 real prose responses, checked in as
  `test/fixtures/files/refusal_corpus.skeleton.json` and pinned by
  `BaseAgent::RefusalPrecisionTest` the way `Story::AuditPrecisionTest` pins the
  audit sweep. The repo is public, so the corpus ships reduced by
  `RefusalCorpusSkeleton` — every letter `x`, offsets intact, 0 mismatches
  against the raw responses. Every refusal is logged under `[refusal]`, because "the repo has
  no record of a refusal" meant nothing while nothing would have recorded one.
  A **crisis response** — a real-world suicide line, twice in 207 responses,
  both times in an NPC's mouth in a world with no telephones — is the second
  thing, and it takes the opposite path: `BaseAgent::CrisisResponseError` does
  NOT rotate, because rotating would be the app routing around a safety
  response. Captain-decided: suppress the model's version so it never becomes a
  `Scene`, and show `Playthrough::SafetyNotice` outside the fiction, in the
  app's own voice, naming no phone number it would have to guess at. The two
  checks are ordered and never merged — one response can be both.
  (`ta-refusal-range`; `data/ta-refusal-range/report.md` is the sweep.)

- **Re-seeding a played world reconciles instead of accumulating.** The loader
  added and never looked, so seeding on top of a world in progress could leave
  two of something — and the captain's own database had three shapes of it at
  once: `The Supply Closet` and `Supply Closet` in *The Unrecorded Hour* with
  the office opening onto both, two `Ward Office 12 daybook` rows in one pair of
  hands, and two anchored doorways off every mobile room in *The Lunar
  Cartographer*, which is where the phantom "Mournwell Lane now opens onto X
  instead of Y" came from. **Decided behaviour: reconcile what the file can
  prove, say out loud what it cannot, delete nothing.** A renamed row is the
  same row, on `WorldSeed.natural_key` — case, whitespace and a leading article
  are not part of a name and nothing wider, because folding two genuinely
  different rooms into one would destroy play rather than duplicate it. A
  doorway `WorldMechanic::ShuffleConnections` has moved is left where the world
  put it: which anchored place a mobile room has come to rest against is
  progress, like `last_run_at`, and the file never carried it. A rename no
  normalized name recognizes is created and **warned about** by name, because
  nothing in the file says which room it replaced. Refusing a played re-seed
  outright was rejected — it is the captain's only way to pick up a file change
  on the database he plays. `rake game:doctor` reports the shapes an older
  database already holds (`duplicate_locations`, `duplicate_items`,
  `mobile_doorway_re_asserted`), each with a `safe` fold in `rake game:repair`
  that moves what is on the row a re-seed created onto the row with the history
  and refuses a row anybody has touched — the first repairs in that class that
  remove anything. `validate!` gained PR 85's authoring note as a rule: a
  connection shuffle's edges must hang off at least two mobile rooms, or the
  world validates, plays and never moves. Walked offline by
  `lib/engine_sweep/scripts/reseed-a-played-world.yml`, which gained a
  `reseed:` step kind for it. (`ta-reseed-safety`.)

### Not built yet

Everything left is in **Next up** below. The loop moves, talks and narrates,
the world moves on its own clock underneath it, a turn runs in a job and
survives the tab closing, and every exchange it has with a model is written down
and bounded. Stage 5 of the browser plan is therefore complete. What it does not
yet do is look like anything -- stage 6, visual style.

The third clause of the standing constraint is now built: `rake game:audit`
verifies stored narration against the records, offline and deterministically,
and `take` / `drop` are state changes the app owns. What is not built is doing
anything with what the sweep finds -- a violation becoming a consequence -- and
the laws digest that would lower the violation rate in the first place.

## Next up

**The queue is authoritative, not this file.** `tasks-axi list --state queued`
in the firstmate repo is the list; each item below names its task id. The
ordering and the measured reasoning behind it are in
`data/ta-direction/report.md` §11 — 1,200 lines of argument that is
deliberately *not* copied here. §12 of the same report says what must
explicitly **not** be built, which is worth reading before proposing anything
in this area.

Steps 1 and 2 of that plan have landed (see **Done**). The rest, in order:

3. **The laws digest in the narrator prompt** (`ta-laws-digest`) — a short list
   of named one-line laws on the universe, in the one prompt that today sends
   zero universe context. ~100 input tokens, no extra round trip, and the live
   A/B halved violations on remote models. **Ship it as odds and prose quality,
   never as mechanics.** Blocked by (2).
4. **The arrival diff** (`ta-arrival-diff`) — record the exit names the player
   was actually shown on `Scene`, and diff them on arrival. ~25 tokens, and it
   is what makes the moving-buildings mechanic *felt* rather than merely true;
   a city that rearranges itself is worth nothing to a player who cannot notice
   it happened.
5. **A violation becomes a consequence** (`ta-violation-consequence`) — when
   verification catches a violation, the world responds to it in a later beat
   rather than the app quietly correcting the past. A scheduled consequence
   `WorldMechanic` applies. This is why the mechanics engine is load-bearing
   rather than merely elegant: the same engine that moves buildings bills for
   violations. Blocked by (2).

   **Sequencing note, from `data/ta-combat-scout/report.md` §8.4.** That task
   body says the consequence is *"a scheduled consequence `WorldMechanic`
   applies"*, and a `WorldMechanic` **cannot cost a player hit points** — it
   runs on the story's clock for the whole world and knows about no
   playthrough (§3.1). So either this task's consequences are world-shaped (a
   door closes, a person moves, a `WorldEvent` is written — all of which a
   mechanic can do) **or** it needs the per-turn, per-playthrough seam combat
   built: step 7 of `Playthrough::Turn#play`, where `Playthrough::Riposte` and
   `Playthrough::Hazards` already run, with `Playthrough::Turn#harm!` as the one
   writer underneath. That seam exists now. Whoever picks this up should decide
   which of the two shapes the consequence is before designing it, because they
   are different tables.
6. **The forward flag** (`ta-forward-flag`) — ~20 tokens per violation, to stop
   drift compounding between turns while (5) is being designed. A cheap holding
   measure, and named as one.
7. **The arc** (`ta-story-arc`) — quests, steps, and `Story#conclusion`. Two
   tables and four predicates the app evaluates from records: no model call per
   turn, no narrator tool calls, no plot generated up front. `reach_location`
   and `speak_to` work today, `time_passed` unblocked at (1) and `hold_item`
   unblocked at (2) — `Item#character` is now a real record the app writes — so
   all four triggers exist. The captain has already
   ruled: add `Story#conclusion`, one sentence, keep the preface open — decided,
   not to be re-litigated when this is built.
8. **The offline model-read compliance sweep** (`ta-compliance-sweep`) —
   quantifies compliance at scale by reading the stored prose with a model,
   which is why it can only ever run offline. A per-turn plausibility call is
   ruled out in both directions: 257–289 input tokens *and* a 2.4–7.3 s round
   trip, to answer "allowed" nearly every time.
9. **The item registry** (`ta-item-registry`) — **landed**, see **Done**. It
   deviates from §12's "populated when the narrator names something": items are
   written as structured records at room realization instead, because the
   narrator-tool version depends on a model complying. The rest of §12's intent
   — lazy, bounded, nothing generated ahead of time — holds.

### Queued out of the evaluation pass

Three tasks, all measured on the 20-turn baseline of 2026-09-03 rather than
proposed. The first is the captain's own instruction; the other two came out of
reading one held-out run the board scored at zero flags.

- **`ta-narration-third-person-fix`** — the dominant defect: arrival narrations
  write the player as somebody else, **159 flags on 113 of 320 tuning turns
  (49.7%)**, 9.4% on the held-out world. It needs the loop rather than a look,
  because one unchanged configuration produced 1 to 13 flags on the same twenty
  turns. **Done means two things:** a REAL verdict from `rake eval:compare` at
  four runs a side that reproduces on `The Salt Assizes`, *and* richness that
  does not fall REAL alongside it — the cheapest way to stop writing the player
  in third person is to stop naming anybody. Then re-baseline, and the existing
  check guards it from there.
- **`ta-take-drop-narration`** — the prose denies the take and invents a pickup
  on the drop. **The instrument half has landed** (`ta-narrator-invents-exit`,
  2026-09-03): `Scene#resolved_action` and `Scene#acted_on` record what each turn
  DID, and `take_denied` / `pickup_invented` read a narration against the state
  *before* the turn — 28 of 32 takes and 4 of 32 drops on the 480-turn baseline,
  frozen in `transition_corpus.json` and reported by `rake game:score`. **What
  is left is the prose fix**, which is now judgeable: the checks are fully
  available to a scripted sweep, so done means a REAL verdict from
  `rake eval:compare` at four runs a side reproducing on `The Salt Assizes`, with
  richness not falling. **`rake eval:prompt` is now the first gate and the
  cheaper one** (`ta-prompt-bench`, landed): 18 take cases and 18 drop cases
  against fixed facts, cents a run, with the defect reproduced at
  **take_denied 0.72 of 18** on the checked-in baseline. Judge the change there
  first and confirm it with `rake eval:compare`. Fold in PR-98's **F3** (the floor list into
  `Moment#narration_context`) and **F1** (a rule about *removing* a possession):
  both are the diagnosed cause and both are already measured.
- ~~**`ta-character-whereabouts`**~~ — **landed.** `characters.location_id`, the
  `Item` shape applied to people; see **Done**. What it left for
  `ta-narrator-memory` is stated there: `Character::Registry` places people and
  does not invent them, and `#admit!` is the seam creation plugs into.

### Alongside those, the older queued work

- ~~**`ta-prompt-bench`**~~ — **landed.** `rake eval:prompt` plays 90 hand-verified
  single-turn cases through the real turn loop with the classifier stood in for,
  makes ONE prose call a case against fixed facts, and scores the passage with
  eight of `Story::Scoreboard`'s twelve checks — the other four reported
  UNAVAILABLE, never as clean. Beside them: richness, refusals, omitted schema
  fields, cap hits, tokens, warm latency and spend, per model and **per prompt
  version**. `rake eval:prompt_compare` gives REAL/NOISE per check off the
  stored files, and says out loud whether the model or the prompt moved.
  `Playthrough::Feedback` freezes `prose_prompt_digest` beside `prose_model`, so
  verdicts group by prompt version too. Baseline of 2026-09-05 checked in under
  `db/eval/prompt-2026-09-05`. **`ta-take-drop-narration` is its first
  consumer**, and the bench already reproduces the defect it was built for. See
  EVALUATION.md → *The prompt bench*. What it deliberately does NOT measure: a
  `talk` turn, because `InteractionAgent`'s narrator pass sends no instructions
  to version. The compliance sweep (8) still sits on top of this.
- **`ta-scene-facts-prose`** — split `Scene::Generator` and `Scene::Narrator` by
  facts versus prose. Promoted by the standing constraint from "worth doing" to
  the structural expression of it: if the generator establishes facts and the
  narrator only renders them, non-compliance corrupts prose but never facts.
  **Land it before the laws digest** — everything prompt-shaped should wait for
  this split. Detail in **4. Persistence and history** is unaffected by it.
- **`ta-narrator-memory`** — **narrowed to the memory half.**
  `ta-character-whereabouts` took creation: `Character::Registry` writes 0–2
  people as structured records when a room is realized, out of the same call
  that describes it, so **characters-by-tool-call is superseded** and the live
  tension that item carried — that tool-call creation is itself a
  narrator-compliance dependency — is resolved by not depending on one. What is
  left is what the name says: a cast list and memory beyond one turn, and
  characters *mentioned in passing* becoming real records, which is a different
  and harder question than a room's own cast. `Playthrough::Moment#conclusions`
  already opened the interaction memory; this is the rest of it.
- ~~**`ta-chat-persist`**~~ — **landed.** Conversations are kept, bounded and
  visible: see **Done** and **4** below. The arc's dependency on scene
  summarisation is discharged — `Playthrough#recap` is there and costs no call.
- **`ta-api-iface`** — the reading experience, stage 6. See **5** below.
- **`ta-prewarm-stubs`** — realize a room's connected stubs off the turn, so
  walking onward does not pay for the room being written. **An optimization,
  filed as one**: realizing is the slowest thing a move does — two calls,
  ~670 output tokens — and today the player waits for all of it. The captain's
  question was whether entering a location could dispatch background workers
  for its stubs; the answer is yes, with three hazards that decide the shape.
  - **It would make the world's shape depend on job scheduling.** Realizing a
    stub writes edges *into* its neighbours, and with
    `Location::ExitsSchema::MAX_EXITS` now enforced on the room, whichever job
    commits first spends the allowance and the loser's exits are refused. The
    same arrival, run twice, would produce different graphs. Generation is
    serialized behind the player today, so the order is decided by where they
    walked.
  - **`Location::Generator#find_location` has a create race and no index to
    catch it.** `locations` carries no unique index on `(story_id, name)`: it is
    a case-insensitive SELECT then a CREATE, so two workers each inventing the
    same name both find nothing and create two, and the de-dup that stops
    A → B → A from making a second A stops working. `location_connections` *is*
    uniquely indexed, so a concurrent edge write raises `RecordNotUnique`
    inside `#write_exits!`'s transaction and rolls back the whole exit set.
    **A unique index on `(story_id, lower(name))` is worth having either way**,
    and is the first commit of this item.
  - **SQLite is one writer.** Solid Queue has its own database; the app's does
    not, so four concurrent realizations contend for the same write lock.
  - **And it is a product decision, not only a technical one.** The premise is a
    world that generates itself as the player explores it. Pre-realizing writes
    it ahead of them: rooms exist nobody has seen, and a room written before
    arrival cannot be written in the context of the scene arrived from.
  - **The shape to build, therefore: one worker, not four.** After the turn
    returns, enqueue a single job that realizes ONE stub, serialized per story
    (a Solid Queue concurrency key) so two never run for the same world. The
    graph stays deterministic, both races are dodged, the cost is one extra
    room per move rather than four, and the latency still goes away on the
    common case of walking onward rather than back.

## The detail, by area

The checklists below are the granular version of the same work: what is
actually done in each area, and what is not. Where an unchecked item is now a
queued task, the task id is named.

### 1. The protagonist

- [x] The player is a `Character` with `is_protagonist` set — at most one per
      story, enforced by validation and exposed as `Story#protagonist`.
- [x] Position lives on a separate `Playthrough` model (`story`, `character`,
      `current_location`, `current_scene`, unguessable unique `token`) rather
      than columns on `Story`. Same split the schema already makes between the
      durable `Location` and the momentary `Scene`: the world is not somebody's
      progress through it, and one generated world can be played twice. The
      `token` is what will bind a browser session to a playthrough.
- [x] `PlaythroughsController#create` creates the `Playthrough`, points it at
      `Story#protagonist` and at the story's first location, and binds the
      browser session to it with the playthrough's `token`. No auth, no user
      model — a single unguessable token in the cookie is the whole mechanism.
- [ ] `Character::Generator` still never sets `is_protagonist` (nor
      `is_companion`), so a generated story has no protagonist and the
      playthrough's `character` stays nil. Narration copes; it should not have to.

### 2. Scene generation

- [x] `Scene::Generator` — given a `Location` and the `previous_scene`, narrate
      arriving and persist the `Scene`. Reads differently on a first visit
      versus a return: `Location#last_protagonist_visit` decides which, and
      `#time_since_last_visit` puts the gap in the prompt in words. Both are
      read **before** `Scene.create!`, because `Scene`'s `after_create` stamps
      the visit — read them after and every return is "less than a minute ago".
- [x] Populate `scene.characters` from who is present.
- [x] It does not advance the `Playthrough` itself, by design: it returns the
      scene and lets the caller place the player, because moving the player is
      the game loop's decision and it also has to set `current_location`.
      `Playthrough::Turn#move_to` is that caller.
- [x] `#holdovers` read the plain latest scene in a location, so any turn that
      was not an arrival emptied the room -- only an arrival records a cast, and
      a `Scene::Narrator` turn writes a scene with nobody in it. It now reads
      the last scene that recorded anyone. Unreachable before movement existed.
- [x] `Scene::Generator.characters_present(location)` answers the same question
      without building an arrival, so `Playthrough::Classifier` offers exactly
      the people the arrival paragraph introduced.

### 3. The game loop

- [x] A reach that resolves to nothing is **refused, and the player is asked
      for one thing they can actually do** (`Playthrough::Refusal`) — the ruling
      of 2026-09-04. It used to be stated to the narrator as a fact
      (`Playthrough::Turn#reach_fact`, now gone) through the same `fact:` seam
      `take` and `drop` still use for what they DID. The narrator prompt still
      carries the room's exits, cast and the player's inventory
      (`Playthrough::Moment`) on every turn it is asked for.
- [x] **A line that names two things is refused whole**, and the player is asked
      to pick one. Same ruling, same author, and the same three shapes in
      `rake game:mechanics` as in the browser — the mode's `also named:` note is
      gone with the half-played turn it reported.
- [x] Classify player input: move / talk / examine / take / drop / other, in one
      schema'd `BaseAgent` call. `Playthrough::IntentSchema` is a factory rather
      than a declared schema because `target` is an enum built per turn from the
      room's exits, its cast, what is lying in it and what the player carries:
      the loop has to turn the answer back into a `Location`, a `Character` or an
      `Item`, and "north" resolves to nothing. Closing the
      set means the model names something that exists or names `nothing`, and
      there is no third answer to write a matcher for.
- [x] On **move**: resolve the target from `Location#exits`, realize it if it is
      a stub, narrate arriving, and point the playthrough at both. The
      load-or-generate seam, and there is no branch in it: `realize!` returns an
      already-realized location untouched, so the same four lines cover walking
      somewhere new and walking back.
- [x] On **talk**: `InteractionAgent`, through `BaseAgent`. The exchange keeps
      two records -- the `Scene` the player reads and the `Interaction` the
      character felt.
- ~~`rake game:play[story_id]`~~ -- skipped on purpose. The browser is the
      playable interface; the rake tasks build worlds and the browser plays
      them. Do not add a `game:play` task. `rake game:mechanics` is not that and
      does not weaken it: it renders no prose and duplicates no part of the loop
      -- it is an instrument pointed at the engine, and the moment it printed
      narration it would be the second UI this rule exists to prevent.
- [ ] **A move is 3 model calls and does not stream**, so the player watches a
      blinking cursor for as long as realizing a room takes. Nothing is wrong;
      it is just slow, and the job-and-cable stage below is where it is fixed.
      Do not "fix" it by schema-ing less -- `Scene::Generator` cannot stream.
- [x] **`take` and `drop` are state changes the app owns.** `Item` is in exactly
      one place — held by a character or lying in a location — and each action
      resolves against that distinction as a closed set, moves the row, and only
      then hands the narrator the fact to write a sentence about. So a narration
      that says the player pocketed something cannot make it so, and one that
      forgets the compass cannot take it away. Both directions on purpose: an app
      that owns picking up while the narrator asserts putting down has records
      that go stale the first time a player sets something down.
- [ ] `examine` is told apart and then handed to `Scene::Narrator` like anything
      else. It is classified so the branch exists when there is something for it
      to do.
- [x] **The app creates `Item`s.** `Item::Registry` writes them at room
      realization, out of the same call that describes the room
      (`Location::DetailSchema`), bounded per room and per world — so `take` and
      `drop` are real over a set a generated room actually has. Not a narrator
      tool and not a scan of prose: the engine decides what exists and
      `Playthrough::Moment` tells the narrator. A seed file remains the other
      writer, and puts things on the **floor** of a room as well as in somebody's
      hands (`locations[].items`); see `db/seeds/worlds/README.md`. The registry
      leaves seeded rooms alone.
- [x] **The mechanics can be walked with the narration off.**
      `Playthrough::Mechanics` (`rake game:mechanics`) keeps the classifier — the
      intent it resolved is printed, so how the typing was read is visible — and
      keeps the world generating itself, so a move is `Playthrough::Turn#move_to`
      whole. What it drops is `Scene::Narrator` and `InteractionAgent`: no prose,
      just the records and a one-line diff. `model: false` (`NO_MODEL=1`) is the
      offline fallback, a fixed grammar with no model call at all, asserted in
      `Playthrough::MechanicsTest` with `BaseAgent.new` raising. It is the answer
      to *"we are testing too many variables at the same time"*: movement and
      possession, on their own, with the prose out of the way. See the README.

### 4. Persistence and history

`ta-chat-persist`, landed. The prose summary is in **Done**; this is the
checklist.

- [x] **The `chats` / `messages` tables are wired up.** Every `BaseAgent` writes
      a `Chat` and its `Message`s — the prompt, the answer, the token counts and
      the model that actually replied — lazily, so an agent nobody asks anything
      leaves no row. One chat per agent CONVERSATION, because a chat's messages
      have to be a list you could send again: one system instruction, one
      schema, one model.
      Which turn a message belongs to is on the **message** (`messages.scene_id`),
      not on the chat, because a durable conversation spans many turns and a
      turn's cost has to come out exactly.
      `messages.content_raw` was added and is load-bearing: RubyLLM stores a
      schema'd answer there with `content` nil, so without it every schema'd
      call in the app persisted an empty assistant message.
- [x] **The debug view gained all of it**, which is what it was built to do:
      prompts, raw responses, token counts and the answering model, per turn and
      per playthrough. Two of the three gaps it named close with it — the
      classifier's exchange holds both the raw typed command and the intent
      label the loop decided in memory.
- [x] **`tool_calls` is wired but unexercised**, and that is honest rather than
      missing: `acts_as_tool_call` is in place and RubyLLM writes the rows when a
      call happens, and nothing in this app gives a model a tool yet. That is
      `ta-narrator-memory`, and it will find the table already there.
- [x] **Persist an `Interaction` at all.** `InteractionAgent#ask` returns the
      structured reaction alongside the prose now, and `Playthrough::Turn#talk_to`
      writes the row.
- [x] `Interaction#inner_resolution` is a **sixth field on `Interaction::Schema`**
      rather than the second call the note used to imagine — no extra round trip,
      ~30 tokens on a call that already happens — so `#completed?` is finally
      capable of being true. `#summary` is derived on create from what was
      already paid for. `inner_resolution` is deliberately NOT interpolated into
      the narrator pass: what a character decided is about what they will do
      next, and handing it to the prose invites narrating that instead.
- [x] Summarize old scenes so long playthroughs stay inside the context window.
      `Playthrough#recap` spends `scenes.summary` — written on every arrival, for
      exactly this — under a fixed character budget, and asks no model anything.
      Measured against `gemma3:12b` on the seeded world, the same commands played
      twice: the narration prompt went 711 → 781 and 684 → 775 input tokens
      (+70 / +91, about 7% of a turn) while its memory went from one turn to
      three. Carrying those three in full prose instead would have been 2,264
      characters against the recap's 343. README has the table.
- [ ] **Nothing summarises a narrated turn.** Only an arrival is schema'd, so
      only an arrival has a `summary`; the recap contributes such a turn's own
      first sentence instead. Truncation is honest and free, and the alternative
      is a second model call on every turn — but a real summary is better prose
      in the prompt. Worth revisiting only alongside `ta-scene-facts-prose`,
      which is where the narrator stops being the only thing that writes a turn.

### 4a. The world's own mechanics

Step 1 of the direction plan, landed as PR #77. The prose summary is in
**Done**; this is the checklist.

- [x] **`Story#clock`** — what time it is in the fiction, derived from
      `scenes.story_timestamp` rather than stored. A story nobody has played is
      at its own `start_time`.
- [x] **Story time on every `Scene`.** An arrival is the previous scene plus
      `LocationConnection.travel_minutes` for the edge actually walked; every
      other turn costs what `Scene::TURN_MINUTES` says. `Time.current` is gone
      from that whole path, which closed the wall-clock defect that used to be
      the first entry under **Known issues**: `Location#last_protagonist_visit`
      now holds a story moment, so `#time_since_last_visit` — the value
      `Scene::Generator` turns into "you were last here about an hour ago" — is
      measured in the fiction. Fixed in the one place the issue asked for.
- [x] **`WorldMechanic`** — a fixed catalogue of Ruby operations over records,
      on a story-time schedule. `kind` and `cadence` are keys into tables in
      code; a world supplies parameters (`locations.mobile`, the cadence, the
      in-fiction reason) and never behaviour. `last_run_at` is a column in story
      time, so catching up is arithmetic: no timer, no job, nothing in memory,
      and a process that was down for a week pays the nights it owes on the next
      turn. Driven from `Playthrough::Turn#play`; ~90 µs and **0 tokens** on a
      turn where nothing is due.
- [x] **`WorldMechanic::ShuffleConnections`** — repoints one endpoint of every
      edge joining a `mobile` location to a fixed one, permuting rather than
      choosing so every location keeps its degree, with an explicit connectivity
      check before an arrangement is applied. Deterministic per (story, night).
      Hand-written into `the-lunar-cartographer.yml`, whose universe has claimed
      since it was generated that Nocturnis rearranges itself nightly.
      An arrangement is judged on the **induced adjacency** — the set of
      unordered pairs of places that end up joined — and not edge by edge, so a
      permutation confined to one mobile location's own edges is a no-op and is
      refused. `settle` first rewrites every candidate into the one form that
      says what it means: within a location's own edges, an endpoint it keeps
      stays on the edge that already had it. Reordering endpoints among one
      location's edges cannot change the graph, so `valid?` judges exactly what
      gets written — and every sentence the log writes is then true of the
      graph, not merely of an edge. (`ta-shuffle-noop`.)
- [x] **`WorldEvent`** — the audit trail, in story time, with the locations it
      touched. Deliberately NOT a narration source: over two nights a shuffle
      can return a place to the same neighbour, so replaying the log would
      announce a change the player never experienced.
- [ ] **The arrival diff — "what changed while you were gone".** Record the exit
      names the player was actually shown on `Scene` and diff them on arrival.
      That is what makes the mechanic *felt* rather than merely true, and it is
      the honest version of the previous point. ~25 tokens. `ta-arrival-diff`,
      step 4 of the order above.
- [ ] **Judge the edge shuffle in play.** Captain-decided: build the simple
      version, play ten turns, and only then decide whether whole districts
      should travel as units instead. The districts variant is neither adopted
      nor rejected.
      **First nine turns played** (`ta-debug-view`, against the local models).
      The mechanic fired on schedule off the story's own clock and cost nothing,
      but the one arrangement it drew was a transposition within a single mobile
      location's own edges, so the graph did not actually change and the event
      said it did. That was a broken guarantee and is **fixed**
      (`ta-shuffle-noop`) — such an arrangement is now refused and the night
      writes nothing. Note what it implies for the districts variant, which the
      fix does not settle either way: a district travelling as a unit cannot
      produce a no-op of this shape, because its edges out have distinct mobile
      ends. The edge shuffle now has to reach for a valid arrangement where the
      districts variant would not, which on a sparse world is a real cost in
      nights that do nothing — one data point, recorded as one. **Still nine
      turns played, not ten, and none since the fix**: the judgement wants a
      night that visibly moved something.
- [ ] Generating a mechanic from a model at world-creation time. Deliberately
      not built: the parameters are hand-authored first, so the mechanic that
      exists is one somebody chose.
- [ ] A second `kind`. `WorldMechanic::KINDS` has one entry, and the next one is
      an operation in Ruby rather than a field in a file — including the one the
      direction wants for violation-becomes-consequence
      (`ta-violation-consequence`, step 5).

### 5. Interface

`ta-api-iface`. The first playable browser interface has landed (see **Done**).
What it still owes, roughly in order:

- [ ] Echo past commands in the turn log. **The column has landed** —
      `Scene#typed`, written on every branch by `Playthrough::Turn#play`, with a
      migration that backfills from `Interaction#user_input` and from whatever
      classifier prompts were still kept. The debug view reads it. What is left
      is presentation: the play page's turn log is still narration only, so a
      reloaded transcript reads as answers without questions.
- [x] **Jobs, Turbo Streams over Action Cable, and durability.** Landed — see
      **Done**. `NarrationJob` replaced `NarrationsController`, `propshaft` +
      `importmap-rails` + `turbo-rails` are in, and there is still no Node and
      no `package.json`. The conversation-persistence half of the same stage
      (`ta-chat-persist`) has landed too, so stage 5 is complete.
- [x] **A verdict on each turn while playing** (`ta-turn-feedback`) — see
      **Done**. It is the one thing that has landed on the play page ahead of
      the visual style below, and it is deliberately not an exception to it:
      the control is dim until hovered, absent when the instrument is off, and
      carries the least styling that makes one click usable. It is also why the
      footer under a turn is a `<footer>` and not a `<div>` — the dimming rule
      is `.log:not(.streaming) > .turn:last-of-type`.
- [ ] Re-join a turn already in flight. Reopen the page mid-narration and the
      log is what was persisted; the prose written so far lives in the job's
      buffer and nowhere else. The finished turn still arrives over the cable
      when it lands, so nothing is lost — only the live view of the middle.
- [ ] Visual style. Deferred on purpose until there is a real loop to look at.
      The debug view (`ta-debug-view`) is **not** an exception to this and does
      not pre-empt it: it has its own layout and shares no CSS with the game, so
      the two can be styled independently and neither constrains the other. Its
      whole mark on the game is one link on the play page, absent when the view
      is off.
- [x] **The page stays where the story is.** Submitting a turn used to land at
      the top of the document while the answer streamed in below the fold: the
      streaming render emits no form, so the `autofocus` that had been pulling
      the viewport down was missing at exactly that moment. A `#bottom` anchor
      at the foot of `playthroughs/show` — which a plain reload and the index's
      Resume link aim at — does the landing with no script, and
      `app/javascript/play.js` follows the narration down only while the player
      is already at the bottom, so scrolling up to re-read is not overridden.
      The redirect anchors went away with SSE, as predicted; the follow was
      ported. With no end-of-turn reload, `stick` is honoured throughout: a
      player who had scrolled up is no longer dragged to the bottom when the
      turn lands.
- [x] A playthrough starts in the story's first **realized** location — the
      opening room `game:new` generates. Stubs are skipped: they are exits
      nobody has walked into, with a name and a teaser and nothing to read.
- [x] **The turn log starts where the story starts.** The opening room used to
      be read out *above* the log and only while the log was empty, so the
      first turn — the first thing to put a `Scene` in that log — made the
      opening text vanish from under the player. `PlaythroughsController#opening_scene`
      writes it as a `Scene` when the playthrough starts, so it stays where it
      was written. Two things fall out: `Scene`'s after_create stamps
      `last_protagonist_visit`, so the explicit `mark_protagonist_visit!` is
      gone, and the first move now gets a real `previous_scene` instead of
      `Scene::Generator` being told "this is where the story opens" one room
      too late. It is a room description standing in for an arrival nobody
      narrates, which was the honest limit of it — closed by the next item.
- [x] **Where the opening arrival comes from.** It comes from the world now —
      `Scene::Generator.opening` at `rake game:new` time, `opening_scene` in the
      seed file, loaded with everything else. See **Status → Done**. The ruling
      on the "progress rather than world" line, and the natural key a `Scene`
      did not have, are both written up in `db/seeds/worlds/README.md`.
- [x] A story generated before opening locations existed has nowhere to start,
      so the index lists it without a Play button and `create` refuses it. That
      branch stays, but it is no longer the only thing that says so:
      `rake game:doctor` names such a story and every other way one can be
      unplayable, and says whether it can be repaired or should be deleted.
      Measured on the captain's own database: of five stories, two were
      unplayable with no locations at all, one was playable with nine warnings,
      and two were healthy.

## Known issues

- ~~**A room one party has emptied is empty for the other**~~ — **fixed**
  (`ta-items-per-playthrough`, 2026-09-04, on the captain's ruling). The world
  is the template and the playthrough owns the instances: `items.playthrough_id`
  is the LAYER, `items.template_id` is the link, and `Item::Snapshot` copies a
  room's contents into a game at first contact. The two options this entry
  listed were "scope room contents per playthrough" and "leave rooms shared and
  say so"; the captain chose the first, and what stays shared is the world
  itself — the geometry, the descriptions, the cast. See **Done**, and
  `lib/engine_sweep/scripts/the-unrecorded-hour-two-players.yml` (independence),
  `…-first-contact.yml` (timing) and `EngineSweep::Invariants#world_items_unmoved`
  (no typed line moves one of the world's own rows).

- **The narration erases the `take` and invents the pickup on a `drop`**
  (`ta-take-drop-narration`, queued). **Two checks see it now** — see the
  resolution note at the end of this entry. On a turn the app
  resolves as `take`, the prose says *"You **already hold** the Assize
  tide-slate"* — of a slate that was lying on the bench until this turn moved
  it. On a `drop`, the mirror: *"You **lift** the tide-slate **from where it
  lies against the wall** and set it down"*, of a slate the player was carrying.
  **30 of 32 take turns and 5 of 32 drop turns, on the 480-turn baseline.**
  `Playthrough::Turn#taken_fact` hands the narrator the right sentence stated as
  done; the narrator writes the opposite. Likely cause: `Playthrough::Moment`
  carries the post-write inventory as standing state beside a fact describing
  the transition, so the state reads as prior and the fact as redundant. **No
  check catches it because every check in `Story::Audit` reads one scene against
  the state it was written against, and this is a claim about a transition** —
  the prose and the records agree about who holds the slate and disagree about
  whether anything happened. Found by reading a held-out run the board scored at
  zero flags.

  **The blindness is fixed; the prose is not** (`ta-narrator-invents-exit`,
  2026-09-03). `scenes.resolved_action` and `scenes.acted_on` record what each
  turn did, written by `Playthrough::Turn#play` beside `typed`, and
  `Story::Audit`'s `take_denied` and `pickup_invented` read a narration against
  the transition rather than against a state. The manual figures re-measured by
  the check itself are **28 of 32 takes and 4 of 32 drops** — the four takes it
  gives up deny the pickup by handing the slate to a third person who is the
  player, which `third_person_protagonist` catches, and the drop it gives up
  writes "the slate" of an item recorded as the "Assize tide-slate". Both misses
  are pinned in `Story::Audit::TransitionTest`. Nothing about the narrator
  changed: that is `ta-take-drop-narration`, and it is now a number that can
  move.

- ~~**Nothing records where a character is**~~ — **fixed**
  (`ta-character-whereabouts`, 2026-09-04). `characters.location_id` is the
  record and `Character.present_in` is the closed set `talk` resolves against;
  the scene cast is a derived snapshot written on every branch rather than the
  only place presence ever lived. The Tide Post records Neb Halloran. See
  **Done**. The `character_not_present` check that this entry said must not be
  built was then measured with the records in place and **still not built** —
  `Story::Audit` finding 5 has the numbers, and the reason is now a property of
  prose rather than of the records.

- **The local model rotation is off by default** (`TA_LOCAL_MODELS=1` to bring
  it back), on the captain's ruling of 2026-09-03: *"if we are still falling
  back to local models, let's stop doing that for now."* The failure it closes
  is not a crash — it is a turn answered slowly by a 4k-context CPU model, after
  which every measurement and quality claim downstream is silently about a
  different model. Same argument `#ask` already made for not rotating on a 401,
  applied to the rest of the rotation. A fresh clone with no key now raises
  `BaseAgent::NoModelConfiguredError` with both ways out in the message, where
  it used to fall through to ollama.

- **A scripted talk turn that names a place is a move, and the classifier is
  right.** `lib/eval/scripts/the-lunar-cartographer.yml` first said *"Grenn,
  unlock the roof door and take me up onto the Larkspur Quarter rooftops
  yourself"* and `Playthrough::Classifier` resolved it as `move` on all eight
  runs — the sentence names a destination the room has an exit to. The rest of
  the run then played out somewhere the script did not intend. Fixed in the
  script, and recorded here because it is the general shape: an eval script's
  talk beats must name no place. Not a defect in the game.

- **The third-person narration bug is world-dependent, and nobody knows why.**
  Over 24 runs of `ta-eval-pipeline`'s sweep, `third_person_protagonist` fired on
  30.1% of tuning turns and **0 of 88** turns of `The Salt Assizes`. Every
  instance in the two tuning worlds is an ARRIVAL narration inventing a figure in
  the room and giving it the player's name; the held-out world's arrivals never
  do it. Whatever separates them is the thing `ta-narration-third-person` should
  be diagnosed against.

- **One passage earns two `third_person_protagonist` flags when it uses the
  protagonist's full name.** `Prose.protagonist_names` yields "Isbet Marrow",
  "Isbet" and "Marrow", and a sentence containing the full name matches two of
  them, so the flag count runs ahead of the number of turns affected — 63 flags
  over 46 turns in the `ta-eval-pipeline` sweep. The check's own rule is one per
  sentence per grammar and this is the letter of it rather than the spirit.
  Deliberately not changed here: it would move the count `Story::Scoreboard::CorpusTest`
  pins, which is a change with its own measurement to do. `Eval::Board` prints a
  distinct-turn column beside the rate and its worksheet shows each passage once.

- **`unrecorded_arrival` has never fired on real prose.** It detects 7 arrival
  assertions across 224 real passages and the records agreed with all 7, and it
  flagged nothing across 264 freshly generated turns. That is a live, precise
  check reporting zero rather than a check that cannot fire —
  `Story::Audit::ArrivalTest` proves the difference by moving the record under a
  real sentence — but until it catches something in the wild it is unproven in
  the way the other checks are not.

- **Three findings from the refusal sweep, measured and deliberately not acted
  on** (`data/ta-refusal-range/report.md`). None is a refusal problem, and each
  is its own piece of work: (1) **`mistral-medium-3.1` refused nothing and is
  3–4× faster**, but its prose is markedly thinner — *decided: it is now the
  default, and the thinner prose is the accepted trade. See Done.* (2) **The talk path
  hangs.** Three calls in ~150 stalled indefinitely, all on the unschema'd
  streaming pass inside `InteractionAgent`, and `RubyLLM`'s `request_timeout`
  demonstrably did not bound them — one ran 21 minutes with it set to 150s.
  `NarrationJob` has no timeout of its own, so a stalled talk turn holds a Solid
  Queue worker with the player watching a dead cursor. (3) **minimax drops
  required `Interaction::Schema` fields on ~29% of talk turns** (12 of 41; 0 of
  14 on mistral), each one a silent wasted call that `verify_schema_honored!`
  recovers from. The rate is *higher* on benign input than on charged input, so
  it is flakiness rather than steering.
- **How often minimax hits a cap is its own property, and prompt wording does
  not move it.** `minimax/minimax-m3` uses the first string field it is handed
  as a scratchpad: over 30 real character passes, `pre_thought` came back at
  exactly its 320-cap on 26 of 30, every one of them a stage note about how to
  play the character. Rewording `Character#interaction_instructions` — scoping
  the third-person rule, naming the addressee, telling it not to plan — moved
  that to 23 of 30, which is to say not at all. `mistral-medium-3.1` and
  `gemini-2.5-flash` overrun 0 of 180 fields on the same prompts, so it is the
  model and not the prompt. Both arms were measured against the **pre-#92** talk
  path, where a cap-hit killed the turn: 27 of 28 turns died before the
  rewording and 28 of 29 after. #92 changed what a cap-hit *costs* — a rotation
  instead of the turn — and did not change how often minimax produces one, so
  the rate above is what the rotation now pays for. Do not reach for prompt
  wording here; it was measured and it does not work.

- **The suppressed prose is still streamed before it is suppressed.** Both
  checks read the finished response, so a refusal or a crisis line has already
  been broadcast into `#stream` chunk by chunk by the time it is caught. It is
  never persisted and the end-of-turn `#turn_log` replace takes it off the page
  — the log renders persisted scenes — but a player watching closely saw it
  arrive. Catching it mid-stream is a different design on partial text, and the
  detector was measured on whole responses.
- **The story clock is the story's, not a playthrough's.** `Story#clock` is a
  `MAX` over every scene in the story, because `WorldMechanic` is story-level:
  the world moves for everybody. So two playthroughs of one world share a world
  clock, and the further-along player pulls the other's nights forward. Each
  playthrough's own next turn is still measured from its own last scene
  (`Playthrough#story_now`), so nobody's timestamps go backwards — but a second
  player can walk into a city that rearranged itself while they personally did
  nothing. Irrelevant for one player; the fix, if it matters, is a per-world
  clock rather than a per-story one.
- ~~**Re-seeding a played world re-asserts the graph the file declares**~~ —
  **fixed.** `WorldSeed::Loader` reconciles what the file can prove: a room or
  an item the file renamed is the same row renamed (`WorldSeed.natural_key`),
  and a doorway the nightly shuffle has moved is left where the world put it
  rather than written back as a second one. What it cannot prove — a rename no
  normalized name recognizes — is created and **warned about** on a world that
  has been played, and `rake game:doctor` names the pair whenever it can
  recognize one (`duplicate_locations`, `duplicate_items`,
  `mobile_doorway_re_asserted`), each with a `safe` fold in `rake game:repair`.
  Still adds and updates and never deletes anything play created.
- **A failed arrival leaves a realized room nobody has stood in**, which is the
  designed behaviour working and is worth knowing how to read. Observed in the
  same run: the move's `Scene::Generator` call rotated to `qwen3:8b`, which
  omitted `summary`, so `BaseAgent` raised `SchemaIgnoredError` and the turn
  failed. `Location::Generator#realize!` had already committed, so Mournwell
  Lane is realized with its exits stubbed out, and `Playthrough::Turn#move_to`
  correctly did not move the player — exactly as its comment promises. On the
  debug view it reads as a realized place with `last visit (never)` and nobody
  in it, which is the signature of a half-finished move and is not otherwise
  visible anywhere.
- **The play page does not show what the player typed.** The column exists now
  -- `Scene#typed`, written on every branch, and the debug view reads it -- but
  the turn log is still narration only, so a reloaded transcript reads as
  answers without questions. That is presentation, not plumbing.
- ~~**A generated room has nobody in it**~~ — **fixed** in the same PR. A room
  is realized with 0–2 people written as records out of the call that describes
  it (`Character::Registry`), and the prompt asks for nobody as the ordinary
  answer. What is still true, and is the honest limit: **a person the model
  names in prose is still nobody**, because nothing reads narration for a name
  and nothing should. Only the structured `people` array becomes a record. A
  character mentioned in passing becoming real is `ta-narrator-memory`'s
  remaining half.
- **Solid Queue's worker count is the new ceiling on concurrent turns.** The
  Puma-thread problem is genuinely gone — WebSockets consume no request threads,
  and the turn runs outside the request entirely — but it has a successor:
  `config/queue.yml` gives one worker process 3 threads, so a fourth
  simultaneous turn queues rather than starting. That is a much better failure
  than the old one — the site stays responsive and nobody loses a turn — and
  `JOB_CONCURRENCY` raises it. `deploy.yml` sets `SOLID_QUEUE_IN_PUMA: true`, so
  in production those threads share the web container.
- **A development server keeps the columns it booted with.** ActiveRecord caches
  each table's columns the first time a model touches it, and a migration is
  always run in another process — so a server that was up before `db:migrate`
  goes on serving a class built from the old schema, and a column that is right
  there in the database raises `undefined method`. That is what
  `NoMethodError: undefined method 'is_opening?' for an instance of Scene` was:
  not bad data and not a pending migration, an eleven-hour-old process.
  `StaleSchemaGuard` (development only) now compares the schema version on every
  request against the one the process first saw, and says *restart the server*
  rather than letting the first attribute the code reaches for fail. It reports
  and does not repair: resetting column information in place leaves the
  connection's prepared statements still selecting the old columns, so a new
  process is the honest answer. **`bin/jobs` is a second long-lived process with
  the same hazard**, and no guard: it serves no requests, so restart it after a
  migration too.
- **`Scene::Narrator`'s `ensure` cannot cover a `Scene` that will not save.**
  Closing the tab no longer costs anything — the turn is a job and nobody has to
  be watching — but that was only ever half of what the `ensure` was for. When
  the captain lost 82 seconds of a turn to the stale process above, the `ensure`
  ran exactly as designed and the `Scene.create!` inside it was what raised;
  there is nowhere to put prose when the model cannot be written at all. On a
  **move** most of that time was in fact kept: `Location::Generator` saves the
  room before it asks for the exits, so both of those calls had already landed
  and only the arrival narration was lost. The narration branch is the one that
  loses everything, and what fixes it is a process that is not stale rather than
  another `ensure`.
- **RubyLLM's model registry is a process-wide memoized snapshot.**
  `RubyLLM::Models.instance` is built once, out of the `models` table, falling
  back to the registry JSON the gem ships only when that table is empty. It is
  never re-read. In tests that made model resolution depend on test order:
  registry rows are created inside transactions that roll back, so a snapshot
  taken by one test resolved the next test's model names against rows that no
  longer existed. `test_helper.rb` now drops the memo before every test. In
  development and production the same memoization means a `models` row added
  after boot is invisible until the process restarts or something calls
  `Model.refresh!`.
- **A factory that rolled dice made one view test fail 1 run in 35, and
  parallel workers were the reason nobody could reproduce it.**
  `DebugControllerTest#test_show_flags_a_one-way_edge...` failed a full-suite
  run with `Expected at least 1 element matching ".warn", found 0`, then
  survived nine further full runs including a re-run of the failing seed and
  every run of the file alone. Cause: `test/factories/location_connections.rb`
  picked `distance` and `travel_method` with `.sample` off the two fixed tables.
  The test wrote the *return* edge with a hard-coded `("a long journey",
  "riding")` and left the *outbound* edge to the factory, so 1 time in 35 (5
  distances × 7 methods) the two rows matched, `Playthrough::Debug::Exit#directions_disagree?`
  correctly answered false, the cell rendered `yes`, and the page carried no
  `.warn` at all — which is why the count was zero rather than merely
  unmatched. **Parallelism was the exposing condition, not the cause.** Minitest
  `srand`s the global RNG once from the run seed, so the sequence is fixed, but
  the *position* it has reached when a given test's factories fire depends on
  how many earlier `rand` calls landed in that forked worker — and work is
  handed to the 16 workers as they come free. Same seed, different schedule,
  different dice: that is the whole of why the seed did not reproduce it, and
  it is the same shape as the registry issue above, one layer down.
  **Proven rather than argued:** a record-level probe predicted the 10 global
  seeds in 0...300 that collide, and all 10 fail the old test through the real
  request path while 5 predicted-clean seeds pass. **Fixed twice over:** the
  factory's two values are now fixed (`across the district` / `walking`, chosen
  so its 20 minutes collides with neither entry in `Scene::TURN_MINUTES`), and
  the test writes both directions of the edge itself, because a disagreement is
  a relationship between two rows and a test that pins one and leaves the other
  to a factory is asserting against a value it does not know. The `.warn`
  assertions now match whole phrases, and the agreeing case — the state the
  flake actually rendered — has a test of its own. `test/factories/characters.rb`
  still uses `rand`/`.sample` for `age` and `sex`; nothing pins those today, so
  it is a latent instance of the same shape rather than a live one.
- **The suite used to read behaviour out of whoever's shell started it.** Found
  while confirming the above: three tests failed for a worker who had
  `OPENROUTER_API_KEY` set in their environment — `BaseAgent.default_model_options`
  puts the hosted models ahead of the local ones when the key is present, so two
  tests pinning the answering model to `gemma3:12b` got `minimax/minimax-m3`, and
  `ChatTest#test_resolving_a_model_name_needs_the_provider_configured` got no
  exception because the initializer had configured the provider from the same
  key. Worse and unnoticed: `TA_DEBUG_VIEW=0` in a shell turned
  `Playthrough::Debug.enabled?` off and took 11 of `DebugControllerTest`'s 13
  tests with it, and `TA_CHAT_KEEP_TURNS` / `TA_CHAT_HISTORY_EXCHANGES` are read
  into `Chat` constants at class-load time. Every one of the five is something a
  person working on this app legitimately keeps in `.env` or `.envrc`, and the
  ROADMAP tells them to. `test_helper.rb` now deletes all five, so the suite
  boots in a declared environment; a test that wants one sets it itself and puts
  it back, which `BaseAgentTest#with_env` and `Playthrough::DebugTest#with_env`
  already did. **It needs two passes, and finding out why cost a second round**:
  deleting them *before* `config/environment` is required is necessary for the
  two frozen into `Chat` constants at class-load time, but `dotenv-rails` loads
  `.env` during that same require and declines to override only the keys it
  finds already set — so the first pass is precisely what gives it the opening,
  and with that pass alone both `ENV["OPENROUTER_API_KEY"]` and
  `RubyLLM.config.openrouter_api_key` are populated again by the time the first
  test runs. Measured on a checkout with a `.env`, which is every checkout
  anybody plays the game from.
- **`sanitize_string` used to delete every digit a model wrote.** Its regex was
  `\p{Emoji}`, a property that matches the ASCII digits, `#` and `*` because
  those are the bases of the keycap emoji — so "80 meters" was stored as
  "meters". It now matches `\p{Extended_Pictographic}` instead. Any text
  generated before this fix has silently lost its numbers.
- **The move path does not work on local models, and rotation cannot reach the
  one that does.** Measured on a real playthrough: `gemma3:12b`, `gpt-oss:20b`
  and `qwen3:8b` all return `Scene::Schema` with `description` and no
  `summary`, so `verify_schema_honored!` rejects all three and the turn ends with
  the reason broadcast back and the player left where they were. `qwen3:4b` returns both
  fields — but it is 4th in `LOCAL_MODEL_OPTIONS` and `BaseAgent::MAX_ATTEMPTS`
  is 3, so rotation stops one short of it. Raising the cap is not obviously
  right: four attempts at up to a 600s timeout is 40 minutes for one failed
  turn, and `qwen3:4b` took **490s** for that single arrival call. Set
  `OPENROUTER_API_KEY` to move. The classification call is not affected — it
  honored its schema on `gemma3:12b` first try, including the per-turn enum.
  This is also why the loop's **talk** path was verified end to end in a
  running browser session against ollama and the **move** path was not: the
  classification and the arrival call were each verified live and separately,
  but the composition of the two is covered by `test/models/playthrough/turn_test.rb`
  rather than by a live playthrough. A single local arrival is ~8 minutes of
  CPU. Anyone with a key should walk the loop once and delete this paragraph.
- **Local models are slow, and they run on CPU here.** `ollama ps` reports
  `size_vram: 0`, so nothing is GPU-accelerated on this machine. Measured on a
  small 3-field schema: `gemma3:12b` ≈ 39s, `qwen3:8b` ≈ 92s (it burns the budget
  on thinking tokens). Paragraph-length schemas like `Universe::PhysicalSchema`
  take *many* minutes and exceeded RubyLLM's 120s default request timeout, which
  surfaced as `Faraday::TimeoutError` and looked exactly like a broken model.
  `config.request_timeout` is now 600s, overridable via `LLM_REQUEST_TIMEOUT`.
  Set `OPENROUTER_API_KEY` for anything interactive; `BaseAgent` prefers remote
  models automatically when the key is present.
- **A model that ignores your schema is worse than one that fails.** OpenRouter's
  `:free` endpoints frequently accept a JSON schema and answer in prose anyway --
  `minimax/minimax-m3:free` does exactly this, while the paid `minimax/minimax-m3`
  honors it. Ruby's `String#[]` does substring matching, so `content["fullname"]`
  on a prose response returns `"fullname"` rather than raising, silently poisoning
  the record. `BaseAgent#verify_schema_honored!` now raises `SchemaIgnoredError`
  and rotates to the next model. It also rejects a Hash that came back missing
  required fields, which is the same failure one step further along.
  **Before adding any model, check it:**
  `curl -s https://openrouter.ai/api/v1/models | jq '.data[] | select(.id == "MODEL") | .supported_parameters'`
- **Watch the ollama context window.** `ollama ps` reports `context_length: 4096`
  for these models. The universe prompt plus ten paragraphs of output is already
  close to that, and `Story::Generator` still feeds the whole universe back in
  (`:full` is the right audience there). `Scene::Generator` fits — 1,302 input
  tokens on the `:scene` audience, measured — but it carries exactly one prior
  scene. A playthrough that wants more history than that has to summarize
  first; `scenes.summary` is now written on arrival for that purpose.
- **`Location::Generator#realize!` can leave a room with no way out.** The
  description is saved before the exits call so an exits failure does not throw
  away the more expensive of the two calls — but `realize!` then returns that
  realized room untouched on a retry, which is the "generate once per place"
  guarantee working against recovery. Finishing such a room means calling
  `Location::Generator#write_exits!` directly. Harmless until the game loop
  resolves movement against `Location#exits`; give it a real completeness
  marker before then.
- **`Location#parent_location` is never written.** Every stub is created from an
  exit, and an exit says where you can walk, not what is inside what. The dead
  `parent_context` branch in `Location::Generator` is gone; the association and
  column remain, so a caller has to write it before any prompt can read it.
- **A talk turn is not durable, where a narrated turn is.** `Scene::Narrator`
  persists partial prose in an `ensure`, so closing the tab mid-stream keeps
  what was written. `Playthrough::Turn#talk_to` has no equivalent: the
  character pass has already been paid for and the narration is streaming, and
  a disconnect loses both calls with nothing recorded. Deliberately not fixed
  with a second bespoke `ensure` -- the job-and-cable stage deletes that shape
  for the narrator too, and should cover both paths at once.
- The migration to the new `acts_as` API left `chats.model_id_string` and
  `messages.model_id_string` behind — dead columns the generator's `down` step
  needs. Drop them if the migration is ever squashed.
- The `async` gem is still in the `Gemfile` but no longer used after
  `Character::Generator` was made synchronous.
