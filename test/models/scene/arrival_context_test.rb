require "test_helper"

class Scene::ArrivalContextTest < ActiveSupport::TestCase
  def setup
    @game = create(:playthrough, :started)
    @destination = create(:location, story: @game.story)
  end

  test "reads destination instances while the player is still in the origin" do
    here = lying_here(@game, @game.current_location, name: "origin coin")
    there = lying_here(@game, @destination, name: "destination key")
    carried = lying_here(@game, @destination, name: "old ledger")
    Playthrough::Turn.new(@game).carry!(carried)
    context = Scene::ArrivalContext.new(@game, location: @destination)

    assert_equal [ there ], context.floor
    assert_equal [ carried ], context.carried
    assert_not_includes context.floor, here
    assert_not_equal @destination, @game.reload.current_location
    assert_equal @destination, carried.template.reload.location
  end

  test "a killed resident remains a dead body and cannot join the living arrival cast" do
    person = create(:character, story: @game.story, location: @destination)
    Playthrough::Turn.new(@game).harm!(person, person.max_hp)
    context = Scene::ArrivalContext.new(@game, location: @destination)

    assert_equal [ person ], context.dead
    assert_not_includes context.living, person
    assert_includes context.facts.join(" "), "Dead here: #{person.fullname}"
    assert_equal @destination, person.reload.location
  end

  test "arrival toll IDs are the frozen supplied set and exclude already told tolls" do
    pending = create(:playthrough_toll, playthrough: @game, location: @destination)
    told = create(:playthrough_toll, :told, playthrough: @game, location: @destination)
    context = Scene::ArrivalContext.new(@game, location: @destination)

    assert_equal [ pending.id ], context.toll_ids
    later = create(:playthrough_toll, playthrough: @game, location: @destination)
    assert_equal [ pending.id ], context.toll_ids
    assert_not_includes context.toll_ids, told.id
    assert_not_includes context.toll_ids, later.id
    assert_includes context.facts.join(" "), "#{pending.damage} hit points"
    assert_nil pending.reload.scene_id
  end

  test "facts state wounds and a saved crossing without inventing harm" do
    Playthrough::Turn.new(@game).harm!(@game.character, 1)
    toll = create(:playthrough_toll, :saved, playthrough: @game, location: @destination)
    context = Scene::ArrivalContext.new(@game, location: @destination)

    assert_includes context.facts.join(" "), @game.condition.in_words
    assert_includes context.facts.join(" "), "got clear of #{@destination.name} and lost nothing"
    assert_equal [ toll.id ], context.toll_ids
  end

  test "projects an agreed follower into the destination without moving their world row" do
    person = create(:character, story: @game.story, location: @game.current_location)
    state = create(:playthrough_npc_state, playthrough: @game, character: person,
                                             location: @game.current_location, following: true)
    context = Scene::ArrivalContext.new(@game, location: @destination)

    assert_includes context.living, person
    assert_equal @game.current_location, state.reload.location
    assert_equal @game.current_location, person.reload.location
  end

  test "a relocated dead NPC is a body only in the room where this game left them" do
    person = create(:character, story: @game.story, location: @game.current_location)
    create(:playthrough_npc_state, playthrough: @game, character: person, location: @destination)
    Playthrough::Turn.new(@game).harm!(person, person.max_hp)

    assert_includes Scene::ArrivalContext.new(@game, location: @destination).dead, person
    assert_not_includes Scene::ArrivalContext.new(@game, location: @game.current_location).dead, person
    assert_equal @game.current_location, person.reload.location
  end

  test "another game still arrives to the original resident and floor item" do
    person = create(:character, story: @game.story, location: @destination)
    item = lying_here(@game, @destination, name: "brass key")
    Playthrough::Turn.new(@game).harm!(person, person.max_hp)
    Playthrough::Turn.new(@game).carry!(item)
    other = create(:playthrough, story: @game.story, character: @game.character, current_location: @game.current_location)
    Playthrough::Snapshot.new(other).of_the_room!(@destination)
    context = Scene::ArrivalContext.new(other, location: @destination)

    assert_empty context.dead
    assert_includes context.living, person
    assert_equal [ "brass key" ], context.floor.map(&:name)
    assert_empty context.carried
  end
end
