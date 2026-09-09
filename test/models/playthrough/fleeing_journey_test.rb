require "test_helper"

class Playthrough::FleeingJourneyTest < ActiveSupport::TestCase
  ARRIVAL = { "description" => "You reach the next place.", "summary" => "You arrive." }.freeze

  setup do
    @game = create(:playthrough, :started)
    @game.character.update!(level: 10)
    @market = @game.current_location
    @market.update!(name: "Market")
    @quay = create(:location, story: @game.story, name: "Quay")
    @tower = create(:location, story: @game.story, name: "Tower")
    @opening = create(:scene, story: @game.story, location: @market, story_timestamp: @game.story.start_time)
    @game.update!(current_scene: @opening)
    @foe = create(:character, story: @game.story, location: @market, hostile: true,
                              fullname: "Maren Vosk", age: 40, sex: "female")
    create(:location_connection, location: @market, connected_location: @quay,
                                 distance: "adjacent", travel_method: "walking")
    @long_edge = create(:location_connection, location: @quay, connected_location: @tower,
                                            distance: "across the district", travel_method: "walking")
    @long_minutes = LocationConnection.travel_minutes(@long_edge.distance, @long_edge.travel_method)
  end

  test "fleeing preserves fight history and prices the next journey from the quay" do
    arrival, = play("/move Quay")
    closing = @game.reload.current_scene

    assert_equal @quay, @game.current_location
    assert_equal @quay, closing.location
    assert_equal arrival, closing.previous_scene
    assert_equal @market, closing.blows.sole.location
    assert_equal @foe, closing.blows.sole.attacker
    before = @game.story_now

    tower_arrival, agent = play("/move Tower")

    assert_equal @tower, @game.reload.current_location
    assert_equal closing, tower_arrival.previous_scene
    assert_equal before + @long_minutes.minutes, @game.story_now
    assert_includes agent.prompts.last, "The player has come from Quay."
    assert_equal [ @opening, arrival, closing, tower_arrival ], @game.scene_chain
    assert_equal 1, @game.blows.count
  end

  test "a failed arrival renderer preserves the same escape origin and following travel time" do
    escaped, = play("/move Quay", response: RuntimeError.new("renderer unavailable"))
    assert escaped.engine_authored?
    before = @game.reload.story_now
    assert_equal @quay, @game.current_scene.location

    arrived, = play("/move Tower", response: RuntimeError.new("renderer unavailable"))

    assert arrived.engine_authored?
    assert_equal before + @long_minutes.minutes, @game.reload.story_now
    assert_equal @tower, @game.current_scene.location
  end

  test "an older game whose last closing scene is elsewhere still uses its actual departure" do
    old_closing = create(:scene, story: @game.story, location: @market, previous_scene: @opening,
                                description: "The fight in Market is over.", resolved_action: "attack",
                                story_timestamp: @opening.story_timestamp + 6.minutes)
    @game.update!(current_scene: old_closing, current_location: @quay)

    scene, agent = play("/move Tower")

    assert_equal old_closing, scene.previous_scene
    assert_equal old_closing.story_timestamp + @long_minutes.minutes, scene.story_timestamp
    assert_includes agent.prompts.last, "The player has come from Quay."
    assert_equal @market, old_closing.reload.location
  end

  private

  def play(command, response: ARRIVAL)
    agent = FakeAgent.new(response)
    scene = BaseAgent.stub(:new, agent) { Playthrough::Turn.new(@game).play(command) }
    [ scene, agent ]
  end
end
