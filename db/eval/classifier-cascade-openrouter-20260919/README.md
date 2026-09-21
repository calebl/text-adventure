# Cascade via OpenRouter Decisions — transport parity reading

**Frozen snapshot.** `Playthrough::Classifier::Cascade` in front of
`mistralai/mistral-medium-3.1`, four repetitions, the 343 labelled lines at
corpus digest `a259e93e6b865af1`, with the System One request answered through
OpenRouter's Decisions API (`typesafe/jev-1.13`) rather than TypeSafe direct.
The request body is unchanged from the kept cascade set of record except the
model id spelling the transport requires.

Arm name: `mistralai/mistral-medium-3.1+openrouter-decisions`. Compared against
`classifier-cascade-state-20260919` (TypeSafe direct, same request identity
`v2:8fc01b135f1ed5fa`).

## Pre-registered expectation

Quoted before any number below was read:

> noise on accuracy and escalation rate with threshold-edge lines routing
> differently at about two percent.

## Verdict

| metric | kept (direct) | this set (OpenRouter) | compare |
|---|---|---|---|
| accuracy | 0.940 median | 0.936 median | WORSE, **NOISE** |
| strict_accuracy | 0.939 | 0.937 | WORSE, **NOISE** |
| intent_accuracy | 0.977 | 0.974 | WORSE, **REAL** (p=0.0286) |
| refusal_agreement | 0.957 | 0.959 | BETTER, NOISE |
| closed_set_misses | 13 | 13 | unchanged, NOISE |
| escalations / rep | 88, 87, 90, 91 | 91, 91, 88, 90 | aggregate load unchanged |
| `resolved_by` diffs | — | **20 / 1,372 (1.46%)** across 12 unique lines | ~2% threshold-edge routing |

**REAL WORSE on `intent_accuracy` is reported, not explained away.** Accuracy and
escalation rate match the noise expectation; threshold-edge routing sits at
about one and a half percent.

## Conditions

- 4 repetitions, concurrency 8, warm call excluded
- Jev pin: `typesafe/jev-1.13` via OpenRouter Decisions
- Escalation model: `mistralai/mistral-medium-3.1`
- Every reading carries `system_one_transport: openrouter_decisions`
- No new `scenes` column: transport provenance lives on the bench row beside
  `resolved_by`; typed calls leave no chat receipt

## Reproduce

```sh
MODELS=mistralai/mistral-medium-3.1+openrouter-decisions REPS=4 \
  SET=classifier-cascade-openrouter-20260919 rake eval:classifier
rake eval:classifier_compare \
  BEFORE=classifier-cascade-state-20260919 \
  AFTER=classifier-cascade-openrouter-20260919
```
