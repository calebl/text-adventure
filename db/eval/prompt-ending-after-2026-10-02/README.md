# The ending's `Dead here:` line, judged

The pair `prompt-ending-before-2026-10-02` and `prompt-ending-after-2026-10-02`,
`mistralai/mistral-medium-3.1`, four repetitions a side, on the six-case ending
corpus (`test/fixtures/files/prompt_ending_corpus.yml`). The after side is the
ending's current baseline; `prompt-ending-2026-09-10` stays as history at the
five-case corpus it scored.

**The change.** On the ending's pass alone, the moment names who lies dead in
the room: `Dead here: Halkett Rowe (Sub-Inspector Rowe). They cannot speak or
act.` It renders only where somebody is dead, which is the new sixth case
(`ending-take-the-writ-over-the-dead`); the five Iron Gate cases sent
byte-identical requests on both sides. The ending's own instructions did not
move (`instructions_digest` identical); the request identity did
(`v2:0ac9fd7c4a6a76e3` -> `v2:4e5e367c21bbf5dc`).

**The verdict.** `rake eval:prompt_compare BEFORE=prompt-ending-before-2026-10-02
AFTER=prompt-ending-after-2026-10-02`: NOISE on every figure. The only flags
were two `item_not_held` readings on the Iron Gate's `ending-take-the-ring`
on the after side, a case whose request did not change, inside the spread the
unchanged runs already span. `commitments` 2.416 -> 2.750 and `words` 53 -> 48,
both NOISE.

**The line's own case, read by hand**, because no check reads a dead person
written as standing in a single turn (`dead_shown_alive` needs the scene's
engine receipt). Without the line none of the four endings mentions Rowe; with
it two of four name him, and none has him standing, moving or speaking.

Before:

- rep 1: You sit at your desk with Perrin’s index and the unsigned writ before you, the missing hour accounted for at last—the same hand that closed 0714, 0902, and Perrin Lasco now tied to the blank writ in your fingers, Query 1188 left open in your name with its reason recorded. The rain streaks the cold window, the gas mantle hisses, and the empty line on the writ waits, unfilled.

- rep 2: You hold the blank writ, its unbroken seal matching the borrowed slant of the amendment in your daybook, and the missing hour at last has a source: Perrin Lasco’s hand, the same that closed 0714, 0902, and now this. Query 1188 stays open in your name, and the record, for once, says why. The gas mantle hisses, the rain streaks the cold glass, and the office is silent but for the distant echo of a door closing down the hallway.

- rep 3: You hold the blank closure writ in one hand and Perrin’s index in the other, the missing hour accounted for at last—0714, 0902, Perrin Lasco, all closed by the same borrowed hand. Query 1188 stays open in your name, and the record now says why. The gas mantle hisses, the rain streaks the cold glass, and the desk across from you remains empty, its chair squared to the wood as if its occupant never was.

- rep 4: You hold the blank writ in one hand and Perrin’s index in the other, the missing hour accounted for at last—closed by the same borrowed hand that erased 0714, 0902, and Perrin Lasco, with Query 1188 left open in your name, the reason now recorded. The gas mantle hisses, the rain streaks the cold glass, and the desk across remains empty, the chair squared to the wood.

After:

- rep 1: You hold the blank writ in one hand and Perrin’s index in the other, the missing hour accounted for at last—the same countersignature that sealed 0714, 0902, and Perrin Lasco now ties to Query 1188, left open in your name with the reason finally recorded. The gas mantle hisses, the rain scrapes the glass, and the desk across from you stays empty, its chair squared to the wood as if waiting for someone who will never sit there again.

- rep 2: You hold the blank writ in one hand and Perrin’s index in the other, the missing hour accounted for at last—Rowe’s name, Perrin’s hand, the Inspectorate’s seal. The ruled gap in your daybook stays empty, but Query 1188 remains open, and the record now bears the reason: *By order of the Inspectorate. Countersigned.* The gas mantle hisses, the rain streaks the cold glass, and the supply closet door stands unmarked and unlatched behind you.

- rep 3: You hold the blank closure writ in one hand and Perrin’s index in the other, the missing hour accounted for at last—Rowe’s borrowed slant on the countersignature, the same hand that closed 0714, 0902, and Perrin Lasco, the same hand that now leaves Query 1188 open in your name, the record finally saying why. The gas mantle hisses, the rain streaks the cold glass, and the long hallway beyond the door stays quiet.

- rep 4: You hold the blank writ in one hand and Perrin’s index in the other, the missing hour accounted for at last—the same borrowed hand that closed 0714, 0902, and Perrin Lasco now leaves Query 1188 open in your name, the record finally noting why. The rain streaks the cold glass, the gas mantle hisses, and the empty line on the writ waits, unfilled.

**Cost.** The bench printed $0.0264 (before) and $0.0250 (after) for the scored
calls, against the estimator's $0.047 a side. The OpenRouter account's
`total_usage` read 63.570525 before the inscription re-buy and these two sets,
and 63.652480 once it settled (unchanged from 12:25 to 12:31 UTC on 2026-10-02): $0.0820 for all three, an upper bound
because the account is shared.
