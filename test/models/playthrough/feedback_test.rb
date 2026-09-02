require "test_helper"

# The evaluation instrument. What matters is that a verdict is one click and
# amendable, and above all that the PROVENANCE SURVIVES THE PRUNER -- that is
# the requirement the whole feature stands on and the one most easily lost, so
# it is asserted directly rather than inferred from the columns existing.
class Playthrough::FeedbackTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @protagonist = create(:character, story: @story, is_protagonist: true)
    @here = create(:location, story: @story, name: "Ashgate Market")
    @opening = create(:scene, :opening, story: @story, location: @here,
                                        description: "Stalls stand under wet canvas.",
                                        story_timestamp: @story.start_time)
    @turn = create(:scene, story: @story, location: @here, previous_scene: @opening,
                           description: "Rain starts falling on the awnings.",
                           typed: "look at the awnings",
                           story_timestamp: @story.start_time + 5.minutes)
    @playthrough = create(:playthrough, story: @story, character: @protagonist,
                                        current_location: @here, current_scene: @turn)
  end

  # --- the row itself --------------------------------------------------------

  test "a verdict is valid with a playthrough, a turn and one of the three words" do
    assert_predicate build(:playthrough_feedback, playthrough: @playthrough, scene: @turn), :valid?
  end

  # The three are a fixed table in code for the same reason
  # `Playthrough::Drift::ACTIONS` is one: free text here would make every later
  # comparison a string-matching exercise.
  test "a verdict outside the closed set is not one the instrument records" do
    feedback = build(:playthrough_feedback, playthrough: @playthrough, scene: @turn, verdict: "sublime")

    assert_not_predicate feedback, :valid?
    assert_includes feedback.errors[:verdict], "is not included in the list"
  end

  test "a verdict on a scene from another world mixes two stories together" do
    elsewhere = create(:scene, story: create(:story))
    feedback = build(:playthrough_feedback, playthrough: @playthrough, scene: elsewhere)

    assert_not_predicate feedback, :valid?
    assert_includes feedback.errors[:scene], "must be a turn in the playthrough's story"
  end

  # ONE VERDICT PER TURN, which is what makes recording and amending the same
  # request rather than two.
  test "a turn holds one verdict from one playthrough" do
    create(:playthrough_feedback, playthrough: @playthrough, scene: @turn)
    second = build(:playthrough_feedback, playthrough: @playthrough, scene: @turn, verdict: "bad")

    assert_not_predicate second, :valid?
  end

  # ...but a story's opening arrival is world data shared by every playthrough
  # of it, so two players judging the same opening are two judgements. That is
  # why the key is (playthrough, scene) and not the scene alone.
  test "two playthroughs each judge the opening arrival they share" do
    other = create(:playthrough, story: @story, character: @protagonist,
                                 current_location: @here, current_scene: @opening)

    create(:playthrough_feedback, playthrough: @playthrough, scene: @opening, verdict: "good")

    assert_nothing_raised do
      create(:playthrough_feedback, playthrough: other, scene: @opening, verdict: "bad")
    end
  end

  # --- recording, and what it freezes ---------------------------------------

  test "record writes the verdict and the note" do
    feedback = Playthrough::Feedback.record(
      playthrough: @playthrough, scene: @turn, verdict: "good",
      note: "  the rain did work in the paragraph  "
    )

    assert_predicate feedback, :persisted?
    assert_equal "good", feedback.verdict
    assert_equal "the rain did work in the paragraph", feedback.note
  end

  # THE ANSWER THE WHOLE TABLE EXISTS FOR: which model wrote the prose being
  # judged. Read out of `chats` / `messages` at the moment of recording, which
  # is the only moment it is guaranteed to be there.
  test "record freezes the model that wrote the prose, not merely the one it asked" do
    receipts(@turn, purpose: "classifier", model: "minimax/minimax-m3", input: 118, output: 9)
    receipts(@turn, purpose: "narration", model: "mistralai/mistral-medium-3.1", input: 900, output: 210)

    feedback = Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "good")

    assert_equal "mistralai/mistral-medium-3.1", feedback.prose_model
    assert_equal "narration", feedback.prose_purpose
    assert_equal [ "mistralai/mistral-medium-3.1" ], feedback.prose_model_ids
    assert_equal [ "minimax/minimax-m3", "mistralai/mistral-medium-3.1" ], feedback.answering_model_ids
    assert_equal 1_018, feedback.input_tokens
    assert_equal 219, feedback.output_tokens
    assert_predicate feedback, :receipts_kept?
  end

  # An arrival realizes the room and THEN narrates walking into it. Only the
  # second one is what the player read.
  test "record takes the last prose answer on a turn that wrote two" do
    receipts(@turn, purpose: "location", model: "minimax/minimax-m3")
    receipts(@turn, purpose: "arrival", model: "mistralai/mistral-medium-3.1")

    feedback = Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "weak")

    assert_equal "arrival", feedback.prose_purpose
    assert_equal "mistralai/mistral-medium-3.1", feedback.prose_model
  end

  # A talk turn is two passes: the character's five structured fields, then the
  # prose. It is the second that is being judged.
  test "record names the prose pass on a conversation turn" do
    receipts(@turn, purpose: Chat::CHARACTER, model: "minimax/minimax-m3")
    receipts(@turn, purpose: "interaction-narration", model: "mistralai/mistral-medium-3.1")

    feedback = Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "good")

    assert_equal "interaction-narration", feedback.prose_purpose
  end

  # A turn that never had receipts of its own -- an opening arrival, generated
  # when the world was built -- says so rather than reading as a turn that cost
  # nothing.
  test "record is honest about a turn with no receipts at all" do
    feedback = Playthrough::Feedback.record(playthrough: @playthrough, scene: @opening, verdict: "good")

    assert_nil feedback.prose_model
    assert_nil feedback.prose_purpose
    assert_equal 0, feedback.input_tokens
    assert_not_predicate feedback, :receipts_kept?
  end

  # `BaseAgent` rotated on the call being judged -- past a model that failed, or
  # a refusal it would not write. A verdict on prose two models had a hand in is
  # not clean evidence about either alone, so the row keeps the whole chain and
  # says so.
  test "a rotation on the prose is visible in the frozen provenance" do
    receipts(@turn, purpose: "narration", model: "minimax/minimax-m3")
    receipts(@turn, purpose: "narration", model: "mistralai/mistral-medium-3.1")

    feedback = Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "weak")

    assert_predicate feedback, :rotated?
    assert_equal [ "minimax/minimax-m3", "mistralai/mistral-medium-3.1" ], feedback.prose_model_ids
    assert_equal "mistralai/mistral-medium-3.1", feedback.prose_model, "the kept answer is the last one"
  end

  # ...AND A ROTATION SOMEWHERE ELSE ON THE TURN IS NOT ONE. This is the whole
  # reason there are two frozen lists: reading `answering_models` for this would
  # flag a verdict for something that happened in the classifier, which says
  # nothing about the prose being judged.
  test "a rotation in the classifier does not flag the prose it did not write" do
    receipts(@turn, purpose: "classifier", model: "minimax/minimax-m3")
    receipts(@turn, purpose: "classifier", model: "mistralai/mistral-medium-3.1")
    receipts(@turn, purpose: "narration", model: "mistralai/mistral-medium-3.1")

    feedback = Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "good")

    assert_not_predicate feedback, :rotated?
    assert_equal 2, feedback.answering_model_ids.size, "the turn as a whole did rotate, and that is still recorded"
  end

  # --- amending -------------------------------------------------------------

  test "record amends the verdict on the same row rather than adding a second" do
    Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "good")

    assert_no_difference -> { Playthrough::Feedback.count } do
      Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "bad")
    end

    assert_equal "bad", @playthrough.feedbacks.sole.verdict
  end

  # THE PROVENANCE DESCRIBES THE TURN, NOT THE VERDICT. Amending must not
  # re-snapshot: by the time he changes his mind the receipts may be gone, and a
  # second reading would replace a true record with an empty one.
  test "amending keeps the provenance frozen at the first recording" do
    receipts(@turn, purpose: "narration", model: "mistralai/mistral-medium-3.1")
    Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "good")

    @playthrough.chats.destroy_all

    feedback = Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "weak")

    assert_equal "weak", feedback.verdict
    assert_equal "mistralai/mistral-medium-3.1", feedback.prose_model
  end

  test "changing a verdict does not throw away the note that explained the old one" do
    Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "good", note: "the awnings")
    feedback = Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "weak")

    assert_equal "the awnings", feedback.note
  end

  test "an empty note is how a note is cleared" do
    Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "good", note: "the awnings")
    feedback = Playthrough::Feedback.record(playthrough: @playthrough, scene: @turn, verdict: "good", note: "")

    assert_nil feedback.note
  end

  # --- THE REQUIREMENT THE FEATURE STANDS ON --------------------------------

  # `Playthrough#prune_conversations!` runs at the end of EVERY turn and
  # destroys the one-shot conversations older than `Chat::KEEP_TURNS`. It is not
  # something to work around -- this is a SQLite file on a laptop and a
  # playthrough runs for hours -- so a verdict that held a reference to
  # `Chat#answering_model_ids` would be unreadable on exactly the turns a long
  # session produces most of.
  #
  # `keep:` is passed explicitly so the test does not have to build twenty-six
  # turns to reach the default; the pruner's behaviour is the same either way
  # and `Chat::KEEP_TURNS` is only what the game passes.
  test "the frozen provenance survives the pruner that destroys the receipts" do
    receipts(@turn, purpose: "classifier", model: "minimax/minimax-m3", input: 118, output: 9)
    receipts(@turn, purpose: "narration", model: "mistralai/mistral-medium-3.1", input: 900, output: 210)

    feedback = Playthrough::Feedback.record(
      playthrough: @playthrough, scene: @turn, verdict: "good", note: "best paragraph so far"
    )

    # A later turn, so the judged one is no longer among the recent ones the
    # pruner keeps.
    later = create(:scene, story: @story, location: @here, previous_scene: @turn,
                           description: "The rain stops.", typed: "wait",
                           story_timestamp: @story.start_time + 10.minutes)
    @playthrough.update!(current_scene: later)

    assert_equal 2, @playthrough.prune_conversations!(keep: 1)
    assert_empty @turn.reload.messages, "the receipts for the judged turn are gone, which is the premise"

    feedback.reload

    assert_equal "good", feedback.verdict
    assert_equal "best paragraph so far", feedback.note
    assert_equal "mistralai/mistral-medium-3.1", feedback.prose_model,
                 "the model that wrote the judged prose is still on the row"
    assert_equal "narration", feedback.prose_purpose
    assert_equal [ "mistralai/mistral-medium-3.1" ], feedback.prose_model_ids
    assert_equal [ "minimax/minimax-m3", "mistralai/mistral-medium-3.1" ], feedback.answering_model_ids
    assert_equal 1_018, feedback.input_tokens
    assert_equal 219, feedback.output_tokens
    assert_predicate feedback, :receipts_kept?

    # And the durable half is still readable through the Scene, which is why it
    # was never copied: the prose being judged and the words that asked for it.
    assert_equal "Rain starts falling on the awnings.", feedback.scene.description
    assert_equal "look at the awnings", feedback.typed
    assert_equal @turn.story_timestamp, feedback.story_timestamp
  end

  # --- what goes with what --------------------------------------------------

  # A verdict is a judgement OF this prose, so it means nothing once the prose
  # is gone. That is the opposite of `Playthrough::Drift`, which is nullified
  # because there the measurement is the durable half.
  test "destroying the turn destroys the verdict on it" do
    create(:playthrough_feedback, playthrough: @playthrough, scene: @turn)

    assert_difference -> { Playthrough::Feedback.count }, -1 do
      @playthrough.update!(current_scene: @opening)
      @turn.destroy!
    end
  end

  test "destroying the playthrough destroys its verdicts" do
    create(:playthrough_feedback, playthrough: @playthrough, scene: @turn)

    assert_difference -> { Playthrough::Feedback.count }, -1 do
      @playthrough.destroy!
    end
  end

  test "the log reads its verdicts in one query, keyed by turn" do
    feedback = create(:playthrough_feedback, playthrough: @playthrough, scene: @turn)

    assert_equal({ @turn.id => feedback }, @playthrough.feedback_by_scene)
  end

  private

  # One conversation's worth of receipts for a turn, written the way
  # `BaseAgent#attribute_to!` leaves them: the prompt and the answer both filed
  # under the scene, the answering model on the assistant row.
  def receipts(scene, purpose:, model:, input: 100, output: 20)
    registry = create(:model, model_id: model, provider: "openrouter")
    chat = create(:chat, playthrough: @playthrough, purpose: purpose, model: registry)

    create(:message, chat: chat, scene: scene, role: "user", model: nil, content: "go on then")
    create(:message, :assistant, chat: chat, scene: scene, model: registry,
                                 input_tokens: input, output_tokens: output)
    chat
  end
end
