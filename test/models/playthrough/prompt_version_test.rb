require "test_helper"

# WHICH VERSION OF THE PROSE PROMPT WROTE A TURN.
#
# The digest is a short hash and there is nothing clever in it; what has to hold
# is what it is a digest OF, because that decides what a matching digest means.
# It covers the INSTRUCTION BLOCK -- the system message the prose call was given
# -- and, for a narrated turn, the PER-TURN SCAFFOLD around the facts. Every
# assertion below is about that boundary, and the ones that matter most are the
# pair at the bottom: a changed fact sentence moves the version, and a run that
# changed nothing does not.
class Playthrough::PromptVersionTest < ActiveSupport::TestCase
  test "the same instructions digest the same, whatever the whitespace around them" do
    assert_equal Playthrough::PromptVersion.of("You narrate."),
                 Playthrough::PromptVersion.of("\n  You narrate.  \n")
  end

  test "a changed word is a changed version" do
    refute_equal Playthrough::PromptVersion.of("You narrate."),
                 Playthrough::PromptVersion.of("You narrate briefly.")
  end

  test "nothing at all has no version, rather than a version of nothing" do
    assert_nil Playthrough::PromptVersion.of(nil)
    assert_nil Playthrough::PromptVersion.of("   ")
    assert_nil Playthrough::PromptVersion.for_chat(nil)
  end

  test "it is short enough to read off a board and long enough to be a fingerprint" do
    assert_equal Playthrough::PromptVersion::LENGTH, Playthrough::PromptVersion.narration.length
  end

  # THE ONE READER, and it reads the message `Playthrough::Debug` already treats
  # as the instructions -- so the debug view and the verdict cannot come to
  # disagree about which message that is.
  test "a chat's version is the digest of its system message" do
    chat = create(:chat, purpose: "narration")
    chat.messages.create!(role: "system", content: Scene::Narrator::INSTRUCTIONS, model: chat.model)
    chat.messages.create!(role: "assistant", content: "You do the thing.", model: chat.model)

    assert_equal Playthrough::PromptVersion.narration, Playthrough::PromptVersion.for_chat(chat)
  end

  # A PASS WHOSE SCAFFOLD IS NOT RENDERED GETS THE INSTRUCTION BLOCK ALONE, and
  # that is the honest answer rather than a shortcut: `Scene::Generator`'s
  # arrival prompt has a scaffold of its own and nothing here renders it, so
  # folding the NARRATOR's scaffold into an arrival's digest would fingerprint
  # an arrival with text no arrival was ever sent.
  test "an arrival's version is its instructions alone, because its scaffold is not this one" do
    chat = create(:chat, purpose: "arrival")
    chat.messages.create!(role: "system", content: Scene::Narrator::INSTRUCTIONS, model: chat.model)

    assert_equal Playthrough::PromptVersion.narration_instructions, Playthrough::PromptVersion.for_chat(chat)
    refute_equal Playthrough::PromptVersion.narration, Playthrough::PromptVersion.for_chat(chat),
                 "the two readers answer different questions and must not collapse into one"
  end

  # A TALK TURN HAS NO INSTRUCTION DIGEST AND NIL IS THE HONEST ANSWER.
  # `InteractionAgent`'s narrator pass sends no system message: its prose rules
  # are interpolated into the per-turn user prompt with the character's name and
  # pronouns inside them, so a digest of it would be a digest of the cast.
  test "a conversation with no instructions has no version" do
    chat = create(:chat, purpose: "interaction-narration")
    chat.messages.create!(role: "user", content: "Write what happens.", model: chat.model)

    assert_nil Playthrough::PromptVersion.for_chat(chat)
  end

  # THE VERSION IS FROZEN BESIDE THE MODEL, which is the ROADMAP's ask: a
  # verdict groups by prompt as well as by model, and both are copies rather
  # than references because `Playthrough#prune_conversations!` can destroy the
  # receipts.
  test "a verdict freezes the prompt version of the turn it judges" do
    playthrough = create(:playthrough, :started)
    scene = create(:scene, story: playthrough.story, location: playthrough.current_location)
    playthrough.update!(current_scene: scene)

    chat = create(:chat, purpose: "narration", playthrough: playthrough)
    chat.messages.create!(role: "system", content: Scene::Narrator::INSTRUCTIONS, model: chat.model)
    chat.messages.create!(role: "assistant", content: "You do the thing.", model: chat.model, scene: scene)

    feedback = Playthrough::Feedback.record(playthrough: playthrough, scene: scene, verdict: "good")

    assert_equal Playthrough::PromptVersion.narration, feedback.prose_prompt_digest
    assert_equal "narration", feedback.prose_purpose
  end

  test "a turn with no prose call has no prompt version to freeze" do
    playthrough = create(:playthrough, :started)
    scene = create(:scene, story: playthrough.story, location: playthrough.current_location)
    playthrough.update!(current_scene: scene)

    feedback = Playthrough::Feedback.record(playthrough: playthrough, scene: scene, verdict: "weak")

    assert_nil feedback.prose_prompt_digest
  end

  # THE DEFECT THIS WAS WIDENED FOR, AS A TEST. `ta-take-drop-narration` changed
  # `Playthrough::Turn#taken_fact` and `#dropped_fact` and nothing else, and the
  # narration digest did not move -- so two genuinely different prompts wore one
  # fingerprint and the captain's verdicts on either side of the change grouped
  # as evidence about one narrator.
  #
  # IT REDEFINES THE REAL METHOD, on the real class, and that is deliberate: a
  # stub on the rendering seam would prove only that the seam was wired up. What
  # has to hold is that editing the sentence in `Playthrough::Turn` -- which is
  # exactly what that PR did -- moves the version.
  test "a changed take sentence is a changed narration version" do
    before = Playthrough::PromptVersion.narration

    with_fact_sentence(:taken_fact, "<who> now has the <item>, somehow.") do
      refute_equal before, Playthrough::PromptVersion.narration,
                   "a change to what every take turn tells the narrator has to move the version it groups by"
    end

    assert_equal before, Playthrough::PromptVersion.narration, "and it comes back when the sentence does"
  end

  test "a changed drop sentence is a changed narration version" do
    before = Playthrough::PromptVersion.narration

    with_fact_sentence(:dropped_fact, "The <item> is on the floor now.") do
      refute_equal before, Playthrough::PromptVersion.narration
    end
  end

  # AND THE OTHER HALF, which is the half that makes the first one worth having:
  # a version that moved on its own would be a version nobody could read. It is
  # computed off the code with no database and no clock, so two reads in one
  # process and two reads in two are the same read.
  test "changing nothing leaves the narration version exactly where it was" do
    assert_equal Playthrough::PromptVersion.narration, Playthrough::PromptVersion.narration
    assert_equal Playthrough::PromptVersion::Scaffold.text, Playthrough::PromptVersion::Scaffold.text
    assert_equal Playthrough::PromptVersion::LENGTH, Playthrough::PromptVersion.narration.length
  end

  # THE SCAFFOLD IS TEXT THE MODEL RECEIVES, and this is what says so: every
  # wording the fact builders and `Scene::Narrator#prompt_for` can produce is in
  # there, so a change to any of them is a change to the digest. A branch this
  # misses is a wording change the version would sleep through.
  test "the rendered scaffold holds every framing and every fact sentence" do
    text = Playthrough::PromptVersion::Scaffold.text

    assert_includes text, "Narrate it as done. Do not contradict it and do not undo it."
    assert_includes text, Scene::Narrator::DOING[:examine]
    assert_includes text, "ON THIS TURN, and not before it"
    assert_includes text, "picked the <item> up"
    assert_includes text, "it was lying in this room"
    assert_includes text, "put the <item> down"
    assert_includes text, "it is no longer carried"
    assert_includes text, "word for word"
    assert_includes text, Playthrough::Moment::Handled.new(item: nil, direction: :taken).note
    assert_includes text, Playthrough::Moment::Handled.new(item: nil, direction: :dropped).note
    assert_includes text, "NOTHING WAS THROWN"
    assert_includes text, "is still in the party's hands"
    assert_includes text, "is still lying exactly where it was"
    assert_includes text, "and it hit them"
    assert_includes text, "through the way out into"
    assert_includes text, "does not move. Nothing happened."
  end

  # THE ONE THING THIS CLASS DUPLICATES, AND THE TEST THAT KEEPS IT HONEST.
  # `Playthrough::PromptVersion::Scaffold` holds no prompt WORDING -- it
  # subclasses the two classes that own it and calls their real builders -- but
  # it does hold the LIST of which builders exist. A signature change breaks the
  # render loudly; a SIXTH fact sentence added and not rendered would not, and
  # the digest would quietly stop covering a sentence every turn of that shape
  # sends. So the list is asserted against the class itself.
  test "every fact sentence Playthrough::Turn can write is rendered into the scaffold" do
    assert_equal Playthrough::Turn.instance_methods(false).grep(/_fact\z/).sort,
                 Playthrough::PromptVersion::Scaffold.rendered_facts.sort,
                 "a fact builder that is not rendered is a sentence the prompt version cannot see"
  end

  # AND THE SHARPER CASE, because `#thrown_fact` is one method with a sentence
  # per outcome: a fifth `Throw` kind is a whole new paragraph of wording inside
  # a builder that is already rendered, so the method-name check above would
  # pass and the digest would still miss it. `Data.define`'s own boilerplate is
  # subtracted by asking a bare `Data` class what it has, rather than by naming
  # `[]`, `new`, `inspect` and `members` in a list that would go stale.
  test "every outcome a throw can have is rendered into the scaffold" do
    kinds = Playthrough::Turn::Throw.singleton_methods(false) - Data.define.singleton_methods(false)

    assert_equal kinds.sort, Playthrough::PromptVersion::Scaffold.rendered_throw_kinds.sort,
                 "a Throw outcome with no rendered sentence is a branch of #thrown_fact the version sleeps through"
  end

  # THE THIRD CLOSED SET, and this one needs no guard because the render
  # ITERATES it -- the assertion is that it still does.
  test "every DOING line is rendered into the scaffold" do
    text = Playthrough::PromptVersion::Scaffold.text

    refute_empty Scene::Narrator::DOING
    Scene::Narrator::DOING.each_value { |line| assert_includes text, line }
  end

  # AND IT IS NOT A DIGEST OF SOURCE, which is the constraint that keeps it
  # readable: the instruction block is in the narration digest verbatim, so the
  # wider digest is over text and never over the methods that built it.
  test "the scaffold is rendered text, and the instruction block is not part of it" do
    refute_includes Playthrough::PromptVersion::Scaffold.text, Scene::Narrator::INSTRUCTIONS.strip,
                    "the two halves are joined once, in PromptVersion, and neither contains the other"
    refute_includes Playthrough::PromptVersion::Scaffold.text, "def taken_fact",
                    "a digest of method source would churn on a refactor that changed no prompt"
  end

  private

  # ONE OF `Playthrough::Turn`'S FACT SENTENCES, SAYING SOMETHING ELSE FOR THE
  # LENGTH OF A BLOCK, and put back exactly as it was. `#define_method` restores
  # the body AND the visibility the original `UnboundMethod` carried, so nothing
  # here has to assert what that visibility is -- a test that decided for itself
  # would be a test that changed the app for every test after it.
  def with_fact_sentence(name, text)
    original = Playthrough::Turn.instance_method(name)
    Playthrough::Turn.define_method(name) { |*| text }
    yield
  ensure
    Playthrough::Turn.define_method(name, original)
  end
end
