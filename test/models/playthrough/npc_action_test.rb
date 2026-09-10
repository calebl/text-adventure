require "test_helper"

class Playthrough::NpcActionTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @room = create(:location, story: @story, name: "Market")
    @yard = create(:location, story: @story, name: "Courtyard")
    @player = create(:character, :protagonist, story: @story, level: 10)
    @maren = create(:character, story: @story, location: @room, fullname: "Maren", nickname: "Maren", age: 32, sex: "female", level: 10)
    @template = create(:item, character: @maren, name: "brass key")
    @game = create(:playthrough, story: @story, character: @player, current_location: @room)
    @key = @game.items_held_by(@maren).sole
    @actions = Playthrough::NpcAction.new(@game, @maren)
  end

  test "a gift moves only the speaker's copy and cannot repeat or touch a template" do
    result = @actions.apply!("give:#{@key.id}")

    assert_predicate result, :applied?
    assert_includes @game.carried, @key
    assert_equal @maren, @template.reload.character
    assert_equal "rejected", @actions.apply!("give:#{@key.id}").status
    assert_equal "rejected", @actions.apply!("give:#{@template.id}").status
    second = create(:playthrough, story: @story, character: @player, current_location: @room)
    assert_equal [ "brass key" ], second.items_held_by(@maren).pluck(:name)
  end

  test "foreign items unknown choices and absent or dead speakers cannot act" do
    outsider = create(:character, story: @story, location: @yard)
    other = create(:item, character: outsider)
    assert_equal "rejected", @actions.apply!("give:#{other.id}").status
    assert_equal "rejected", @actions.apply!("teleport").status

    @maren.update!(location: @yard)
    assert_equal [ "none" ], @actions.choices.keys
    assert_equal "rejected", @actions.apply!("follow").status
    @maren.update!(location: @room)
    Playthrough::Turn.new(@game).harm!(@maren, @maren.max_hp)
    assert_equal [ "none" ], @actions.choices.keys
    assert_equal "rejected", @actions.apply!("ceasefire").status
  end

  test "a follower travels through the turn writer and stays after changing their mind" do
    assert_predicate @actions.apply!("follow"), :applied?
    assert_includes @game.cast_on_arrival(@yard), @maren
    Playthrough::Turn.new(@game).stand_in!(@yard)

    assert_includes @game.cast_in(@yard), @maren
    assert_not_includes @game.cast_in(@room), @maren
    assert_equal @room, @maren.reload.location
    assert_predicate @actions.apply!("stop_following"), :applied?
    Playthrough::Turn.new(@game).stand_in!(@room)
    assert_includes @game.cast_in(@yard), @maren
    assert_not_includes @game.cast_in(@room), @maren
  end

  test "one game's following never moves the character in another game" do
    @actions.apply!("follow")
    Playthrough::Turn.new(@game).stand_in!(@yard)
    other = create(:playthrough, story: @story, character: @player, current_location: @room)

    assert_includes other.cast_in(@room), @maren
    assert_not_includes other.cast_in(@yard), @maren
  end

  test "a relocated follower keeps their inventory and snapshots new possessions once" do
    @actions.apply!("follow")
    Playthrough::Turn.new(@game).stand_in!(@yard)
    lantern = create(:item, character: @maren, name: "lantern")
    2.times { Playthrough::Snapshot.new(@game).of_the_room!(@yard) }

    assert_equal [ "brass key", "lantern" ], @game.items_held_by(@maren).pluck(:name)
    assert_equal 1, @game.items.where(template: lantern).count
    assert_equal @maren, lantern.reload.character
  end

  test "a ceasefire stops natural and provoked hostility until a new player blow" do
    @maren.update!(hostile: true)
    turn = Playthrough::Turn.new(@game)
    turn.strike!(@player, @maren, round: 1)
    assert_includes @game.foes_in(@room), @maren

    assert_predicate @actions.apply!("ceasefire"), :applied?
    assert_empty @game.foes_in(@room)
    assert_not @game.provoked?(@maren)
    assert_predicate @maren.reload, :hostile?
    assert_no_difference("Playthrough::Blow.count") do
      Playthrough::Riposte.new(@game, turn: turn).run!(location: @room, round: 2)
    end

    turn.strike!(@player, @maren, round: 3)
    assert_includes @game.foes_in(@room), @maren
    assert @game.provoked?(@maren)
  end

  test "dead followers stay at the place they died" do
    @actions.apply!("follow")
    Playthrough::Turn.new(@game).stand_in!(@yard)
    Playthrough::Turn.new(@game).harm!(@maren, @maren.max_hp)
    Playthrough::Turn.new(@game).stand_in!(@room)

    assert_includes @game.characters_located_in(@yard), @maren
    assert_not_includes @game.characters_located_in(@room), @maren
    assert_equal @yard, @key.reload.location
    assert_nil @key.character_id
    assert_equal @room, @maren.reload.location
  end

  test "a legacy companion's body no longer follows the party after death" do
    companion = create(:character, story: @story, is_companion: true, location: nil, age: 32, sex: "female")
    lantern = create(:item, character: companion, name: "companion lantern")
    Playthrough::Snapshot.new(@game).of_the_room!(@room)
    copy = @game.items.find_by!(template: lantern)
    Playthrough::Turn.new(@game).harm!(companion, companion.max_hp)
    Playthrough::Turn.new(@game).stand_in!(@yard)

    assert_includes @game.characters_located_in(@room), companion
    assert_not_includes @game.characters_located_in(@yard), companion
    assert_equal @room, copy.reload.location
    assert_nil companion.reload.location_id
  end

  test "a legacy companion can agree to stay on the first conversation" do
    companion = create(:character, story: @story, is_companion: true, location: nil, age: 32, sex: "female")
    actions = Playthrough::NpcAction.new(@game, companion)

    assert_includes actions.choices, "stop_following"
    assert_not_includes actions.choices, "follow"
    assert_predicate actions.apply!("stop_following"), :applied?
    Playthrough::Turn.new(@game).stand_in!(@yard)
    assert_includes @game.cast_in(@room), companion
    assert_not_includes @game.cast_in(@yard), companion
  end
end
