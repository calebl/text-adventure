# arrival-reactions-2026-09-28

The arrival bench's staged walk into the counting house, with the people there
reacting as the party comes in (`test/fixtures/files/arrival_reactions_corpus.json`,
`Eval::Arrival::Reactions::Stage`): Maren greets, warns of the flood, walks
out, hands over the brass key, or, hostile, demands it; and in one case Tobin
beside her tells the player to leave. The rows are the ones the engine's
reactions step writes, with its own facts, and the request is the engine's,
with the "## As You Come In" block after the records. Six cases, four
repetitions, `mistralai/mistral-medium-3.1`.

One reading, `walk_out` rep 2, was refused by the provider with a rate limit
and read again; the refused row is kept under `superseded_rows`, and its
reservation stays unsettled in `budget` because no receipt came back. 25
calls, $0.011047 at the provider's billed cost.

`rake eval:arrival_compare` has nothing to compare this with: no set before it
told a reaction. What the readings show, read by hand:

| case | the reaction rendered |
| --- | --- |
| `greet` | 4 of 4: Maren greets the player |
| `warn` | 4 of 4 name a warning; 3 of 4 say what about (the flood) |
| `walk_out` | 0 of 4 show Maren leaving; 3 of 4 write her absence, 1 does not mention her, and every summary finds the room empty |
| `give` | 4 of 4: the key is handed over |
| `foe_demand` | 4 of 4: Maren demands the key, and it stays with the player |
| `two_speakers` | 4 of 4: both people, in the order given |

No reading added a person, and none moved a thing the records did not move.
The owner's plan adds an arrival instruction only on an invented transfer or
an invented speaker, and there is neither, so none is added. The walk-out is
told as an empty room rather than a person seen going: the arrival's own
instructions write whoever is listed as already present, and the leaver is
not listed.
