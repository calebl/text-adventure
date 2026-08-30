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
        "distance" => "80 meters",
        "time_to_travel" => "3 minutes",
        "travel_method" => "wading"
      },
      {
        "name" => "Tidewater Stair",
        "teaser" => "Steps that go up out of the water.",
        "distance" => "20 meters",
        "time_to_travel" => "1 minute",
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
    assert_equal "80 meters", connection.distance
    assert_equal "3 minutes", connection.time_to_travel
    assert_equal "wading", connection.travel_method
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

  test "includes the universe and the story in the prompt" do
    agent = FakeAgent.new(DETAIL, EXITS)
    realize(stub_location(name: "The Drowned Ledger"), agent)

    assert_includes agent.prompts.first, @story.universe.politics
    assert_includes agent.prompts.first, @story.preface
    assert_includes agent.prompts.first, "The Drowned Ledger"
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

  test "leaves nothing behind when exit generation fails" do
    location = stub_location(name: "The Drowned Ledger")
    broken = { "exits" => [ EXITS["exits"].first.merge("distance" => nil) ] }

    assert_raises(ActiveRecord::RecordInvalid) do
      realize(location, FakeAgent.new(DETAIL, broken))
    end

    assert location.reload.stub?
    assert_equal 1, @story.locations.count
  end

  test "opening names, describes and realizes the story's first location" do
    agent = FakeAgent.new(OPENING, DETAIL, EXITS)
    location = BaseAgent.stub(:new, agent) { Location::Generator.opening(@story) }

    assert_equal "The Drowned Ledger", location.name
    assert_equal OPENING["teaser"], location.teaser
    assert location.realized?
    assert_equal @story, location.story
    assert_equal [ Location::OpeningSchema, Location::DetailSchema, Location::ExitsSchema ], agent.schemas
    assert_equal 2, location.exits.count
  end
end
