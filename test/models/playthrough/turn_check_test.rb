require "test_helper"

# ONE ATTEMPT AT SOMETHING, ROLLED FROM THIS GAME'S OWN SEED.
#
# `Character#check` is the kernel and `CharacterTest` pins its arithmetic. What
# is pinned here is the SEED -- the thing that makes a check re-derivable, and
# therefore assertable by `rake game:sweep` -- and the one property the whole
# instrument depends on: a check writes nothing at all.
class Playthrough::TurnCheckTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story)
    @vance = create(:character, :protagonist, story: @story, fullname: "Odile Vance",
                                              level: 1, hit_die: 6,
                                              strength: 9, dexterity: 11, will: 15)
    @game = create(:playthrough, story: @story, character: @vance, current_location: @room)
    @turn = Playthrough::Turn.new(@game)
  end

  # THE SEED IS THE ROLL'S IDENTITY: which world, which game, where the story's
  # clock stood, and which roll within that moment. Recomputed here by hand off
  # `Roll`, because that is the whole reason a sweep can assert an outcome.
  test "the die is the one Roll would throw for this game at this story moment" do
    Character::ABILITIES.each_with_index do |ability, index|
      rng = Roll.generator(story: @story.id, playthrough: @game.id,
                           at: @story.clock.to_i, sequence: index + 1)

      assert_equal Roll.die(20, rng: rng), @turn.check(@vance, ability).die, ability
    end
  end

  test "one ability checked twice at one story moment is one roll" do
    assert_equal @turn.check(@vance, :will).die, @turn.check(@vance, :will).die
  end

  # The three abilities are three rolls because `Character::ABILITIES`'s index is
  # the sequence -- otherwise one moment's three checks would be one number
  # three times, which is what `Roll`'s `sequence` exists to stop.
  test "the three abilities are three different rolls" do
    dice = Character::ABILITIES.map { |ability| @turn.check(@vance, ability).die }

    assert_operator dice.uniq.size, :>, 1
  end

  # THE PENALTY IS NOT IN THE SEED: it moves the target and not the die, which is
  # the kernel's shape read back out of it.
  test "a penalty changes the target and leaves the die alone" do
    plain = @turn.check(@vance, :will)
    harder = @turn.check(@vance, :will, penalty: 5)

    assert_equal plain.die, harder.die
    assert_equal 15, plain.target
    assert_equal 10, harder.target
  end

  test "two games of one world do not share a check" do
    other = create(:playthrough, story: @story, character: @vance, current_location: @room)

    assert_not_equal @turn.check(@vance, :will).die,
                     Playthrough::Turn.new(other).check(@vance, :will).die
  end

  # IT WRITES NOTHING. No condition row, no scene, no clock movement -- which is
  # what makes it safe to type into a real game as often as you like, and what
  # `EngineSweep::Invariants#stat_blocks_unmoved` asserts after a walk that used
  # it.
  test "a check writes nothing at all" do
    before = [ Scene.count, Playthrough::Vitals.count, @story.clock, @vance.updated_at ]

    Character::ABILITIES.each { |ability| @turn.check(@vance, ability, penalty: 2) }

    assert_equal before, [ Scene.count, Playthrough::Vitals.count, @story.reload.clock, @vance.reload.updated_at ]
  end

  test "an impossible check answers without a die" do
    result = @turn.check(@vance, :strength, penalty: 9)

    assert_predicate result, :impossible?
    assert_nil result.die
  end

  test "somebody with no abilities cannot be checked" do
    nobody = create(:character, :without_abilities, story: @story)

    assert_nil @turn.check(nobody, :will)
  end

  test "nobody at all is nil rather than a raise" do
    assert_nil @turn.check(nil, :will)
  end

  # One error about one thing, from the class that owns the list.
  test "an ability outside the three raises" do
    assert_raises(ArgumentError) { @turn.check(@vance, :constitution) }
  end
end
