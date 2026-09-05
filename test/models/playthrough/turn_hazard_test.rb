require "test_helper"

# THE HAZARD IN THE BROWSER'S LOOP: where it is paid, and what stops it being
# told to the prose twice.
#
# `Playthrough::HazardsTest` is the branches on their own; this is the two
# places `Playthrough::Turn` calls them from -- `#move_to`, after the room is
# realized and after the snapshot, and step 7 beside `Playthrough::Riposte` --
# and the one line that claims a toll with the Scene that carried it.
#
# ONE FakeAgent STANDS IN FOR EVERY BaseAgent THE TURN BUILDS, so the queued
# responses ARE the model calls it is allowed to make, in order. Nothing about a
# hazard costs one, and running out of answers raises -- so a hazard that
# reached for a model would fail here loudly.
class Playthrough::TurnHazardTest < ActiveSupport::TestCase
  CLASSIFY = ->(intent, target) { { "intent" => intent, "target" => target } }

  # A realized room needs no detail call; an arrival still needs its own. See
  # `Playthrough::TurnTest` for the whole sequence a move makes.
  ARRIVAL = {
    "description" => "You come down into the closet and the shelves close over you.",
    "summary" => "The protagonist arrives in The Supply Closet."
  }.freeze

  def setup
    @story = create(:story)
    @vance = create(:character, story: @story, fullname: "Odile Vance", is_protagonist: true,
                                level: 3, hit_die: 8)
    @office = create(:location, story: @story, name: "Ward Office 12")
    @closet = create(:location, story: @story, name: "The Supply Closet")
    door(@office, @closet)
    door(@closet, @office)

    @rowe = create(:character, story: @story, fullname: "Halkett Rowe", nickname: "Rowe", location: @office)
    @playthrough = create(:playthrough, story: @story, character: @vance, current_location: @office)
    @stamp = create(:item, :lying, playthrough: @playthrough, location: @office, name: "ward stamp")
    @cord = create(:item, :lying, playthrough: @playthrough, location: @office, name: "tube-carrier cord")
  end

  def door(from, to, **attributes)
    create(:location_connection, location: from, connected_location: to,
                                 distance: "adjacent", travel_method: "walking", **attributes)
  end

  def play(command, *responses)
    agent = FakeAgent.new(*responses)
    outcome = BaseAgent.stub(:new, agent) { Playthrough::Turn.new(@playthrough).play(command) }

    [ outcome, agent ]
  end

  # --- where it is paid -----------------------------------------------------

  # THE ARRIVAL PAYS THE DOORWAY THAT WAS WALKED AND THE ROOM IT ARRIVED IN, in
  # that order, and BEFORE the arrival is narrated -- which is what lets the
  # arrival paragraph be the one that says the water took your legs.
  test "a move pays the doorway and then the room" do
    LocationConnection.walked(@office, @closet).update!(hazard: "drop", hazard_die: 4)
    @closet.update!(hazard: "flooded", hazard_die: 4)

    play("/go The Supply Closet", ARRIVAL)

    assert_equal %w[drop flooded], @playthrough.tolls.chronological.pluck(:hazard)
  end

  test "the way back over the same doorway is free" do
    LocationConnection.walked(@office, @closet).update!(hazard: "drop", hazard_die: 4)
    play("/go The Supply Closet", ARRIVAL)
    @playthrough.tolls.delete_all

    play("/go Ward Office 12", { "description" => "You climb back out into the office.", "summary" => "Back at the desk." })

    assert_equal 0, @playthrough.tolls.count
  end

  # STEP 7, BESIDE THE RIPOSTE and on the room the turn BEGAN in: a room whose
  # hazard is `every_turn` costs you for staying, on every line the engine
  # played and not only on a move.
  test "an every_turn room charges a line that did something else entirely" do
    @office.update!(hazard: "airless", hazard_die: 4)

    assert_difference("Playthrough::Toll.count", 1) do
      play("/take ward stamp", "You lift the brass stamp.")
    end
  end

  # *"A REFUSED LINE WRITES NOTHING"* -- the captain's ruling of 2026-09-04 --
  # and a toll is something. It stops in front of the dispatch, so step 7 is
  # never reached.
  test "a refused line pays no toll" do
    @office.update!(hazard: "airless", hazard_die: 4)

    assert_no_difference("Playthrough::Toll.count") do
      play("take the stamp and the cord",
           CLASSIFY.call("take", "ward stamp").merge("also_named" => "tube-carrier cord"))
    end
  end

  # AND A GAME THAT IS OVER PAYS NOTHING: the refusal is in front of everything,
  # so a line typed into a finished game costs no model call and writes nothing.
  test "a dead playthrough pays no toll" do
    @office.update!(hazard: "airless", hazard_die: 4)
    @playthrough.end!

    assert_no_difference("Playthrough::Toll.count") { play("/take ward stamp") }
  end

  # --- what stops it being told twice ---------------------------------------

  # `Playthrough::Moment` states the UNTOLD tolls as facts, so one of them has
  # to stop being untold once a paragraph has carried it. The stamp is here
  # rather than in `Playthrough::Hazards` for the reason `typed` is: this is the
  # one place with the turn's Scene on every branch.
  #
  # AN `every_turn` TOLL IS TOLD ON THE NEXT TURN, and that is the same shape
  # the riposte's blows already have: step 7 runs after the paragraph, so what
  # the place took this turn is a fact the NEXT paragraph carries. It is untold
  # while the turn that caused it ends, and claimed by the turn that says it.
  test "an every_turn toll is told by the next turn and claimed by it" do
    @office.update!(hazard: "airless", hazard_die: 4)

    play("/take ward stamp", "You lift the brass stamp.")
    assert_equal 1, @playthrough.tolls.untold.count, "step 7 runs after the paragraph"

    second, = play("/take tube-carrier cord", "You wind the cord off the hook.")

    assert_equal second, @playthrough.tolls.chronological.first.reload.scene
    assert_equal 1, @playthrough.tolls.untold.count, "and this turn's own toll waits for the next one"
  end

  # THE ARRIVAL'S OWN TOLL IS TOLD BY THE ARRIVAL. It is written before
  # `Scene::Generator` runs, so the paragraph that pays for the room is the one
  # that gets to mention what walking in cost -- and it is claimed straight
  # after.
  test "an arrival's toll is claimed by the arrival scene" do
    @closet.update!(hazard: "flooded", hazard_die: 4)

    scene, = play("/go The Supply Closet", ARRIVAL)

    assert_equal scene, @playthrough.tolls.sole.reload.scene
  end

  # A TURN THAT WROTE NO SCENE AT ALL CLAIMS NOTHING, and the toll waits for the
  # next paragraph rather than being quietly dropped. An attack is that turn:
  # the exchange is `playthrough_blows` and one Scene closes the fight.
  test "an attack turn leaves a toll untold for the next paragraph" do
    @office.update!(hazard: "airless", hazard_die: 4)

    play("/attack Halkett Rowe")

    assert_equal 1, @playthrough.tolls.untold.count
  end

  # --- what it must never do ------------------------------------------------

  test "a hazard costs no model call" do
    @closet.update!(hazard: "flooded", hazard_die: 4)
    LocationConnection.walked(@office, @closet).update!(hazard: "drop", hazard_die: 4)

    _, agent = play("/go The Supply Closet", ARRIVAL)

    assert_equal 1, agent.prompts.count, "the arrival's own narration and nothing else"
  end

  # A HAZARD IS NEVER A BLOW: `Playthrough::Fight#open_blows` is "the fight that
  # is still on", so a toll must not open one -- `#over?` would close it on the
  # same turn with a `Scene` about a fight nobody was in.
  test "a hazard opens no fight" do
    @office.update!(hazard: "airless", hazard_die: 4)

    play("/take ward stamp", "You lift the brass stamp.")

    assert_equal 0, @playthrough.blows.count
    assert_not Playthrough::Fight.new(@playthrough).on?
  end

  test "no typed line writes a hazard onto the world" do
    @office.update!(hazard: "airless", hazard_die: 4)
    LocationConnection.walked(@office, @closet).update!(hazard: "drop", hazard_die: 4)

    play("/take ward stamp", "You lift the brass stamp.")

    assert_equal "airless", @office.reload.hazard
    assert_equal 4, @office.hazard_die
    assert_equal "drop", LocationConnection.walked(@office, @closet).hazard
    assert_nil LocationConnection.walked(@closet, @office).hazard
  end
end
