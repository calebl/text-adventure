require "test_helper"

# WHICH VERSION OF THE PROSE INSTRUCTIONS WROTE A TURN.
#
# The digest is a short hash and there is nothing clever in it; what has to hold
# is what it is a digest OF, because that decides what a matching digest means.
# It covers the INSTRUCTION BLOCK -- the system message the prose call was
# given -- and nothing else, and every assertion below is about that boundary.
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
end
