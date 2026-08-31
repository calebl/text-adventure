require "test_helper"

# The loop. What matters here is not the prose -- it is where the player ends
# up, what got generated on the way, and what did NOT get generated on the way
# back, which is the whole claim the project makes.
#
# One FakeAgent stands in for every BaseAgent the turn builds, so the queued
# responses are the turn's model calls in order:
#
#   classify -> [realize detail, realize exits] -> arrival
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
