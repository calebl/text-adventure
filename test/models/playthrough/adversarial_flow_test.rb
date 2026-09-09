require "test_helper"

# Walks the seams between NPC decisions, arrival state and failed rendering.
# Model choices are fixtures; every effect and subsequent turn uses the engine.
class Playthrough::AdversarialFlowTest < ActiveSupport::TestCase
  setup do
    @story = create(:story, start_time: Time.utc(2026, 1, 1, 12))
    @hero = create(:character, :protagonist, story: @story, fullname: "Iri Calder",
                   nickname: "Iri", age: 25, sex: "female", level: 10)
    @market = create(:location, story: @story, name: "Market")
    @quay = create(:location, story: @story, name: "Quay")
    create(:location_connection, :short_distance, location: @market, connected_location: @quay)
    create(:location_connection, :short_distance, location: @quay, connected_location: @market)
    @opening = create(:scene, :opening, story: @story, location: @market,
                      story_timestamp: @story.start_time)
    @game = create(:playthrough, story: @story, character: @hero,
                   current_location: @market, current_scene: @opening)
    @maren = create(:character, story: @story, location: @market, fullname: "Maren Vosk",
                    nickname: "Maren", age: 40, sex: "female", level: 10)
  end

  test "a gifted item and follower survive a failed arrival without changing another game" do
    template = create(:item, character: @maren, name: "brass key")
    Playthrough::Snapshot.new(@game).of_the_room!(@market)
    key = @game.items_held_by(@maren).sole
    play("/talk Maren", reaction("give:#{key.id}"), "Maren gives you the brass key.")
    play("/talk Maren", reaction("follow"), "Maren agrees to accompany you.")

    dead_resident = create(:character, story: @story, location: @quay,
                           fullname: "Oren Moss", age: 50, sex: "male")
    Playthrough::Turn.new(@game).harm!(dead_resident, dead_resident.max_hp)
    arrived = play("/move Quay", RuntimeError.new("arrival provider unavailable"))

    assert_predicate arrived, :engine_authored?
    assert_equal @quay, @game.reload.current_location
    assert_includes arrived.characters, @maren
    assert_not_includes arrived.characters, dead_resident
    assert_includes @game.carried, key
    assert_equal @market, @maren.reload.location
    assert_equal @maren, template.reload.character
    other = create(:playthrough, story: @story, character: @hero, current_location: @market)
    assert_includes other.cast_in(@market), @maren
    assert_not_includes other.cast_in(@quay), @maren
    assert_equal [ "brass key" ], other.items_held_by(@maren).pluck(:name)
  end

  test "a failed conversation render retains the validated gift and completes the turn" do
    template = create(:item, character: @maren, name: "brass key")
    Playthrough::Snapshot.new(@game).of_the_room!(@market)
    key = @game.items_held_by(@maren).sole
    scene = play("/talk Maren", reaction("give:#{key.id}"), RuntimeError.new("narrator unavailable"))

    assert_predicate scene, :engine_authored?
    assert_includes @game.reload.carried, key
    assert_equal "applied", @maren.interactions.last.action_status
    assert_equal @opening, scene.previous_scene
    assert_operator scene.story_timestamp, :>, @opening.story_timestamp
    assert_equal @maren, template.reload.character
  end

  test "an invented action cannot transfer an item from an absent character" do
    owner = create(:character, story: @story, location: @quay, age: 45, sex: "male")
    template = create(:item, character: owner, name: "silver crown")
    Playthrough::Snapshot.new(@game).of_the_room!(@quay)
    crown = @game.items.find_by!(template: template)

    play("/talk Maren", reaction("give:#{crown.id}"), "Maren has no crown to give you.")

    assert_equal "rejected", @maren.interactions.last.action_status
    assert_equal owner, crown.reload.character
    assert_not_includes @game.carried, crown
  end

  test "redelivery of a failed-render arrival neither pays the crossing twice nor adds a scene" do
    edge = LocationConnection.find_by!(location: @market, connected_location: @quay)
    edge.update!(hazard: "drop", hazard_die: 4)
    first = play("/move Quay", RuntimeError.new("provider unavailable"), token: "arrival-once")
    hp = @game.reload.condition.hp
    toll_ids = @game.tolls.pluck(:id)
    scene_ids = @game.scene_chain.map(&:id)

    repeated = play("/move Quay", token: "arrival-once", game: Playthrough.find(@game.id))

    assert_equal first, repeated
    assert_equal @quay, @game.reload.current_location
    assert_equal hp, @game.condition.hp
    assert_equal toll_ids, @game.tolls.pluck(:id)
    assert_equal scene_ids, @game.scene_chain.map(&:id)
    assert_not_empty toll_ids
    assert_empty @game.tolls.untold
  end

  private

  def reaction(choice)
    { "pre_thought" => "I will decide for myself.", "pre_feeling" => "calm",
      "action" => "Maren answers Iri.", "post_thought" => "I have made my choice.",
      "post_feeling" => "resolved", "inner_resolution" => "I will keep my agreement.",
      "engine_action" => choice }
  end

  def play(command, *responses, token: nil, game: @game)
    BaseAgent.stub(:new, FakeAgent.new(*responses)) do
      Playthrough::Turn.new(game).play(command, request_token: token)
    end
  end
end
