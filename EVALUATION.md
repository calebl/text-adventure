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

## The classifier bench

Everything above measures **narration**. This measures the one model call the
engine *acts* on.

`Playthrough::Classifier` runs on every turn and turns a typed line into a
branch and a record: a `move` writes `playthroughs.current_location_id`, a
`take` moves an `items` row, a `talk` picks which character prompt gets built.
Until 2026-09-04 nothing scored whether it was right. `Playthrough::Drift` and
`Playthrough::Overreach` count its misses *indirectly* and **neither knows the
answer** — a drift row is written whether the player reached for a door that is
not there or the model failed to see a door that is.

**The ruling of 2026-09-04 made that gap cost the player something.** Since
`Playthrough::Refusal` shipped, a wrong resolution is a refusal somebody reads
and a wrong `also_named` refuses a line that should have played. So:

```bash
rake eval:classifier                    # 300 labelled lines x 4 reps x 2 models, ~$0.39
rake eval:classifier_offline            # the same corpus with NO model -- free, and in CI
rake eval:classifier_omission           # the also_named omission rate alone (~30 lines)
rake eval:classifier_compare BEFORE=a AFTER=b
```

| knob | what it does |
| --- | --- |
| `REPS=4` | repetitions. **Four is the default because four is `Eval::Noise::MIN_RUNS`** — a run taken at the default can actually be judged later |
| `MODELS=a,b` | which models to ask. Defaults to `BaseAgent::REMOTE_MODEL_IDS` |
| `SET=name` | where the numbers land (`tmp/eval/<set>/classifier.json`). Defaults to a timestamp |
| `SAMPLE=20` | how many missed lines the board prints in full |
| `YES=1` | spend past the $0.50 ceiling |

### What it measures

Every figure is printed as **min..max with the median in the middle**, per
model, never pooled — the same discipline as the prose loop, and for the same
reason: the classifier runs at `TEMPERATURE = 0.0` and a provider is *still* not
deterministic.

| figure | what it is |
| --- | --- |
| `strict_accuracy` | **the headline.** The whole answer — intent *and* record — over the lines whose English admits one reading |
| `accuracy` | the same over every line, arguable ones included |
| `intent_accuracy` | the branch right, whatever record it landed on |
| `refusal_agreement` | whether the line earned the refusal `Playthrough::Refusal` gives it |
| `closed_set_misses` | **right branch, wrong record** — a count, not a rate, because it is the failure the closed enum exists to prevent |

Beside them: **accuracy per intent** (six branches with six different
consequences), a **confusion matrix**, **`also_named` precision and recall** (it
is a detector, so it has two ways to be wrong), the **omission rate**, and the
**offline floor**. Every missed line is printed with what was typed, what was
expected and what came back — the same rule `rake game:score` follows.

### The corpus

`test/fixtures/files/classifier_corpus.yml` — **300 hand-labelled lines across
11 positions in the three seeded worlds.** YAML rather than JSON like its four
siblings, because every line carries a `why` and three hundred of those in JSON
is a file nobody audits.

A line names a **position** — a seeded world, a room, and the typed lines that
get to the state the label was written against — because a classifier answer is
only meaningful next to the closed sets the model was offered. `take the apron`
resolves to a record in the supply closet and to nothing in the office.

**How the labels were verified**, which is the part worth being suspicious of:

1. **The closed sets were read off the records and printed**, not read out of
   the seed file. Every `target` and `also_named` was written against that
   printout.
2. **`Eval::Classifier::Corpus#problems` checks every name back** against the
   set the action really reads (`Playthrough::Classifier#offered_for`), and
   `Eval::Classifier::CorpusTest` fails the build if one does not fit. A label
   naming something out of reach cannot survive a commit.
3. **`refusal:` is redundant on purpose.** The three kinds are derivable from
   intent, target and `also_named` through the same predicates
   `Playthrough::Classifier::Intent#refused?` uses; the validator derives them
   and compares. Two readings of one line have to agree.
4. **What neither can check** is whether the label is the right reading of the
   English. That is the hand-verification, line by line, and `why` states it.
   **55 of the 300 lines carry `also_accept`** — a second answer the bench
   counts as correct — because their English really does admit two readings, and
   the headline rate excludes them.

Where the lines came from: **the 61 stored classifier conversations in the
captain's own database** (`chats.purpose = "classifier"`, kept since PR 97 —
what a person really typed, with the room and the sets the model was really
shown), **the 60 turns of the `rake eval:run` scripts**, and the shapes the
ruling made load-bearing and nothing yet types. `unreadable` is deliberately
absent: it is an `intent` outside the closed enum, so no typed line can provoke
it.

### Adding a corpus line

Put it under the shape it belongs to, give it a `why`, and run
`bin/rails test test/lib/eval/classifier/corpus_test.rb`. If the shape you need
is not reachable from any position, **add a position rather than stretching an
existing label**. A position may carry `setup:` (typed lines, walked offline
through the fixed grammar) and `cast:` (a whereabouts written through
`Character#move_to!` — the one thing no typed line can do, and the only way two
people in one room is reachable at all).

### The set, and comparing two of them after the fact

**The captain's instruction of 2026-09-04:** *"store every classifier bench run
as a named set with a durable scores artifact… a set should record which model
produced it, and comparing model A's set against model B's set must work from
the stored scores alone."*

Same convention as the prose loop. `SET=<name>`, defaulting to
`classifier-<timestamp>`; the durable artifact is
**`tmp/eval/<set>/classifier.json`**, beside the `scores.json` an `eval:run` set
writes. It is `classifier.json` and not `scores.json` because one set can
legitimately hold both a prose run and a bench, and two files of one name
cannot.

The file holds **every reading of every pass**, not just the rates, so a change
to how a rate is defined does not need the calls paid for again — the same rule
that keeps the prose loop's run databases. It records:

| field | why |
| --- | --- |
| `arms` | **which models the set measured.** The field the cross-model comparison pairs on |
| `answered_by` | the models that *really* answered, read back off the readings — different from `arms` when the rotation answered a line |
| `corpus_digest` | a fingerprint of the labelled lines. Two sets scored on different corpora are not comparable, and a mismatch is **warned about above the verdicts** rather than reported as a change in the model |
| `reps`, `corpus_size` | the shape of the run |

**Comparing two models** works off those files alone:

```bash
rake eval:classifier SET=arm-mistral MODELS=mistralai/mistral-medium-3.1
rake eval:classifier SET=arm-minimax MODELS=minimax/minimax-m3
rake eval:classifier_compare BEFORE=arm-mistral AFTER=arm-minimax
```

With **no model in common and one a side**, the two are paired and the board
says loudly that it is comparing two *different models* rather than two versions
of one. With models in common, each is compared against itself — the ordinary
before/after of a prompt change. With nothing in common and several a side it
**refuses rather than guessing**, and names `BEFORE_MODEL=` / `AFTER_MODEL=`;
those also pick one arm out of a two-model set on either side.

### While it runs

A bench run holds **one write transaction per pass** — a pass being one model's
one repetition of the corpus, a few minutes — against a copy of each seeded
world loaded under a title of its own and rolled back at the end. So it is safe
against a database somebody is mid-game in, exactly as `rake game:sweep` is, but
SQLite gives one writer at a time: **while a pass is open, another writing task
in the next terminal (`rake game:sweep`, a browser turn) will wait and may fail
with `database is locked`.** Run one at a time.

### The offline floor

`rake eval:classifier_offline` runs the same 300 lines through the fixed grammar
`Playthrough::Mechanics` uses with `model: false` — no key, no network, no
spend, and it runs in `bin/rails test`. **It is what a classifier call is bought
against**, and the answer is a number rather than an assumption.

Five outcomes, told apart: `resolved`, `refused` (right refusal, possibly the
wrong reason — the grammar has no refusal *kinds*), `wrong` (an answer the label
does not accept, produced silently), `over_refused` (a line it refused that
should have played) and `unparsed`.

**Measured 2026-09-04: 127 of 300 right (0.423), and 156 of the 173 failures are
over-refusals.** It gets every reach-that-finds-nothing right and *none* of the
`other` or `examine-nothing` lines — a fixed grammar has no word for an ordinary
remark, so it refuses every one.

### The `also_named` omission rate

PR 102's review finding **F4**: `also_named` is a **required** field on the
commonest model call in the app, and the worry was that a provider would send it
missing or null. Neither the resolved `Intent` nor a rate over it can tell an
omitted field from an answer of `nothing`, so the bench reads the provider's own
JSON back off `messages.content_raw` and counts.

It is reported on every bench run at no extra cost, over every call the run
already paid for. `rake eval:classifier_omission` is the targeted probe — the
~30 two-noun lines alone, for a fraction of a cent — for re-checking it on its
own.

**The claim being checked is that a truly absent field is a *failed call*:**
`BaseAgent#missing_schema_keys` rotates on it, so an omission shows up as a
rotation or a failure and never as a quiet nil.

### What it is not

**It does not tune a prompt.** A prompt fitted against the run that measured it
is a prompt fitted to 300 lines. The bench is the instrument;
`rake eval:classifier_compare` is how the next change is judged, and four
repetitions a side is the same arithmetic floor as everywhere else in this file.

There is **no held-out half**, and that is a difference from the prose loop
rather than an oversight: holding `The Salt Assizes` out is about not tuning
narration checks on prose nobody has read, and a labelled line is not prose
anybody tuned a check on. All three worlds are in the corpus.

---

## The instrument this is not: `rake game:sweep`

Everything above measures **narration**, costs money and is noisy enough to need
a rank test. The engine sweep is the other half and shares none of those
properties:

| | `rake eval:run` | `rake game:sweep` | `rake eval:classifier` |
| --- | --- | --- | --- |
| what it reads | prose, against the records | the records, after a typed line | the classifier's answer, against a label |
| what it needs | a key, the network, minutes, dollars | nothing | a key, minutes, cents |
| what it answers | a rate with a noise floor | pass or fail | a rate with a noise floor |
| in CI | never | every `bin/rails test` | its offline floor and its corpus validator, yes; the calls, never |

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
lib/eval/classifier*                 the classifier bench
test/fixtures/files/classifier_corpus.yml   the 300 labelled lines
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

`inscription_misquoted` is the most recent one through this, and it is the
worked example of a check that clears the bar on precision and admits to poor
recall: 0 flags over all 367 real passages, the captain's own narration as the
positive case, and two plausible widenings (`says` as a cue; the item's own
name) measured and killed at 7 and 3 flags of dialogue. Its stated miss is
larger than most — three live read narrations, two of which quote the record
inside quote marks, and it detected neither. See
`test/models/story/audit/inscription_test.rb`.
