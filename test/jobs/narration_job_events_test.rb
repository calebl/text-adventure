require "test_helper"

# THE EVENT-ROW ADAPTER: a turn an API client asked for, played through the
# one loop with the fake at the model boundary, and the rows it leaves
# validated against docs/protocol/v1.
class NarrationJobEventsTest < ActiveJob::TestCase
  include ProtocolV1

  NOT_A_MOVE = { "intent" => "other", "target" => "nothing" }.freeze
  NARRATION = "The ledger falls open on a page of names, and every one of them has been struck through twice.".freeze

  setup do
    @player = create(:player)
    @game = create(:playthrough, :started, player: @player)
  end

  def play(line, token, *responses)
    command = Playthrough::Session.new(@game).accept!(line, token)
    BaseAgent.stub(:new, FakeAgent.new(*responses)) { NarrationJob.perform_now(@game.id, command.command, token, "events") }
    command.reload
  end

  test "a narrated turn leaves started, batched prose and finished, each conforming" do
    command = play("open the ledger", "t1", NOT_A_MOVE, NARRATION)
    events = command.turn_events.order(:sequence).to_a

    assert_equal (1..events.size).to_a, events.map(&:sequence)
    assert_equal "started", events.first.kind
    assert_equal "finished", events.last.kind
    assert_equal NARRATION, events.select { |event| event.kind == "prose" }.map { |event| event.data["text"] }.join
    schemas = { "started" => "StartedEvent", "prose" => "ProseEvent", "glance" => "GlanceEvent", "finished" => "FinishedEvent" }
    events.each { |event| assert_protocol schemas.fetch(event.kind), event.data }
    events.each { |event| assert_like_example ProtocolV1.event_example(event.kind), event.data }

    finished = events.last.data
    assert_equal "narrated", finished.dig("outcome", "kind")
    assert_equal NARRATION, finished["text"], "finished carries the saved scene, which is what a client redraws from"
    assert_equal @game.reload.current_scene.description, finished["text"]
    assert_nil finished["refusal"]
    assert_equal false, finished.dig("standing", "busy")
  end

  test "a refused line finishes as refused with the refusal's kind and sentence" do
    create(:item, :lying, location: @game.current_location, name: "ward stamp")
    command = play("pick up the cellar key", "t2", { "intent" => "take", "target" => "nothing" })
    finished = command.turn_events.find_by!(kind: "finished").data

    assert_protocol "FinishedEvent", finished
    assert_like_example ProtocolV1.event_example("finished"), finished
    assert_equal "completed", command.status
    assert_equal "refused", finished.dig("outcome", "kind")
    assert_includes Playthrough::Refusal::KINDS.map(&:to_s), finished.dig("refusal", "kind")
    assert_equal finished.dig("refusal", "text"), finished["text"]
  end

  test "the turn's player does not outlive the turn" do
    play("open the ledger", "t3", NOT_A_MOVE, NARRATION)
    assert_nil Current.player
  end

  # THE OWNER'S TURN 17. `/attack marek` over the API, in front of a foe the one
  # blow cannot drop: the blow lands, the foe answers, and the fight is still on,
  # so the turn writes no Scene -- a fight is told once, when it ends. The finish
  # used to read that as `failed` with no text, no rolls and no notice, while
  # the blows had landed. 18 hit points a side against one d8 a blow, so no face
  # of the die ends the fight in this round.
  test "a round that leaves the fight on finishes as attacked, with its blows and the panel's line" do
    game = fighting_game
    command = Playthrough::Session.new(game).accept!("/attack marek", "t4")
    exploded = ->(*) { raise "a round of a fight must make no model call" }
    BaseAgent.stub(:new, exploded) { NarrationJob.perform_now(game.id, command.command, "t4", "events") }
    command.reload
    finished = command.turn_events.find_by!(kind: "finished").data

    assert_protocol "FinishedEvent", finished
    assert_equal "completed", command.status
    assert_nil command.result_scene, "a round that did not end the fight writes no Scene"
    assert_equal "attacked", finished.dig("outcome", "kind")
    assert_equal "Round 1 is done: you struck Marek Sollen, and Marek Sollen answered. " \
                 "The fight is on because you struck.", finished["text"]
    blows = game.blows.order(:id).to_a
    assert_equal 2, blows.size
    assert_equal blows.map { |blow| { "kind" => "blow", "die" => nil, "result" => blow.damage, "target" => nil } },
                 finished["rolls"], "the player's blow and the answer, in the order they landed"
    assert_empty finished["notices"]
  end

  # AND A FAILED TURN ALWAYS SAYS WHY. A submission that completed with no
  # Scene, no refusal and no round fought is a turn the player would read as
  # nothing at all; the finish carries the app's failure copy instead.
  test "a finish with nothing to show is failed with the app's failure notice" do
    command = create(:playthrough_command, playthrough: @game, status: "completed")
    finished = Protocol::V1.finished(Playthrough::Session.new(@game), command, Playthrough::Session::Ending.plain).as_json

    assert_protocol "FinishedEvent", finished
    assert_equal "failed", finished.dig("outcome", "kind")
    assert_equal [ Playthrough::TurnFailureNotice::MESSAGE ], finished["notices"]
  end

  test "the rolls a turn threw are read off its journal" do
    command = create(:playthrough_command, playthrough: @game, status: "completed", journal: {
      "version" => 1, "steps" => { "check" => { "data" => "Character::Check",
                                               "fields" => { "hash" => {}, "ability" => "strength", "score" => 12, "penalty" => 2, "die" => 7 } } }
    })
    assert_equal [ { kind: "check", die: 20, result: 7, target: 10 } ], Protocol::V1.rolls(command, nil)
  end

  test "a toll a fall took is a fall, and any other hazard's a toll" do
    scene = create(:scene, story: @game.story, location: @game.current_location)
    command = create(:playthrough_command, playthrough: @game, status: "completed")
    create(:playthrough_toll, playthrough: @game, scene: scene, hazard: "fall", damage: 4)
    create(:playthrough_toll, playthrough: @game, scene: scene, damage: 2, sequence: -2)

    assert_equal [ { kind: "fall", die: nil, result: 4, target: nil }, { kind: "toll", die: nil, result: 2, target: nil } ],
                 Protocol::V1.rolls(command, scene)
  end

  private

  # A GAME STANDING IN FRONT OF A MONSTER, as `NarrationJobTest`'s is, and
  # belonging to a player because it is played over the API.
  def fighting_game
    story = create(:story)
    room = create(:location, story: story, name: "The Bell of Saint Aravel")
    hero = create(:character, :protagonist, story: story, level: 3, hit_die: 8)
    create(:character, :monster, story: story, location: room, fullname: "Marek Sollen", level: 3, hit_die: 8)
    create(:playthrough, story: story, player: @player, character: hero, current_location: room,
                         current_scene: create(:scene, story: story, location: room))
  end
end
