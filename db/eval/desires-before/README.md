# The before side of the objects-of-desire change

Four repetitions a side, on `mistralai/mistral-medium-3.1`, against the tree at
`e0e64eb` — before `Character::Schema` and `Location::DetailSchema` gained the
four objects of desire and the two pursuit labels. `../desires-after` is the
same three benches against the tree with them.

| file | bench | judged with |
| --- | --- | --- |
| `genesis.json` | `rake eval:genesis` | `rake eval:genesis_compare` |
| `realization.json`, `requests.json` | `rake eval:realization` | `rake eval:realization_compare` |
| `dialogue.json` | `rake eval:dialogue` | `rake eval:dialogue_compare` |

## The realization side was bought twice, and this is the second one

The first realization before side lost a median of 10 of its 29 cases a pass to
`RubyLLM::RateLimitError` — 41 of them over the run — while the after side lost
none. Every count in a realization set is a **count** rather than a rate, so
comparing them would have been comparing two different denominators: `cap_hits`
read `0 -> 3` and `output_tokens` read a near-doubling, both of which are the
missing cases rather than the prompt.

So it was re-bought against the same tree, on a quiet account, and **that** is
the file here: 0 failures on both sides, 116 realizations each. Against it the
same two figures read `1 -> 3` and `22,338 -> 27,690`, which is what six more
fields on a person actually cost.

The discarded set is not kept. A measurement nobody would judge against is not
evidence, and keeping it beside one that is would invite somebody to quote the
wrong number.

## What the comparison said

Every check on all three benches came back **noise** except three figures on
the realization bench, all of them the direct price of a wider answer:

- `cap_hits` 1 -> 3 over 116 realizations (REAL, p=0.0286)
- `proposal_refused` 0.018 -> 0.040 (REAL, p=0.0286)
- `latency_median` 7.12s -> 8.31s (REAL, p=0.0286)
- `output_tokens` 22,338 -> 27,690, reported rather than a check

`people_named`, `people_offered` and `people_take_up` did not move, so the
rooms kept their cast: what the wider answer bought was longer prose in the
fields that were already there, not fewer people in the room.
