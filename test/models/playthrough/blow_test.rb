require "test_helper"

# ONE BLOW LANDED IN ONE GAME. The durable per-round record of a fight, and this
# is the test of the ROW -- what it validates, what it reads back, and the one
# class method every blow's dice depend on.
class Playthrough::BlowTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story)
    @protagonist = create(:character, :protagonist, story: @story)
    @monster = create(:character, :monster, story: @story, location: @room, fullname: "Marek Sollen")
    @game = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
  end

  test "a blow needs everybody in it, a room, and the numbers" do
    blow = build(:playthrough_blow, playthrough: @game, attacker: @protagonist, target: @monster, location: @room)

    assert_predicate blow, :valid?
  end

  test "the numbers are whole and not negative" do
    blow = build(:playthrough_blow, playthrough: @game, damage: -1)

    assert_not blow.valid?
    assert_includes blow.errors[:damage].join, "greater than or equal to 0"
  end

  test "a round is counted from one" do
    assert_not build(:playthrough_blow, playthrough: @game, round: 0).valid?
  end

  # THE SEQUENCE COMES OFF THE ROWS AND NEVER OFF A COUNTER IN MEMORY. A fight
  # does not advance the story's clock until it ends, so `sequence` is the whole
  # of what tells one blow of it from the next -- and a counter would not
  # survive the process that held it, which is the property `Roll`'s header
  # calls load-bearing.
  test "the next sequence is this game's own blow count" do
    assert_equal 0, Playthrough::Blow.next_sequence(@game)

    create(:playthrough_blow, playthrough: @game)
    create(:playthrough_blow, playthrough: @game)

    assert_equal 2, Playthrough::Blow.next_sequence(@game)
  end

  test "another game's blows are not this game's sequence" do
    other = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
    create(:playthrough_blow, playthrough: other)

    assert_equal 0, Playthrough::Blow.next_sequence(@game)
  end

  # NIL `scene_id` IS THE WHOLE OF "the fight is still on" -- see
  # `Playthrough::Fight#open_blows`.
  test "an open blow is one no closing scene has claimed" do
    open = create(:playthrough_blow, playthrough: @game)
    closed = create(:playthrough_blow, :closed, playthrough: @game)

    assert_equal [ open ], @game.blows.open.to_a
    assert_includes @game.blows.chronological, closed
  end

  # WHAT WAS TRUE WHEN THE BLOW LANDED, and not a live read: the row is a record
  # of a moment, so its condition is a value built out of its own column.
  test "the condition is the hit points on the row and not the ones on the record" do
    blow = create(:playthrough_blow, playthrough: @game, target: @monster, hp_after: 2)
    Playthrough::Turn.new(@game).harm!(@monster, 1)

    assert_equal 2, blow.condition.hp
    assert_equal @monster.max_hp, blow.condition.max
    assert_not_predicate blow, :killed?
  end

  test "a blow that took the last hit point says so" do
    assert_predicate create(:playthrough_blow, :killing, playthrough: @game), :killed?
  end

  # It is read out by `rake game:mechanics` and asserted by `rake game:sweep`,
  # so it says the numbers rather than a mood.
  test "it prints who hit whom for how much, and what was left" do
    blow = create(:playthrough_blow, playthrough: @game, attacker: @protagonist, target: @monster,
                                     damage: 3, hp_after: 5, round: 2)

    assert_equal "#{@protagonist.fullname} hit #{@monster.fullname} for 3 (round 2); " \
                 "#{@monster.fullname} is hurt (5 of 8)", blow.to_s
  end

  # A blow is this player's progress, exactly as a vitals row and an item copy
  # are. The world's `characters.hostile` is untouched by any of it.
  test "blows go with the playthrough" do
    create(:playthrough_blow, playthrough: @game)

    assert_difference "Playthrough::Blow.count", -1 do
      @game.destroy!
    end
  end

  # --- and with everything a blow names ---------------------------------------
  #
  # A blow points at a playthrough, two characters, a room and (once the fight
  # is closed) a Scene, and four of those five are NOT NULL. `rake game:delete`
  # tears a story down in association order -- characters, then locations, then
  # scenes, then playthroughs -- so a row left pointing at any of them raises a
  # foreign key error halfway through and leaves the story half-deleted. These
  # are the four statements that stop that, and they are tests rather than
  # assumptions because it is the shape a `dependent:` nobody wrote fails in.

  test "a whole story with a fight in it can be deleted" do
    @turn = Playthrough::Turn.new(@game)
    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.harm!(@monster, @monster.max_hp)
    Playthrough::Fight.new(@game).close!

    @story.destroy!

    assert_equal 0, Playthrough::Blow.count
  end

  test "destroying the person who threw a blow takes the blow with them" do
    create(:playthrough_blow, playthrough: @game, attacker: @monster, target: @protagonist)

    assert_difference "Playthrough::Blow.count", -1 do
      @monster.destroy!
    end
  end

  test "destroying the room a fight happened in takes its blows with it" do
    create(:playthrough_blow, playthrough: @game, location: @room)

    assert_difference "Playthrough::Blow.count", -1 do
      @room.destroy!
    end
  end

  # NULLIFIED AND NOT DESTROYED, on the drift's own reasoning: the blow is the
  # durable record of the round and the Scene is only the sentence about it, so
  # losing the sentence must not lose what the dice did. It reads as an OPEN
  # fight afterwards, which is the truth -- nothing has closed it.
  test "destroying the scene that closed a fight keeps the blows" do
    blow = create(:playthrough_blow, :closed, playthrough: @game)

    assert_difference "Playthrough::Blow.count", 0 do
      blow.scene.destroy!
    end

    assert_nil blow.reload.scene_id
    assert_includes @game.blows.open, blow
  end
end
