# Measuring whether a change made the game better

> *"I'm fine with the loop being manual initially. I just want more confidence
> that changes we are making are improving results."*

This is the protocol for getting that confidence, and the first thing it has to
tell you is how easy it is to fool yourself.

**Generated runs are model output. Run the same code over the same world twice
and the numbers move.** On the baseline this was built with, one unchanged
configuration produced between **1 and 13** `third_person_protagonist` flags on
the same twenty turns of the same world — a rate of 0.050 on one run and 0.650
on another, with nothing at all changed between them. That is wider than almost
any improvement anybody is going to claim. So no number in this loop is reported
without the spread of the runs that produced it, and no before/after is reported
without a verdict that can say *noise*.

---

## The one command

```bash
rake eval:run                 # generate across the three seeded worlds, then print a board
```

Defaults to 5 repetitions of each world's 20-turn script — 15 runs, 300 turns,
**roughly $0.39**. It prints the estimate before it spends anything and the
actual figure on the board afterwards. It refuses to start without
`OPENROUTER_API_KEY`, and it aborts rather than spend more than $1.00 unattended
(`YES=1` overrides).

| knob | what it does |
| --- | --- |
| `REPS=8` | repetitions per world. **Four is the minimum for a verdict** — see the rule below |
| `TURNS=4` | stop each run after n turns. Cheap smoke test |
| `EVAL_MODEL=…` | pin a different model (see below) |
| `STORIES="The Salt Assizes"` | one world instead of three |
| `SET=main` | name the run set. Defaults to a timestamp |
| `SAMPLE=60` | how many flagged turns the board prints in full |
| `EVAL_RUN_TIMEOUT=1200` | seconds one run may take before it is killed. A killed run leaves no manifest and is simply absent from the scoring |
| `CONCURRENCY=3` | runs in flight at once. One per world by default |

Everything else is free and offline:

```bash
rake eval:score SET=main      # score a set again -- no model call, no key, no network
rake 'eval:read[The Salt Assizes,1]'   # one whole run as prose, every turn, flagged or not
rake eval:compare BEFORE=main AFTER=my-branch
rake eval:null SET=main       # split one set in half; everything should read NOISE
rake eval:estimate REPS=8     # what a sweep of that shape would cost
rake eval:manifest            # the measurement files, with a digest of each
```

The run databases live under `tmp/eval/<set>/runs/`. They are not checked in and
they are large; `scores.json` beside them is the durable artifact, and
`eval:compare` reads only that, so a set can be compared long after its
databases are gone.


### Reading a run, when a board looks too clean

The board prints what a check **caught** — that is the point of it. When you want
the opposite, `rake eval:read` prints one whole run as prose: every turn in
order, what was typed, the passage the player would have read, and a mark
against any turn a check flagged.

```bash
rake 'eval:read[The Salt Assizes,1]' SET=main
```

**A turn with no mark is a turn every check passed.** Those are the ones to read
when a rate of zero looks suspicious: a clean board is only worth something if
the turns behind it hold up. The seeded worlds are also playable in the browser
(`bin/dev`), which is the other way to check the same thing.

---

## The before/after protocol

This is the thing to actually use on a change.

```bash
git switch main
rake eval:run SET=before REPS=8         # ~$0.63

git switch my-branch
rake eval:run SET=after  REPS=8         # ~$0.63

rake eval:compare BEFORE=before AFTER=after
```

Read the output in this order:

1. **Was the change real?** Per check, per corpus: `REAL`, `NOISE` or
   `INCONCLUSIVE`.
2. **What did it cost?** The `RICHNESS` row, directly underneath. A check that
   improved for real while richness fell for real is a warning printed in words,
   because that trade has to be taken on purpose.
3. **Did it hold on the world it was not tuned on?** The held-out corpus is
   printed separately and never pooled.

### The rule, and why it is this rule

A check is **REAL** when a two-sided exact rank test on the per-run rates
separates the two sets at p ≤ 0.05. **NOISE** when it does not and the
difference is no larger than the spread the unchanged runs already produced.
**INCONCLUSIVE** otherwise — in practice, almost always *not enough runs*.

The test is a permutation test on ranks rather than a t-test because flag counts
per run are small integers, frequently zero, and nothing about them is normal.
It asks: of all the ways these runs could have been split between "before" and
"after", how many separate at least this well?

**Four runs a side is the floor, and it is arithmetic rather than taste:**

| runs a side | arrangements | smallest p the test can return |
| --- | --- | --- |
| 3 | 20 | 0.100 — **above 0.05, so no verdict is reachable** |
| 4 | 70 | 0.029 |
| 5 | 252 | 0.008 |

At three a side, a *perfect* separation — every run of one set worse than every
run of the other — still cannot clear 0.05. Reporting anything but
`INCONCLUSIVE` there would be reporting the sample size as a result.

`rake eval:null` is the self-check: it splits one set's runs in half and compares
them. Both halves are the same code over the same worlds, so **any `REAL` there
is the protocol manufacturing a result**. Run it whenever the rule changes.

### What reduces the noise, in the order worth reaching for

1. **More turns per run.** The cheapest: it enlarges the denominator without
   another process start. The scripts went from 11 turns to 20 on 2026-09-03 for
   exactly this reason, and **it worked on one world and not on another** — The
   Unrecorded Hour's band more than halved (0.455 wide to 0.200) while The Lunar
   Cartographer's widened (0.455 to 0.600), because one of its eight runs turned
   in a single flag where its siblings turned in six to thirteen. A bigger
   denominator steadies a rate that is already stable; it does not stop a run
   wandering off on its own. What the extra turns did buy outright is the
   held-out world, which at eleven turns never fired the check at all.
2. **More repetitions.** Linear in money and the only thing that improves the
   test's resolution. **Prompt caching does not make them cheaper and was
   measured, not assumed**: OpenRouter caches automatically for the pinned model,
   but the minimum cacheable prompt is 2,048 tokens and this app's calls average
   615, so eighteen real prompts replayed back to back read zero cached tokens.
   Even a perfect cache would only take a $0.47 sweep to $0.36. See the header of
   `Eval::Cost` and `script/cache_probe.rb`.
3. **Pinning the model**, which the runner already does — a turn answered after
   a rotation is a different measurement.

Temperature is deliberately **not** on that list. The sweep has to measure the
game a player gets; a run at a temperature the app never uses is a measurement
of a different app.

---

## What the checks miss, and how that was found

Every check on the board is measured for false positives before it ships. **None
of them is measured for recall, and there is no way to measure it** — the errors
a check does not name are not enumerable. The substitute is reading a run: pick a
run the board scored **clean** and read it end to end against the records, since
that is where a missed defect hides. `rake eval:read SET=… STORY=… REP=…` prints
one for exactly this.

One pass over a zero-flag run of the held-out world, on 2026-09-03, found two
defects that every check passed:

1. **The narration denies the `take` and invents the pickup on the `drop`** — 30
   of 32 and 5 of 32 turns across the whole 480-turn baseline. It is invisible
   because every check reads one scene against the state it was written against,
   and this is a claim about a **transition**: the prose and the records agree
   about who holds the thing and disagree about whether anything happened.
2. **The generated arrival cast drops characters the world is about**, and
   nothing can contradict it, because no record says where a character is.

Both are in ROADMAP's *Known issues* with the figures, and both are queued. The
lesson for anybody adding a check: **a board of zeroes is a claim about the
checks, not about the game.** One read of one clean run cost twenty minutes and
found a defect on 94% of a mechanic the app owns.

---

## The instrument this is not: `rake game:sweep`

Everything above measures **narration**, costs money and is noisy enough to need
a rank test. The engine sweep is the other half and shares none of those
properties:

| | `rake eval:run` | `rake game:sweep` |
| --- | --- | --- |
| what it reads | prose, against the records | the records, after a typed line |
| what it needs | a key, the network, minutes, dollars | nothing |
| what it answers | a rate with a noise floor | pass or fail |
| in CI | never | every `bin/rails test` |

It plays stored scripts through `Playthrough::Mechanics` with **no model at all**
— the classifier off, the fixed grammar in front of the engine, and
`BaseAgent.new` replaced for the length of the run so a call from anywhere raises
rather than reaching a provider. Each script loads its own copy of a seeded world
and rolls it back, so it can be run against a database somebody is mid-game in.

**It asserts; it does not measure.** There is no rate, no baseline and no
comparison, because there is no sampling: two runs of a script are identical to
the row. A change to movement, to exits, to item possession or to what the
grammar refuses either keeps the scripts green or does not.

Both instruments walk the same three seeded worlds, and `The Salt Assizes` being
held out does not apply here: holding it out is about not tuning narration checks
on prose nobody has read, and the sweep reads no prose. See README → *Sweep the
engine*.

---

## What is measured

Ten checks, all of them from `Story::Audit`, all offline and deterministic.
Four categories that are never merged — see `AGENTS.md` → *Auditing the
difference*. Each one counts an error that is objectively present or absent and
each was measured for false positives on real prose before it shipped.

**Two of them read a change rather than a state**, which is new and is the
reason the board's recall was poor before. `take_denied` and `pickup_invented`
read a narration against `Scene#resolved_action` and `Scene#acted_on` — what
the turn DID, written by `Playthrough::Turn#play` beside the typed line. The
app owns `take` and `drop` outright, so on a turn recorded as one of them the
state *before* the turn is not in question either, and the prose is the only
loose half. They are the first two checks that are fully available to a sweep
**and** fully available offline: a script's fixed line has no bearing on what
the narrator does with a fact it was handed, so they are deliberately not in
`Eval::UNAVAILABLE_TO_A_SCRIPT`.

**Richness is reported beside them and never folded in.** It counts what the
prose committed to: the room, the exits, the items and the people the records
know, named in the passage. It exists because the cheapest way to stop the
narrator contradicting the records is to make it say less — vague prose asserts
nothing, so it cannot be wrong. A change that buys a lower contradiction rate
with blander prose has to show up as a loss somewhere, and this is where. It is
**not** a quality score, and it is gameable on its own: read it only as a
counterweight. `Eval::Richness` has the measurement and the one normalisation
that was tried and thrown out.

---

## The held-out world

`The Salt Assizes` is played by every sweep and used to tune nothing.

Every check in `Story::Audit` was measured against passages from the other two
worlds — `narration_corpus.json` and `eval_corpus.json` are drawn from them — so
the held-out world is prose no check has ever seen. A rate that holds up on it is
a rate that did not come from fitting the passages.

**This is a documented convention, not enforced machinery.** The rule:

- Tune on `Eval::TUNING`. Report on `Eval::HELD_OUT`.
- Do not read a held-out passage while changing a check.
- Do not add a held-out passage to a fixture.

`Eval::Board` prints the two corpora apart and labels them, so an accidental
pooling is visible in the output. When an agent is driving this loop rather than
a person, that convention needs teeth; today it does not have them.

---

## The transition corpus

`test/fixtures/files/transition_corpus.json` is 119 turns that the classifier
resolved to a `take` or a `drop`, cut out of the `rake eval:run` databases on
this machine on 2026-09-03 before they were lost. `Story::Scoreboard::Transitions`
scores it and `rake game:score CORPUS=transitions` prints it.

Each row carries the typed line, the resolved action, the item, **where that
item was before the turn and after it**, the closed set the classifier was
offered, and the prose. The action was recovered offline from the classifier's
own stored answer (`messages.content_raw`, kept by default since PR 97) and
confirmed against that same prompt's list — no generation, no spend. The
position before and after needs no item history: `take` resolves against what
is lying in the room and `drop` against what the player is carrying, so the
action itself says where the row was.

**The set `main20` is the 24-run, 480-turn baseline** the manual read of that
day was done against; it carries exactly 32 takes and 32 drops, and every
headline figure is quoted for it:

| | flagged | of | rate |
| --- | --- | --- | --- |
| `take_denied` | 28 | 32 | 87.5% |
| `pickup_invented` | 4 | 32 | 12.5% |

**Two things about this corpus are worse than the others and are stated rather
than hidden.**

- **It contains held-out passages.** `The Salt Assizes` is `Eval::HELD_OUT` and
  the convention above says not to add its passages to a fixture. It is in here
  because the run databases were about to be lost and freezing half of them
  would have thrown away half the evidence for nothing. The consequence is
  uneven: `take_denied` has positives in both worlds and an independent
  confirmation in `whole_run_corpus.json` (six real detections in the tuning
  world, every one on a turn that corpus records as a `take`), while
  `pickup_invented` has flags **only** in the held-out world. Its tuning-world
  evidence is that the grammar fires on real tuning prose — the two lab
  narrations of "burn the daybook in the grate" — plus a constructed positive
  case, not an independent rate.
- **It is two worlds and two items.** Every row argues about the "Assize
  tide-slate" or the "Ward Office 12 daybook", because those are the only items
  any seeded world has (`Item` rows are created in one place in the whole app,
  the seed loader — see `ta-item-registry`). A rate here is a rate over a lot of
  runs of a little prose.

---

## The measurement, and what an improving agent may not touch

`rake eval:manifest` prints the files that constitute the measurement, with a
digest of each. An agent set loose on improving the baseline changes the **game**
and none of these:

```
app/models/story/audit.rb            the checks
app/models/story/audit/prose.rb      what can be read out of a passage
app/models/story/scoreboard*.rb      the rates and the frozen corpus
lib/eval/**                          generation, scoring, noise, richness, cost
lib/tasks/eval.rake                  the commands
script/eval_run.rb                   the harness
db/eval_baseline.json                the line the next run moves against
test/fixtures/files/*_corpus.json    the passages the checks were measured on
```

Snapshot the digests before a change and again after: nothing in the list may
have moved. This is **declared, not enforced** — there is no hook and no lock.
It is here so that the skill which eventually drives this loop can say "these are
off-limits" without somebody having to work out which they are.

---

## Adding a check

The same bar every existing check cleared, and PR 99 killed five plausible
candidates against it:

1. **A complaint behind it.** Every check here answers an error the captain named
   while playing, in his own words.
2. **A measured false-positive rate on real prose**, in a test, not in a commit
   message. The corpora are `eval_corpus.json` (92 passages),
   `narration_corpus.json` (24), `whole_run_corpus.json` (132 whole-run
   narrations with the records around them) and — for a check that reads a
   change — `transition_corpus.json` (119 real `take` and `drop` turns with the
   transition each one made frozen beside the prose).
3. **A demonstrated positive case.** A check that cannot fire looks exactly like
   a clean result, which is worse than no check. If the real corpora contain no
   violation, take a real sentence and move the record underneath it —
   `Story::Audit::ArrivalTest` is the worked example.
4. **A stated miss.** Every check here says where it knowingly gives up recall
   for precision.

A check that cannot be made precise is reported **unavailable**, never shipped
loose.
