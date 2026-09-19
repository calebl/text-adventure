require "test_helper"

# THE SIX COLUMNS, THEIR TWO RULES AND THE ONE PROMPT THEY REACH.
#
# The four prose fields are checked for a LENGTH and the two labels for
# MEMBERSHIP, which is the same pair of rules the stat block and the abilities
# are under one set of columns over -- and every one of them is nullable,
# because a database older than the columns is a real state.
class Character::DesiresTest < ActiveSupport::TestCase
  setup { @story = create(:story) }

  test "a character with none of the six is valid, because an old database is a real state" do
    assert_predicate build(:character, :without_desires, story: @story), :valid?
  end

  test "the four are refused past the limit and accepted at it" do
    Character::DESIRES.each do |field|
      assert_predicate build(:character, story: @story, field => "x" * Character::DESIRE_LIMIT), :valid?

      person = build(:character, story: @story, field => "x" * (Character::DESIRE_LIMIT + 1))

      assert_not person.valid?, "#{field} is capped at #{Character::DESIRE_LIMIT}"
    end
  end

  test "a pursuit outside the table is refused and every entry of it is accepted" do
    Character::PURSUIT_COLUMNS.each do |field|
      Character::PURSUIT_NAMES.each do |label|
        assert_predicate build(:character, story: @story, field => label), :valid?
      end

      assert_not build(:character, story: @story, field => "plot").valid?
    end
  end

  test "the two predicates are separate and neither widens into the other" do
    labelled = build(:character, :without_desires, story: @story, desire_pursuit: "keep", need_pursuit: "keep")

    assert_not_predicate labelled, :desires?
    assert_predicate labelled, :pursuits?

    prose_only = build(:character, story: @story)

    assert_predicate prose_only, :desires?
    assert_not_predicate prose_only, :pursuits?, "the two labels are not defaulted by the factory"
    assert_predicate build(:character, :driven, story: @story), :pursuits?
  end

  test "every label in the table has a column in the weight table, and the other way round" do
    assert_equal Character::PURSUIT_NAMES.sort, Playthrough::Volition::Weights::TABLE.keys.sort

    Playthrough::Volition::Weights::TABLE.each_value do |row|
      assert_equal Playthrough::Volition::Weights::SHAPES.sort, row.keys.sort
    end
    assert_nil Playthrough::Volition::Weights.row_for(nil), "no pursuit means no behaviour"
    assert_not Playthrough::Volition::Weights.weighted?("plot")
  end

  # --- the one prompt they reach, and the many they do not -----------------

  test "the four are on the character's own sheet" do
    person = create(:character, story: @story)
    sheet = person.interaction_instructions

    Character::DESIRES.each { |field| assert_includes sheet, person.public_send(field) }
  end

  test "the two labels are not on the sheet -- they are the engine's parameter" do
    person = create(:character, story: @story, desire_pursuit: "withhold", need_pursuit: "avoid")

    assert_not_includes person.interaction_instructions, "withhold"
    assert_not_includes person.interaction_instructions, "desire_pursuit"
  end

  test "somebody with no desires sends the prompt they always sent, byte for byte" do
    person = create(:character, :without_desires, story: @story)
    with = create(:character, story: @story, fullname: person.fullname + " II")

    assert_not_includes person.interaction_instructions, "what you want, and would say out loud:"
    assert_includes with.interaction_instructions, "what you want, and would say out loud:"
  end

  # --- and the narrator is never told any of it ----------------------------

  test "nothing a character wants reaches the narrator" do
    room = create(:location, story: @story)
    player = create(:character, :protagonist, story: @story)
    game = create(:playthrough, story: @story, character: player, current_location: room)
    person = create(:character, :driven, story: @story, location: room,
                                conscious_desire: "Vance wants the query answered in writing before seven")
    context = Playthrough::Moment.new(game).narration_context

    assert_includes context, person.fullname, "who is here is a fact the narrator is told"
    Character::DESIRES.each do |field|
      assert_not_includes context, person.public_send(field).to_s
    end
    assert_not_includes context, "obtain"
  end
end
