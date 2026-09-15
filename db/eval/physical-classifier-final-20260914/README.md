# Final classifier candidate: measured and recommended for promotion

This third R02 candidate tightens conservative target matching and separates
opening a barrier from crossing it. `source/` freezes the exact measured
classifier and unchanged 343-case corpus. Its request identity is v2
`8cab930ca8f08d00`; the corpus digest is `abc2535c473693d9`.

The run measured all 343 cases four times plus one warmup: 1,373 serial calls
through `BaseAgent` to OpenRouter's pinned
`mistralai/mistral-medium-3.1`. There were no provider failures or rotations.
The study accounted $0.366033 in the cumulative ledger; provider-reported and
registry-priced usage were both $0.36545240. `readings.jsonl.gz` retains each
request, answer, actual model, latency, and call receipt.

All requests were captured first with actual staged record IDs. Against the
revised candidate, all 344 requests changed only the system instructions and
the history entry containing them. User text, schemas, and IDs were identical.
The uncompressed allowlist SHA-256 is
`74fc57a4c9fc6464e8c1011790caf2a22561f83c107598b7e8108e7f85e41908`.
The pre-send gate required exact equality and allowed one call per reading.

`matched-comparison.json` is oriented **revised candidate -> final candidate**
over the same current 343-case corpus:

| Metric | Revised median | Final median | Verdict |
| --- | ---: | ---: | --- |
| Strict accuracy | 95.16% | 95.33% | NOISE |
| Overall accuracy | 95.63% | 95.19% | NOISE |
| Intent accuracy | 98.83% | 99.13% | NOISE |
| Refusal agreement | 95.85% | 96.19% | NOISE |
| Closed-set misses | 11 | 13 | REAL worse, p=.028571 |
| Failures | 0 | 0 | NOISE |

The final instructions are more conservative. New refusals include a
misspelled present name (4/4), an index described by its columns (4/4), a stair
described by its position (3/4), and dialogue relying on recent context (six
misses across two cases). Those are player-facing failures and explain the REAL
increase in closed-set misses.

They replace known answers that could mutate the wrong record. Every dangerous
case that motivated this candidate is correct in 4/4 readings:

- an unlisted copy room stays `move -> nothing`;
- opening an already-open closet stays `use -> nothing` and does not cross it;
- an absent landlord stays `talk -> nothing`;
- an absent offered index stays `use -> nothing` instead of selecting a
  different carried item.

It also stops turning “take the seal from Rowe” into a conversation with Rowe:
all four readings retain `take -> nothing`. This tradeoff follows the standing
rule: a conservative refusal is visible and recoverable, while a substituted
record can change game state the player did not authorize.

`audit.json` is separately oriented **original main -> final candidate** over
334 unchanged labels. All six judged non-latency metrics are NOISE: strict
94.46% -> 95.18%, overall 94.61% -> 95.06%, intent 98.50% -> 99.10%, refusal
95.54% -> 96.07%, closed-set misses 12.5 -> 13, and failures 0 -> 0. Latency is
suppressed because concurrency changed from two to one. The historical339
projection's REAL intent decrease is driven by obsolete give-as-drop and
open-as-move labels; it is not the current-label comparison.

The initial and revised candidates remain frozen as evidence. This package is
the recommended classifier baseline because it closes the demonstrated
wrong-state paths without a REAL regression against the original run on the
unchanged current labels. The closed-set refusal regression against the revised
candidate must remain documented; it is an accepted safety tradeoff, not an
accuracy improvement.

The post-run immovable-item refusal is an engine-only guard. It does not change
the measured instructions or request assembly, so the frozen source hashes stay
historical rather than being rewritten. The gzip container was also rewritten
at completed export; `preflight.json` now records its final byte hash, while the
reviewed uncompressed allowlist digest above is unchanged.
