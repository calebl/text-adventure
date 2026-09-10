| figure | `mistralai/mistral-medium-3.1` |
| --- | --- |
| set | `prompt-branches-2026-09-10` |
| prompt version | `780ae0948949c3d9` |
| corpus | `32791221dca0b007` |
| reps × cases | 4 × 9 |
| `unrecorded_departure` | 0.000 (0..0 of 9) |
| `unrecorded_arrival` | 0.000 (0..0 of 9) |
| `item_not_held` | 0.000..0.111 (0.000) (0..1 of 9) |
| `take_denied` | unavailable |
| `pickup_invented` | unavailable |
| `inscription_misquoted` | unavailable |
| `truncated_prose` | 0.000 (0..0 of 9) |
| `third_person_protagonist` | 0.000..0.111 (0.000) (0..1 of 9) |
| `blow_contradicted` | 0.000 (0..0 of 3) |
| `toll_contradicted` | 0.000 (0..0 of 2) |
| `throw_contradicted` | 0.000 (0..0 of 1) |
| `body_contradicted` | 0.000 (0..0 of 9) |
| `beat_contradicted` | 0.000 (0..0 of 9) |
| `words` (richness) | 82..95 (89) |
| `commitments` (richness) | 2.000..2.556 (2.388) |
| human truthfulness | unlabelled (human-only) |
| refusals | 0 |
| failed calls | 0 |
| omitted fields | 0 |
| fields cut at the cap | 0 |
| latency median (warm) | 1.38s..1.55s (1.44s) |
| latency p95 (warm) | 1.59s..1.89s (1.78s) |
| first call (cold, excluded) | 1.8s |
| cost per 1,000 narrations | $1.18 |
| rotations | 0 of 36 |

Not in this table, because one turn cannot answer them, and they are **unavailable rather than clean**:
- `unreachable_transition` — a case is one turn, and the one turn that moves walks an edge the records have
- `reached_for_nothing` — a drift row needs the turn AFTER the narration, and a case has no next turn
- `named_more_than_one` — a case types a fixed line, so what it named measures the corpus, not the game
- `still_run` — four turns of nothing needs four turns
