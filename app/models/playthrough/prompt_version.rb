# WHICH VERSION OF THE PROSE INSTRUCTIONS WROTE THIS, as one short digest.
#
# WHY IT EXISTS. `Playthrough::Feedback` freezes which MODEL wrote a turn, so
# the captain's verdicts group by model. They could not group by PROMPT, and
# every prompt-shaped change this project makes moves the thing being judged
# underneath the verdicts already recorded: a turn marked `good` in the morning
# and one marked `good` after lunch are evidence about two different narrators
# if the instructions changed in between, and nothing said so. The ROADMAP's
# `ta-prompt-bench` entry asks for exactly this -- *"freeze a digest of the
# prose instructions alongside `prose_model`"* -- and this is the digest.
#
# WHAT IT IS A DIGEST OF, stated narrowly because a version nobody can define is
# a version nobody can trust: THE INSTRUCTION TEXT ACTUALLY SENT WITH THE CALL,
# which for every prose pass in this app is the system message of the
# conversation that answered (`Scene::Narrator::INSTRUCTIONS` for a narrated
# turn, `Scene::Generator#system_prompt` for an arrival). It is read back off
# `messages` rather than recomputed from a constant, so a digest describes what
# was sent on the day rather than what the file says now.
#
# WHAT IT IS DELIBERATELY NOT A DIGEST OF:
#
#   * THE FACTS. `Playthrough::Moment` builds those out of the records, and they
#     differ every turn by design -- folding them in would give every turn its
#     own "version" and group nothing.
#   * THE PER-TURN SCAFFOLD around them: `Scene::Narrator#prompt_for`'s framing
#     of a `fact:`, `Playthrough::Turn#taken_fact` and its siblings. Those are
#     instructions in every meaningful sense and they are NOT covered here,
#     because they arrive interleaved with the facts and cannot be told from
#     them one turn at a time. `Eval::Prompt` covers them from the other side:
#     a bench run stores the whole prompt of one designated case per shape and
#     digests that, which is a fingerprint of everything, and it can do that
#     only because its corpus is fixed. Read `Eval::Prompt::Version` before
#     assuming a matching digest here means two turns had identical prompts.
#   * `InteractionAgent`'s narrator pass, which sends NO system message at all
#     -- its prose rules are interpolated into the per-turn user prompt with the
#     character's name and pronouns inside them. A talk turn therefore has no
#     instruction digest, and nil is the honest answer rather than a digest of
#     the cast.
#
# SIXTEEN HEX CHARACTERS, the same length and for the same reason as
# `Eval::Classifier.digest`: it is read by a person off a board and compared by
# eye, and a full SHA is a column nobody reads.
class Playthrough::PromptVersion
  LENGTH = 16

  # The digest of one instruction text. Whitespace-normalized at the edges only
  # -- a heredoc gains and loses a trailing newline for reasons that are not
  # prompt changes -- and never in the middle, because a blank line between two
  # paragraphs of instructions is part of what was sent.
  def self.of(text)
    body = text.to_s.strip
    return nil if body.empty?

    Digest::SHA256.hexdigest(body).first(LENGTH)
  end

  # THE INSTRUCTIONS A STORED CONVERSATION WAS GIVEN. `Playthrough::Debug`
  # already reads this message for the debug view; this is the same read with a
  # digest over it, so the two cannot come to disagree about which message holds
  # the instructions.
  #
  # Nil for a chat with no system message, which is `interaction-narration` and
  # is a real shape rather than a missing one.
  def self.for_chat(chat)
    return nil if chat.nil?

    of(chat.messages.find_by(role: "system")&.content)
  end

  # WHAT THE APP WOULD SEND TODAY for the narrated turn -- the commonest prose
  # call in the game and the one `Eval::Prompt` is built around. Read from the
  # constant rather than from a conversation, so a test and a doc can name
  # today's version without a database.
  def self.narration = of(Scene::Narrator::INSTRUCTIONS)
end
