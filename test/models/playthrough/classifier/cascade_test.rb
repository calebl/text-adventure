require "test_helper"

# THE COMPOSITION, RULE BY RULE. Each test below is one rule of the engine's
# reading of a System One answer, and the reason they are worth a file of their
# own is that the provider is the part that can be wrong and this is the part
# that must not be: a Choice is only a closed set because the app closed it, and
# everything downstream of here -- the refusals, the branch, the row that moves
# -- acts on the record this class resolved.
#
# Never a live provider: `FakeSystemOne` stands in at the `SystemOneAgent`
# boundary, and it builds a real `SystemOneAgent::Answers`, so an answer this
# file queues is one the real verification accepted.
class Playthrough::Classifier::CascadeTest < ActiveSupport::TestCase
  # A CLEAN READING, and the baseline every test below varies one field of:
  # one act, on a record that is here.
  CLEAR = { "named_more_than_one" => 0.02, "target_present" => 0.95 }.freeze

  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ward Office 12")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    @classifier = Playthrough::Classifier.new(@playthrough)

    @closet = create(:location, story: @story, name: "The Supply Closet")
    create(:location_connection, location: @here, connected_location: @closet)
    @perrin = create(:character, story: @story, location: @here, fullname: "Perrin Lasco", nickname: "Perrin")
    @rowe = create(:character, story: @story, location: @here, fullname: "Halkett Rowe", nickname: nil)
    @press = lying_here(@playthrough, @here, name: "filing press")
    @stamp = lying_here(@playthrough, @here, name: "ward stamp")
    @daybook = create(:item, :carried, :consumable, playthrough: @playthrough, name: "Ward Office 12 daybook")
  end

  # Returns `[intent, cascade]` -- nil intent means the line goes on to the
  # model call, and `cascade.path` says why.
  def read(answers, command: "take the ward stamp")
    agent = FakeSystemOne.new(CLEAR.merge(answers))
    cascade = Playthrough::Classifier::Cascade.new(@classifier, agent: agent)

    [ cascade.read(command), cascade, agent ]
  end

  # --- rule 1: only the chosen intent's target is read -----------------------

  test "the chosen intent's target is the one that resolves" do
    intent, cascade = read({ "intent" => "take", "target_take" => "available_item_2" })

    assert_predicate intent, :take?
    assert_equal @stamp, intent.item
    assert_equal "typed_model", cascade.path
  end

  test "every other action's target answer is discarded unread" do
    intent, = read({ "intent" => "take", "target_take" => "available_item_1",
                     "target_move" => "way_1", "target_talk" => "person_2",
                     "target_examine" => "player_item_1" })

    assert_equal @press, intent.item
    assert_nil intent.destination
    assert_nil intent.speaker
  end

  test "other reads no target at all" do
    intent, = read({ "intent" => "other", "target_take" => "available_item_1" }, command: "wonder about the weather")

    assert_equal :other, intent.action
    assert_nil intent.subject
    assert_nil intent.also_named
  end

  # A question that was never sent resolves to nothing by construction, which is
  # the same answer one extra round of wording would have bought.
  test "an action whose question was not sent resolves to nothing" do
    @playthrough.carried.destroy_all
    intent, = read({ "intent" => "drop" }, command: "put down the daybook")

    assert_predicate intent, :drop?
    assert_nil intent.item
    assert_predicate intent, :reached_for_nothing?
  end

  test "nothing resolves to no record and keeps the requested intent" do
    intent, = read({ "intent" => "move", "target_move" => "nothing" }, command: "go down to the cellar")

    assert_predicate intent, :move?
    assert_nil intent.destination
  end

  # --- rule 2: also_named, through the chosen intent's own set ---------------

  test "a second name out of the same set is the record the turn is not acting on" do
    intent, = read({ "intent" => "take", "target_take" => "available_item_1", "also_named" => "available_item_2" },
                   command: "take the press and the stamp")

    assert_equal @press, intent.item
    assert_equal @stamp, intent.also_named
    assert_predicate intent, :named_more_than_one?
  end

  # THE ANSWER IS ASKED OVER EVERY RECORD, so it can name one this action cannot
  # reach. That is not a second act on this line and the engine drops it.
  test "a second name this action cannot reach is dropped" do
    intent, = read({ "intent" => "take", "target_take" => "available_item_1", "also_named" => "person_1" },
                   command: "take the press and ask Perrin about it")

    assert_equal @press, intent.item
    assert_nil intent.also_named
    assert_not_predicate intent, :named_more_than_one?
  end

  test "a second name that is the target is one record and not two" do
    intent, = read({ "intent" => "take", "target_take" => "available_item_1", "also_named" => "available_item_1" })

    assert_equal @press, intent.item
    assert_nil intent.also_named
  end

  # --- rule 3: the presence gate --------------------------------------------

  # 0.15 is the threshold of record: chosen on the fixed 80-line trial slice,
  # confirmed on the 263-line holdout, never tuned on the corpus that scores it.
  test "a reading below the presence threshold escalates rather than composing" do
    intent, cascade = read({ "intent" => "talk", "target_talk" => "person_1", "target_present" => 0.05 },
                           command: "ask my landlord for another week")

    assert_nil intent
    assert_equal "typed_model_escalated", cascade.path
  end

  test "a reading exactly at the presence threshold is composed" do
    intent, cascade = read({ "intent" => "take", "target_take" => "available_item_1", "target_present" => 0.15 })

    assert_equal @press, intent.item
    assert_equal "typed_model", cascade.path
  end

  # THE GATE ITSELF, reached by driving the composition with the escalation rule
  # out of the way. It cannot fire under today's rule -- a low reading has
  # already escalated -- and it is asserted anyway because it is what keeps
  # `nothing (and a record)` unreachable if that rule ever changes.
  test "a discarded target discards also_named with it" do
    agent = FakeSystemOne.new(CLEAR.merge("intent" => "take", "target_take" => "available_item_1",
                                          "also_named" => "available_item_2", "target_present" => 0.02))
    cascade = Playthrough::Classifier::Cascade.new(@classifier, agent: agent)
    intent = cascade.stub(:escalate?, false) { cascade.read("take the press and the stamp") }

    assert_equal "typed_model", cascade.path
    assert_nil intent.item, "a target below the presence threshold survived the gate"
    assert_nil intent.also_named, "the engine emitted `nothing` and a record"
  end

  # --- rule 4: the two-name flag --------------------------------------------

  test "a two-name reading at the threshold escalates" do
    intent, cascade = read({ "intent" => "take", "target_take" => "available_item_1",
                             "also_named" => "available_item_2", "named_more_than_one" => 0.5 },
                           command: "take the press and the stamp")

    assert_nil intent
    assert_equal "typed_model_escalated", cascade.path
  end

  test "a two-name reading below the threshold is composed and both names survive" do
    intent, cascade = read({ "intent" => "take", "target_take" => "available_item_1",
                             "also_named" => "available_item_2", "named_more_than_one" => 0.49 },
                           command: "take the press and the stamp")

    assert_equal "typed_model", cascade.path
    assert_predicate intent, :named_more_than_one?, "both names survived and the refusal did not follow"
  end

  # A line asking for absent things is ONE unresolved act, not two: the presence
  # flag escalates it before the two-name flag can turn it into an overreach.
  test "a low presence reading and a two-name reading escalate on one call" do
    _, cascade, agent = read({ "intent" => "talk", "named_more_than_one" => 0.91, "target_present" => 0.03 },
                             command: "ask the landlord and the clerk about it")

    assert_equal "typed_model_escalated", cascade.path
    assert_equal 1, agent.calls, "an escalated line asked System One twice"
  end

  # --- rule 4, read against the composition it is NOT allowed to depend on ---
  #
  # THE THREE TESTS BELOW ARE COUNTERFACTUALS AND NOT NEW RULES. The measured
  # cascade escalated about 90 lines of the 343-line corpus a repetition and the
  # shipped one escalates about 62, and the three shapes below are the coded
  # defects that difference was attributed to. Each one is written so that it
  # FAILS if the composition ever acquires that shape -- a flag consulted only
  # once a record survived, a second name thrown away on a line the engine
  # answered, or a second name lost on the way through an escalation. They pass
  # today: replaying the measured arm's own 1,112 recorded provider answers
  # through this class escalates 90, 90, 91 and 93, which is the simulation to
  # the line. See the header.

  # THE FLAG IS READ OFF THE ANSWER AND NOT OFF THE COMPOSITION. Were it
  # consulted only when `also_named` had already resolved a record, it would
  # collapse to "both names survived" and this line would compose.
  test "the two-name flag escalates even when also_named resolved nothing" do
    intent, cascade = read({ "intent" => "take", "target_take" => "available_item_1",
                             "also_named" => Playthrough::IntentSchema::NOTHING,
                             "named_more_than_one" => 0.91 },
                           command: "take the press and whatever else is going")

    assert_nil intent
    assert_equal "typed_model_escalated", cascade.path
  end

  # The same test from the other side: a second name the chosen action cannot
  # reach is dropped by the composition, and the flag still escalates.
  test "the two-name flag escalates even when the second name is not this action's" do
    intent, cascade = read({ "intent" => "take", "target_take" => "available_item_1",
                             "also_named" => "person_1", "named_more_than_one" => 0.77 },
                           command: "take the press and ask Perrin about it")

    assert_nil intent
    assert_equal "typed_model_escalated", cascade.path
  end

  # NOR ON THE TARGET. A line whose target resolved to nothing is still two
  # names to the flag, and the escalation is decided before either is resolved.
  test "the two-name flag escalates even when the target resolved nothing" do
    intent, cascade = read({ "intent" => "take", "target_take" => Playthrough::IntentSchema::NOTHING,
                             "named_more_than_one" => 0.88 },
                           command: "take the crowbar and the ledger")

    assert_nil intent
    assert_equal "typed_model_escalated", cascade.path
  end

  # THE TYPED READER'S SECOND NAME SURVIVES A LINE THE ENGINE ANSWERS ITSELF.
  # Losing it here is the difference between the second-name recall the arm of
  # record measured and the one the shipped set reads.
  test "a composed line keeps the typed reader's second name and refuses on both records" do
    intent, cascade = read({ "intent" => "take", "target_take" => "available_item_1",
                             "also_named" => "available_item_2", "named_more_than_one" => 0.31 },
                           command: "take the press and the stamp")

    assert_equal "typed_model", cascade.path
    assert_equal @press, intent.item
    assert_equal @stamp, intent.also_named

    refusal = Playthrough::Refusal.for(intent, typed: "take the press and the stamp")
    assert_equal :named_more_than_one, refusal.kind
    assert_includes refusal.fact, "filing press"
    assert_includes refusal.fact, "ward stamp"
  end

  # --- rule 5: unresolved is derived, never answered -------------------------

  test "unresolved is derived from a reaching intent with no target" do
    intent, = read({ "intent" => "move", "target_move" => "nothing" }, command: "go down to the cellar")

    assert_predicate intent, :reached_for_nothing?
    assert_predicate intent, :refused?
  end

  # --- rule 6: unreadable and immovable stay engine-owned --------------------

  # `unknown_action` can only come from an answer outside the closed table, and
  # the intent question IS the closed table -- so this reader cannot produce one.
  test "a composed reading is never unreadable" do
    intent, = read({ "intent" => "take", "target_take" => "available_item_1" })

    assert_not_predicate intent, :unreadable?
    assert_nil intent.unknown_action
  end

  # Bulk is a fact in the item table and was ruled out of the model's hands. The
  # cascade resolves the record; the engine still decides it does not move.
  test "an immovable thing is refused off the record and not off the answer" do
    anvil = lying_here(@playthrough, @here, :immovable, name: "ward anvil")
    state = Playthrough::Classifier::State.new(@classifier, "take the anvil")
    key = state.keys_for(:take).find { |candidate| state.record_for(candidate) == anvil }

    intent, = read({ "intent" => "take", "target_take" => key }, command: "take the anvil")

    assert_equal anvil, intent.item
    assert_predicate intent, :takes_the_immovable?
    assert_predicate intent, :refused?
  end

  # --- a use, which resolves a whole closed attempt --------------------------

  test "a use resolves to the attempt token, exactly as the model call does" do
    state = Playthrough::Classifier::State.new(@classifier, "drink the daybook")
    key = state.keys_for(:use).first
    intent, = read({ "intent" => "use", "target_use" => key }, command: "drink the daybook")

    assert_equal :use, intent.action
    assert_not_nil intent.physical
    assert_equal @daybook, intent.subject
  end

  # --- the provider, when it cannot be believed ------------------------------

  test "a provider failure is not a refusal and sends the line to the model call" do
    cascade = Playthrough::Classifier::Cascade.new(
      @classifier, agent: FakeSystemOne.new(SystemOneAgent::Unavailable.new("timed out"))
    )

    assert_nil cascade.read("take the ward stamp")
    assert_equal "typed_model_unavailable", cascade.path
  end

  test "an answer set that does not match the questions sent falls through" do
    cascade = Playthrough::Classifier::Cascade.new(
      @classifier, agent: FakeSystemOne.new({ "answers" => { "intent" => { "type" => "choice", "choice" => "take" } } })
    )

    assert_nil cascade.read("take the ward stamp")
    assert_equal "typed_model_unavailable", cascade.path
  end

  test "a choice outside the options sent falls through" do
    cascade = Playthrough::Classifier::Cascade.new(
      @classifier, agent: FakeSystemOne.new(CLEAR.merge("intent" => "take", "target_take" => "way_1"))
    )

    assert_nil cascade.read("take the ward stamp")
    assert_equal "typed_model_unavailable", cascade.path
  end

  # --- what was sent ---------------------------------------------------------

  test "the request carries the line the player typed and the position they are in" do
    _, _, agent = read({ "intent" => "talk", "target_talk" => "person_2" }, command: "ask Rowe about the hour")

    assert_equal "ask Rowe about the hour", agent.states.first["player_action"]
    assert_equal "Ward Office 12", agent.states.first["location"]
    assert_equal 11, agent.questions.first.size
  end

  test "the thresholds are the ones the measurement chose" do
    assert_in_delta 0.15, Playthrough::Classifier::Cascade::PRESENCE_THRESHOLD, 0.0001
    assert_in_delta 0.5, Playthrough::Classifier::Cascade::TWO_NAME_THRESHOLD, 0.0001
  end
end
