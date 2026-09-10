# ta-exits-lab-promotion — validation evidence

Kept in the tree because the PR body's claims about a bought measurement should be
checkable by somebody who never paid for the calls. Nothing here is read by any test;
the figures that ARE read live in `db/eval/exits-quantifier-after/realization.json`.

| file | what it is |
| --- | --- |
| `vantage-promotion-panel.png` | `/lab/exits/vantages/:id` in headless Chromium at 1280x3600, showing the promotion panel printing the case with its `absent` list, its quantifier and the notes saying what stayed in the lab. `chrome-devtools-axi`'s page attachment does not work on this machine, so this is direct Chromium CDP. |
| `exits-lab-index.png` | the lab index beside it, unchanged by this PR and captured so the panel can be read in context. |
| `rake-lab-exits-promote.txt` | `rake lab:exits:promote VANTAGE=<id>` on the same vantage — the same case, the same notes, and the preamble that warns a promoted case moves both digests. |
| `realization-digest-and-compare.txt` | `rake eval:realization_digest` (offline, free) and `rake eval:realization_compare BEFORE=kind-to-corpus-after AFTER=exits-quantifier-after`. Both are re-runnable with no key. |

## Reading the comparison

The two sets record the SAME `prompt_digest` and DIFFERENT `corpus_digest`s, so the
comparison prints its mismatched-corpus refusal — which is the point, and the reason the
run was bought at all.

`inside_where_the_world_wanted_none 0.833 -> 0.000` is **PR #171's correction and not this
change**. The before set records `insides_reaching` and
`inside_on_a_place_that_already_exists` as `null`, which is what a set bought before those
two landed looks like — so its 0.833 was scored by the pre-#171 rule (any pick made) and
this set's 0.000 by the corrected one (only picks that OPENED a place). The denominator is
3 on both sides, unmoved by the widening. Both facts are readable off the two JSON files.
