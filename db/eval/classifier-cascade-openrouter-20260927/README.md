# Cascade via OpenRouter Decisions, on the worlds with arcs

The same cascade request as `classifier-cascade-state-20260927`, with System One
answered through OpenRouter's Decisions API (`typesafe/jev-1.13`) rather than
TypeSafe direct. Arm name: `mistralai/mistral-medium-3.1+openrouter-decisions`;
four repetitions; corpus digest `027013dd5a020328`; every reading kept, each
carrying `system_one_transport: openrouter_decisions`. It replaces
`classifier-cascade-openrouter-20260919`, which stays as history.

## Verdict against the TypeSafe-direct set beside it

NOISE on every figure -- strict accuracy 0.936 -> 0.936, accuracy 0.936 ->
0.936, intent accuracy 0.974 -> 0.975, refusal agreement 0.954 -> 0.952, misses
13 -> 13. It escalates 353 lines over four repetitions against 349. The set of
2026-09-19 read `intent_accuracy` REAL worse through this transport; this pair
does not.

## Spend

The escalations to Mistral cost $0.081327, provider-reported, over 353 calls.
The Decisions requests are billed by OpenRouter and are in the credit readings
that bracket the cascade group (`doc/evidence/seed-world-arcs-rebuy/credit-readings.log`);
the account is shared, so a delta there is this run's only if nothing else was
spending.
