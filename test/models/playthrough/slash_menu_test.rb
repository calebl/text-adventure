require "test_helper"

# WHAT THE BOX OFFERS, and the one claim worth testing about it: it is the same
# closed sets the engine reads back, and it invents nothing.
class Playthrough::SlashMenuTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @vance = create(:character, story: @story, fullname: "Odile Vance", is_protagonist: true)
    @office = create(:location, story: @story, name: "Ward Office 12")
    @closet = create(:location, story: @story, name: "The Supply Closet")
    create(:location_connection, location: @office, connected_location: @closet,
                                 distance: "adjacent", travel_method: "walking")
    create(:location_connection, location: @closet, connected_location: @office,
                                 distance: "adjacent", travel_method: "walking")

    @rowe = create(:character, story: @story, fullname: "Halkett Rowe", nickname: "Rowe", location: @office)
    @playthrough = create(:playthrough, story: @story, character: @vance, current_location: @office)
    @stamp = create(:item, :lying, playthrough: @playthrough, location: @office, name: "ward stamp")
    @daybook = create(:item, :carried, playthrough: @playthrough, name: "Ward Office 12 daybook")
  end

  def menu = Playthrough::SlashMenu.new(@playthrough).to_h

  test "it offers the five verbs that resolve a record and no others" do
    assert_equal %w[go talk take drop read], menu[:verbs].map { |verb| verb[:word] }
    assert(menu[:verbs].all? { |verb| verb[:hint].present? })
  end

  test "each verb carries the closed set its action reads against, this turn" do
    assert_equal [ "The Supply Closet" ], menu[:targets]["go"]
    assert_equal [ "Halkett Rowe" ], menu[:targets]["talk"]
    assert_equal [ "ward stamp" ], menu[:targets]["take"]
    assert_equal [ "Ward Office 12 daybook" ], menu[:targets]["drop"]
    assert_equal [ "ward stamp", "Ward Office 12 daybook" ], menu[:targets]["read"]
  end

  # THE SAME LISTS, AND NOT A SECOND COPY OF THEM. Whatever the classifier is
  # offered for an action is what the box offers, or the player would be shown a
  # completion the engine refuses.
  test "it is the classifier's own offered sets, name for name" do
    classifier = Playthrough::Classifier.new(@playthrough)

    Playthrough::Grammar::RESOLVING.each do |word, action|
      expected = classifier.offered_for(action).map { |record| Playthrough::Classifier.label_for(record) }

      assert_equal expected.uniq, menu[:targets][word], "the #{word} menu should be #{action}'s closed set"
    end
  end

  # A nickname is matched by both resolvers and is deliberately NOT offered:
  # one person twice in a menu reads as two people.
  test "somebody is offered once, by the name a refusal would give them" do
    assert_equal [ "Halkett Rowe" ], menu[:targets]["talk"]
  end

  test "a turn that changed the room changes the menu with it" do
    @playthrough.update!(current_location: @closet)

    assert_equal [ "Ward Office 12" ], menu[:targets]["go"]
    assert_empty menu[:targets]["take"]
    assert_empty menu[:targets]["talk"]
    assert_equal [ "Ward Office 12 daybook" ], menu[:targets]["drop"]
  end

  # EVERY NAME IT OFFERS IS ONE THE GRAMMAR READS BACK, which is the whole
  # contract between the box and the engine: a completion the player accepts is
  # a line that resolves offline, for no model call. The box writes the `/`, and
  # since the captain's ruling of 2026-09-05 that slash is the whole of what
  # sends a line to the grammar -- so this test is the contract, not a detail.
  test "every name it offers resolves through the grammar it was written for" do
    grammar = Playthrough::Grammar.new(@playthrough)

    EngineSweep.without_a_model do
      Playthrough::Grammar::RESOLVING.each_key do |word|
        menu[:targets][word].each do |name|
          reading = grammar.reading_first("/#{word} #{name}")

          assert_predicate reading, :resolved?, "/#{word} #{name} should resolve offline"
          assert_equal name, Playthrough::Classifier.label_for(reading.intent.subject)
        end
      end
    end
  end

  test "it serializes to the JSON the form carries" do
    parsed = JSON.parse(Playthrough::SlashMenu.new(@playthrough).to_json)

    assert_equal %w[go talk take drop read], parsed["verbs"].map { |verb| verb["word"] }
    assert_equal [ "ward stamp" ], parsed["targets"]["take"]
  end
end
