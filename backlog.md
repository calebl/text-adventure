# Backlog

## In flight
## Queued
- [ ] ta-narration-third-person-fix - Fix the third-person protagonist bug and prove it stayed fixed (repo: text-adventure) (kind: ship) (priority: 1) (since 2026-09-03)
  Fix the third-person protagonist bug, and use the eval loop to prove it stayed fixed.

  WHAT IT IS. Arrival narrations write the player as somebody else: "Isbet Marrow
  sits in the corner, her sharp eyes tracking the dust" -- of the player, who is
  only ever "you". It is the dominant defect on the board by an order of magnitude
  and it is almost entirely an ARRIVAL behaviour: the player is put in the doorway
  watching themselves arrive.

  MEASURED, on the 20-turn baseline of 2026-09-03 (`rake eval:score SET=main20`):

    tuning worlds     159 flags on 113 of 320 turns   rate 49.7%
    held out          15 flags on 11 of 160 turns     rate  9.4%

  The world-dependence is real and unexplained -- that is part of the work.

  WHY IT NEEDS THE LOOP RATHER THAN A LOOK. The noise floor on this check is
  enormous: one unchanged configuration produced 1 to 13 flags on the same twenty
  turns of the same world (The Lunar Cartographer, 0.050..0.650). So "I changed the
  prompt and it looks better" is not evidence at this scale, and no fix should land
  on one before-and-after pair.

  WHAT DONE LOOKS LIKE, and both halves are required:

    1. The rate falls, with a REAL verdict from `rake eval:compare BEFORE= AFTER=`
       at four runs a side minimum (the arithmetic floor -- at three, the exact
       test cannot reach p <= 0.05 however clean the separation), and it
       reproduces on the held-out world, `The Salt Assizes`, which must not be
       tuned against.
    2. `Eval::Richness` does not fall REAL alongside it. The cheapest way to stop
       writing the player in third person is to stop naming anybody, and the board
       prints richness next to the rate for exactly this reason. A fix that thins
       the prose is not a fix.

  Then re-baseline (`rake eval:run`, keep the set) so `third_person_protagonist`
  guards the fix from then on -- the check already exists and is measured for false
  positives, so "keep it fixed" costs nothing new once the rate is down.

  READ BEFORE STARTING: EVALUATION.md (the protocol), `Eval::Noise`'s header (the
  spread and the verdict rule), and AGENTS.md -> *Measuring a change against the
  noise it makes*. Generation spends money and never runs in CI; a 3-world,
  4-run-a-side comparison is about $0.47 a side.

  NOT IN SCOPE: the prose-quality question. This counts one error that is
  objectively present or absent.

- [ ] ta-take-drop-narration - The narration erases the take and invents the pickup (repo: text-adventure) (kind: ship) (priority: 1) (since 2026-09-03)
  The narration erases the take and invents the pickup, and no check can see it.

  FOUND by reading a clean held-out run end to end -- the captain's accuracy pass
  on `The Salt Assizes`, which the board scored at zero flags. The board was right
  about every check it has. It missed this entirely.

  WHAT HAPPENS. On a turn the app resolves as `take`, the prose says the player
  already had the thing:

    typed:  "pick up the Assize tide-slate"
    prose:  "You ALREADY HOLD the Assize tide-slate, its weight familiar in your
             hands."
    record: the slate was lying on the bench; this turn is what moved it.

  And on a `drop`, the mirror -- the prose invents a pickup that never happened,
  because the item has already left the player's hands by the time the prose is
  written:

    typed:  "put the Assize tide-slate down on the bench"
    prose:  "You LIFT the Assize tide-slate FROM WHERE IT LIES AGAINST THE WALL and
             set it down on the Justicar's bench"
    record: the player was carrying it.

  MEASURED across the 24-run, 480-turn baseline of 2026-09-03:

    take turns that deny the pickup     30 of 32   94%
    drop turns that invent a pickup      5 of 32   16%

  THE APP IS NOT AT FAULT, which is what makes this worth a task rather than a bug
  fix in passing. `Playthrough::Turn#taken_fact` hands the narrator the right
  sentence, stated as done: "Coraith Vell has picked up the Assize tide-slate and
  is now carrying it." The row has already moved. The narrator is told the truth
  and writes the opposite.

  THE LIKELY CAUSE, to be confirmed rather than assumed: `Playthrough::Moment`
  builds the inventory from the records, and the records were updated BEFORE the
  narrator was called (deliberately -- see the comment above `#take_item`: a failed
  narration must leave the item taken). So the prompt carries "the player is
  carrying: the Assize tide-slate" as standing state next to a fact describing the
  transition, and the model reads the state as prior and the fact as redundant. If
  that is it, the fix is about telling the narrator what CHANGED this turn as
  distinct from what IS -- which is the same shape as `ta-arrival-diff`.

  WHY NO CHECK CATCHES IT. `item_not_held` asks whether the prose claims the player
  has something the records give to somebody else. Here the prose and the records
  agree about who holds the slate at the end of the turn; they disagree about
  whether anything happened. That is a claim about a TRANSITION, and every check in
  `Story::Audit` reads one scene against the state it was written against. A new
  check has to read the turn against the state BEFORE it -- `Scene#previous_scene`
  and the item's position then -- which is a genuinely new shape for that class.

  WHAT DONE LOOKS LIKE:

    1. The prose on a take says a take happened, and on a drop says only a drop
       happened, with a REAL verdict from `rake eval:compare` at four runs a side
       and reproduction on the held-out world.
    2. A check that would have caught it, measured for false positives on real
       prose before it ships -- the standing rule (`Story::Audit`'s header, and
       `Story::AuditPrecisionTest`). At 94% the positive cases are not scarce, so
       the measurement is cheap; the risk is all in the false-positive direction,
       because "you already hold" is a legitimate sentence on a turn where the
       player reaches for something already in hand.
    3. `Eval::Richness` does not fall REAL alongside it.

  NOT IN SCOPE: how items come to exist (`ta-item-registry`).

  ITEM 2 HAS LANDED (2026-09-03, `ta-narrator-invents-exit`), and it is the half
  that was blocking measurement rather than the half the captain feels. What
  shipped: `scenes.resolved_action` and `scenes.acted_on` -- what the turn DID,
  written by `Playthrough::Turn#play` beside `typed` -- and the two checks that
  read a narration against it, `take_denied` and `pickup_invented`. The
  transition corpus was cut out of the baseline run databases before they were
  lost (`test/fixtures/files/transition_corpus.json`, 119 real take and drop
  turns) and `rake game:score CORPUS=transitions` prints the rate. The check's
  own re-measurement of the figures above is 28 of 32 takes and 4 of 32 drops:
  the four takes it gives up deny the pickup by handing the item to a third
  person who is the player, and the drop it gives up writes "the slate" of an
  "Assize tide-slate". Zero false positives on all three existing corpora.
  ITEMS 1 AND 3 ARE STILL OPEN, and both checks are available to a scripted
  sweep, so the prose fix can now be judged the way this entry asks.

- [ ] ta-character-whereabouts - Nothing records where a character is (repo: text-adventure) (kind: scout) (priority: 2) (since 2026-09-03)
  Nothing records where a character is, so half the presence claims in the prose
  cannot be checked -- or kept.

  FOUND in the same accuracy pass. `Item` is in exactly one place at a time, held
  by somebody or lying somewhere, and that single record is what makes `take` and
  `drop` app-owned state changes rather than prose. `Character` has no equivalent:
  it `belongs_to :story` and `has_and_belongs_to_many :scenes`, and that is the
  whole answer to "where is Ammon Brace".

  SO A CHARACTER'S WHEREABOUTS ARE WHATEVER THE LAST ARRIVAL SCENE'S CAST SAID,
  and only arrival turns write a cast at all -- a `talk`, `take`, `drop` or
  `narrate` turn writes none. On the 480-turn baseline, 296 of 480 turns have a
  recorded cast; the other 184 have no record of who was in the room.

  TWO CONSEQUENCES, and the second is the one that matters.

    1. A "character not present" check is not implementable, and must not be
       built. Prose naming somebody the cast omits is measurable -- 25 of the 296
       turns with a cast do it -- but the measurement is worthless, because the
       records are not authoritative about presence. It is the same trap as
       `reached_for_nothing` on a generated run: a check that measures the harness
       rather than the game (`Eval::UNAVAILABLE_TO_A_SCRIPT`).

    2. THE GENERATED CAST QUIETLY DROPS PEOPLE THE WORLD IS ABOUT. Arriving at
       The Tide Post, `Scene::Generator` recorded a cast of the protagonist alone
       -- on all three runs checked -- in a world whose entire premise is that Neb
       Halloran is chained to that post awaiting a hearing. The narrator put him
       there ("Neb Halloran's chain clinks once as he shifts his weight"), correctly
       and unfalsifiably, and no record kept it. The world generates itself and
       what it generates is supposed to be KEPT; here the prose knows something the
       records will have forgotten by the next turn.

  THIS IS THE PEOPLE HALF OF THE NOUN REGISTRY and it overlaps `ta-narrator-memory`
  (a cast list and memory beyond one turn) and `ta-item-registry` (how nouns come
  to exist). It should be designed with them rather than bolted on: the question is
  whether a character gets a whereabouts record of its own -- the `Item` shape,
  one place at a time -- or whether scene cast becomes authoritative and every
  branch writes one.

  WHAT IT UNLOCKS, stated because it is the argument for doing it: `speak_to` as an
  arc trigger that means anything, an interaction that can refuse to happen because
  the person is not in the room, and a real `character_not_present` check. None of
  those can exist while the answer to "who is here" is regenerated from scratch on
  every arrival.

## Done
