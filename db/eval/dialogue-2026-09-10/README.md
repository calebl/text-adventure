# Standing NPC dialogue baseline

Recompute the state board with `rake eval:dialogue_board SET=dialogue-2026-09-10`
and full request identity with `rake eval:dialogue_digest SET=dialogue-2026-09-10`.
Compare future matching sets using `rake eval:dialogue_compare`.

The fictional study situations are reconstructed by `Eval::Dialogue::Stage`;
its header explains the unshipped evaluator and the universe-association
reconstruction difference. The additional staying case has a fixed, replayed
exchange from the original study. Cases and follow-up state requirements were
fixed before the paid run. No individual answer was replaced or omitted.

The model and repetitions, estimated versus registry-priced usage, raw answers,
full system/user/schema/history requests, actual model receipts and conservative
budget accounting are in `dialogue.json`. The budget's provider-reported charges
are partial because streamed responses do not all expose raw billing metadata.
The durable task ledger and command logs are in
`doc/evidence/ta-bench-npc-dialogue/`.

The staying case records a requested-outcome miss: choosing `none` keeps the
existing following agreement, so the NPC accompanies the player through the
actual move. This is a measurement, not a reason to change a prompt in this task.
Read its reaction and narration against its immediate records before judging
whether prose also contradicts those records.

Human contradiction judgments have not been supplied for this new set. The
board reports them unavailable. The original `npc-protocol.md` remains the
rubric, and `ANNOTATIONS` accepts signed, prose-digested judgments beside the
state checks. A future attack is scored in follow-up `facts`; it does not
retroactively contradict the preceding narration's `immediate` ceasefire.

This bench does not measure voice, memory fidelity across turns, long-term
character behavior, or personality. Replaying history detects changed inputs;
it is not a memory-quality assessment.
