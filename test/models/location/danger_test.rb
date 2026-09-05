require "test_helper"

# WHERE MONSTERS COME FROM, and the two rolls that decide it. Both go through
# `Roll`, which means both are re-derivable for ever -- the property that lets
# `DRY_RUN=1` print the numbers a real run writes and lets `rake game:sweep`
# assert an outcome. These tests are that property and the two tables' bounds.
class Location::DangerTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
  end

  # ------------------------------------------------------------------------
  # WHAT A ROOM IS, thrown once as it comes into existence.

  test "a room born in a generated world is one of the danger keys the engine rolls" do
    20.times do |n|
      create(:location, :stub, story: @story, name: "Room #{n}")
      assert_includes Location::Danger::ROLLED, Location::Danger.for_a_new_room(@story)
    end
  end

  test "the engine never rolls deadly -- that is a seed file's word" do
    assert_not_includes Location::Danger::ROLLED, "deadly"
    assert_equal [], Location::Danger::ROLLED - Location::DANGERS.keys,
                 "the roll can only produce keys the table has"
  end

  test "the same story at the same moment with the same rooms rolls the same danger" do
    first = Location::Danger.for_a_new_room(@story)

    assert_equal first, Location::Danger.for_a_new_room(@story)
  end

  test "one more room in the story is a different roll" do
    rolls = 8.times.map do |n|
      create(:location, :stub, story: @story, name: "Room #{n}")
      Location::Danger.for_a_new_room(@story)
    end

    assert_operator rolls.uniq.size, :>, 1, "every room in a world came out the same way, so nothing is being rolled"
  end

  # A DANGER ROLL AND A BODY ROLLED AT THE SAME STORY MOMENT MUST NOT BE THE
  # SAME NUMBER TWICE. `Roll.seed` is four integers, one of which says which
  # roll within a moment, and `Location::Danger::SEQUENCE_BASE` is what keeps
  # this file's stream out of `Character::StatBlock`'s.
  test "a danger roll is seeded out of every sequence a stat block reaches" do
    assert_operator Location::Danger::SEQUENCE_BASE, :>, 100_000

    body = Roll.seed(story: @story.id, at: @story.clock.to_i, sequence: 0)
    danger = Roll.seed(story: @story.id, at: @story.clock.to_i,
                       sequence: Location::Danger::SEQUENCE_BASE + 0)

    assert_not_equal body, danger
  end

  # ------------------------------------------------------------------------
  # WHETHER ONE PERSON WRITTEN INTO A ROOM IS ONE OF ITS MONSTERS.

  test "a safe room throws no die at all and consumes nobody else's roll" do
    room = create(:location, story: @story)
    rng = Random.new(1)
    before = rng.rand(1..1000)
    rng = Random.new(1)

    assert_not Location::Danger.monstrous?(room, rng: rng)
    assert_equal before, rng.rand(1..1000), "a safe room took a number out of the generator"
  end

  test "a deadly room is every face of the die" do
    room = create(:location, :deadly, story: @story)
    rng = Location::Danger.generator_for(room)

    20.times { assert Location::Danger.monstrous?(room, rng: rng) }
  end

  test "a dangerous room is some of the die and not all of it" do
    room = create(:location, :dangerous, story: @story)
    rng = Location::Danger.generator_for(room)
    answers = 60.times.map { Location::Danger.monstrous?(room, rng: rng) }

    assert_includes answers, true
    assert_includes answers, false
  end

  test "one room's generator gives the same answers in any process" do
    room = create(:location, :dangerous, story: @story)
    first = 10.times.map { Location::Danger.monstrous?(room, rng: Location::Danger.generator_for(room)) }
    second = 10.times.map { Location::Danger.monstrous?(room, rng: Location::Danger.generator_for(room)) }

    assert_equal first, second
  end
end
