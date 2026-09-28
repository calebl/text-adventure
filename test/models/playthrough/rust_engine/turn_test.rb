require "test_helper"

# `Playthrough::Session#play` on the Rust engine, against a stand-in for the
# extension: it writes the rows the engine would write and answers the engine's
# document, so these pin Ruby's half of the crossing -- the callbacks, the
# outcome, and a turn the engine could not play -- without a Rust toolchain.
# The engine itself is held to the sweep by `bin/rails engine:rust_gates`.
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

  test "a turn the engine could not play fails in its words, is counted, and never plays on Ruby" do
    extension = Extension.new do |game, line, token, _block|
      Playthrough::Command.accept!(game, line, token).update!(status: "failed", error_kind: "error")
      { error: { kind: "unsupported", failure: nil, message: "this engine does not play an offer yet" } }
    end
    before = Playthrough::RustEngine.failures.fetch("unsupported", 0)
    finished = []

    error = assert_raises(Playthrough::RustEngine::EngineError) do
      on_rust(extension) do
        BaseAgent.stub(:new, ->(*, **) { flunk "the Ruby engine was asked to play the line" }) do
          Playthrough::Session.new(@game).play("give the key to the warden", request_token: "t-3",
                                               on_finish: ->(ending) { finished << ending })
        end
      end
    end

    assert_equal "unsupported", error.kind
    assert_equal "The engine could not play that turn: this engine does not play an offer yet", finished.sole.error
    assert_equal "failed", @game.commands.find_by!(request_token: "t-3").status
    assert_equal before + 1, Playthrough::RustEngine.failures.fetch("unsupported")
  end

  test "without the extension a turn fails and says how to build it" do
    submission = Playthrough::Session.new(@game).accept!("/look", "t-5")
    finished = []

    Playthrough::RustEngine.stub(:extension, nil) do
      assert_raises(Playthrough::RustEngine::EngineError) do
        Playthrough::RustEngine.using(:rust) do
          Playthrough::Session.new(@game).play("/look", request_token: "t-5", on_finish: ->(ending) { finished << ending })
        end
      end
    end

    assert_match "bin/rails engine:build", finished.sole.error
    assert_equal "failed", submission.reload.status
  end

  # A TURN THAT CAME BACK WITH NOTHING TO SHOW -- completed, no Scene, no
  # refusal, no round fought -- is told in the app's failure copy, on the
  # finish and on a reload, rather than ending in silence.
  test "a completed turn with nothing to show is told in the app's failure copy" do
    extension = Extension.new do |game, line, token, _block|
      Playthrough::Command.accept!(game, line, token).update!(status: "completed")
      { turned: { scene: nil, refusal: nil, safety_notice: false, setup: false }, state: {} }
    end
    finished = []

    on_rust(extension) do
      Playthrough::Session.new(@game).play("/look", request_token: "t-6", on_finish: ->(ending) { finished << ending })
    end

    assert_equal Playthrough::TurnFailureNotice::MESSAGE, finished.sole.error
    assert_equal Playthrough::TurnFailureNotice::MESSAGE, Playthrough::Session.new(@game).last_ending.error
  end

  # AND A ROUND OF A FIGHT THAT DID NOT END IT IS NOT THAT: its blows are what
  # the turn did, so the finish carries no failure copy and says what round it
  # was.
  test "a round the engine fought with no Scene is not told as a failure" do
    foe = create(:character, :monster, story: @game.story, location: @game.current_location, fullname: "Marek Sollen")
    extension = Extension.new do |game, line, token, _block|
      command = Playthrough::Command.accept!(game, line, token)
      command.update!(status: "completed", journal: { "version" => 1, "steps" => { "round" => 1 } })
      create(:playthrough_blow, playthrough: game, attacker: game.character, target: foe, location: game.current_location,
                                damage: 3, hp_after: 7, round: 1, sequence: 1)
      { turned: { scene: nil, refusal: nil, safety_notice: false, setup: false }, state: {} }
    end
    finished = []

    on_rust(extension) do
      Playthrough::Session.new(@game).play("/attack marek", request_token: "t-7", on_finish: ->(ending) { finished << ending })
    end

    assert_nil finished.sole.error
    round = Playthrough::Session.new(@game).round_fought(@game.commands.find_by!(request_token: "t-7"))
    assert_equal 1, round.blows.sole.round
    assert_match(/\ARound 1 is done: you struck Marek Sollen/, round.sentence)
  end

  test "a line with no token is given one, since the engine keeps every line in the queue" do
    extension = Extension.new do |game, line, token, _block|
      Playthrough::Command.accept!(game, line, token).update!(status: "completed")
      { turned: { scene: nil, refusal: nil, safety_notice: false, setup: false }, state: {} }
    end

    on_rust(extension) { Playthrough::Session.new(@game).play("/look") }

    assert_predicate extension.submitted.sole[:token], :present?
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

  private

  # The Rust engine, with the stand-in loaded and the transaction every test
  # runs in set aside: the engine is on another connection in life, here it is
  # the stand-in's block on this one.
  def on_rust(extension, &)
    Playthrough::RustEngine.stub(:extension, extension) do
      Playthrough::RustEngine.stub(:unplayable, nil) do
        Playthrough::RustEngine.using(:rust, &)
      end
    end
  end
end
