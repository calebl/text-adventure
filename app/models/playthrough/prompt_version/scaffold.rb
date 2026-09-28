# THE PER-TURN SCAFFOLD, RENDERED ONCE AGAINST FIXED PLACEHOLDERS, SO A DIGEST
# CAN COVER IT.
#
# WHAT THE SCAFFOLD IS. A narrated turn's prompt is not one block of text: it is
# the narrator's instructions as the system message, and then a user message the
# engine builds (`renderedstep_engine::narration`) -- the framing of a `fact:`
# and the `DOING` line -- wrapped around whatever the turn wrote as that fact (a
# take, a drop, a throw, a reading, written words). Every one of those sentences
# is an INSTRUCTION in every meaningful sense: "Narrate it as done. Do not
# contradict it and do not undo it." is the app telling the narrator how to
# write, and changing it changes the prose exactly the way changing the
# instruction block does.
#
# WHY IT WAS NOT COVERED, AND WHAT CHANGED. `Playthrough::PromptVersion` read
# the instruction text back off the stored conversation, and the scaffold cannot
# be read back that way -- it arrives interleaved with the facts and no reader of
# one stored user message can tell one from the other. That is a true statement
# about a STORED PROMPT and it was taken, wrongly, as a reason the scaffold could
# not be versioned at all. It can: the scaffold is CODE, and code can be rendered
# against fixed inputs and digested. That is what this class hands over, and it
# is the same thing `Eval::Prompt::Version`'s `prompt_digest` does from the other
# side -- except that one needs a corpus, a database and a paid run, and this
# needs nothing.
#
# THE ENGINE RENDERS IT, because the engine is what sends it. Every narrated
# turn is played by the Rust engine, so the frame and the fact sentences a
# narrator receives are the engine's own code, and a copy of them here would be
# a digest of what the game no longer says. `Playthrough::RustEngine.scaffold`
# renders the engine's builders against fixed placeholders
# (`renderedstep_engine::prompt_version`): every framing, one per `DOING` key,
# every branch of every fact sentence -- a take and a drop with and without
# their optional clauses, a reading, every way a throw comes out and a fumble
# both ways -- and the mark a moved row carries in the standing lists, in a
# fixed order under `Playthrough::PromptVersion::JOINER`.
#
# TEXT THE MODEL ACTUALLY RECEIVES, and never method source. A digest of source
# would move on a rename, a comment, an extracted helper -- refactors that change
# no prompt -- and a version that cries wolf is a version nobody reads. So every
# branch is RENDERED and the rendered strings are what is digested: change a word
# of the wording and the digest moves; move the same words into a new function
# and it does not. The placeholders are fixed for ever, angle-bracketed so no
# rendered scaffold can be mistaken for a real prompt, and changing one moves
# the digest for no prompt change.
#
# WHAT IS STILL NOT COVERED, stated so nobody reads more into a matching digest
# than it can carry: the rest of the framing of the engine's
# `moment::narration_context` -- its `Handled` note IS rendered, because it is a
# fixed sentence about a change of possession and belongs with the fact that
# names the same row, but the surrounding lines are built together with the live
# records they state and rendering them needs a database -- and
# `Scene::Generator`'s arrival prompt. Both are covered by
# `Eval::Prompt::Version#prompt_digest`, which is a fingerprint of everything
# and the reason that digest exists.
class Playthrough::PromptVersion::Scaffold
  def self.text = Playthrough::RustEngine.scaffold
end
