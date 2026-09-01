require "test_helper"

# The safe half of these runs against records only -- no agent is stubbed at all,
# because a repair that reached for a model here would blow up rather than
# quietly cost the captain a call. The generated half uses FakeAgent, the same
# seam every generator test uses.
class Story::RepairTest < ActiveSupport::TestCase
  def story_with_one_way_edge
    story = create(:story)
    opening = create(:location, story: story, name: "Your Office")
    street = create(:location, :stub, story: story, name: "The Street")
    create(:location_connection, location: opening, connected_location: street,
                                 distance: "a short walk", travel_method: "walking")
    create(:character, :protagonist, story: story)
    create(:scene, :opening, story: story, location: opening, story_timestamp: story.start_time)
    story
  end

  test "writes the missing direction of a one-way connection" do
    story = story_with_one_way_edge
    opening = story.locations.find_by(name: "Your Office")
    street = story.locations.find_by(name: "The Street")

    results = Story::Repair.new(story).apply!

    assert_equal [ :one_way_connection ], results.map(&:code)
    assert results.all?(&:repaired?)

    back = LocationConnection.find_by(location: street, connected_location: opening)

    assert back, "the player has to be able to walk back the way they came"
    assert_equal "a short walk", back.distance
    assert_equal "walking", back.travel_method
    # Derived by LocationConnection rather than copied, which is the point of
    # deriving it there.
    assert_equal LocationConnection.find_by(location: opening, connected_location: street).time_to_travel,
                 back.time_to_travel
  end

  test "makes two disagreeing directions agree with the way out" do
    story = story_with_one_way_edge
    opening = story.locations.find_by(name: "Your Office")
    street = story.locations.find_by(name: "The Street")
    create(:location_connection, location: street, connected_location: opening,
                                 distance: "days away", travel_method: "riding")

    results = Story::Repair.new(story).apply!

    assert_equal [ :connection_directions_disagree ], results.map(&:code)
    back = LocationConnection.find_by(location: street, connected_location: opening)

    assert_equal "a short walk", back.distance
    assert_equal "walking", back.travel_method
  end

  test "derives a missing start_time from the story's earliest scene" do
    story = story_with_one_way_edge
    at = story.start_time
    story.update_columns(start_time: nil)

    Story::Repair.new(story.reload).apply!

    assert_in_delta at.to_i, story.reload.start_time.to_i, 1
  end

  test "puts a playthrough with no location back where its scene happens" do
    story = story_with_one_way_edge
    opening = story.locations.find_by(name: "Your Office")
    playthrough = create(:playthrough, story: story, current_location: opening, current_scene: story.opening_scene)
    playthrough.update_columns(current_location_id: nil)

    Story::Repair.new(story.reload).apply!

    assert_equal opening, playthrough.reload.current_location
  end

  # THE LINE THIS WHOLE CLASS TURNS ON. A missing opening arrival can only be
  # written by a model, so an ordinary repair leaves it alone and says so.
  test "does not make a model call unless generation was asked for" do
    story = story_with_one_way_edge
    story.opening_scene.destroy!
    repair = Story::Repair.new(story.reload)

    assert_equal 0, repair.model_calls
    assert_equal [ :no_opening_scene ], repair.deferred.map(&:code)
    # No agent is stubbed: if this reached for one it would raise here.
    results = repair.apply!

    assert_equal [ :one_way_connection ], results.map(&:code)
    assert_nil story.reload.opening_scene
  end

  test "narrates the missing opening arrival when generation is allowed" do
    story = story_with_one_way_edge
    story.opening_scene.destroy!
    repair = Story::Repair.new(story.reload, generate: true)

    assert_equal 1, repair.model_calls

    agent = FakeAgent.new({ "description" => "The door sticks, then gives.", "summary" => "The story opens." })
    results = BaseAgent.stub(:new, agent) { repair.apply! }

    assert_includes results.map(&:code), :no_opening_scene
    assert results.all?(&:repaired?), results.map(&:message).join("\n")

    scene = story.reload.opening_scene

    assert scene
    assert_equal "The door sticks, then gives.", scene.description
    assert_equal story.start_time.to_i, scene.story_timestamp.to_i
  end

  test "writes the exits of a realized room that has none" do
    story = create(:story)
    opening = create(:location, story: story, name: "The Cell")
    create(:character, :protagonist, story: story)
    create(:scene, :opening, story: story, location: opening, story_timestamp: story.start_time)
    repair = Story::Repair.new(story, generate: true)

    assert_equal 1, repair.model_calls

    agent = FakeAgent.new({ "exits" => [ { "name" => "The Corridor", "teaser" => "Cold light under the door.",
                                           "distance" => "adjacent", "travel_method" => "walking" } ] })
    results = BaseAgent.stub(:new, agent) { repair.apply! }

    assert_equal [ :opening_has_no_exits ], results.map(&:code)
    assert results.all?(&:repaired?), results.map(&:message).join("\n")
    assert_equal [ "The Corridor" ], opening.reload.exits.map(&:name)
    # Both directions, the way Location::Generator writes them.
    assert LocationConnection.find_by(location: opening.exits.first, connected_location: opening)
  end

  test "realizes an opening location that is still a stub" do
    story = create(:story)
    create(:location, :stub, story: story, name: "The Drowned Ledger", teaser: "The tide is coming in.")
    repair = Story::Repair.new(story, generate: true)

    assert_equal 2, repair.model_calls, "a room is its detail and then its exits"

    agent = FakeAgent.new(
      { "description" => "Water over the floorboards.", "lore" => "It was a counting house once." },
      { "exits" => [ { "name" => "The Stair", "teaser" => "Up, and dry.", "distance" => "adjacent", "travel_method" => "taking stairs" } ] }
    )
    BaseAgent.stub(:new, agent) { repair.apply! }

    opening = story.reload.opening_location

    assert opening.realized?
    assert_equal "Water over the floorboards.", opening.description
    assert_equal [ "The Stair" ], opening.exits.map(&:name)
  end

  # NEVER INVENT DATA TO MAKE A VALIDATION PASS. A story with nothing to derive
  # from is reported and left exactly as it was.
  test "refuses to repair what would have to be invented" do
    story = create(:story)
    story.update_columns(start_time: nil, summary: nil)
    repair = Story::Repair.new(story, generate: true)

    assert_empty repair.plan
    assert_empty repair.apply!
    assert_includes repair.manual.map(&:code), :no_locations
    assert_includes repair.manual.map(&:code), :missing_start_time
    assert_nil story.reload.start_time
    assert_nil story.summary
  end

  test "a failing repair is reported and does not stop the ones after it" do
    story = story_with_one_way_edge
    story.opening_scene.destroy!
    repair = Story::Repair.new(story.reload, generate: true)

    # An agent with nothing queued raises on the first ask, which is what a
    # missing API key looks like from in here.
    results = BaseAgent.stub(:new, FakeAgent.new) { repair.apply! }

    assert_equal 2, results.size
    assert_equal [ :repaired ], results.select { |r| r.code == :one_way_connection }.map(&:status)
    assert_equal [ :failed ], results.select { |r| r.code == :no_opening_scene }.map(&:status)
  end

  test "a healthy story has nothing to plan, defer or report" do
    story = story_with_one_way_edge
    opening = story.locations.find_by(name: "Your Office")
    street = story.locations.find_by(name: "The Street")
    create(:location_connection, location: street, connected_location: opening,
                                 distance: "a short walk", travel_method: "walking")
    repair = Story::Repair.new(story.reload, generate: true)

    assert_empty repair.plan
    assert_empty repair.deferred
    assert_empty repair.manual
  end
end
