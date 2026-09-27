require "test_helper"

# THE TYPED VOLITION REQUEST, WITH NO MODEL CALL ANYWHERE IN IT.
#
# Three things are pinned: the request's exact bytes for one staged room
# (`test/fixtures/files/volition_system_one_request.json`, rewritten only when
# the request is meant to change), that a typed act maps back to the token it
# stood for and is applied through the rebuilt set, and that a failed call
# leaves a receipt on every row the die then decides.
class Playthrough::Volition::SystemOneTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join("test/fixtures/files/volition_system_one_request.json")

  # Stands in for `SystemOneAgent`: answers every question from a table, or
  # raises what it is told to.
  class FakeAgent
    attr_reader :requests

    def initialize(answers: {}, raises: nil)
      @answers, @raises, @requests = answers, raises, []
    end

    def ask_questions(state:, questions:)
      @requests << { state: state, questions: questions }
      raise @raises if @raises

      SystemOneAgent::Answers.new({ "answers" => @answers }, questions)
    end
  end

  setup do
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Counting Room")
    @next_door = create(:location, story: @story, name: "The Stairwell")
    create(:location_connection, location: @room, connected_location: @next_door)
    create(:location_connection, location: @next_door, connected_location: @room)
    @player = create(:character, :protagonist, story: @story)
    @game = create(:playthrough, story: @story, character: @player, current_location: @room)
    @clerk = create(:character, :driven, story: @story, location: @room, fullname: "Odile Vance", nickname: "Odile")
    create(:item, character: nil, location: @room, playthrough: @game, name: "a brass ledger key")
    Playthrough::Volition.new(@game, @clerk, location: @room).apply!(Playthrough::Volition::WAIT)
  end

  def overlay(agent)
    Playthrough::Volition::SystemOne.new(@game, [ @clerk ], location: @room, line: "read the docket", agent: agent)
  end

  def answers(act:, pressure:)
    { "person_1:act" => { "type" => "choice", "choice" => act },
      "person_1:serves" => { "type" => "choice", "choice" => "conscious" },
      "person_1:pressure" => { "type" => "noul", "noul" => pressure } }
  end

  test "the request is byte for byte the pinned one" do
    request = overlay(FakeAgent.new).request

    assert_equal FIXTURE.read, "#{JSON.pretty_generate(request.deep_stringify_keys)}\n"
  end

  test "the request names no row id, so it is the same whatever ids the rows got" do
    json = overlay(FakeAgent.new).request.to_json

    [ @room, @next_door, @clerk ].each { |row| assert_not_includes json, ":#{row.id}\"" }
  end

  test "a pressured answer's label is applied as the token it stood for" do
    agent = FakeAgent.new(answers: answers(act: "act_2", pressure: 0.9))
    outcome = overlay(agent).decisions

    assert_equal({ @clerk.id => "move:#{@next_door.id}" }, outcome.acts)
    assert_nil outcome.failure
  end

  test "an answer below the threshold leaves the person to the die" do
    outcome = overlay(FakeAgent.new(answers: answers(act: "act_2", pressure: 0.1))).decisions

    assert_equal({}, outcome.acts)
  end

  test "a failed call hands back its reason instead of nothing" do
    outcome = overlay(FakeAgent.new(raises: SystemOneAgent::Unavailable.new("the provider answered 503"))).decisions

    assert_nil outcome.acts
    assert_equal "SystemOneAgent::Unavailable: the provider answered 503", outcome.failure
  end

  test "an answer outside the offered labels is a failure, not an act" do
    outcome = overlay(FakeAgent.new(answers: answers(act: "act_99", pressure: 0.9))).decisions

    assert_nil outcome.acts
    assert_match(/not one of the options sent/, outcome.failure)
  end

  test "with no credential nothing is asked and the die decides with a plain receipt" do
    SystemOneAgent.stub(:configured?, false) do
      rows = Playthrough::Volition.run!(@game, location: @room, line: "read the docket")

      assert_equal 1, rows.size
    end
    row = @game.volitions.where(character: @clerk).order(:id).last

    assert_equal Playthrough::Volition::DECIDED_BY_DIE, row.decided_by
    assert_nil row.system_one_error
  end

  test "a failed call falls back to the die and the row says why" do
    agent = FakeAgent.new(raises: SystemOneAgent::Unavailable.new("the provider answered 503"))
    SystemOneAgent.stub(:configured?, true) do
      SystemOneAgent.stub(:new, agent) do
        Playthrough::Volition.run!(@game, location: @room, line: "read the docket")
      end
    end
    row = @game.volitions.where(character: @clerk).order(:id).last

    assert_equal 1, agent.requests.size
    assert_equal Playthrough::Volition::DECIDED_BY_DIE_AFTER_FAILURE, row.decided_by
    assert_equal "SystemOneAgent::Unavailable: the provider answered 503", row.system_one_error
    assert_includes Playthrough::Volition::STATUSES, row.status
  end

  test "the die's pick after a failure is the pick it makes with no call at all" do
    die = Playthrough::Volition::Weights.pick(
      Playthrough::Volition.new(@game, @clerk, location: @room).choices.keys,
      pursuit: @clerk.desire_pursuit,
      rng: Roll.generator(story: @game.story_id, playthrough: @game.id, at: @game.story_now.to_i,
                          sequence: @clerk.id, kind: Roll::VOLITION)
    )
    agent = FakeAgent.new(raises: Timeout::Error.new("slow"))
    SystemOneAgent.stub(:configured?, true) do
      SystemOneAgent.stub(:new, agent) { Playthrough::Volition.run!(@game, location: @room) }
    end

    assert_equal die, @game.volitions.where(character: @clerk).order(:id).last.chosen
  end

  test "a typed act is applied through the rebuilt set and says so" do
    agent = FakeAgent.new(answers: answers(act: "act_2", pressure: 0.9))
    SystemOneAgent.stub(:configured?, true) do
      SystemOneAgent.stub(:new, agent) { Playthrough::Volition.run!(@game, location: @room, line: "wait") }
    end
    row = @game.volitions.where(character: @clerk).order(:id).last

    assert_equal "move:#{@next_door.id}", row.chosen
    assert_equal "applied", row.status
    assert_equal Playthrough::Volition::DECIDED_BY_SYSTEM_ONE, row.decided_by
    assert_equal "wait", agent.requests.first[:state]["player_action"]
  end
end
