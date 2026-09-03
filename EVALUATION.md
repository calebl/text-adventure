# Measuring whether a change made the game better

> *"I'm fine with the loop being manual initially. I just want more confidence
> that changes we are making are improving results."*

This is the protocol for getting that confidence, and the first thing it has to
tell you is how easy it is to fool yourself.

**Generated runs are model output. Run the same code over the same world twice
and the numbers move.** On the sweep this was built with, one unchanged
configuration produced between **1 and 8** `third_person_protagonist` flags on
the same eleven turns of the same world. That is wider than almost any
improvement anybody is going to claim. So no number in this loop is reported
without the spread of the runs that produced it, and no before/after is reported
without a verdict that can say *noise*.

---

## The one command

```bash
rake eval:run                 # generate across the three seeded worlds, then print a board
```

Defaults to 5 repetitions of each world's script — 15 runs, about 165 turns,
**roughly $0.22**. It prints the estimate before it spends anything and the
actual figure on the board afterwards. It refuses to start without
`OPENROUTER_API_KEY`, and it aborts rather than spend more than $1.00 unattended
(`YES=1` overrides).

| knob | what it does |
| --- | --- |
| `REPS=8` | repetitions per world. **Four is the minimum for a verdict** — see the rule below |
| `TURNS=4` | stop each run after n turns. Cheap smoke test |
| `STORIES="The Salt Assizes"` | one world instead of three |
| `SET=main` | name the run set. Defaults to a timestamp |
| `EVAL_MODEL=…` | pin a different model. Defaults to the app's own first choice |
| `SAMPLE=60` | how many flagged turns the board prints in full |
| `EVAL_RUN_TIMEOUT=1200` | seconds one run may take before it is killed. A killed run leaves no manifest and is simply absent from the scoring |
| `CONCURRENCY=3` | runs in flight at once. One per world by default |

Everything else is free and offline:

```bash
rake eval:score SET=main      # score a set again -- no model call, no key, no network
rake eval:compare BEFORE=main AFTER=my-branch
rake eval:null SET=main       # split one set in half; everything should read NOISE
rake eval:estimate REPS=8     # what a sweep of that shape would cost
rake eval:manifest            # the measurement files, with a digest of each
```

The run databases live under `tmp/eval/<set>/runs/`. They are not checked in and
they are large; `scores.json` beside them is the durable artifact, and
`eval:compare` reads only that, so a set can be compared long after its
databases are gone.

---

## The before/after protocol

This is the thing to actually use on a change.

```bash
git switch main
rake eval:run SET=before REPS=8         # ~$0.35

git switch my-branch
rake eval:run SET=after  REPS=8         # ~$0.35

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
   another process start.
2. **More repetitions.** Linear in money and the only thing that improves the
   test's resolution.
3. **Pinning the model**, which the runner already does — a turn answered after
   a rotation is a different measurement.

Temperature is deliberately **not** on that list. The sweep has to measure the
game a player gets; a run at a temperature the app never uses is a measurement
of a different app.

---

## What is measured

Eight checks, all of them from `Story::Audit`, all offline and deterministic.
Four categories that are never merged — see `AGENTS.md` → *Auditing the
difference*. Each one counts an error that is objectively present or absent and
each was measured for false positives on real prose before it shipped.

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
   `narration_corpus.json` (24) and `whole_run_corpus.json` (132 whole-run
   narrations with the records around them).
3. **A demonstrated positive case.** A check that cannot fire looks exactly like
   a clean result, which is worse than no check. If the real corpora contain no
   violation, take a real sentence and move the record underneath it —
   `Story::Audit::ArrivalTest` is the worked example.
4. **A stated miss.** Every check here says where it knowingly gives up recall
   for precision.

A check that cannot be made precise is reported **unavailable**, never shipped
loose.
