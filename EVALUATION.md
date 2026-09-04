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
| `MODELS=a,b` | **the arm selector.** Names exactly which models the run measures; the app's rotation is not consulted. A bare id is OpenRouter, `ollama:qwen3:8b` names the provider. Defaults to `BaseAgent::REMOTE_MODEL_IDS`, which is what a player gets |
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
| `latency_median` | seconds the median call took. What a turn usually costs the player |
| `latency_p95` | seconds the worst call in twenty took. On a local model this is not the same number |
| `failures` | calls that failed outright. **A slow arm and a flaky arm read differently**, so this is printed beside the latency and compared with it |

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

### Speed, and the arm selector

**An arm is one model with nothing behind it.** `MODELS=` names it —
`mistralai/mistral-medium-3.1`, or `ollama:qwen3:8b` for one of the captain's
local models — and `Eval::Classifier::Arm#pinned` replaces
`BaseAgent.default_model_options` for the length of that arm's passes. Nothing
in `app/` changes: `REMOTE_MODEL_IDS` is untouched, `OPENROUTER_MODEL` is not
read, and `TA_LOCAL_MODELS` still defaults to off — it gates the *app's*
rotation, and an arm **replaces** the rotation rather than joining it.

A local spec may carry a **`+nothink`** suffix, which is the one thing an arm
changes about the request itself and the reason it is spelled out in the label:
see *A local model, and the reasoning block in front of the answer* below.

**The rotation being off is the point, not a side effect.** `BaseAgent#ask`
retries only while `attempts < @model_options.count`, so an arm of one never
retries. Three things follow, all of them wanted in a measurement:

- **No cross-contamination.** The first remote baseline pinned with
  `OPENROUTER_MODEL` and left the rotation behind it; one run had
  `minimax/minimax-m3` fail **223 of 1,200** calls, so mistral answered them and
  the board had to declare the arm impure. With an arm of one that cannot
  happen — and `rotations` survives as a *guard* that says **THE PINNING
  FAILED** if it is ever non-zero.
- **Clean latency.** A retried call's wall clock is the failed attempt plus the
  one that worked.
- **Flakiness is a failure count with its error classes**, which says *why* — a
  local model that will not honour a schema fails differently from a provider
  that timed out.

Latency is `CLOCK_MONOTONIC` (a wall clock can step backwards under NTP, and a
negative latency is unreadable), taken around the whole `#classify` — the schema
build and the resolution back to records included, both microseconds beside a
round trip. **A failed call carries no latency**, deliberately: how long it took
to fail is a fact about the failure.

### Cold start, and why the latencies are warm-cache figures

A local model pays a load cost of seconds to tens of seconds on its first call,
and **ollama unloads it again after about five minutes idle** and may evict one
when another is loaded. So:

- **Every arm gets one warm call before its first pass**, timed and reported as
  `first call`, and **excluded from the median and the p95.** For a local model
  that number is mostly the model being read into memory; for a hosted one it
  makes the first-call outlier visible as its own figure instead of hidden in
  the band.
- **Repetitions run contiguously and models are never interleaved** — the loop
  is arms outside, reps inside — so a local model answers the whole corpus four
  times over without another model being loaded in between.
- **`Arm#keep_resident!` pins it for 45 minutes through the daemon's own
  `/api/generate`**, out of band, so the app's calls stay ordinary calls.
  `RubyLLM::Chat#with_params` would carry `keep_alive`, but `BaseAgent` does not
  expose it and reaching through `agent.chat` to set a provider parameter would
  be the instrument reconfiguring the app's own call. Whether the daemon
  accepted is printed (`resident` / `refused` / `unreachable`).
- **The cold start is reported and never judged.** It is one observation per arm
  per set, and `Eval::Noise` needs `MIN_RUNS` of anything before it will speak.

So **every latency on the board is a warm-cache figure**, and the board says so
in its own header.

### A local model, and the reasoning block in front of the answer

**There is no local bench set, on the captain's direction of 2026-09-04: this
machine is not powerful enough to run one.** What is below is a handful of spot
single-call measurements and the machinery that makes the run possible later on
hardware that can carry it. Read every figure here as one call, not as a bench
result — a bench result is four repetitions of 300 lines with a band, and none
was taken.

Two things had to be measured before a local arm would have been a measurement
of the classifier at all, and they are worth keeping written down because they
are what a later run on better hardware needs to know.

**The machine is CPU-only.** `/api/ps` reports `size_vram: 0` for every loaded
model, so every figure below is a CPU figure and none of them transfers to a
box with a working GPU driver. It has 19 GB of RAM, and one 6 GB model resident
beside a running pass put it into swap.

**And a thinking model thinks before it answers, even under a schema.** RubyLLM
reaches ollama through its **OpenAI-compatible** endpoint —
`config.ollama_api_base` ends in `/v1` — which returns the reasoning in a field
of its own beside the answer. The schema constrains the *content*; the thinking
happens in front of it. Warm `qwen3:4b`, the app's own prompt and schema, one
call each:

| request says | wall clock | |
| --- | --- | --- |
| nothing | 100.2s | a `reasoning` field comes back beside 23 tokens of answer |
| `think: false` | 100.7s | **ignored** — an ollama-native field, and `/v1` is not it |
| `chat_template_kwargs: {enable_thinking: false}` | 100.0s | **ignored** |
| `reasoning_effort: "low"` | 100.2s | honoured, and low is not none |
| `reasoning_effort: "none"` | **2.1s** | no reasoning field, same correct answer |

So it is **`reasoning_effort`, a standard OpenAI field**, and not ollama's own
`think`. A 48-fold difference on the one call a player waits for, and the same
23 tokens of answer either way. (For the record, the native `/api/chat` endpoint
with `format:` and `think: false` answers the same call in 1.95s. The app does
not speak it, so neither does the bench — an instrument reaching past the app's
own client would be measuring a different client.)

**How the bench asks.** A spec may carry a `+nothink` suffix —
`MODELS=ollama:qwen3:4b+nothink` — and that arm, and only that arm, gets
`reasoning_effort: "none"`. It reaches the call through
`BaseAgent.default_provider_params`, **a seam that is empty in every shipped
path** and pinned empty by `BaseAgent::ProviderParamsTest`: an ordinary agent's
chat is never handed `with_params` at all. `Arm#pinned` replaces it for the
length of one pass and restores it in an `ensure`, exactly as it does the model
options. It is refused for a hosted arm.

**It is never inferred, and the app as shipped would run qwen3 with thinking
ON.** An arm that does not ask measures the model the way this app would really
use it, which is the 100-second figure — and *that is the finding*, not a
footnote to it. Making the app fast on ollama is a change to the app, to be
decided on its own evidence; the seam is a measurement asking a question. Two
arms of one model with the thinking on and off are two rows on the board.

**The spot figures, all warm, all one call each.** Stated as what they are:

| model | one warm call | |
| --- | --- | --- |
| `qwen3:4b` no thinking | **3.0s** | and >120s with thinking on |
| `qwen3:8b` no thinking | **7.2s** | cold load 60.9s |
| `gemma3:12b` | **no answer in 600s** | cold and warm alike; it has no thinking mode to turn off, so there is nothing to try next |

`gemma3:12b` is recorded as **unmeasurable on this machine** rather than as a bad
score, and the other two are recorded as unmeasured rather than as absent. The
arm selector, the latency machinery and the seam are all in and green, so
`MODELS=ollama:qwen3:4b+nothink REPS=4` is one command away on a machine that
can carry it.

### The baseline of 2026-09-04 — four hosted models, 4,800 calls

**These three sets are checked in**, under `db/eval/`, and this table is printed
from them: `rake eval:classifier_board` with no arguments reads them on any
machine, with no key, no network and no database. So the table below and the
files agree by construction, and a later run can be given a real REAL / NOISE
verdict against today's numbers rather than against a paragraph.

```bash
rake eval:classifier_board                              # today's baseline, from db/eval
rake eval:classifier SET=after-a-prompt-change          # your run, into tmp/eval
rake eval:classifier_compare BEFORE=classifier-remote AFTER=after-a-prompt-change \
    BEFORE_MODEL=mistralai/mistral-medium-3.1 AFTER_MODEL=mistralai/mistral-medium-3.1
```

Three sets, printed as one table by `rake eval:classifier_board`. 300 lines × 4
reps an arm; every rate `min..max (median)` across repetitions, never pooled. A
single number means the four repetitions agreed exactly.

| figure | `mistral-medium-3.1` | `minimax-m3` | `mistral-small-3.2-24b` | `gemini-2.5-flash-lite` |
| --- | --- | --- | --- | --- |
| set | `classifier-remote` | `classifier-remote` | `classifier-mistral-small` | `classifier-gemini-flash-lite` |
| `strict_accuracy` | **0.939..0.951 (0.947)** | 0.905..0.938 (0.918) | 0.872..0.877 (0.875) | 0.898 |
| `accuracy` | **0.943..0.953 (0.950)** | 0.906..0.936 (0.918) | 0.857..0.866 (0.861) | 0.913 |
| `intent_accuracy` | **0.980..0.983 (0.980)** | 0.966..0.977 (0.973) | 0.962..0.973 (0.967) | 0.950 |
| `refusal_agreement` | **0.951..0.959 (0.955)** | 0.946..0.971 (0.949) | 0.893..0.902 (0.896) | 0.931 |
| `closed_set_misses` | **8..11 (9.5)** | 11..18 (17) | 30..32 (30.5) | 11 |
| `also_named` precision | **1.000** | 0.788 | 0.553 | **1.000** |
| `also_named` recall | 0.888 | 0.897 | **0.948** | 0.862 |
| omission rate | **0.000** | **0.000** | **0.000** | **0.000** |
| latency median (warm) | 0.61s | **0.44s** | 0.92s | 0.53s |
| latency p95 (warm) | 0.88s | 1.83s | 3.23s | **0.64s** |
| cost per 1,000 calls | $0.19 | $0.14 | **$0.03** | $0.05 |
| failed calls | **0** | 1..3 (1.5) | 1..24 (7) | **0** |
| rotations | 0 of 1200 | 0 of 1200 | 0 of 1200 | 0 of 1200 |

**`also_named` is a precision/recall trade and the four sit all over it.**
`mistral-medium` and `gemini-flash-lite` miss a second name (the engine plays
half a line); `minimax` invents one 28 times in 132; `mistral-small` invents one
**89 times in 199**, and since the ruling of 2026-09-04 each of those is a
refusal the player reads for no reason. The shipped first model gets the safe
direction.

**Read `latency_p95` beside `latency_median`, because they do not rank the same
way.** `minimax-m3` has the fastest median of the four and the second-worst p95:
one line in twenty costs four times the typical line. `gemini-flash-lite` is the
only arm whose p95 stays inside a second.

**`gemini-2.5-flash-lite` returned the identical figure on all four
repetitions** — 274 of 300, 11 closed-set misses, every time. A band of zero,
which makes it the most sensitive arm a later prompt change could be judged
against: any movement at all is movement.

**The cheapest arm is not cheap.** `mistral-small-3.2` costs a sixth of
`mistral-medium` and returns **three times the closed-set misses**, on the one
call whose answer moves a row.

**Failures are stated, never hidden, and the flakiness ranking is not the
accuracy ranking.** `minimax-m3` is the only arm that failed the SCHEMA (7 of
1,200 `BaseAgent::SchemaIgnoredError`; an earlier run of this same bench had
**223 of 1,200**). `mistral-small-3.2` failed 39 of 1,200 and none of them on
schema — 27 rate-limit, 12 transport, 24 of them inside one repetition, which is
why its own band on `failures` is 1..24. An arm of one cannot retry, so every
one of those is a counted, attributed failure rather than a call some other
model quietly answered.

**Reproducibility, incidentally.** `classifier-remote` re-measured
`mistral-medium-3.1` on a different day and a different base from the first
1,200-call baseline: 0.939..0.943 (0.941) then, 0.939..0.951 (0.947) now.
Overlapping bands, independent runs.

### The set, and comparing two of them after the fact

**The captain's instruction of 2026-09-04:** *"store every classifier bench run
as a named set with a durable scores artifact… a set should record which model
produced it, and comparing model A's set against model B's set must work from
the stored scores alone."*

Same convention as the prose loop. `SET=<name>`, defaulting to
`classifier-<timestamp>`; the durable artifact is
**`tmp/eval/<set>/classifier.json`**, beside the `scores.json` an `eval:run` set
writes.

**Two places a set is read from, in this order:** `tmp/eval/<set>` first, then
**`db/eval/<set>`** — the checked-in baseline. A run you just paid for therefore
wins over one the repo ships under the same name, which is the less surprising of
the two possible surprises; nothing writes to `db/eval` except a person deciding
to keep a set. `Eval.set_path` is the one place that order lives, and
`Eval::Classifier::KeptSetsTest` pins it.

**A kept set is a SUMMARY, and that is deliberate.** A whole set is 1.1 MB a
model because it keeps every reading — right for `tmp/eval`, where a rate can be
redefined and recomputed without paying for the calls again, and wrong for a file
in the repo. `Result#summary` drops the rows and keeps every pass's figures plus
the four `also_named` counts and the answered count, which is exactly what
`eval:classifier_board` and `eval:classifier_compare` read: **12 KB for the whole
baseline against 4.4 MB, rendering a byte-identical table.** What it gives up is
stated rather than discovered later — the MISSED list, the per-shape and
per-intent breakdowns, and any figure not already computed. Those live in the
run's own output.

```bash
# keeping a set, which is a decision and not a side effect of running one
bin/rails runner 'Eval::Classifier::Result.load(Eval.root.join("my-set")) \
  .summary.write!(Eval.kept_root.join("my-set"), name: "my-set")'
``` It is `classifier.json` and not `scores.json` because one set can
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

**Every set on disk as one table** — the cross-model comparison the captain
asked for, and the check on this whole convention, because it reads
`tmp/eval/<set>/classifier.json` and nothing else. No database, no key, no
corpus:

```bash
rake eval:classifier_board                      # every set it can find
rake eval:classifier_board SETS=arm-mistral,arm-minimax
```

One column per **arm**, not per set: the hosted pair is measured in one run and
a local model needs a set to itself (its repetitions have to be contiguous). It
prints in markdown, because a cross-model table is read in a PR body rather than
a terminal, and it **gives no verdicts** — a band is printed and overlapping
bands are visible, but REAL / NOISE / INCONCLUSIVE is `Eval::Noise`'s to say,
two arms at a time, with the digests checked. A figure a set never recorded
reads **`not recorded`** and never as a zero; the first baseline predates the
latency machinery, and a table that printed `0.00s` for it would have invented a
fast model out of a missing field.

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
