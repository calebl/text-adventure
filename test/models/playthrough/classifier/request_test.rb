require "test_helper"

# WHAT IS ACTUALLY SENT. The questions are measured text, so most of what is
# worth pinning here is structural: that the option set of each target question
# IS its own action's closed set and nothing else, that a question with no
# records is not sent at all, and that the criteria are keyed by the same keys
# the state uses and the composition resolves.
#
# AND THE WORDING ITSELF IS PINNED AGAINST THE ARM THAT WAS SCORED, at the
# bottom of this file, because it once quietly was not: the shipped
# `also_named` and per-action target sentences were an earlier revision of
# themselves and nothing was comparing them to anything.
# `test/fixtures/files/scored_classifier_request.json` is the design of record's
# own stored request -- the collective-word arm with the presence question
# appended, for the position `ask Rowe and Perrin what happened at four
# o'clock` was sent in -- and `#the_scored_position` rebuilds that position out
# of records so the two can be compared string by string.
class Playthrough::Classifier::RequestTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ward Office 12")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    @classifier = Playthrough::Classifier.new(@playthrough)
  end

  def a_full_position
    @closet = create(:location, story: @story, name: "The Supply Closet")
    create(:location_connection, location: @here, connected_location: @closet)
    @perrin = create(:character, story: @story, location: @here, fullname: "Perrin Lasco", nickname: "Perrin")
    @press = lying_here(@playthrough, @here, name: "filing press")
    @daybook = create(:item, :carried, :consumable, playthrough: @playthrough, name: "Ward Office 12 daybook")
  end

  def questions(command = "take the filing press")
    state = Playthrough::Classifier::State.new(@classifier, command)
    Playthrough::Classifier::Request.new(state).to_h
  end

  # --- what is asked --------------------------------------------------------

  test "a full position asks ten questions" do
    a_full_position

    assert_equal %w[intent target_move target_talk target_attack target_take target_drop
                    target_examine target_use also_named named_more_than_one target_present],
                 questions.keys
  end

  test "a target question whose record set is empty is not sent at all" do
    asked = questions

    assert_equal %w[intent named_more_than_one target_present], asked.keys
    assert_not asked.key?("target_take"), "a room with nothing in it asked what to pick up"
  end

  test "the options of a target question are that action's closed set plus nothing" do
    a_full_position

    assert_equal [ "available_item_1", Playthrough::IntentSchema::NOTHING ],
                 questions["target_take"]["criteria"].keys
    assert_equal [ "available_item_1", "player_item_1", Playthrough::IntentSchema::NOTHING ],
                 questions["target_examine"]["criteria"].keys
    assert_equal [ "person_1", Playthrough::IntentSchema::NOTHING ],
                 questions["target_attack"]["criteria"].keys
  end

  # THE WHOLE POINT OF ONE QUESTION PER ACTION. A doorway is not an option of
  # `target_take`, so a `take` answering with one is not a thing the engine has
  # to null -- it is a thing the provider cannot say.
  test "a record another action reaches is not an option of this one" do
    a_full_position

    assert_not_includes questions["target_take"]["criteria"].keys, "way_1"
    assert_not_includes questions["target_move"]["criteria"].keys, "available_item_1"
  end

  test "a criterion describes its option by the name the record answers to" do
    a_full_position

    assert_equal "filing press", questions["target_take"]["criteria"]["available_item_1"]
    assert_equal "Perrin Lasco", questions["target_talk"]["criteria"]["person_1"]
  end

  # `also_named` is asked before anybody has decided what the line is, so it
  # offers everything; narrowing it to the chosen intent is the engine's job.
  test "also_named is asked over every record in the position" do
    a_full_position
    asked = questions["also_named"]["criteria"].keys

    assert_equal %w[way_1 person_1 available_item_1 player_item_1 attempt_1 nothing], asked
  end

  test "a position with no records at all asks no also_named" do
    assert_not questions.key?("also_named")
  end

  # --- the types ------------------------------------------------------------

  test "the two flags are nouls and everything else is a choice" do
    a_full_position
    asked = questions

    assert_equal %w[noul noul], asked.values_at("named_more_than_one", "target_present").map { |q| q["type"] }
    assert_equal [ "choice" ], (asked.keys - %w[named_more_than_one target_present])
                                 .map { |id| asked[id]["type"] }.uniq
  end

  test "the intent question offers the closed enum and nothing else" do
    assert_equal Playthrough::IntentSchema::INTENTS, questions["intent"]["criteria"].keys
  end

  # --- the one wording change -----------------------------------------------

  # BOTH READERS OR NEITHER. Two definitions of `examine` would make the
  # escalation itself a source of disagreement, which is the one thing a cascade
  # must not add.
  test "examine admits a look at the room in general, in both readers" do
    assert_includes questions["intent"]["criteria"]["examine"], "looking around the place in general"
    assert_includes Playthrough::Classifier::INSTRUCTIONS,
                    "examine - they are looking at something more closely, or looking around\n" \
                    "            the place in general"
  end

  # The clause was measured MISSING once: without it a collective phrasing has no
  # single record to point at, and 11 lines went with it.
  test "a target question tells the model a collective request still picks one" do
    a_full_position

    assert_includes questions["target_take"]["instructions"],
                    "answer with one of them, never `#{Playthrough::IntentSchema::NOTHING}`; `also_named` handles another."
  end

  test "every target question is asked under its own premise" do
    a_full_position

    assert questions["target_move"]["instructions"]
      .start_with?("Assume, for this question only, that the player is crossing a doorway to another location.")
    assert questions["target_use"]["instructions"]
      .start_with?("Assume, for this question only, that the player is consuming or burning an item,")
  end

  test "the id a target answer is read from is one definition" do
    assert_equal "target_examine", Playthrough::Classifier::Request.target_id(:examine)
    assert_equal "target_examine", Playthrough::Classifier::Request.target_id("examine")
  end

  # --- the request against the arm that was scored --------------------------
  #
  # THE FIXTURE IS EVIDENCE, NOT A GOLDEN FILE TO REGENERATE. It is the request
  # the design of record was measured on, kept byte for byte; a sentence here
  # that no longer matches it means the prompt has changed, and a prompt change
  # is a measured change -- `EVALUATION.md`. Updating the fixture to match new
  # code would be the one thing that makes it worthless.

  SCORED_REQUEST_FIXTURE = "scored_classifier_request.json".freeze

  def scored_request
    JSON.parse(file_fixture(SCORED_REQUEST_FIXTURE).read)
  end

  # The position `ask Rowe and Perrin what happened at four o'clock` was sent
  # in: two ways out, two people with one alias each, two things lying here, one
  # carried, and therefore two complete offer attempts.
  def the_scored_position
    hallway = create(:location, story: @story, name: "The Long Hallway")
    create(:location_connection, location: @here, connected_location: hallway)
    create(:character, story: @story, location: @here, fullname: "Halkett Rowe", nickname: "Sub-Inspector Rowe")
    lying_here(@playthrough, @here, name: "ward stamp")
  end

  # THE ONE DIFFERENCE THAT IS ALLOWED, and it is named rather than tolerated:
  # `examine` gained "or looking around the place in general" as this ship's one
  # deliberate prompt change, and it has its own baseline either side of it
  # (`db/eval/classifier-examine-before-20260918` and
  # `classifier-examine-wording-20260918`). Anything else differing is drift.
  EXAMINE_EDIT = [ "without moving or taking it.", "without moving or taking it, or looking around the place in general." ].freeze

  test "every instruction string is the text of the arm the design of record was scored on" do
    a_full_position
    the_scored_position
    scored = scored_request.fetch("questions")
    asked = questions("ask Rowe and Perrin what happened at four o'clock")

    assert_equal scored.keys, asked.keys, "the questions asked are not the questions that were scored"
    scored.each do |id, question|
      assert_equal question.fetch("instructions"), asked.fetch(id)["instructions"],
                   "#{id}'s instructions are not the scored arm's -- a prompt change needs a baseline either side"
    end
  end

  test "nothing else in the request differs from the scored arm but the one deliberate examine edit" do
    a_full_position
    the_scored_position
    scored = scored_request.fetch("questions")
    asked = questions("ask Rowe and Perrin what happened at four o'clock")

    scored.each do |id, question|
      assert_equal question.fetch("type"), asked.fetch(id)["type"]
      wanted = question.fetch("criteria")
      wanted = wanted.merge("examine" => wanted.fetch("examine").sub(*EXAMINE_EDIT)) if id == "intent"
      assert_equal wanted, asked.fetch(id)["criteria"],
                   "#{id}'s criteria are not the scored arm's"
    end
  end

  # WHAT THE COLLECTIVE-WORD PASS BOUGHT, in the two sentences it bought it
  # with. Named here so a later edit that drops them has to argue with a test
  # rather than with a paragraph.
  test "both questions name the collective words and the and-then continuation" do
    a_full_position

    [ questions["target_take"]["instructions"], questions["also_named"]["instructions"] ].each do |text|
      assert_includes text, "all of it"
      assert_includes text, "`and then`"
    end
    assert_includes questions["target_take"]["instructions"], "never `#{Playthrough::IntentSchema::NOTHING}`"
  end
end
