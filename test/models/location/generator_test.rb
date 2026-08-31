require "test_helper"

class Location::GeneratorTest < ActiveSupport::TestCase
  OPENING = {
    "name" => "The Drowned Ledger",
    "teaser" => "A counting house with the tide coming in."
  }.freeze

  DETAIL = {
    "description" => "Water laps at the third stair and the ledgers are floating.",
    "lore" => "The house has collected debts here for two hundred years."
  }.freeze

  EXITS = {
    "exits" => [
      {
        "name" => "The Pump Gallery",
        "teaser" => "Something down there is still turning.",
        "distance" => "across the district",
        "travel_method" => "swimming"
      },
      {
        "name" => "Tidewater Stair",
        "teaser" => "Steps that go up out of the water.",
        "distance" => "adjacent",
        "travel_method" => "climbing"
      }
    ]
  }.freeze

  def setup
    @story = create(:story)
  end

  def realize(location, agent)
    BaseAgent.stub(:new, agent) do
      Location::Generator.new(location).realize!
    end
  end

  def stub_location(**attributes)
    create(:location, :stub, story: @story, **attributes)
  end

  test "fills in a stub's description and lore" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    assert_equal DETAIL["description"], location.description
    assert_equal DETAIL["lore"], location.lore
    assert location.realized?
    assert location.persisted?
  end

  test "creates a stub location for every exit" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    exits = location.reload.exits
    assert_equal [ "The Pump Gallery", "Tidewater Stair" ], exits.map(&:name).sort
    assert exits.all?(&:stub?), "exits should be stubs until the player walks into them"
    assert exits.all? { |neighbour| neighbour.teaser.present? }
  end

  test "records the connection details on the exit" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    connection = LocationConnection.find_by(location: location, connected_location: Location.find_by(name: "The Pump Gallery"))
    assert_equal "across the district", connection.distance
    assert_equal "swimming", connection.travel_method
  end

  # The generator never sets it; LocationConnection works it out from the
  # distance and the method, so it cannot contradict them.
  test "the travel time is derived, not taken from the model" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    connection = LocationConnection.find_by(location: location, connected_location: Location.find_by(name: "The Pump Gallery"))
    assert_equal LocationConnection.humanize_minutes(
      LocationConnection.travel_minutes("across the district", "swimming")
    ), connection.time_to_travel
  end

  # Both rows are written from one answer. They used to carry the same prose,
  # so "climb down the drainpipe to the lane below" was stored as the way up
  # as well. The enum values are direction-neutral, so identical is correct.
  test "the way back records the same distance and method, and is valid" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))
    neighbour = Location.find_by(name: "The Pump Gallery")

    out = LocationConnection.find_by(location: location, connected_location: neighbour)
    back = LocationConnection.find_by(location: neighbour, connected_location: location)

    assert back.valid?
    assert_equal out.distance, back.distance
    assert_equal out.travel_method, back.travel_method
    assert_equal out.time_to_travel, back.time_to_travel
  end

  test "connects the exit back the way the player came" do
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    neighbour = Location.find_by(name: "The Pump Gallery")
    assert_includes neighbour.exits, location
  end

  # The whole design: generation happens once per place, never twice.
  test "does not regenerate an already realized location" do
    location = create(:location, story: @story, name: "The Drowned Ledger")
    original = location.description

    agent = FakeAgent.new(DETAIL, EXITS)
    realize(location, agent)

    assert_empty agent.prompts
    assert_equal original, location.reload.description
    assert_empty location.exits
  end

  test "realizing a neighbour does not duplicate the location it came from" do
    location = stub_location(name: "The Drowned Ledger")
    realize(location, FakeAgent.new(DETAIL, EXITS))

    neighbour = Location.find_by(name: "The Pump Gallery")
    back_the_way_we_came = {
      "exits" => [ EXITS["exits"].first.merge("name" => "the drowned ledger") ]
    }
    realize(neighbour, FakeAgent.new(DETAIL, back_the_way_we_came))

    assert_equal 1, @story.locations.where("LOWER(name) = ?", "the drowned ledger").count
    assert_equal 1, LocationConnection.where(location: neighbour, connected_location: location).count
    assert_equal 1, LocationConnection.where(location: location, connected_location: neighbour).count
  end

  test "ignores an exit that names the location itself" do
    location = stub_location(name: "The Drowned Ledger")
    itself = { "exits" => [ EXITS["exits"].first.merge("name" => "The Drowned Ledger") ] }

    realize(location, FakeAgent.new(DETAIL, itself))

    assert_empty location.reload.exits
    assert_equal 1, @story.locations.count
  end

  test "asks for the detail schema then the exits schema" do
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location, agent)

    assert_equal [ Location::DetailSchema, Location::ExitsSchema ], agent.schemas
  end

  # A room gets the place-shaped half of the universe -- what the world is made
  # of and who lives in it -- not how it is governed or what it believes.
  test "includes the universe and the story in the prompt" do
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location(name: "The Drowned Ledger"), agent)

    assert_includes agent.prompts.first, @story.universe.geographies
    assert_includes agent.prompts.first, @story.universe.technology
    assert_includes agent.prompts.first, @story.preface
    assert_includes agent.prompts.first, "The Drowned Ledger"
  end

  test "does not spend the room prompt on how the world is governed" do
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location(name: "The Drowned Ledger"), agent)

    assert_not_includes agent.prompts.first, @story.universe.politics
    assert_not_includes agent.prompts.first, @story.universe.economics
  end

  test "names the locations that already exist so exits reuse them" do
    existing = create(:location, story: @story, name: "The Pump Gallery")
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location(name: "The Drowned Ledger"), agent)

    assert_includes agent.prompts.last, existing.name
  end

  test "reuses an existing location rather than inventing a second one" do
    existing = create(:location, story: @story, name: "The Pump Gallery")
    location = stub_location(name: "The Drowned Ledger")

    realize(location, FakeAgent.new(DETAIL, EXITS))

    assert_includes location.reload.exits, existing
    assert existing.reload.realized?, "reusing a location must not downgrade it to a stub"
  end

  test "strips emoji from generated text" do
    location = stub_location
    realize(location, FakeAgent.new(DETAIL.merge("lore" => "Two hundred years 🌊"), EXITS))

    assert_equal "Two hundred years", location.lore
  end

  test "raises when the model call fails" do
    failing = Object.new
    def failing.with_instructions(_) = self
    def failing.with_schema(_) = self
    def failing.ask(_) = raise(RubyLLM::Error.new(nil, "boom"))

    assert_raises(RubyLLM::Error) { realize(stub_location, failing) }
  end

  # The description is the expensive call of the two. It used to be held
  # unsaved until the exits came back, so an exits failure threw it away.
  test "keeps the description it already paid for when exits fail" do
    location = stub_location(name: "The Drowned Ledger")
    broken = { "exits" => [ EXITS["exits"].first.merge("distance" => "80 meters") ] }

    assert_raises(ActiveRecord::RecordInvalid) do
      realize(location, FakeAgent.new(DETAIL, broken))
    end

    assert location.reload.realized?
    assert_equal DETAIL["description"], location.description
  end

  test "writes no partial exits when one of them fails" do
    location = stub_location(name: "The Drowned Ledger")
    broken = { "exits" => [ EXITS["exits"].first, EXITS["exits"].last.merge("travel_method" => "wading") ] }

    assert_raises(ActiveRecord::RecordInvalid) do
      realize(location, FakeAgent.new(DETAIL, broken))
    end

    assert_empty location.reload.exits
    assert_equal 1, @story.locations.count
  end

  # Recovering from that failure means finishing the exits, not realizing the
  # room again -- realize! returns an already-realized location untouched.
  test "write_exits! finishes a room whose exits call failed" do
    location = stub_location(name: "The Drowned Ledger")
    broken = { "exits" => [ EXITS["exits"].first.merge("distance" => "80 meters") ] }

    assert_raises(ActiveRecord::RecordInvalid) { realize(location, FakeAgent.new(DETAIL, broken)) }

    BaseAgent.stub(:new, FakeAgent.new(EXITS)) do
      Location::Generator.new(location.reload).write_exits!
    end

    assert_equal 2, location.reload.exits.count
    assert_equal DETAIL["description"], location.description
  end

  # Story::Generator already named the opening room from the same call that
  # wrote the preface, so `.opening` only writes it out -- two calls, not three.
  test "opening realizes the stub the story generator already created" do
    opening = stub_location(name: "The Drowned Ledger", teaser: OPENING["teaser"])
    agent = FakeAgent.new(DETAIL, EXITS)

    location = BaseAgent.stub(:new, agent) { Location::Generator.opening(@story) }

    assert_equal opening, location
    assert_equal "The Drowned Ledger", location.name
    assert_equal OPENING["teaser"], location.teaser
    assert location.realized?
    assert_equal [ Location::DetailSchema, Location::ExitsSchema ], agent.schemas
    assert_equal 2, location.exits.count
  end

  test "opening realizes the story's oldest location, not a later stub" do
    opening = stub_location(name: "The Drowned Ledger")
    stub_location(name: "Somewhere Else")

    location = BaseAgent.stub(:new, FakeAgent.new(DETAIL, EXITS)) do
      Location::Generator.opening(@story)
    end

    assert_equal opening, location
  end

  test "opening raises rather than inventing a room the story does not have" do
    assert_raises(ArgumentError) { Location::Generator.opening(@story) }
  end
end
