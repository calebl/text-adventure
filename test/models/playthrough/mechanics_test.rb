require "test_helper"

# The engine with the prose taken out. What matters here is not what anything
# read like -- nothing reads like anything -- it is that after every command the
# DATABASE says what the read-out said, and that a refused command changed
# nothing at all.
#
# TWO PATHS IN, AND THE FILE IS SPLIT ALONG THEM:
#
#   `play`      the offline mode (`model: false`), run with `BaseAgent.new`
#               RAISING. That guarantee is asserted rather than assumed -- no
#               API key is deleted, no network is blocked, nothing is hoped for.
#               If any path through the offline mode ever reaches for a model,
#               every test using this helper fails on the spot.
#   `interpret` the default mode, driven through a FakeAgent standing in for
#               every BaseAgent the command builds. The queued responses ARE the
#               model calls the mode is allowed to make, in order, and running
#               out of them raises -- so a narrator call this mode must not make
#               fails the test loudly instead of passing quietly.
#
# The world is shaped like `the-unrecorded-hour.yml` -- an opening room, a
# realized dead end off it, an unwritten stub, something on each floor and
# something in the protagonist's hands -- and built with factories rather than
# loaded from the seed file, because `SeededWorldsTest` is deliberately the one
# test that reads those.
class Playthrough::MechanicsTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @vance = create(:character, story: @story, fullname: "Odile Vance", is_protagonist: true)
    @rowe = create(:character, story: @story, fullname: "Halkett Rowe")

    @office = create(:location, story: @story, name: "Ward Office 12")
    @closet = create(:location, story: @story, name: "The Supply Closet")
    @hallway = create(:location, :stub, story: @story, name: "The Long Hallway")
    connect(@office, @closet)
    connect(@office, @hallway)

    @stamp = create(:item, :lying, location: @office, name: "ward stamp")
    @index = create(:item, :lying, location: @closet, name: "Perrin's private index")
    @daybook = create(:item, character: @vance, name: "Ward Office 12 daybook")

    # The world's opening arrival, which is what puts Rowe in the room:
    # `Scene::Generator.characters_present` answers from the last scene played
    # in a location, so a world with no scene at all has nobody standing in it.
    # The seeded worlds carry one for exactly this reason.
    @opening = create(:scene, story: @story, location: @office, characters: [ @vance, @rowe ],
                              description: "The gap in the daybook is still under your hand.")
    @playthrough = create(:playthrough, story: @story, character: @vance,
                                        current_location: @office, current_scene: @opening)
  end

  def connect(from, to)
    create(:location_connection, location: from, connected_location: to,
                                 distance: "adjacent", travel_method: "walking")
    create(:location_connection, location: to, connected_location: from,
                                 distance: "adjacent", travel_method: "walking")
  end

  # One command in the OFFLINE mode, with no model reachable from anywhere
  # inside it.
  def play(command)
    BaseAgent.stub(:new, ->(*) { raise "the offline mechanics mode made a model call" }) do
      Playthrough::Mechanics.new(@playthrough, model: false).run(command)
    end
  end

  # One command in the DEFAULT mode: the classifier reads it and the world
  # generates itself. `responses` are the model calls this command is allowed to
  # make, in order -- a classification, then whatever a move has to generate.
  # The agent comes back so a test can count the prompts and prove no more were
  # asked for.
  def interpret(command, *responses)
    agent = FakeAgent.new(*responses)

    report = BaseAgent.stub(:new, agent) do
      Playthrough::Mechanics.new(@playthrough).run(command)
    end

    [ report, agent ]
  end

  CLASSIFY = ->(intent, target) { { "intent" => intent, "target" => target } }

  DETAIL = {
    "description" => "Doors on both sides, and the gas turned down to nothing.",
    "lore" => "The east ring's hallways were built for carts that no longer exist."
  }.freeze

  ARRIVAL = {
    "description" => "You step out and the hallway takes the sound of the door away.",
    "summary" => "Vance leaves the office for the long hallway."
  }.freeze

  # --- the offline mode: a scripted walk -------------------------------------

  test "a walk through the world moves the playthrough and the items, and the records say so at every step" do
    report = play("take stamp")
    assert_change report, "took: ward stamp"
    assert_equal @vance, @stamp.reload.character
    assert_nil @stamp.location

    report = play("go closet")
    assert_change report, "moved: Ward Office 12 -> The Supply Closet"
    assert_equal @closet, @playthrough.reload.current_location

    # DROPPED WHERE IT WAS DROPPED, not back where it was taken from. This is
    # the whole reason `Item` is in exactly one place rather than carrying a
    # note about where it came from.
    report = play("drop stamp")
    assert_change report, "dropped: ward stamp"
    assert_equal @closet, @stamp.reload.location
    assert_nil @stamp.character

    report = play("take index")
    assert_change report, "took: Perrin's private index"
    assert_equal @vance, @index.reload.character

    report = play("go ward office")
    assert_change report, "moved: The Supply Closet -> Ward Office 12"
    assert_equal @office, @playthrough.reload.current_location

    # And the stamp stayed in the closet when she walked out of it.
    assert_equal @closet, @stamp.reload.location
    assert_empty Item.lying_in(@office)
    assert_equal [ @daybook, @index ].map(&:id).sort, Item.for_character(@vance).pluck(:id).sort
  end

  test "the read-out matches the database after every command of the walk" do
    [ "look", "take stamp", "go closet", "drop stamp", "take index", "go ward office", "go hallway" ].each do |command|
      assert_reads_true play(command), command
    end
  end

  test "the offline mode walks into a stub without writing the room, because writing it is a model call" do
    report = play("go hallway")

    assert_equal @hallway, @playthrough.reload.current_location
    assert_predicate @hallway.reload, :stub?
    assert_nil @hallway.description
    assert_includes report.change, "a stub"
  end

  test "the offline mode writes no Scene, so the turn log and the story clock are untouched" do
    scenes = @story.scenes.count
    clock = @story.clock

    [ "take stamp", "go closet", "drop stamp", "go ward office" ].each { |command| play(command) }

    assert_equal scenes, @story.reload.scenes.count
    assert_equal clock, @story.clock
  end

  # --- the offline mode: refusals --------------------------------------------

  test "an exit that does not exist is refused, and nothing moves" do
    report = play("go cellar")

    assert_refusal report, "there is no way out called \"cellar\""
    assert_includes report.refusal, "The Supply Closet"
    assert_equal @office, @playthrough.reload.current_location
  end

  test "taking something that is not lying here is refused, and nothing moves" do
    report = play("take index")

    assert_refusal report, "there is no thing lying here called \"index\""
    assert_nil @index.reload.character
    assert_equal @closet, @index.location
  end

  test "taking something the player is already carrying is refused" do
    report = play("take daybook")

    assert_refusal report, "there is no thing lying here called \"daybook\""
    assert_equal @vance, @daybook.reload.character
  end

  test "dropping something the player is not carrying is refused, and nothing moves" do
    report = play("drop stamp")

    assert_refusal report, "there is no thing you are carrying called \"stamp\""
    assert_equal @office, @stamp.reload.location
    assert_nil @stamp.character
  end

  test "an ambiguous name is refused with what it matched rather than resolved to the first" do
    create(:item, :lying, location: @office, name: "ward stamp pad")

    report = play("take ward")

    assert_refusal report, "matches more than one"
    assert_includes report.refusal, "ward stamp pad"
    assert_nil @stamp.reload.character
  end

  test "a word that is not in the grammar is refused with the whole grammar" do
    report = play("sing to the filing press")

    assert_refusal report, "I do not understand \"sing\""
    assert_includes report.to_s, "go <exit>"
    assert_equal @office, @playthrough.reload.current_location
  end

  test "a bare verb with nothing after it says what it could have taken" do
    assert_refusal play("go"), "go where?"
    assert_refusal play("take"), "take what?"
    assert_refusal play("drop"), "drop what?"
  end

  # --- the offline mode: resolving a typed name ------------------------------

  test "a name resolves exactly, then by prefix, then by fragment, ignoring case and spacing" do
    assert_change play("go   THE supply CLOSET  "), "-> The Supply Closet"
    assert_change play("go ward"), "-> Ward Office 12"
    assert_change play("go closet"), "-> The Supply Closet"
  end

  test "an exit name typed on its own is a move, so a world with compass exits can be walked" do
    north = create(:location, story: @story, name: "north")
    connect(@office, north)

    report = play("north")

    assert_change report, "moved: Ward Office 12 -> north"
    assert_equal north, @playthrough.reload.current_location
  end


  # --- the default mode: the classifier reads it, the world generates ---------

  # THE POINT OF THE WHOLE MODE. One classification, then the same engine
  # method the browser calls, and nothing else asked of any model.
  test "a take goes through the classifier to the same engine write, and asks for nothing more" do
    report, agent = interpret("pick up that stamp", CLASSIFY.call("take", "ward stamp"))

    assert_equal "take -> ward stamp", report.understood
    assert_includes report.change, "took: ward stamp"
    assert_equal @vance, @stamp.reload.character
    assert_nil @stamp.location
    # One prompt: the classification. A narrator call would have been a second,
    # and FakeAgent would have raised on it.
    assert_equal 1, agent.prompts.count
  end

  test "a drop goes through the classifier to the same engine write, and asks for nothing more" do
    report, agent = interpret("put the daybook down", CLASSIFY.call("drop", "Ward Office 12 daybook"))

    assert_equal "drop -> Ward Office 12 daybook", report.understood
    assert_includes report.change, "dropped: Ward Office 12 daybook"
    assert_equal @office, @daybook.reload.location
    assert_nil @daybook.character
    assert_equal 1, agent.prompts.count
  end

  # THE WORLD STILL GENERATES ITSELF. Walking into a room nobody has written
  # writes it, its exits and the arrival -- exactly the calls the browser makes,
  # and no narrator among them.
  test "walking into a stub realizes it and writes the arrival, as the real game does" do
    report, agent = interpret("go out into the hallway",
                              CLASSIFY.call("move", "The Long Hallway"),
                              DETAIL, { "exits" => [] }, ARRIVAL)

    assert_predicate @hallway.reload, :realized?
    assert_equal DETAIL["description"], @hallway.description
    assert_equal @hallway, @playthrough.reload.current_location
    assert_equal ARRIVAL["description"], @playthrough.current_scene.description
    assert_includes report.change, "written for the first time"
    # classify, detail, exits, arrival. Nothing narrated on top.
    assert_equal 4, agent.prompts.count
  end

  test "walking back into a realized room generates nothing but the arrival" do
    _report, agent = interpret("into the closet", CLASSIFY.call("move", "The Supply Closet"), ARRIVAL)

    assert_equal @closet, @playthrough.reload.current_location
    assert_equal 2, agent.prompts.count
    assert_equal "A mysterious place filled with wonder and potential adventure", @closet.reload.description
  end

  # The two stamps `Playthrough::Turn#play` makes on every branch, so a turn
  # walked here reads afterwards like one walked in the browser.
  test "an arrival records what was typed and joins the turn log" do
    before = @playthrough.current_scene

    interpret("into the closet", CLASSIFY.call("move", "The Supply Closet"), ARRIVAL)

    scene = @playthrough.reload.current_scene
    assert_equal "into the closet", scene.typed
    assert_equal before, scene.previous_scene
    assert_includes @playthrough.scene_chain, scene
  end

  # THE PROSE IS THE ONE THING DROPPED. Talking is answered by a character, so
  # it is refused rather than half-played -- and the person it resolved to is
  # still named, because that half is worth seeing.
  test "talking is refused without a character call, and writes no Interaction" do
    report, agent = interpret("ask Rowe what he wants", CLASSIFY.call("talk", "Halkett Rowe"))

    assert_predicate report, :refused?
    assert_equal "talk -> Halkett Rowe", report.understood
    assert_includes report.refusal, "Halkett Rowe"
    assert_includes report.refusal, "prose"
    assert_equal 0, Interaction.count
    assert_equal 1, agent.prompts.count
  end

  test "an examine is refused without a narrator call" do
    report, agent = interpret("look closely at the tube", CLASSIFY.call("examine", "nothing"))

    assert_predicate report, :refused?
    assert_equal "examine -> nothing", report.understood
    assert_includes report.refusal, "prose"
    assert_equal 1, agent.prompts.count
  end

  # DRIFT IS STILL COUNTED, because it is one of the things this mode exists to
  # watch: the classifier reached for a way out that the records do not have.
  test "a reach that resolved to nothing is refused, counted as drift, and changes nothing" do
    report, = interpret("go down to the cellar", CLASSIFY.call("move", "nothing"))

    assert_predicate report, :refused?
    assert_equal "move -> nothing", report.understood
    assert_includes report.refusal, "Playthrough::Drift"
    assert_equal @office, @playthrough.reload.current_location
    assert_equal 1, @playthrough.drifts.count
    assert_equal "move", @playthrough.drifts.sole.action
  end

  test "the read-out after a classified command matches the database too" do
    report, = interpret("pick up that stamp", CLASSIFY.call("take", "ward stamp"))
    assert_reads_true report, report.command

    report, = interpret("into the closet", CLASSIFY.call("move", "The Supply Closet"), ARRIVAL)
    assert_reads_true report, report.command
  end

  test "help says what the mode understands, in whichever mode is running" do
    assert_includes Playthrough::Mechanics.new(@playthrough).help.to_s, "Playthrough::Classifier"
    assert_includes Playthrough::Mechanics.new(@playthrough, model: false).help.to_s, "go <exit>"
  end

  # --- the closed sets ------------------------------------------------------

  test "the read-out offers exactly what the classifier would offer a model" do
    classifier = Playthrough::Classifier.new(@playthrough)
    state = Playthrough::Mechanics.new(@playthrough).state

    assert_equal classifier.exits_here, state.exits
    assert_equal classifier.items_here, state.items_here
    assert_equal classifier.items_carried, state.carried
    assert_equal classifier.characters_here, state.present
  end

  test "a playthrough with no protagonist cannot carry anything, and says so" do
    @playthrough.update!(character: nil)

    assert_refusal play("take stamp"), "no protagonist"
    assert_nil @stamp.reload.character
  end

  test "a playthrough standing nowhere has no room to put anything down in" do
    @playthrough.update!(current_location: nil)
    report = play("drop daybook")

    assert_refusal report, "standing nowhere"
    assert_equal @vance, @daybook.reload.character
    assert_includes report.to_s, "nowhere"
  end

  private

  def assert_change(report, expected)
    refute_predicate report, :refused?, "expected a change, got: #{report.refusal}"
    assert_includes report.change, expected
    assert_reads_true report, report.command
  end

  def assert_refusal(report, expected)
    assert_predicate report, :refused?, "expected a refusal, got: #{report.change}"
    assert_includes report.refusal, expected
    assert_nil report.change, "a refused command must not report a change"
    assert_reads_true report, report.command
  end

  # THE ACCEPTANCE TEST, applied to every command in this file: what was printed
  # is what the database holds, read back independently of the class that
  # printed it.
  def assert_reads_true(report, command)
    @playthrough.reload
    state = report.state
    here = @playthrough.current_location
    who = @playthrough.character
    where = "after #{command.inspect}"

    # `nil` on either side is a real state -- a playthrough can stand nowhere and
    # can have no protagonist -- and both are empty sets rather than "everything
    # whose column is null", which is what an unguarded scope would answer.
    if here.nil?
      assert_nil state.location, where
    else
      assert_equal here, state.location, where
    end

    assert_equal here ? here.exits.order(:id).to_a : [], state.exits, where
    assert_equal here ? Item.lying_in(here).order(:id).to_a : [], state.items_here, where
    assert_equal who ? Item.for_character(who).order(:id).to_a : [], state.carried, where

    state.items_here.each { |item| assert_equal here, item.reload.location, where }
    state.carried.each { |item| assert_equal who, item.reload.character, where }

    # And the printed block names them, so a read-out cannot be right in the
    # records and wrong on the screen.
    (state.items_here + state.carried).each { |item| assert_includes report.to_s, item.name, where }
    state.exits.each { |exit| assert_includes report.to_s, exit.name, where }
  end
end
