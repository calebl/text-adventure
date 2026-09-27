# The inscription baseline on the worlds with arcs

`mistralai/mistral-medium-3.1`, four repetitions, the twelve first-read cases.
It replaces `inscription-2026-09-19`, which stays as history.

Only the corpus digest forced the re-buy: it hashes the seed files the cases
are staged in, and those files gained arcs. The requests themselves are byte
for byte the ones the set before sent -- the same request identity
(`v1:666515f4006a5926`) and the same identity for every case -- and the figures
match it: no empty, framed, over-long or repeated answer in either set, and one
failed call in one repetition of each. `rake eval:inscription_compare` refuses
the pair because the corpus digests differ; the two boards side by side are in
`doc/evidence/seed-world-arcs-rebuy/inscription-boards.log`.
