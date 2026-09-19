require "test_helper"

# THE ONE TABLE TEST. `Playthrough::Classifier::State` exists to say the
# position in records rather than in prose, and the whole of its correctness is
# that it says the SAME thing `Playthrough::Classifier#offered_for` says -- which
# is what the closed enum, the refusals and the resolution all read. So the test
# that matters walks every action in the closed enum and asserts the two agree
# in both directions: nothing an action can reach is missing from the state, and
# nothing in the state claims an intent that action's own set does not hold.
class Playthrough::Classifier::StateTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ward Office 12")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
    @classifier = Playthrough::Classifier.new(@playthrough)
  end

  # A FULL POSITION: a way out, two people, two things on the floor, one carried
  # and a physical attempt built out of them. Every group has something in it, so
  # a group this builder forgot cannot pass by being empty.
  def a_full_position
    @closet = create(:location, story: @story, name: "The Supply Closet")
    create(:location_connection, location: @here, connected_location: @closet)
    @perrin = create(:character, story: @story, location: @here, fullname: "Perrin Lasco", nickname: "Perrin")
    @rowe = create(:character, story: @story, location: @here, fullname: "Halkett Rowe", nickname: nil)
    @press = lying_here(@playthrough, @here, name: "filing press")
    @stamp = lying_here(@playthrough, @here, name: "ward stamp")
    @daybook = create(:item, :carried, :consumable, playthrough: @playthrough, name: "Ward Office 12 daybook")
  end

  def state(command = "take the ward stamp")
    Playthrough::Classifier::State.new(@classifier, command)
  end

  # --- the one table --------------------------------------------------------

  test "every record an action can reach is in the state, carrying that action" do
    a_full_position
    built = state

    Playthrough::IntentSchema::INTENTS.each do |intent|
      @classifier.offered_for(intent).each do |record|
        key = built.all_keys.find { |candidate| built.record_for(candidate) == record }

        assert_not_nil key, "#{intent} can reach #{record.inspect} and the state does not list it"
        assert_includes built.to_h.values.grep(Hash).flat_map(&:values)
                             .find { |entry| entry["name"] == built.label_for(record) }["valid_intents"],
                        intent,
                        "#{record.inspect} is reachable by #{intent} and does not say so"
      end
    end
  end

  test "no record claims an intent whose own closed set does not hold it" do
    a_full_position
    built = state

    built.all_keys.each do |key|
      record = built.record_for(key)

      built.intents_for(record).each do |intent|
        assert_includes @classifier.offered_for(intent), record,
                        "#{key} claims #{intent}, which does not offer it"
      end
    end
  end

  # `examine` and `attack` have no state block of their own -- one reads both
  # item lists and the other reads the cast -- so the only place they can appear
  # is a record's derived intents. That they DO appear is what proves the
  # derivation is a derivation and not a written-down list of the five groups.
  test "an action with no block of its own still reaches its records" do
    a_full_position
    built = state

    # In `Playthrough::IntentSchema::INTENTS` order, because that is the order
    # the derivation walks and a reader comparing two rooms wants one order.
    assert_equal %w[examine take], built.intents_for(@press)
    assert_equal %w[examine drop], built.intents_for(@daybook)
    assert_equal %w[talk attack], built.intents_for(@rowe)
    assert_equal %w[move], built.intents_for(@closet)
  end

  test "an intent that reaches nothing is on no record at all" do
    a_full_position
    built = state

    assert_empty built.all_keys.select { |key| built.intents_for(built.record_for(key)).include?("other") }
  end

  # --- the shape ------------------------------------------------------------

  test "the state names where the player stands and the line they typed" do
    built = state("ask Rowe what happened at four o'clock").to_h

    assert_equal "Ward Office 12", built["location"]
    assert_equal "ask Rowe what happened at four o'clock", built["player_action"]
  end

  # AN EMPTY BLOCK IS SENT, AS AN EMPTY MAP. This file once asserted the
  # opposite, and the opposite was never measured: every reading the cascade
  # rests on came off a state that sent all five blocks whatever was in them.
  # A block that is present and empty says "there is nothing of this kind here";
  # an absent block says nothing and leaves the absence to be inferred. The
  # QUESTION over an empty block is still not asked -- that is
  # `Playthrough::Classifier::Request`'s decision, and it reads `#keys_for`
  # rather than this.
  test "an empty group is sent as an empty map rather than left out" do
    built = state.to_h

    Playthrough::Classifier::State::GROUPS.each do |group|
      assert_equal({}, built[group.key], "#{group.key} was left out of a bare room instead of sent empty")
    end
    assert_not Playthrough::Classifier::Request.new(state).to_h.key?("target_take"),
               "an empty block must still not be asked a question"
  end

  test "player_action comes last, after every record block" do
    a_full_position

    assert_equal "player_action", state.to_h.keys.last
  end

  # --- byte for byte against the arm that was scored ------------------------
  #
  # THE FIXTURE IS THE REQUEST THE DESIGN OF RECORD WAS MEASURED ON, kept whole.
  # The state is half of that request and is as much a measured thing as the
  # wording is: a block order, an empty block, an intent list order. This test
  # is what caught all three drifting, and it is the reason the fixture is in
  # the repository rather than in somebody's notes.

  def the_scored_position
    a_full_position
    @rowe.update!(nickname: "Sub-Inspector Rowe")
    hallway = create(:location, story: @story, name: "The Long Hallway")
    create(:location_connection, location: @here, connected_location: hallway)
  end

  test "a staged position is the state the arm was scored on, byte for byte" do
    the_scored_position
    scored = JSON.parse(file_fixture("scored_classifier_request.json").read).fetch("state")
    built = state(scored.fetch("player_action")).to_h

    assert_equal scored.to_json, built.to_json,
                 "the state is half the request and every figure was read off this shape"
  end

  test "every block leads with its own intent, which is the order that was measured" do
    the_scored_position
    built = state.to_h

    assert_equal %w[take examine], built.dig("available_items", "available_item_1", "valid_intents")
    assert_equal %w[drop examine], built.dig("player_items", "player_item_1", "valid_intents")
    assert_equal %w[talk attack], built.dig("other_characters", "person_1", "valid_intents")
    assert_equal %w[move], built.dig("ways_out", "way_1", "valid_intents")
    assert_equal %w[use], built.dig("physical_actions", "attempt_1", "valid_intents")
  end

  test "each group says what kind of record it holds" do
    a_full_position
    built = state.to_h

    assert_equal "way out", built.dig("ways_out", "way_1", "kind")
    assert_equal "person present here", built.dig("other_characters", "person_1", "kind")
    assert_equal "item lying here", built.dig("available_items", "available_item_1", "kind")
    assert_equal "item the player is carrying", built.dig("player_items", "player_item_1", "kind")
    assert_equal "one complete physical action attempt", built.dig("physical_actions", "attempt_1", "kind")
  end

  # ALIASES ARE `Character#nickname` AND NOTHING ELSE. A place or a thing has one
  # name, so the key is absent rather than empty; a person whose nickname is
  # their fullname is one name too.
  test "a nickname is the only alias any record carries" do
    a_full_position
    built = state.to_h

    perrin = built["other_characters"].values.find { |entry| entry["name"] == "Perrin Lasco" }
    rowe = built["other_characters"].values.find { |entry| entry["name"] == "Halkett Rowe" }

    assert_equal [ "Perrin" ], perrin["aliases"]
    assert_not rowe.key?("aliases")
    assert_not built.dig("ways_out", "way_1").key?("aliases")
    assert_not built.dig("available_items", "available_item_1").key?("aliases")
  end

  test "a key resolves back to the record it was built from, and nothing else does" do
    a_full_position
    built = state

    assert_equal @stamp, built.record_for("available_item_2")
    assert_nil built.record_for(Playthrough::IntentSchema::NOTHING)
    assert_nil built.record_for("way_9")
  end

  test "the keys one action offers are its own closed set in state order" do
    a_full_position
    built = state

    assert_equal %w[available_item_1 available_item_2], built.keys_for(:take)
    assert_equal %w[available_item_1 available_item_2 player_item_1], built.keys_for(:examine)
    assert_equal %w[person_1 person_2], built.keys_for(:attack)
    assert_empty built.keys_for(:other)
  end

  test "whether one action offers a record is asked of the same table" do
    a_full_position
    built = state

    assert built.offers?(:take, @press)
    assert_not built.offers?(:drop, @press)
    assert built.offers?(:examine, @press)
  end
end
