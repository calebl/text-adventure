require "test_helper"

class Scene::GeneratorTest < ActiveSupport::TestCase
  ARRIVAL = {
    "description" => "The stair gives under you and the smell of wet paper comes up out of the dark.",
    "summary" => "The protagonist arrives at the flooded counting house."
  }.freeze

  def setup
    @story = create(:story)
  end

  def generate(location, previous_scene: nil, agent: FakeAgent.new(ARRIVAL))
    scene = BaseAgent.stub(:new, agent) do
      Scene::Generator.new(location, previous_scene: previous_scene).generate!
    end

    [ scene, agent ]
  end

  def realized_location(**attributes)
    create(:location, story: @story, **attributes)
  end

  # --- what lands in the record -------------------------------------------

  test "persists the arrival as a scene in the location" do
    location = realized_location(name: "The Drowned Ledger")

    scene, = generate(location)

    assert scene.persisted?
    assert_equal ARRIVAL["description"], scene.description
    assert_equal ARRIVAL["summary"], scene.summary
    assert_equal location, scene.location
    assert_equal @story, scene.story
    assert_not_nil scene.story_timestamp
  end

  test "links the scene to the one the player came from" do
    previous = create(:scene, story: @story, location: realized_location)

    scene, = generate(realized_location, previous_scene: previous)

    assert_equal previous, scene.previous_scene
    assert_equal [ scene ], previous.reload.next_scenes.to_a
  end

  test "the story's opening arrival has no previous scene" do
    scene, = generate(realized_location)

    assert_nil scene.previous_scene
  end

  test "strips emoji the model reached for anyway" do
    location = realized_location
    agent = FakeAgent.new("description" => "Water on the stair. 🌊", "summary" => "They arrive. 🏚️")

    scene, = generate(location, agent: agent)

    assert_equal "Water on the stair.", scene.description
    assert_equal "They arrive.", scene.summary
  end

  # --- first visit versus return ------------------------------------------

  test "a first visit is narrated as discovery" do
    location = realized_location(name: "The Drowned Ledger", last_protagonist_visit: nil)

    _scene, agent = generate(location)

    prompt = agent.prompts.first
    assert_match "never been here", prompt
    assert_match "Narrate discovery", prompt
    assert_no_match(/stood here before/, prompt)
  end

  test "a return visit is narrated as coming back, and says how long they were gone" do
    location = realized_location(name: "The Drowned Ledger", last_protagonist_visit: 2.hours.ago)

    _scene, agent = generate(location)

    prompt = agent.prompts.first
    assert_match "stood here before", prompt
    assert_match "about 2 hours ago", prompt
    assert_match "Narrate coming back", prompt
    assert_no_match(/never been here/, prompt)
  end

  test "the elapsed time is the real gap, not a fixed phrase" do
    _scene, agent = generate(realized_location(last_protagonist_visit: 3.days.ago))

    assert_match "3 days ago", agent.prompts.first
  end

  # `Scene#mark_location_visit` is an after_create that stamps the visit with
  # now. Read the gap after the record exists and every return reads as "less
  # than a minute ago", which is the one thing this generator is for.
  test "reads the elapsed time before creating the scene stamps it away" do
    location = realized_location(last_protagonist_visit: 5.days.ago)

    _scene, agent = generate(location)

    assert_match "5 days ago", agent.prompts.first
    assert_in_delta Time.current, location.reload.last_protagonist_visit, 5.seconds
  end

  test "the second arrival in a location is a return even though the first was not" do
    location = realized_location(last_protagonist_visit: nil)

    _first, first_agent = generate(location)
    _second, second_agent = generate(location.reload)

    assert_match "never been here", first_agent.prompts.first
    assert_match "stood here before", second_agent.prompts.first
  end

  # --- story time ----------------------------------------------------------

  # An arrival happens at the end of the journey, and how long the journey took
  # is `LocationConnection`'s answer from its own fixed tables. No model, no wall
  # clock.
  test "an arrival is stamped the journey's length after the scene it came from" do
    from = realized_location(name: "Mournwell Lane")
    to = realized_location(name: "The Celestial Spire")
    create(:location_connection, location: from, connected_location: to,
                                 distance: "across the district", travel_method: "walking")
    left = create(:scene, story: @story, location: from, story_timestamp: @story.start_time + 1.hour)

    scene, = generate(to, previous_scene: left)

    assert_equal left.story_timestamp + 20.minutes, scene.story_timestamp
  end

  test "a slower way of travelling costs more story time" do
    from = realized_location(name: "Mournwell Lane")
    to = realized_location(name: "Larkspur Quarter rooftops")
    create(:location_connection, location: from, connected_location: to,
                                 distance: "across the district", travel_method: "climbing")
    left = create(:scene, story: @story, location: from, story_timestamp: @story.start_time)

    scene, = generate(to, previous_scene: left)

    assert_equal @story.start_time + 60.minutes, scene.story_timestamp
  end

  test "an arrival with nothing before it happens at the story's clock" do
    location = realized_location

    scene, = generate(location)

    assert_equal @story.clock, scene.story_timestamp
  end

  # THE DEFECT THIS CLOSES. The player shuts the tab for three weeks and comes
  # back; the fiction should say twenty minutes, because twenty minutes of the
  # story is what passed.
  test "how long they were gone is story time, not how long the tab was shut" do
    location = realized_location(name: "Room 3")
    lane = realized_location(name: "Mournwell Lane")
    create(:location_connection, location: lane, connected_location: location,
                                 distance: "a short walk", travel_method: "walking")

    first, = generate(location)
    left = create(:scene, story: @story, location: lane, previous_scene: first,
                          story_timestamp: first.story_timestamp + 15.minutes)

    travel 3.weeks do
      _second, agent = generate(location.reload, previous_scene: left)

      assert_match "20 minutes ago", agent.prompts.first
      assert_no_match(/weeks ago/, agent.prompts.first)
    end
  end

  test "the visit is stamped with the arrival's own story moment" do
    location = realized_location

    scene, = generate(location)

    assert_equal scene.story_timestamp, location.reload.last_protagonist_visit
  end

  # --- who is present ------------------------------------------------------

  test "the protagonist is present" do
    protagonist = create(:character, :protagonist, story: @story)

    scene, = generate(realized_location)

    assert_includes scene.characters, protagonist
  end

  test "companions travel with the protagonist" do
    companion = create(:character, :companion, story: @story)
    bystander = create(:character, story: @story)

    scene, = generate(realized_location)

    assert_includes scene.characters, companion
    assert_not_includes scene.characters, bystander
  end

  # The world persists and so do the people in it: whoever the records place
  # here is here, whether or not anybody has ever walked in.
  test "whoever the records place here is here" do
    location = realized_location(last_protagonist_visit: 1.hour.ago)
    innkeeper = create(:character, story: @story, fullname: "Grenn Halloway", location: location)

    scene, = generate(location)

    assert_includes scene.characters, innkeeper
  end

  # WHAT THE WHEREABOUTS RECORD REPLACED. The cast used to be reconstructed
  # from the last scene in this room that had recorded anybody, so presence
  # depended on a scene having been written -- and only an arrival writes a
  # cast. A room nobody had walked into was therefore empty however central the
  # person standing in it was: The Tide Post recorded the protagonist alone in
  # a world about a man chained to it. Nothing here writes a scene at all.
  test "presence does not depend on any scene having recorded a cast" do
    location = realized_location(last_protagonist_visit: 1.hour.ago)
    innkeeper = create(:character, story: @story, fullname: "Grenn Halloway", location: location)

    assert_equal [], location.scenes.to_a
    assert_equal [ innkeeper ], Scene::Generator.characters_present(location)

    scene, = generate(location)

    assert_includes scene.characters, innkeeper
  end

  # And the other half of it: a scene's cast is a SNAPSHOT of the records, so a
  # stale one cannot put somebody back in a room the records have moved them
  # out of.
  test "an old scene's cast does not override the records" do
    location = realized_location(last_protagonist_visit: 1.hour.ago)
    elsewhere = realized_location(name: "The Pump Gallery")
    innkeeper = create(:character, story: @story, fullname: "Grenn Halloway", location: elsewhere)
    create(:scene, story: @story, location: location, story_timestamp: 1.hour.ago)
      .characters << innkeeper

    scene, = generate(location)

    assert_not_includes scene.characters, innkeeper
  end

  # `.characters_present(location)` is the same answer without building an
  # arrival, and Playthrough::Classifier depends on the two agreeing.
  test "the cast can be asked for without generating a scene" do
    location = realized_location
    companion = create(:character, :companion, story: @story)
    protagonist = create(:character, :protagonist, story: @story)

    assert_no_difference -> { Scene.count } do
      assert_equal [ protagonist, companion ].sort_by(&:id),
                   Scene::Generator.characters_present(location).sort_by(&:id)
    end
  end

  test "people in some other location are not here" do
    elsewhere = realized_location(name: "The Pump Gallery")
    stranger = create(:character, story: @story, location: elsewhere)

    scene, = generate(realized_location(name: "The Drowned Ledger"))

    assert_not_includes scene.characters, stranger
  end

  test "a place nobody has been and nobody follows you into is empty" do
    create(:character, story: @story)

    scene, = generate(realized_location)

    assert_empty scene.characters
  end

  test "attaches each present character once" do
    protagonist = create(:character, :protagonist, story: @story)
    location = realized_location(last_protagonist_visit: 1.hour.ago)
    create(:scene, story: @story, location: location).characters << protagonist

    scene, = generate(location)

    assert_equal [ protagonist ], scene.characters.to_a
  end

  test "names who is present in the prompt without their whole character sheet" do
    companion = create(:character, :companion, story: @story, fullname: "Mira Vance", nickname: "Mira")

    _scene, agent = generate(realized_location)

    prompt = agent.prompts.first
    assert_match "Mira Vance (Mira)", prompt
    assert_no_match(/#{Regexp.escape(companion.backstory)}/, prompt)
  end

  # --- the prompt ----------------------------------------------------------

  test "asks with a schema -- this writes a record, it does not stream" do
    _scene, agent = generate(realized_location)

    assert_equal [ Scene::Schema ], agent.schemas
  end

  test "prompts with the place the player is standing in" do
    location = realized_location(name: "The Drowned Ledger",
                                 description: "Water laps at the third stair.",
                                 lore: "The house has collected debts here for two hundred years.")

    _scene, agent = generate(location)

    prompt = agent.prompts.first
    assert_match "The Drowned Ledger", prompt
    assert_match "Water laps at the third stair.", prompt
    assert_match "two hundred years", prompt
  end

  test "lists the ways out so the arrival cannot invent one" do
    location = realized_location(name: "The Drowned Ledger")
    neighbour = realized_location(name: "The Pump Gallery")
    LocationConnection.create!(location: location, connected_location: neighbour,
                               distance: "adjacent", travel_method: "walking")

    _scene, agent = generate(location)

    assert_match "The Pump Gallery", agent.prompts.first
  end

  # The summary is written for exactly this: the same moment in a fraction of
  # the tokens the description costs.
  test "leads in with the previous scene's summary rather than its prose" do
    previous = create(:scene, story: @story, location: realized_location(name: "Tidewater Stair"),
                              description: "A long paragraph the player already read.",
                              summary: "They climbed down out of the rain.")

    _scene, agent = generate(realized_location, previous_scene: previous)

    prompt = agent.prompts.first
    assert_match "They climbed down out of the rain.", prompt
    assert_match "come from Tidewater Stair", prompt
    assert_no_match(/A long paragraph the player already read\./, prompt)
  end

  test "falls back to the previous scene's prose when it has no summary" do
    previous = create(:scene, story: @story, location: realized_location,
                              description: "The door swings open.", summary: nil)

    _scene, agent = generate(realized_location, previous_scene: previous)

    assert_match "The door swings open.", agent.prompts.first
  end

  # `:scene` is `:place` minus everything the location record already carries.
  # See Universe::AUDIENCE_FIELDS.
  test "sends the scene audience of the universe, not the whole record" do
    _scene, agent = generate(realized_location)

    universe = @story.universe
    prompt = agent.prompts.first

    assert_match universe.physics, prompt
    assert_match universe.technology, prompt
    assert_no_match(/#{Regexp.escape(universe.geographies)}/, prompt)
    assert_no_match(/#{Regexp.escape(universe.politics)}/, prompt)
    assert_no_match(/#{Regexp.escape(universe.history)}/, prompt)
  end

  # --- failures ------------------------------------------------------------

  test "refuses to narrate arriving in a stub" do
    stub_location = create(:location, :stub, story: @story, name: "The Pump Gallery")

    error = assert_raises(ArgumentError) do
      Scene::Generator.new(stub_location).generate!
    end

    assert_match "still a stub", error.message
  end

  test "makes no model call for a stub" do
    stub_location = create(:location, :stub, story: @story)
    agent = FakeAgent.new(ARRIVAL)

    BaseAgent.stub(:new, agent) do
      assert_raises(ArgumentError) { Scene::Generator.new(stub_location).generate! }
    end

    assert_empty agent.prompts
  end

  # --- the story's opening arrival ----------------------------------------
  #
  # The one arrival that is narrated at WORLD-BUILDING time rather than when the
  # player walks in, because the player never walks in -- they start standing in
  # it. `rake game:new` pays for it once; the exporter carries it into the seed
  # file; a player starting a story pays no model call at all.

  test "narrates the story's opening arrival in the opening location" do
    opening = realized_location(name: "The Salt Chapel")
    realized_location(name: "Somewhere Later")
    agent = FakeAgent.new(ARRIVAL)

    scene = BaseAgent.stub(:new, agent) { Scene::Generator.opening(@story) }

    assert scene.is_opening?
    assert_equal opening, scene.location
    assert_equal ARRIVAL["description"], scene.description
    assert_nil scene.previous_scene
    assert_equal scene, @story.reload.opening_scene
  end

  # It is the moment the story begins, and the world already holds that moment.
  test "the opening arrival is stamped with the story's start time" do
    realized_location
    agent = FakeAgent.new(ARRIVAL)

    scene = BaseAgent.stub(:new, agent) { Scene::Generator.opening(@story) }

    assert_equal @story.start_time, scene.story_timestamp
  end

  # THE STORY-TIME HAZARD. A world can be built weeks before anybody plays it,
  # so an opening arrival must not date the protagonist's presence to when the
  # world was made -- see Scene#mark_location_visit.
  test "the opening arrival does not mark the opening room as visited" do
    opening = realized_location
    agent = FakeAgent.new(ARRIVAL)

    BaseAgent.stub(:new, agent) { Scene::Generator.opening(@story) }

    assert_nil opening.reload.last_protagonist_visit
  end

  test "an ordinary arrival still marks the room as visited" do
    location = realized_location

    generate(location)

    assert location.reload.last_protagonist_visit.present?
  end

  test "refuses to open a story with nowhere to open in" do
    error = assert_raises(ArgumentError) { Scene::Generator.opening(@story) }

    assert_match "no location to open in", error.message
  end

  # Generators raise. A rescue that returns a half-built record turns a bad
  # model response into "the AI produced garbage" three layers downstream.
  test "raises rather than saving a scene the model left blank" do
    agent = FakeAgent.new("description" => "", "summary" => "")

    assert_no_difference -> { Scene.count } do
      assert_raises(ActiveRecord::RecordInvalid) { generate(realized_location, agent: agent) }
    end
  end
  # The instruction says to write everyone listed as already present. Unmarked,
  # the protagonist's own line read as an instruction to write the player into
  # the room as a bystander they then meet.
  test "the cast list marks the protagonist as the player" do
    protagonist = create(:character, :protagonist, story: @story, fullname: "Isbet Marrow", nickname: "Iz")
    companion = create(:character, :companion, story: @story, fullname: "Mira Vance", nickname: "Mira")

    _scene, agent = generate(realized_location)
    prompt = agent.prompts.first

    assert_match(/Isbet Marrow \(Iz\), #{Regexp.escape(protagonist.race.name)} -- the player, the one arriving/, prompt)
    assert_match(/Mira Vance \(Mira\), #{Regexp.escape(companion.race.name)}\n/, prompt)
    assert_no_match(/Mira Vance.*the player/, prompt)
  end
end
