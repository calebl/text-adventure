require "/home/calebl/Projects/text-adventure/test/test_helper"

# Review probes: these assert the observed defects, not desired behavior.
# All provider responses are explicit fixtures; no live model is called.
# Each test rolls back its database writes through ActiveSupport::TestCase.
class AdversarialReviewTest < ActiveSupport::TestCase
  ARRIVAL = { "description" => "You enter the room.", "summary" => "The player enters the room." }.freeze
  DETAIL = { "description" => "A stone chamber.", "lore" => "It once housed a clerk.", "items" => [], "people" => [] }.freeze

  def setup
    @story = create(:story, start_time: Time.utc(2026, 1, 1, 12))
    @hero = create(:character, story: @story, fullname: "Iri Calder", age: 25, sex: "female", is_protagonist: true, level: 3)
    @here = create(:location, story: @story, name: "Market")
    @opening = create(:scene, story: @story, location: @here, story_timestamp: @story.start_time, is_opening: true)
    @game = create(:playthrough, story: @story, character: @hero, current_location: @here, current_scene: @opening)
  end

  def connect(name, **attributes)
    room = create(:location, story: @story, name: name, **attributes)
    create(:location_connection, :short_distance, location: @here, connected_location: room)
    create(:location_connection, :short_distance, location: room, connected_location: @here)
    room
  end

  def npc(room = @here)
    create(:character, story: @story, location: room, fullname: "Maren Vosk", nickname: "Maren", age: 40, sex: "female")
  end

  def play(command, *responses, game: @game)
    fake = FakeAgent.new(*responses)
    result = BaseAgent.stub(:new, fake) { Playthrough::Turn.new(game).play(command) }
    [result, fake]
  end

  test "dialogue promises a transfer and following but applies neither" do
    person = npc
    key = create(:item, character: person, name: "brass key")
    reaction = {
      "pre_thought" => "I trust her.", "pre_feeling" => "relieved",
      "action" => 'Maren hands Iri the brass key. "I will follow you."',
      "post_thought" => "I will keep her safe.", "post_feeling" => "determined",
      "inner_resolution" => "I will follow Iri and protect her."
    }
    play("/talk Maren", reaction, "Maren hands you the brass key and agrees to follow you.")
    assert_equal person, @game.items.find_by!(template: key).character
    assert_empty @game.carried
    assert_equal reaction["inner_resolution"], person.interactions.last.inner_resolution
    destination = connect("Quay")
    play("/move Quay", ARRIVAL)
    assert_equal destination, @game.reload.current_location
    assert_equal @here, person.reload.location
    refute_includes @game.cast_in(destination), person
  end

  test "an other action can narrate consuming a potion without consuming or healing" do
    potion = create(:item, :carried, playthrough: @game, name: "healing potion")
    Playthrough::Turn.new(@game).harm!(@hero, 5)
    before_hp = @game.condition.hp
    result, = play("I drink the healing potion", { "intent" => "other", "target" => "nothing" },
                   "You drink the healing potion. Your wounds close.")
    assert_equal "other", result.resolved_action
    assert_equal before_hp, @game.condition.hp
    assert_includes @game.carried, potion
    assert_includes result.description, "Your wounds close"
  end

  test "arrival prompt explicitly offers a dead person and original floor contents" do
    destination = connect("Counting House", description: "Maren Vosk waits beside a brass key on the desk.")
    person = npc(destination)
    key = create(:item, :lying, location: destination, name: "brass key")
    Playthrough::Snapshot.new(@game).of_the_room!(destination)
    turn = Playthrough::Turn.new(@game)
    turn.harm!(person, 100)
    turn.carry!(@game.items.find_by!(template: key))
    scene, fake = play("/move Counting House", ARRIVAL)
    prompt = fake.prompts.last
    assert_match(/## Who Is Here.*Maren Vosk/m, prompt)
    assert_includes prompt, "a brass key on the desk"
    refute_includes prompt, "dead"
    refute_includes prompt, "carrying"
    refute_includes scene.characters, person
    assert @game.vitals_for(person).dead?
  end

  test "arrival toll is marked told without being supplied to its narrator" do
    destination = connect("Flooded Cellar", hazard: "flooded", hazard_die: 4)
    scene, fake = play("/move Flooded Cellar", ARRIVAL)
    toll = @game.tolls.sole
    assert_equal scene.id, toll.scene_id
    assert_equal destination, toll.location
    refute_includes fake.prompts.last, "hit point"
    refute_includes fake.prompts.last, "got clear"
    assert_empty @game.tolls.untold
  end

  test "exit failure permanently skips exit generation on retry" do
    destination = connect("New Chamber", detail_level: :stub, description: nil, lore: nil)
    failing = FakeAgent.new(DETAIL, RuntimeError.new("provider unavailable"))
    assert_raises(RuntimeError) do
      BaseAgent.stub(:new, failing) { Location::Generator.new(destination).realize! }
    end
    assert destination.reload.realized?
    assert_equal [@here.id], destination.exits.pluck(:id)
    retry_agent = FakeAgent.new
    BaseAgent.stub(:new, retry_agent) { Location::Generator.new(destination.reload).realize! }
    assert_empty retry_agent.prompts
    assert_equal [@here.id], destination.exits.pluck(:id)
  end

  test "failed arrival charges crossing damage again on retry" do
    destination = connect("Quay")
    edge = LocationConnection.find_by!(location: @here, connected_location: destination)
    edge.update!(hazard: "drop", hazard_die: 4)
    @hero.update!(dexterity: 3)
    failing = FakeAgent.new(RuntimeError.new("provider unavailable"))
    BaseAgent.stub(:new, failing) do
      assert_raises(RuntimeError) { Playthrough::Turn.new(@game).play("/move Quay") }
    end
    assert_equal @here, @game.reload.current_location
    assert_equal 1, @game.tolls.count
    play("/move Quay", ARRIVAL)
    assert_equal 2, @game.tolls.count
    assert_equal destination, @game.reload.current_location
  end

  test "failed take moves the item and skips the enemy response" do
    person = npc
    person.update!(hostile: true)
    item = lying_here(@game, @here, name: "red coin")
    failing = FakeAgent.new(RuntimeError.new("provider unavailable"))
    BaseAgent.stub(:new, failing) do
      assert_raises(RuntimeError) { Playthrough::Turn.new(@game).play("/take red coin") }
    end
    assert_includes @game.carried, item
    assert_empty @game.blows
    assert_equal @opening, @game.reload.current_scene
  end

  test "interleaved turns overwrite one scene while keeping both item mutations" do
    first = lying_here(@game, @here, name: "red coin")
    second = lying_here(@game, @here, name: "blue coin")
    stale_game = Playthrough.find(@game.id)
    stale_game.current_scene
    hook_agent = FakeAgent.new("You pick up the blue coin.", "You pick up the red coin.")
    hook_agent.define_singleton_method(:ask) do |prompt, verify: nil, &block|
      unless @interleaved
        @interleaved = true
        Playthrough::Turn.new(Playthrough.find(stale_game.id)).play("/take blue coin")
      end
      super(prompt, verify: verify, &block)
    end
    BaseAgent.stub(:new, hook_agent) { Playthrough::Turn.new(stale_game).play("/take red coin") }
    assert_equal [first.id, second.id].sort, @game.reload.carried.pluck(:id).sort
    assert_equal 2, @story.scenes.where(previous_scene: @opening).count
    assert_equal 2, @game.scene_chain.size, "opening plus only one of the two completed turns"
    refute @game.scene_chain.any? { |scene| scene.typed == "take blue coin" }
  end

  test "fleeing closes combat in the old room then prices the next move from that room" do
    person = npc
    person.update!(hostile: true, hit_die: 6)
    quay = connect("Quay")
    tower = create(:location, story: @story, name: "Tower")
    edge = create(:location_connection, location: quay, connected_location: tower, distance: "across the district")
    play("/move Quay", ARRIVAL)
    assert_equal quay, @game.reload.current_location
    assert_equal @here, @game.current_scene.location
    before = @game.story_now
    play("/move Tower", ARRIVAL)
    actual_minutes = (@game.reload.story_now - before) / 60
    assert_equal LocationConnection::DISTANCES.fetch("adjacent"), actual_minutes
    refute_equal edge.time_to_travel, actual_minutes
  end

  test "important NPC conclusions fall out after enough small exchanges" do
    person = npc
    9.times do |i|
      scene = create(:scene, story: @story, location: @here, previous_scene: @game.current_scene,
                             story_timestamp: @story.start_time + (i + 1).minutes)
      create(:interaction, character: person, location: @here, scene: scene,
                           inner_resolution: i.zero? ? "Iri murdered my brother; I will never trust her." : "I will continue discussing weather #{i}.")
      @game.update!(current_scene: scene)
    end
    assert_equal 9, person.interactions.count
    context = Playthrough::Moment.new(@game).character_context(person)
    refute_includes context, "murdered my brother"
    assert_includes context, "weather"
    person.update!(level: 3)
    Playthrough::Turn.new(@game).strike!(@hero, person, round: 1)
    context = Playthrough::Moment.new(@game).character_context(person)
    refute_includes context, "struck"
    refute_includes context, "hurt"
    refute_includes context, "fighting"
  end

  test "reaching the world cast cap forces even a populated new room to be empty" do
    (Character::Registry::MAX_PER_STORY - @story.characters.count).times do |i|
      create(:character, story: @story, fullname: "Resident #{i}", age: 40, sex: "male")
    end
    destination = connect("Busy Tavern", detail_level: :stub, population: "a crowd")
    registry = Character::Registry.new(destination)
    assert_equal 0, registry.allowance
    assert_includes Location::Generator.new(destination).detail_prompt, "Write NOBODY"
    Item::Registry::MAX_PER_STORY.times do |i|
      create(:item, :lying, location: @here, name: "world item #{i}")
    end
    assert_equal 0, Item::Registry.new(destination).world_for_items
  end

  test "one playthrough makes a second player's first visit a return" do
    destination = connect("Tower")
    another = create(:playthrough, story: @story, character: @hero, current_location: @here, current_scene: @opening)
    play("/move Tower", ARRIVAL)
    _, fake = play("/move Tower", ARRIVAL, game: another)
    assert_includes fake.prompts.last, "has stood here before"
    assert_equal 1, another.scene_chain.count { |scene| scene.location == destination }
  end

  test "world catching up fires another game's event from the global maximum clock" do
    another = create(:playthrough, story: @story, character: @hero, current_location: @here, current_scene: @opening)
    future = create(:scene, story: @story, location: @here, previous_scene: @opening, story_timestamp: @story.start_time + 2.hours)
    @game.update!(current_scene: future)
    event = @story.world_events.create!(source: "quest", playthrough: @game, occurred_at: @story.start_time,
                                       scheduled_for: @story.start_time + 1.hour, summary: "The tower explodes.")
    play("/look", { "intent" => "examine", "target" => "nothing" }, "You look around.", game: another)
    assert event.reload.fired?
    assert_operator event.fired_at, :>, another.story_now
    refute_includes Playthrough::Moment.new(another).narration_context, "tower explodes"
  end

  test "a scheduled catastrophe fires without changing the named location or narration context" do
    event = @story.world_events.create!(source: "seeded", occurred_at: @story.start_time,
                                       scheduled_for: @story.start_time, summary: "The market burns to the ground.")
    event.locations << @here
    before = @here.attributes
    @story.catch_up_world!
    assert event.reload.fired?
    assert_equal before, @here.reload.attributes
    refute_includes Playthrough::Moment.new(@game).narration_context, event.summary
  end

  test "two loaded stubs can generate the same location twice" do
    destination = connect("New Chamber", detail_level: :stub, description: nil, lore: nil)
    first_copy = Location.find(destination.id)
    second_copy = Location.find(destination.id)
    first = FakeAgent.new(DETAIL, { "exits" => [] })
    second = FakeAgent.new(DETAIL.merge("description" => "An entirely different room."), { "exits" => [] })
    BaseAgent.stub(:new, first) { Location::Generator.new(first_copy).realize! }
    BaseAgent.stub(:new, second) { Location::Generator.new(second_copy).realize! }
    assert_equal 2, first.prompts.count
    assert_equal 2, second.prompts.count
    assert_equal "An entirely different room.", destination.reload.description
  end

  test "generated alternative endings have no reachable condition" do
    content = {
      "title" => "Rescue the Prince", "premise" => "Bring the prince home.",
      "steps" => [
        { "summary" => "Find the tower.", "trigger" => "reach_location", "target" => "Tower", "teaser" => "A prison tower." },
        { "summary" => "Pick up the key.", "trigger" => "hold_item", "target" => "cell key", "teaser" => "An iron key." },
        { "summary" => "Speak to the prince.", "trigger" => "speak_to", "target" => "Prince Arlo", "teaser" => "A captive prince." }
      ],
      "outcomes" => [
        { "name" => "rescued", "summary" => "The prince was rescued.", "is_default" => true },
        { "name" => "betrayed", "summary" => "The prince was betrayed.", "is_default" => false }
      ]
    }
    agent = FakeAgent.new(content)
    quest = BaseAgent.stub(:new, agent) { Quest::Generator.new(@story).generate! }
    assert_equal 2, quest.outcomes.count
    assert_empty quest.outcomes.conditional
    refute Playthrough::Arc.new(@game).satisfies?(quest.outcomes.find_by!(name: "betrayed"))
  end

  test "an NPC agreeing to cease fighting still attacks in the same turn" do
    person = npc
    person.update!(hostile: true)
    reaction = {
      "pre_thought" => "Enough fighting.", "pre_feeling" => "remorseful",
      "action" => 'Maren lowers her weapon. "I accept your truce."',
      "post_thought" => "I will keep the peace.", "post_feeling" => "calm",
      "inner_resolution" => "I will not attack Iri again."
    }
    play("/talk Maren", reaction, "Maren lowers her weapon and accepts your truce.")
    assert_equal 1, @game.blows.where(attacker: person, target: @hero).count
    assert_includes @game.foes_in(@here), person
  end
end
