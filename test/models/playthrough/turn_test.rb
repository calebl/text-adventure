require "test_helper"

# The loop. What matters here is not the prose -- it is where the player ends
# up, what got generated on the way, and what did NOT get generated on the way
# back, which is the whole claim the project makes.
#
# One FakeAgent stands in for every BaseAgent the turn builds, so the queued
# responses are the turn's model calls in order:
#
#   classify -> [realize detail, realize exits] -> arrival     (a move)
#   classify -> character reaction -> narration                (a talk)
#   classify -> narration                                      (anything else)
#
# Running out of queued responses raises, which is how a test that expected a
# call the loop did not make fails loudly instead of passing quietly.
class Playthrough::TurnTest < ActiveSupport::TestCase
  CLASSIFY = ->(intent, target) { { "intent" => intent, "target" => target } }

  DETAIL = {
    "description" => "Water stands ankle deep across the flagstones.",
    "lore" => "The vestibule drowned the winter the river took the lower town."
  }.freeze

  ARRIVAL = {
    "description" => "You come down into the cold and the water takes your boots.",
    "summary" => "The protagonist arrives in the Drowned Vestibule."
  }.freeze

  REACTION = {
    "pre_thought" => "Is that person talking to me?",
    "pre_feeling" => "surprised, wary",
    "action" => "She sets down the crate.",
    "post_feeling" => "steadier",
    "post_thought" => "Say something before this gets strange."
  }.freeze

  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ashgate Market")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
  end

  def play(command, *responses)
    agent = FakeAgent.new(*responses)
    chunks = []

    scene = BaseAgent.stub(:new, agent) do
      Playthrough::Turn.new(@playthrough).play(command) { |chunk| chunks << chunk }
    end

    [ scene, chunks, agent ]
  end

  # A neighbour plus the connection rows in both directions, which is what
  # Location::Generator writes when it realizes a room.
  def connect(name, **attributes)
    neighbour = create(:location, story: @story, name: name, **attributes)
    create(:location_connection, location: @here, connected_location: neighbour,
                                 distance: "adjacent", travel_method: "walking")
    create(:location_connection, location: neighbour, connected_location: @here,
                                 distance: "adjacent", travel_method: "walking")
    neighbour
  end

  # Somebody the game knows is standing here: recorded in the last scene played
  # in this location, which is how Scene::Generator answers the question. The
  # scene doubles as the one the player is currently in.
  def holdover(fullname, **attributes)
    character = create(:character, story: @story, fullname: fullname, **attributes)
    scene = create(:scene, story: @story, location: @here, characters: [ character ])
    @playthrough.update!(current_scene: scene)
    character
  end

  # --- moving into somewhere new -------------------------------------------

  test "walking into a stub realizes it and narrates arriving" do
    vestibule = connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    scene, chunks, = play("go down to the vestibule",
                          CLASSIFY.call("move", "Drowned Vestibule"),
                          DETAIL, { "exits" => [] }, ARRIVAL)

    assert_predicate vestibule.reload, :realized?
    assert_equal DETAIL["description"], vestibule.description
    assert_equal ARRIVAL["description"], scene.description
    assert_equal vestibule, scene.location
    assert_equal [ ARRIVAL["description"] ], chunks
  end

  test "a move points the playthrough at the new location and the new scene" do
    vestibule = connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    scene, = play("go down", CLASSIFY.call("move", "Drowned Vestibule"),
                  DETAIL, { "exits" => [] }, ARRIVAL)

    @playthrough.reload
    assert_equal vestibule, @playthrough.current_location
    assert_equal scene, @playthrough.current_scene
  end

  test "the arrival scene links back to the scene the player left" do
    left_behind = create(:scene, story: @story, location: @here, description: "You turn from the stalls.")
    @playthrough.update!(current_scene: left_behind)
    connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    scene, = play("go down", CLASSIFY.call("move", "Drowned Vestibule"),
                  DETAIL, { "exits" => [] }, ARRIVAL)

    assert_equal left_behind, scene.previous_scene
  end

  # --- moving back into somewhere already written --------------------------

  # THE POINT OF THE WHOLE THING. A realized location is not regenerated, so
  # walking back costs one arrival call instead of three, and the room the
  # player reads is the room they left.
  test "walking back into a realized location generates nothing but the arrival" do
    market = create(:location, story: @story, name: "Ashgate Market",
                               description: "Stalls under wet canvas.", lore: "It was a fish market once.")
    vestibule = create(:location, story: @story, name: "Drowned Vestibule")
    create(:location_connection, location: vestibule, connected_location: market,
                                 distance: "adjacent", travel_method: "walking")
    @playthrough.update!(current_location: vestibule)

    _scene, _chunks, agent = play("back up to the market",
                                  CLASSIFY.call("move", "Ashgate Market"), ARRIVAL)

    # Two prompts: the classification and the arrival. No detail, no exits.
    assert_equal 2, agent.prompts.count
    assert_equal "Stalls under wet canvas.", market.reload.description
  end

  test "a return visit is narrated as coming back rather than as discovery" do
    market = create(:location, story: @story, name: "Riverside", last_protagonist_visit: 2.hours.ago,
                               description: "Stalls under wet canvas.", lore: "A fish market once.")
    create(:location_connection, location: @here, connected_location: market,
                                 distance: "adjacent", travel_method: "walking")

    _scene, _chunks, agent = play("go to the riverside",
                                  CLASSIFY.call("move", "Riverside"), ARRIVAL)

    arrival_prompt = agent.prompts.last
    assert_match(/has stood here before/, arrival_prompt)
    assert_match(/about 2 hours ago/, arrival_prompt)
  end

  # `Scene`'s after_create stamps the visit, so this is what makes the next
  # walk back read as a return.
  test "arriving stamps the location as visited" do
    vestibule = connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    play("go down", CLASSIFY.call("move", "Drowned Vestibule"),
         DETAIL, { "exits" => [] }, ARRIVAL)

    assert_not_nil vestibule.reload.last_protagonist_visit
  end

  # --- story time -----------------------------------------------------------

  test "an arrival costs the story the length of the walk" do
    connect("Drowned Vestibule")
    here_scene = create(:scene, story: @story, location: @here,
                                story_timestamp: @story.start_time + 1.hour)
    @playthrough.update!(current_scene: here_scene)

    scene, = play("go down", CLASSIFY.call("move", "Drowned Vestibule"), ARRIVAL)

    assert_equal here_scene.story_timestamp + 1.minute, scene.story_timestamp
  end

  test "a conversation costs the story ten minutes" do
    holdover("Rell Vance")
    before = @playthrough.reload.story_now

    scene, = play("ask about the crate", CLASSIFY.call("talk", "Rell Vance"),
                  REACTION, "She looks up from the crate.")

    assert_equal before + Scene::TURN_MINUTES.fetch("conversation").minutes, scene.story_timestamp
  end

  test "any other turn costs the story one beat in the room" do
    before = @playthrough.reload.story_now

    scene, = play("look at the awnings", CLASSIFY.call("examine", "awnings"),
                  "Canvas, patched and repatched.")

    assert_equal before + Scene::TURN_MINUTES.fetch("action").minutes, scene.story_timestamp
  end

  test "no turn stamps a scene with the wall clock" do
    travel 3.weeks do
      scene, = play("look at the awnings", CLASSIFY.call("examine", "awnings"), "Canvas.")

      assert_operator scene.story_timestamp, :<, Time.current - 2.weeks
    end
  end

  # --- the world moving on its own ------------------------------------------

  # THE WORLD MOVES FIRST, and it does not need anybody to be watching. Nothing
  # is scheduled and nothing is in memory: the nights are simply owed, and the
  # next turn pays them.
  test "a turn catches the world up on every night the story has passed" do
    mechanic = create(:world_mechanic, story: @story, name: "The nightly rearrangement")
    @playthrough.update!(current_scene: create(:scene, story: @story, location: @here,
                                                       story_timestamp: @story.start_time + 2.days))

    play("look at the awnings", CLASSIFY.call("examine", "awnings"), "Canvas.")

    assert_not_nil mechanic.reload.last_run_at
    assert_operator mechanic.last_run_at, :>, @story.start_time
  end

  test "the world catching up costs no model call of its own" do
    create(:world_mechanic, story: @story, name: "The nightly rearrangement")
    @playthrough.update!(current_scene: create(:scene, story: @story, location: @here,
                                                       story_timestamp: @story.start_time + 2.days))

    # FakeAgent raises when a call it has no queued answer for arrives, so a turn
    # that made an extra one would fail here rather than pass quietly.
    _scene, _chunks, agent = play("look at the awnings", CLASSIFY.call("examine", "awnings"), "Canvas.")

    assert_equal 2, agent.prompts.size
  end

  # --- moving when the move cannot be made ---------------------------------

  test "a move nobody can make is narrated instead, and the player stays put" do
    connect("Drowned Vestibule")

    scene, chunks, = play("go north", CLASSIFY.call("move", "nothing"),
                          "There is nothing north of here but the river wall.")

    assert_equal @here, @playthrough.reload.current_location
    assert_equal "There is nothing north of here but the river wall.", scene.description
    assert_equal @here, scene.location
    assert_equal "There is nothing north of here but the river wall.", chunks.join
  end

  # --- talking -------------------------------------------------------------

  test "talking to someone here keeps the moment and what the character felt" do
    maren = holdover("Maren Vosk")

    scene, chunks, = play("ask Maren about the ledger",
                          CLASSIFY.call("talk", "Maren Vosk"),
                          REACTION, "Maren sets down the crate and squares her shoulders.")

    assert_equal "Maren sets down the crate and squares her shoulders.", scene.description
    assert_equal @here, scene.location
    assert_equal scene, @playthrough.reload.current_scene
    assert_equal "Maren sets down the crate and squares her shoulders.", chunks.join

    interaction = scene.interactions.sole
    assert_equal maren, interaction.character
    assert_equal "ask Maren about the ledger", interaction.user_input
    assert_equal @here, interaction.location
    REACTION.each { |field, value| assert_equal value, interaction.public_send(field) }
  end

  # The next turn in this room has to still know that person is standing in it,
  # and `Scene::Generator#holdovers` reads exactly this.
  test "a talk scene records the player and whoever they spoke to" do
    maren = holdover("Maren Vosk")

    scene, = play("hello", CLASSIFY.call("talk", "Maren Vosk"), REACTION, "She looks up.")

    assert_equal [ @protagonist, maren ].sort_by(&:id), scene.characters.sort_by(&:id)
  end

  test "a talk scene links back to the scene the player was in" do
    holdover("Maren Vosk")
    left_behind = @playthrough.current_scene

    scene, = play("hello", CLASSIFY.call("talk", "Maren Vosk"), REACTION, "She looks up.")

    assert_equal left_behind, scene.previous_scene
  end

  test "a talk summary names who was spoken to without a second model call" do
    holdover("Maren Vosk")

    scene, _chunks, agent = play("hello", CLASSIFY.call("talk", "Maren Vosk"),
                                 REACTION, "She looks up.")

    assert_match(/spoke with Maren Vosk/, scene.summary)
    assert_equal 3, agent.prompts.count # classify, character, narrator
  end

  test "talking to nobody is narrated instead" do
    scene, = play("talk to the ghost", CLASSIFY.call("talk", "nothing"),
                  "Nobody answers. The stalls are empty.")

    assert_equal "Nobody answers. The stalls are empty.", scene.description
    assert_empty scene.interactions
  end

  # Blank prose is not a turn -- Scene validates a description, and a record
  # written from nothing is a turn the player cannot read.
  test "a talk that narrated nothing keeps no records" do
    holdover("Maren Vosk")

    assert_no_difference [ -> { Scene.count }, -> { Interaction.count } ] do
      scene, = play("hello", CLASSIFY.call("talk", "Maren Vosk"), REACTION, "")

      assert_nil scene
    end
  end

  # --- the paths that fall through to the narrator -------------------------

  test "examine, take and other are answered by the narrator in place" do
    %w[examine take other].each do |action|
      scene, chunks, = play("look at the ledger", CLASSIFY.call(action, "nothing"),
                            "The ledger is swollen with damp.")

      assert_equal "The ledger is swollen with damp.", scene.description
      assert_equal @here, scene.location
      assert_equal @here, @playthrough.reload.current_location
      # The narrator streams: one chunk per word, not one paragraph.
      assert_operator chunks.count, :>, 1
    end
  end

  # --- failure ------------------------------------------------------------

  # A generator that raises is the documented contract. The loop must not
  # swallow it into a half-move: the player has to still be where they were.
  test "a failed arrival leaves the player where they were" do
    connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    assert_raises(RuntimeError) do
      # Classification succeeds, realization succeeds, the arrival call has
      # nothing queued.
      play("go down", CLASSIFY.call("move", "Drowned Vestibule"), DETAIL, { "exits" => [] })
    end

    @playthrough.reload
    assert_equal @here, @playthrough.current_location
    assert_nil @playthrough.current_scene
  end

  test "moving into a stub that realization left unrealized raises rather than narrating an empty room" do
    connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    assert_raises(ActiveRecord::RecordInvalid) do
      # A detail answer with no description cannot be saved as realized.
      play("go down", CLASSIFY.call("move", "Drowned Vestibule"),
           { "description" => "", "lore" => "" })
    end
  end
end
