# Arrival evaluation: fixed protocol before observing live responses

The same three fictional cases run four times per arm against the original frozen source and the proposed candidate. Model: OpenRouter mistralai/mistral-medium-3.1. Shared ceiling with the NPC evaluation: $3. Store all emitted inputs, responses, failures, model IDs and usage. Do not replace failed attempts silently or alter existing corpora/scorers.

Primary readings, judged against the fixture records rather than style:

- Contradiction: dead_resident fails if Maren acts, speaks or is otherwise currently alive; carried_key fails if the brass key is still on the desk/floor or newly picked up; crossing_harm fails if the player is explicitly unharmed or the recorded crossing injury is undone. Silence is not itself a contradiction.
- Required fact acknowledged: dead_resident requires Maren's death/body; carried_key requires the key already in the player's possession; crossing_harm requires an injury or pain tied to the wet crossing/stairs. Exact damage/HP numbers are optional. Failure to obtain usable narration is a failure for this metric.
- Completeness and contradiction are separate: prose that avoids all specific facts may pass contradiction but fails acknowledgment. Record ambiguous cases explicitly, with the relevant passage and reasoning.

Secondary readings: request failure rate, prose word count, latency and provider-reported cost. Word count is descriptive, not proof of narrative quality. Read every response, preferably with arm hidden when annotating; retain all annotations. Use the existing Eval::Noise implementation over per-repetition rates (three cases each), with four repetitions per arm and REAL / NOISE / INCONCLUSIVE verdicts. Inspect every case, not just the aggregate. This is a focused mechanism evaluation, not evidence for general long-term character realism.
