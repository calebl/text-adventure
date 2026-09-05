require "test_helper"

# THE BLOW, THE MARK IT LEAVES, AND WHAT A BODY LETS GO OF.
#
# `Playthrough::Turn#strike!` is the ONE writer of `playthrough_blows` and the
# one place a fight touches `#harm!`, `#provoke!` and `#spill!`. Everything a
# fight does to the records goes through it, so this is where each of those is
# asserted on its own.
class Playthrough::TurnStrikeTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Bell Chamber")
    @elsewhere = create(:location, story: @story, name: "The Stair")
    @protagonist = create(:character, :protagonist, story: @story, level: 3, hit_die: 8)
    @monster = create(:character, :monster, story: @story, location: @room, fullname: "Marek Sollen",
                                            level: 3, hit_die: 8)
    @game = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
    @turn = Playthrough::Turn.new(@game)
  end

  # A BLOW ALWAYS CONNECTS AND DEALS ONE DIE OF THE ATTACKER'S `hit_die` -- the
  # captain's call C2. No to-hit, no armour, no critical, and no ability term:
  # `data/ta-combat-scout` §7.2 measured the alternatives and the one that
  # decided it is that a to-hit roll makes the underdog more likely to win, with
  # death terminal.
  test "damage is one die of the attacker's hit die and nothing else" do
    rolls = 200.times.map { |n| @turn.damage_for(@monster, rng: Random.new(n)) }

    assert_equal (1..8).to_a, rolls.uniq.sort
  end

  test "a blow writes one row with everything the engine decided on it" do
    blow = @turn.strike!(@protagonist, @monster, round: 2)

    assert_equal @protagonist, blow.attacker
    assert_equal @monster, blow.target
    assert_equal @room, blow.location
    assert_equal 2, blow.round
    assert_equal @game.story_now, blow.story_timestamp
    assert_includes 1..8, blow.damage
    assert_equal @monster.max_hp - blow.damage, blow.hp_after
    assert_equal blow.hp_after, @game.vitals_for(@monster).hp
  end

  # THE SEED IS THE ROLL'S IDENTITY. A fight does not advance the story's clock
  # until it ends, so `sequence` is the whole of what tells one blow of it from
  # the next -- and it comes off the ROWS, so the same fight replayed in another
  # process throws the same dice.
  test "the sequence comes off the record and rises with every blow" do
    first = @turn.strike!(@protagonist, @monster, round: 1)
    second = @turn.strike!(@protagonist, @monster, round: 2)

    assert_equal first.sequence + 1, second.sequence
    assert_equal Playthrough::Turn::SEQUENCE_OFFSET, first.sequence
  end

  # PAST THE THREE `#check` TAKES AT ONE MOMENT, so a check and a blow at one
  # story moment cannot be the same roll.
  test "the offset clears the ability checks" do
    assert_operator Playthrough::Turn::SEQUENCE_OFFSET, :>, Character::ABILITIES.size
  end

  test "the same fight replayed throws the same dice" do
    damage = @turn.strike!(@protagonist, @monster, round: 1).damage
    @game.blows.destroy_all
    @game.vitals.destroy_all

    assert_equal damage, Playthrough::Turn.new(@game.reload).strike!(@protagonist, @monster, round: 1).damage
  end

  # BEING ATTACKED MAKES SOMEBODY THIS GAME'S FOE -- the captain's sixth ruling
  # of 2026-09-05 -- and the world never hears about it.
  test "a blow marks the target provoked in this playthrough and nowhere else" do
    bystander = create(:character, story: @story, location: @room, fullname: "Grenn Ollivar",
                                   level: 3, hit_die: 8)
    other = create(:playthrough, story: @story, character: @protagonist, current_location: @room)

    @turn.strike!(@protagonist, bystander, round: 1)

    assert @game.provoked?(bystander)
    assert_includes @game.foes_in(@room), bystander
    assert_not other.provoked?(bystander)
    assert_not_includes other.foes_in(@room), bystander
    assert_not_predicate bystander.reload, :hostile?
  end

  test "the mark keeps the moment the fight started" do
    @turn.strike!(@protagonist, @monster, round: 1)
    started = @game.vitals.find_by(character: @monster).provoked_at
    @turn.strike!(@protagonist, @monster, round: 2)

    assert_equal started, @game.vitals.find_by(character: @monster).provoked_at
  end

  # A DEAD BODY LETS GO OF WHAT IT HELD, in the same transaction as the last hit
  # point -- and only of THIS GAME'S copies.
  test "a killed body drops this game's copies on the floor of the room it is standing in" do
    template = create(:item, character: @monster, name: "bell-rope tally")
    Item::Snapshot.new(@game).of_the_room!(@room)
    copy = @game.items_held_by(@monster).first

    @turn.harm!(@monster, @monster.max_hp)

    assert_equal @room, copy.reload.location
    assert_nil copy.character
    assert_equal @game, copy.playthrough
    assert_includes @game.items_lying_in(@room), copy
    assert_equal @monster, template.reload.character, "the world's own row never moved"
  end

  test "spilling a body nobody has met writes nothing" do
    assert_equal [], @turn.spill!(@monster)
  end

  # THE PARTY IS THE STATED EXCEPTION: they stand in no room and their hands are
  # an instance with no holder, so a player dying leaves the inventory alone.
  test "the player dying does not empty the party's hands" do
    create(:item, :carried, playthrough: @game, name: "Ward Office 12 daybook")

    @turn.harm!(@protagonist, @protagonist.max_hp)

    assert_predicate @game.reload, :over?
    assert_equal [ "Ward Office 12 daybook" ], @game.carried.map(&:name)
  end

  test "a body with no stat block cannot be struck" do
    bodiless = create(:character, :without_a_stat_block, story: @story, location: @room)

    assert_nil @turn.strike!(@protagonist, bodiless, round: 1)
    assert_equal 0, @game.blows.count
  end

  test "an attacker with no stat block has no die to hit with" do
    bodiless = create(:character, :without_a_stat_block, story: @story, location: @room)

    assert_nil @turn.strike!(bodiless, @monster, round: 1)
  end

  test "a blow needs a room, because a fight happens somewhere" do
    nowhere = create(:playthrough, story: @story, character: @protagonist)

    assert_nil Playthrough::Turn.new(nowhere).strike!(@protagonist, @monster, round: 1)
  end

  # `characters.level`, `hit_die` and the three abilities are the WORLD's, on
  # the far side of the layer split -- the statement
  # `EngineSweep::Invariants#stat_blocks_unmoved` makes after every walk.
  test "a fight moves no column on a character" do
    before = @monster.attributes.slice("level", "hit_die", "hostile", *Character::ABILITIES.map(&:to_s))

    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.strike!(@monster, @protagonist, round: 1)

    assert_equal before, @monster.reload.attributes.slice("level", "hit_die", "hostile",
                                                          *Character::ABILITIES.map(&:to_s))
  end
end
