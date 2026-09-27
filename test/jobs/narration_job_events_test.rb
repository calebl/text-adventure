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

  test "the rolls a turn threw are read off its journal" do
    command = create(:playthrough_command, playthrough: @game, status: "completed", journal: {
      "version" => 1, "steps" => { "check" => { "data" => "Character::Check",
                                               "fields" => { "hash" => {}, "ability" => "strength", "score" => 12, "penalty" => 2, "die" => 7 } } }
    })
    assert_equal [ { kind: "check", die: 20, result: 7, target: 10 } ], Protocol::V1.rolls(command, nil)
  end
end
