# The inscription baseline after the Lunar Cartographer's ending rule

`mistralai/mistral-medium-3.1`, four repetitions, the twelve first-read cases.
It replaces `inscription-2026-09-26`, which stays as history.

Only the corpus digest forced the re-buy, for the reason the set before gives:
it hashes the seed files the cases are staged in, and
`db/seeds/worlds/the-lunar-cartographer.yml` changed its second ending's rule
from `out_of_order` to `while_alive` (beat 3, Marek Sollen). The requests are
byte for byte the ones the set before sent -- the same request identity
(`v1:666515f4006a5926`) and the same identity for every case, checked offline
before buying -- and the figures match it: no empty, framed, over-long or
repeated answer, and one failed call in each of two repetitions on the tuning
worlds (`failed` 0.111 / 0.111 / 0.000 / 0.000).

Cost: the run printed a receipted $0.032682 against the estimator's $0.168.
The account's `total_usage` read 63.570525 before this set and the two ending
sets after it were bought; see `db/eval/prompt-ending-after-2026-10-02/README.md`
for the reading after all three. The account is shared, so the difference is
an upper bound.
