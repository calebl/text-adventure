require "test_helper"

# WHETHER THIS GAME IS IN A FIGHT, WHEN IT IS OVER, AND THE ONE `Scene` THAT
# CLOSES IT.
#
# THE FIGHT-END RULE IS WHAT THIS FILE IS FOR, and it is exactly three things:
# no live foe is left standing in the room it happened in, the party is no
# longer standing in that room, or the player is dead. Each of the three has a
# test, and so does the fourth case that is not an ending -- a foe still up and
# the party still there.
class Playthrough::FightTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Bell Chamber")
    @elsewhere = create(:location, story: @story, name: "The Stair")
    # LEVEL 3 AND A d8, WHICH IS 18 HIT POINTS -- the captain's call C1 and what
    # the three seeded worlds give their protagonists. It is here so that a
    # single d8 answer cannot end a test that is not about dying: the dice are
    # seeded off ROW IDS (`Roll.seed`), so a fixture must never depend on which
    # face came up.
    @protagonist = create(:character, :protagonist, story: @story, level: 3, hit_die: 8)
    @monster = create(:character, :monster, story: @story, location: @room, fullname: "Marek Sollen")
    @game = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
    @turn = Playthrough::Turn.new(@game)
  end

  def fight = Playthrough::Fight.new(@game)

  test "a game nobody has swung in is not in a fight" do
    assert_not_predicate fight, :on?
    assert_not_predicate fight, :over?
    assert_nil fight.close!
  end

  test "the first round is round one, off the records" do
    assert_equal 1, fight.next_round

    @turn.strike!(@protagonist, @monster, round: 1)

    assert_equal 2, fight.next_round
    assert_predicate fight, :on?
  end

  # A ROUND IS THE TURN, so every blow of one exchange carries one number
  # however many people swung -- which is what the closing scene's story time is
  # counted in.
  test "several blows in one round are still one round" do
    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.strike!(@monster, @protagonist, round: 1)

    assert_equal 2, fight.next_round
    assert_equal 1, fight.rounds
  end

  test "a fight with a live foe in the room the party is standing in is not over" do
    @turn.strike!(@protagonist, @monster, round: 1)

    assert_not_predicate fight, :over?
    assert_nil fight.close!
  end

  # ENDING ONE: nobody left to fight.
  test "it is over when the last live foe in the room is down" do
    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.harm!(@monster, @monster.max_hp)

    assert_predicate fight, :over?
  end

  # ENDING TWO: the party left -- the captain's call C1, a fight is always
  # escapable by leaving the room.
  test "it is over when the party is standing somewhere else" do
    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.stand_in!(@elsewhere)

    assert_predicate fight, :over?
  end

  # ENDING THREE: the player is dead, and nothing will ever change again.
  test "it is over when the player is dead" do
    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.harm!(@protagonist, @protagonist.max_hp)

    assert_predicate @game, :over?
    assert_predicate fight, :over?
  end

  test "closing writes one scene, stamps every open blow with it, and does not do it twice" do
    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.strike!(@monster, @protagonist, round: 1)
    @turn.harm!(@monster, @monster.max_hp)

    scene = nil
    assert_difference "Scene.count", 1 do
      scene = fight.close!
    end

    assert_equal "attack", scene.resolved_action
    assert_equal @monster, scene.acted_on
    assert_equal @room, scene.location
    assert_equal scene, @game.reload.current_scene
    assert_equal [ scene.id ], @game.blows.pluck(:scene_id).uniq
    assert_empty @game.blows.open
    assert_nil fight.close!, "a closed fight has nothing left to close"
  end

  # `Scene::TURN_MINUTES["action"]` PER ROUND, which is the whole of what a
  # fight costs the story's clock -- and it costs it once, when the fight ends,
  # rather than a Scene per round.
  test "the closing scene costs one action beat per round" do
    started = @game.story_now
    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.strike!(@protagonist, @monster, round: 2)
    @turn.harm!(@monster, @monster.max_hp)

    scene = fight.close!

    assert_equal started + (Scene::TURN_MINUTES.fetch("action") * 2).minutes, scene.story_timestamp
  end

  # IT IS THE ENGINE'S OWN WORDS, which is what makes the audit's exclusion of
  # it honest -- see `Scene#engine_authored?` and `Story::Audit#scenes`.
  test "the closing scene is engine-authored and says what the dice did" do
    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.harm!(@monster, @monster.max_hp)

    scene = fight.close!

    assert_predicate scene, :engine_authored?
    assert_includes scene.description, "The fight in The Bell Chamber is over after 1 round."
    assert_includes scene.description, "#{@monster.fullname} is dead."
    assert_includes scene.summary, "A fight in The Bell Chamber"
  end

  # A level-3 body holds 18, and the player's d8 cannot take that in one round
  # -- so this says "nobody was killed" whatever the die came up.
  test "a fight the party walked out of says nobody was killed" do
    tough = create(:character, :monster, story: @story, location: @room, fullname: "Ada Threnn",
                                         level: 3, hit_die: 8)
    @turn.strike!(@protagonist, tough, round: 1)
    @turn.stand_in!(@elsewhere)

    assert_includes fight.close!.description, "Nobody was killed"
  end

  # WHO THE FIGHT WAS WITH, for `scenes.acted_on`: the person the PLAYER last
  # swung at, because that is the one the player named.
  test "the opponent is the last person the player swung at" do
    other = create(:character, :monster, story: @story, location: @room, fullname: "Ada Threnn")
    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.strike!(other, @protagonist, round: 1)

    assert_equal @monster, fight.opponent
  end

  test "the room is the one the first blow landed in and not where the party ended up" do
    @turn.strike!(@protagonist, @monster, round: 1)
    @turn.stand_in!(@elsewhere)

    assert_equal @room, fight.room
    assert_equal @room, fight.close!.location
  end
end
