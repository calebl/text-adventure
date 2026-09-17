# Revised classifier confirmation: measured, not promoted

This package preserves the second R02 classifier candidate. It followed the
initial candidate's REAL intent regression on the 334 labels that did not
change. The revised instructions choose intent before resolving a target,
limit physical tokens to `use`, require the attempted action and named objects
to match, and preserve reading/examine and putting down/drop behavior.

The run measured all 343 cases four times plus one warmup: 1,373 calls through
`BaseAgent` to OpenRouter's pinned `mistralai/mistral-medium-3.1`, with
concurrency two. There were no provider failures or rotations. The study
accounted $0.296616 in the cumulative ledger; provider-reported and
registry-priced usage were both $0.29597864. `readings.jsonl.gz` retains each
request, answer, actual model, latency, and call receipt.

Before buying, all 343 requests and the warmup were captured with actual staged
record IDs. Against the initial candidate, all 344 requests changed only the
system instructions and the history entry containing them. User text, schemas,
and record IDs were identical. The uncompressed allowlist SHA-256 is
`8079c34a0038bdca030f8d19969eb31a5299196df13caea514c45f8d45ba1df0`.
The pre-send gate required exact equality and allowed one call per reading.

`matched-comparison.json` is oriented **initial candidate -> revised
candidate** over the same current 343-case corpus. The ordinary exact rank test
reported:

| Metric | Initial median | Revised median | Verdict |
| --- | ---: | ---: | --- |
| Strict accuracy | 93.60% | 95.16% | REAL better, p=.028571 |
| Overall accuracy | 93.88% | 95.63% | REAL better, p=.028571 |
| Intent accuracy | 96.94% | 98.83% | REAL better, p=.028571 |
| Refusal agreement | 95.16% | 95.85% | NOISE |
| Closed-set misses | 10 | 11 | NOISE |

`audit.json` separately compares the original main result with this candidate
after excluding the same five amended labels on both sides. It is oriented
**original main -> revised candidate** over 334 unchanged cases. Strict,
overall, and intent accuracy are REAL better (p=.028571 each): 94.46% ->
95.71%, 94.61% -> 96.11%, and 98.50% -> 99.10%. Refusal agreement is
inconclusive, closed-set misses are noise, and there are no failures. Latency is
comparable here because both sides used concurrency two; it became REAL slower.

The aggregate recovery did not make this candidate safe enough to promote.
Four dangerous substitutions remained:

- an unlisted copy room became the current Ward Office in 4/4 readings;
- opening the closet became movement into it in 4/4;
- an absent landlord became Ammon Brace in 4/4;
- an absent offered index became the carried daybook in 2/4.

Those answers are within the schema enum, but would authorize the wrong game
action. Under the engine-source-of-truth rule, that outweighs the aggregate
accuracy gain. The final candidate in
`../physical-classifier-final-20260914/` addresses these cases and is the
candidate to consider for promotion. This package remains the before arm for
that comparison.

The gzip container was rewritten when the completed evidence was exported, so
the preparation-time compressed-file hash in `preflight.json` now records the
package's final bytes. The reviewed uncompressed allowlist digest above is
unchanged. `protocol.json` and `source/` retain the measured source and corpus
rather than today's post-run engine-only guard.
