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
# a version nobody can trust: THE INSTRUCTION TEXT ACTUALLY SENT WITH THE CALL --
# the system message of the conversation that answered
# (`Scene::Narrator::INSTRUCTIONS` for a narrated turn,
# `Scene::Generator#system_prompt` for an arrival), read back off `messages`
# rather than recomputed from a constant, so a digest describes what was sent on
# the day rather than what the file says now -- AND, FOR A NARRATED TURN, THE
# PER-TURN SCAFFOLD AROUND THE FACTS: `Scene::Narrator#prompt_for`'s framing of
# a `fact:`, its `DOING` line, and `Playthrough::Turn#taken_fact` and its
# siblings.
#
# THE SCAFFOLD HALF IS RENDERED, NOT READ BACK, and that is the one seam in
# this class worth understanding. Those sentences arrive interleaved with the
# facts, so no reader of one stored user message can tell them apart -- which is
# why they went uncovered, and why the answer is not to read them back at all.
# They are CODE, and `Playthrough::PromptVersion::Scaffold` renders every branch
# of them against fixed placeholders and hands the text here. So the instruction
# half says what was sent on the day and the scaffold half says what the code
# says NOW. Read `#for_chat` for what that means for a verdict.
#
# WHY IT MATTERS THAT THE SCAFFOLD IS IN. A change to `#taken_fact` alone --
# which is a change to what every take turn's narrator was told, and to the
# prose the captain then judges -- used to leave this digest byte-identical, so
# verdicts recorded either side of it grouped under one fingerprint as though
# they were evidence about one narrator. That is the record the digest exists to
# protect, and it was silently wrong.
#
# WHAT IT IS DELIBERATELY NOT A DIGEST OF:
#
#   * THE FACTS. `Playthrough::Moment` builds those out of the records, and they
#     differ every turn by design -- folding them in would give every turn its
#     own "version" and group nothing. The scaffold is the frame around them and
#     the frame is what is covered: the placeholders
#     `Playthrough::PromptVersion::Scaffold` renders against are where the facts
#     would go.
#   * `Playthrough::Moment#narration_context`'s own framing, which is built out
#     of the live records in the same breath as the facts and cannot be rendered
#     without a database; and `Scene::Generator`'s arrival prompt, whose
#     scaffold is its own and is not covered by the narration digest. Read
#     `Eval::Prompt::Version` before assuming a matching digest here means two
#     turns had identical prompts: `prompt_digest` is the fingerprint of
#     everything, and it can be, only because its corpus is fixed.
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

  # WHAT SEPARATES TWO TEXTS BEING DIGESTED TOGETHER, and it is a NUL for the
  # reason `Eval::Prompt::Version#digest` uses one: no prompt in this app can
  # contain it, so two halves cannot run together into a third string that
  # neither of them is, and no edit to either half can forge the boundary.
  JOINER = "\n\0\n".freeze

  # The digest of one instruction text. Whitespace-normalized at the edges only
  # -- a heredoc gains and loses a trailing newline for reasons that are not
  # prompt changes -- and never in the middle, because a blank line between two
  # paragraphs of instructions is part of what was sent.
  def self.of(text)
    body = text.to_s.strip
    return nil if body.empty?

    Digest::SHA256.hexdigest(body).first(LENGTH)
  end

  # THE PROSE PASS WHOSE SCAFFOLD THIS CLASS COVERS, as `BaseAgent` labels it
  # (`Scene::Narrator#agent`). A name and not a list: `arrival` and
  # `interaction-narration` have scaffolds of their own and neither is rendered
  # here, so folding them under one branch would claim a coverage that does not
  # exist.
  NARRATION = "narration".freeze

  # WHAT WAS SENT WITH ONE STORED CONVERSATION. `Playthrough::Debug` already
  # reads the system message for the debug view; this is the same read with a
  # digest over it, so the two cannot come to disagree about which message holds
  # the instructions.
  #
  # AND THE SCAFFOLD, FOR A NARRATED TURN ONLY. The scaffold cannot be recovered
  # from the stored user message, so what is folded in is the scaffold AS THE
  # CODE STANDS WHEN THIS IS READ. `Playthrough::Feedback` reads it once, on
  # create, which is when the captain clicks a verdict -- so for the ordinary
  # case, a verdict on a turn he has just played, the two halves describe the
  # same moment. For a verdict recorded long after the turn, on a checkout whose
  # scaffold has since moved, the scaffold half describes the newer code. That
  # is a weaker claim than the instruction half makes and it is stated rather
  # than hidden; it is also strictly better than the alternative, which is the
  # scaffold going unrepresented and two genuinely different prompts sharing one
  # fingerprint every time.
  #
  # Nil for a chat with no system message, which is `interaction-narration` and
  # is a real shape rather than a missing one.
  def self.for_chat(chat)
    return nil if chat.nil?

    instructions = chat.messages.find_by(role: "system")&.content
    return of(instructions) unless chat.purpose.to_s == NARRATION

    with_scaffold(instructions)
  end

  # THE INSTRUCTION BLOCK ALONE, for the reader that means exactly that and not
  # the whole prompt: `Eval::Prompt::Version` records one of these per pass off
  # the text the run itself sent, and `Eval::Prompt::KeptSetTest` asks whether a
  # kept baseline's narrator instructions are still today's. Folding the
  # scaffold into that question would make a kept set unreadable the first time
  # a fact sentence was edited, which is a different question from the one it
  # asks.
  def self.narration_instructions = of(Scene::Narrator::INSTRUCTIONS)

  # WHAT THE APP WOULD SEND TODAY for the narrated turn -- the commonest prose
  # call in the game and the one `Eval::Prompt` is built around: the instruction
  # block AND the per-turn scaffold. Read from the code rather than from a
  # conversation, so a test and a doc can name today's version without a
  # database.
  def self.narration = with_scaffold(Scene::Narrator::INSTRUCTIONS)

  # ONE DIGEST OVER TWO TEXTS, joined rather than digested separately and
  # concatenated: a version is one short string a person compares by eye, and
  # two of them side by side is a thing nobody would read.
  def self.with_scaffold(instructions)
    body = instructions.to_s.strip
    return nil if body.empty?

    of([ body, Scaffold.text ].join(JOINER))
  end
  private_class_method :with_scaffold
end
