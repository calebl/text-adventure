require "test_helper"

# THE TWO SLOTS, AND THAT THEY AGREE.
#
# `Playthrough::Volition` runs in `Playthrough::Turn#play_serially` and in
# `Playthrough::Mechanics#answered_by_the_world`, in the matching place, and it
# has to run in both or the browser and an offline walk disagree about whether
# the world moved -- the note `Playthrough::Arc`'s header makes about itself.
# These are the assertions that keep them one thing.
class Playthrough::VolitionTurnTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Counting Room")
    @next_door = create(:location, story: @story, name: "The Stairwell")
    create(:location_connection, location: @room, connected_location: @next_door)
    create(:location_connection, location: @next_door, connected_location: @room)
    @player = create(:character, :protagonist, story: @story)
    @game = create(:playthrough, story: @story, character: @player, current_location: @room)
    @clerk = create(:character, :driven, story: @story, location: @room, fullname: "Odile Vance")
  end

  test "an offline walk gives everybody in the room a turn" do
    Playthrough::Mechanics.new(@game, model: false).run("go The Stairwell")

    assert_equal 1, @game.volitions.where(character: @clerk).count
  end

  # AN ENGINE-VIEW INSTRUMENT EVALUATES NOTHING, which is the same rule the
  # riposte and the hazard are under: `look` prints the records and is not a
  # line the world answers.
  test "an engine read-out is not a turn anybody acts on" do
    Playthrough::Mechanics.new(@game, model: false).run("look")

    assert_equal 0, @game.volitions.count
  end

  test "a refused line writes nothing, because a refused line writes nothing" do
    Playthrough::Mechanics.new(@game, model: false).run("take the moon and the stars")

    assert_equal 0, @game.volitions.count
  end

  test "the read-out says what somebody in the room did, and only when they did something" do
    report = Playthrough::Mechanics.new(@game, model: false).run("go The Stairwell")
    said = Array(report.note).grep(/\Asomeone here:/)

    assert_equal @game.volitions.applied.count, said.size
  end

  test "an act is filed against the room the turn began in, not the room the player walked to" do
    Playthrough::Mechanics.new(@game, model: false).run("go The Stairwell")

    assert_equal [ @room.id ], @game.volitions.pluck(:location_id).uniq
  end

  test "no world row moves, however many turns are walked" do
    5.times do
      Playthrough::Mechanics.new(@game, model: false).run("go The Stairwell")
      Playthrough::Mechanics.new(@game, model: false).run("go The Counting Room")
    end

    assert_equal @room, @clerk.reload.location, "characters.location_id is the world layer"
    assert_not @clerk.hostile?
    assert_equal "obtain", @clerk.desire_pursuit, "what somebody wants is the world's"
  end

  # --- the one fact line ----------------------------------------------------

  test "an act that moved something is stated to the narrator once, then claimed" do
    row = create(:playthrough_volition, playthrough: @game, character: @clerk, location: @room)
    moment = EngineMoment.new(@game)

    assert_includes moment.narration_context, row.fact

    scene = create(:scene, story: @story, location: @room)
    Playthrough::Turn.new(@game).send(:claim_volitions!, scene)

    assert_not_includes EngineMoment.new(@game).narration_context, row.fact
  end

  # AN ARRIVAL'S PROMPT IS `Scene::Generator`'s, which states no act, so the
  # arrival scene must not claim one: a departure rolled on the line before a
  # move stays untold until a paragraph whose prompt carried it.
  test "a scene whose prompt stated no act leaves the acts for the next paragraph" do
    row = create(:playthrough_volition, playthrough: @game, character: @clerk, location: @room)
    arrival = create(:scene, story: @story, location: @next_door)
    arrival.narrated_volition_ids = []
    Playthrough::Turn.new(@game).send(:claim_volitions!, arrival)

    assert_nil row.reload.scene_id
    assert_includes EngineMoment.new(@game).narration_context, row.fact

    told = create(:scene, story: @story, location: @next_door)
    Playthrough::Turn.new(@game).send(:claim_volitions!, told)

    assert_equal told.id, row.reload.scene_id
  end

  test "an arrival marks its prompt as having stated no act, across a journal replay" do
    scene = create(:scene, story: @story, location: @next_door)
    scene.narrated_volition_ids = []
    journal = Playthrough::Command::Journal.allocate
    decoded = journal.send(:decode, journal.send(:encode, scene))

    assert_equal [], decoded.narrated_volition_ids
  end

  test "standing still and a rejected pick are never stated -- the prose can already see nothing happened" do
    waited = create(:playthrough_volition, :waited, playthrough: @game, character: @clerk, location: @room)
    refused = create(:playthrough_volition, :rejected, playthrough: @game, character: @clerk, location: @room)
    context = EngineMoment.new(@game).narration_context

    assert_not_includes context, waited.fact
    assert_not_includes context, refused.fact
    assert_not_includes context, "What else happened here"
  end

  # --- the ledger -----------------------------------------------------------

  test "a character's own acts are part of what they remember having experienced" do
    row = create(:playthrough_volition, playthrough: @game, character: @clerk, location: @room)
    facts = EngineMoment.new(@game).personal_facts(@clerk)

    assert(facts.any? { |line| line.include?(row.fact) })
  end
end
