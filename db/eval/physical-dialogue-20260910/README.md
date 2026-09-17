# Physical branch: kept dialogue benchmark

This completed matched study compares the unchanged `dialogue-2026-09-10`
baseline with the physical branch's current `InteractionAgent` prompt. Both
sides contain the same nine fixed fictional cases, four repetitions and two
passes per reading on pinned `mistralai/mistral-medium-3.1`. The after run kept
all 36 readings and 72 calls with no error, fallback or model rotation.

The existing `Eval::Dialogue::Result#compare` and `Eval::Noise` scorer reports
**NOISE** for every available metric. State failure is unchanged at `1/9` in
each repetition (`p=1.0`); exchange failure remains zero (`p=1.0`). Median
reaction length moves from `56.4444` to `55.1667` words (`p=0.657143`) and
median narration length from `36.0556` to `35.2222` (`p=0.685714`). Human
contradiction annotations were not supplied, so contradiction remains
**unavailable**, never zero. The exact board and verdicts are retained in
`after-board.json` and `comparison.json`.

Manual review covered every after reaction, narration, engine effect and
immediate/follow-up fact. Every case has the same action distribution as the
before arm, and no new state or agency regression was observed. The known
staying case still misses its requested outcome in all four runs: Maren refuses
to stop following because of her existing promise, then follows during the
scripted move. That is consistent motivated agency even though it is a corpus
expectation miss. The stale-gift case still has a visible prose/state mismatch
in all four runs: the engine rejects a transfer after the key has moved to the
floor, but both model passes say she hands it over. The baseline has the same
two behaviors. `manual-audit.json` keeps the exhaustive row review without
pretending it is the missing formal annotation set.

The after set is promoted as `Eval::Dialogue::BASELINE` because it guards the
current first-pass request identity, which now includes the NPC's condition,
while the matched evidence shows no measurable or manually observed new
regression. The historical before remains checked in. Offline preflight rebuilt
all 36 stored exchanges: only pass 1 changed, while pass 2 requests and replayed
engine facts stayed identical.

`receipts.json` records 36 readings, 72 settled calls, 51,091 input tokens,
6,244 output tokens and $0.03297904 at registry prices. Provider-reported cost
is partial ($0.02035784 from 36 calls). The shared helper conservatively
accounted $0.172092 for this task; the combined ledger stood at $4.085027 under
the user-approved $5 cap when the run completed. Two zero-call interruptions
remain in `dialogue.json`: the first rejected a non-isolated database, and the
second stopped at the former $4.15 reservation ceiling. `run-provenance.json`
retains hashes, execution shape and these limitations.

The payload gate's offline check passes all nine two-pass exchanges and rejects
altered user, system, schema and history data, premature narration, and
substituted answers or receipts (**6 tests / 42 assertions**). The unchanged
request guards passed **43 tests / 484 assertions**. Recheck the promoted set
without a provider call with:

```sh
bin/rails test test/lib/eval/dialogue/kept_set_test.rb
bin/rails test db/eval/physical-dialogue-20260910/payload_gate_check.rb
RAILS_ENV=test rake eval:dialogue_digest SET=physical-dialogue-20260910
```

This corpus does not independently measure durable experience across turns,
voice, personality, physical item use or general realism. It has no offered
apple path. Those limits remain part of the kept board.
