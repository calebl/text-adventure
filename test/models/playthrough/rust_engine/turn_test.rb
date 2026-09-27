require "test_helper"

# `Playthrough::Session#play` with the switch on, against a stand-in for the
# extension: it writes the rows the engine would write and answers the engine's
# document, so these pin Ruby's half of the crossing -- the callbacks, the
# outcome, the fallback and the hand-back -- without a Rust toolchain. The
# engine itself is held to the sweep by `bin/rails engine:rust_gates`.
class Playthrough::RustEngine::TurnTest < ActiveSupport::TestCase
  # What `RenderedStep` answers to, with the turn played by a block.
  class Extension
    attr_reader :submitted

    def initialize(&turn)
      @turn = turn
      @submitted = []
    end

    def submit(database, playthrough_id, line, token, models, &block)
      @submitted << { database: database, playthrough_id: playthrough_id, line: line, token: token, models: JSON.parse(models) }
      @turn.call(Playthrough.find(playthrough_id), line, token, block).to_json
    end
  end

  setup do
    @game = create(:playthrough, :started)
  end

  test "a turn the engine plays is answered as the Ruby engine answers it" do
    scene = create(:scene, story: @game.story, location: @game.current_location)
    extension = Extension.new do |game, line, token, block|
      block.call("The lamp ")
      block.call("gutters.")
      Playthrough::Command.accept!(game, line, token).update!(status: "completed", result_scene: scene)
      { turned: { scene: scene.id, refusal: nil, safety_notice: false, setup: false }, state: {} }
    end
    chunks = []
    started = []
    finished = []

    outcome = on_rust(extension) do
      Playthrough::Session.new(@game).play("/look", request_token: "t-1", on_start: ->(line) { started << line },
                                                    on_finish: ->(ending) { finished << ending }) { |chunk| chunks << chunk }
    end

    assert_equal scene, outcome
    assert_equal [ "/look" ], started
    assert_equal [ [ nil, nil ] ], finished.map { |ending| [ ending.error, ending.refusal ] }
    assert_not finished.sole.safety_notice
    assert_equal [ "The lamp ", "gutters." ], chunks
    assert_equal [ "/look" ], extension.submitted.map { |call| call[:line] }
    assert_equal File.expand_path(ApplicationRecord.connection_db_config.database, Rails.root),
                 extension.submitted.first[:database]
  end

  test "a refusal the engine wrote comes back as the engine's refusal" do
    extension = Extension.new do |game, line, token, _block|
      Playthrough::Command.accept!(game, line, token)
                          .update!(status: "completed", refusal: { kind: "unresolved", typed: "take the moon", fact: "There is no moon here.", offer: nil })
      { turned: { scene: nil, refusal: { kind: "unresolved" }, safety_notice: false, setup: false }, state: {} }
    end
    finished = []

    outcome = on_rust(extension) do
      Playthrough::Session.new(@game).play("take the moon", request_token: "t-2", on_finish: ->(ending) { finished << ending })
    end

    assert_kind_of Playthrough::Refusal, outcome
    assert_equal :unresolved, outcome.kind
    assert_equal outcome, finished.sole.refusal
  end

  test "an engine error hands the turn back, and the Ruby engine plays it from the same submission" do
    extension = Extension.new do |game, line, token, _block|
      Playthrough::Command.accept!(game, line, token).update!(status: "failed", error_kind: "error",
                                                              journal: { "version" => 1, "steps" => {} })
      { error: { kind: "unsupported", failure: nil, message: "this engine does not play that yet" } }
    end
    before = Playthrough::RustEngine.fallbacks.fetch("unsupported", 0)

    outcome = on_rust(extension) do
      BaseAgent.stub(:new, ->(*, **) { FakeAgent.new("The room is quiet.") }) do
        Playthrough::Session.new(@game).play("/look", request_token: "t-3")
      end
    end

    assert_kind_of Scene, outcome
    assert_equal "completed", @game.commands.find_by!(request_token: "t-3").status
    assert_equal 1, @game.commands.count
    assert_equal before + 1, Playthrough::RustEngine.fallbacks.fetch("unsupported")
  end

  test "a turn Rust cannot take plays on Ruby and is counted, without asking the extension" do
    extension = Extension.new { raise "the extension must not be asked" }
    before = Playthrough::RustEngine.fallbacks.fetch("no_request_token", 0)

    Playthrough::RustEngine.stub(:extension, extension) do
      Playthrough::RustEngine.using(:rust) do
        BaseAgent.stub(:new, ->(*, **) { FakeAgent.new("The room is quiet.") }) { Playthrough::Session.new(@game).play("/look") }
      end
    end

    assert_empty extension.submitted
    assert_equal before + 1, Playthrough::RustEngine.fallbacks.fetch("no_request_token")
  end

  test "a model failure is how the turn ended, told in the app's words and never replayed on Ruby" do
    extension = Extension.new do |game, line, token, _block|
      Playthrough::Command.accept!(game, line, token).update!(status: "failed", error_kind: "crisis")
      { error: { kind: "model", failure: "crisis", message: "a crisis answer was suppressed" } }
    end
    finished = []
    errors = []

    assert_raises(BaseAgent::CrisisResponseError) do
      on_rust(extension) do
        Playthrough::Session.new(@game).play("talk to the warden", request_token: "t-4",
                                             on_finish: ->(ending) { finished << ending },
                                             on_error: ->(error) { errors << error })
      end
    end

    assert finished.sole.safety_notice
    assert_kind_of BaseAgent::CrisisResponseError, errors.sole
    assert_equal "failed", @game.commands.find_by!(request_token: "t-4").status
  end

  test "handing back leaves each submission the engine failed as a stopped worker leaves it" do
    earlier = create(:playthrough_command, playthrough: @game, status: "failed", error_kind: "error")
    untouched = create(:playthrough_command, playthrough: @game, status: "pending")
    started = create(:playthrough_command, playthrough: @game, status: "pending")
    turn = Playthrough::RustEngine::Turn.new(@game)
    before = turn.send(:queue)
    untouched.update!(status: "failed", error_kind: "error", journal: { "version" => 1, "steps" => {} })
    started.update!(status: "failed", error_kind: "error", journal: { "version" => 1, "steps" => { "world_clock" => nil } })

    turn.send(:hand_back!, before)

    assert_equal %w[failed error], earlier.reload.then { |row| [ row.status, row.error_kind ] }
    assert_equal [ "pending", nil ], untouched.reload.then { |row| [ row.status, row.error_kind ] }
    assert_equal [ "running", nil ], started.reload.then { |row| [ row.status, row.error_kind ] }
    assert_predicate started, :recoverable?
  end

  test "an ending the engine reached is written back into the arc step, so Ruby tells it" do
    quest = create(:quest, :with_an_ending, story: @game.story)
    closing = create(:scene, story: @game.story, location: @game.current_location)
    turn = Playthrough::RustEngine::Turn.new(@game)
    submission = create(:playthrough_command, playthrough: @game, status: "pending")
    before = turn.send(:queue)
    ending = Playthrough::Ending.create!(playthrough: @game, quest_outcome: quest.outcomes.sole, reached_at: @game.story_now)
    @game.update!(current_scene: closing)
    submission.update!(status: "failed", error_kind: "error", journal: { "version" => 1, "steps" => { "arc" => nil } })

    turn.send(:hand_back!, before)

    concluded = Playthrough::Command::Journal.new(submission.reload).read("arc")
    assert_equal [ ending, quest.outcomes.sole, closing ], [ concluded.ending, concluded.outcome, concluded.scene ]
  end

  private

  # The switch on and the stand-in loaded, with the transaction every test runs
  # in set aside: the engine is on another connection in life, here it is the
  # stand-in's block on this one.
  def on_rust(extension, &)
    Playthrough::RustEngine.stub(:extension, extension) do
      Playthrough::RustEngine.stub(:unplayable, nil) do
        Playthrough::RustEngine.using(:rust, &)
      end
    end
  end
end
