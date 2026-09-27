require "test_helper"

# EVERY ENGINE SENTENCE THAT NAMES A THING, ON A THING WHOSE NAME CARRIES ITS
# OWN ARTICLE. Generated item rows are stored as the model named them -- "a
# frayed cable tie" -- and a fact that put "the" in front of the column wrote
# "picked the a frayed cable tie up". Each fact and fallback is asked here
# directly, because a playthrough only reaches one of them per line.
class Playthrough::TurnItemArticleTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @here = create(:location, story: @story, name: "Cargo Deck")
    @there = create(:location, story: @story, name: "The Shaft")
    @kael = create(:character, :protagonist, story: @story, fullname: "Kael Veyra",
                                             level: 3, hit_die: 8, strength: 12, dexterity: 11, will: 10)
    @mira = create(:character, story: @story, fullname: "Mira Solis", location: @here,
                               level: 1, hit_die: 8, strength: 10, dexterity: 10, will: 10)
    @game = create(:playthrough, story: @story, character: @kael, current_location: @here)
    @turn = Playthrough::Turn.new(@game)
    @tie = create(:item, name: "a frayed cable tie", character: nil, playthrough: @game)
  end

  def rolling(*faces)
    Class.new do
      def initialize(faces) = @faces = faces
      def rand(range) = @faces.shift.clamp(range.first, range.last)
    end.new(faces)
  end

  def assert_one_article(text)
    assert_no_match(/\bthe (a|an|the) /i, text)
    assert_match(/the frayed cable tie/i, text)
  end

  test "the take fact names the thing once" do
    assert_one_article @turn.send(:taken_fact, @tie, @kael, @here)
  end

  test "the drop fact names the thing once" do
    assert_one_article @turn.send(:dropped_fact, @tie, @here, @kael)
  end

  test "the read fact names the thing once" do
    @tie.update!(readable: true, inscription: "PROPERTY OF DECK 4")

    assert_one_article @turn.send(:read_fact, @tie, "PROPERTY OF DECK 4")
  end

  test "every throw fact names the thing once" do
    struck = @turn.throw_item!(@tie, at: @mira, round: 1, rng: rolling(1, 1))
    assert_one_article @turn.thrown_fact(struck, @kael)

    other = create(:item, name: "the frayed cable tie", character: nil, playthrough: @game)
    fumbled = @turn.throw_item!(other, at: @there, round: 2, rng: rolling(20))
    assert_predicate fumbled, :fumbled?
    assert_one_article @turn.thrown_fact(fumbled, @kael)
  end
end
