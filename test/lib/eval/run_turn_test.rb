require "test_helper"

# `rake eval:run`'s turn, played against a stand-in for the Rust engine's
# extension: it writes the rows the engine would write, so these pin that the
# run hands its line to `Playthrough::Session` and the engine plays it, with no
# model and no Rust toolchain.
class Eval::RunTurnTest < ActiveSupport::TestCase
  class Extension
    attr_reader :submitted

    def initialize(&turn)
      @turn = turn
      @submitted = []
    end

    def submit(_database, playthrough_id, line, token, _models, &block)
      @submitted << { line: line, token: token }
      @turn.call(Playthrough.find(playthrough_id), line, token, block).to_json
    end
  end

  setup do
    @game = create(:playthrough, :started)
  end

  test "a run's turn is played by the Rust engine through the session, never by the Ruby loop" do
    item = create(:item, location: @game.current_location, character: nil)
    scene = create(:scene, story: @game.story, location: @game.current_location, resolved_action: "take", acted_on: item)
    extension = Extension.new do |game, line, token, _block|
      Playthrough::Command.accept!(game, line, token).update!(status: "completed", result_scene: scene)
      { turned: { scene: scene.id, refusal: nil, safety_notice: false, setup: false }, state: {} }
    end
    sessions = []
    session = Playthrough::Session.method(:new)

    played = on_rust(extension) do
      Playthrough::Turn.stub(:new, ->(*) { flunk "the Ruby turn loop was asked to play the line" }) do
        Playthrough::Session.stub(:new, ->(game) { session.call(game).tap { |held| sessions << held } }) do
          Eval::RunTurn.play(@game, "take the #{item.name}")
        end
      end
    end

    assert_equal [ "take the #{item.name}" ], extension.submitted.map { |call| call[:line] }
    assert_equal 1, sessions.size
    assert_equal scene, played.scene
    assert_nil played.failure
    assert_equal({ action: "take", subject: item.name, reached_for_nothing: false }, played.intent)
  end

  test "an action with no record to act on reached for nothing" do
    scene = create(:scene, story: @game.story, location: @game.current_location, resolved_action: "take")

    assert_equal({ action: "take", subject: nil, reached_for_nothing: true }, Eval::RunTurn.intent_of(scene))
    assert_nil Eval::RunTurn.intent_of(create(:scene, story: @game.story, location: @game.current_location))
  end

  test "a turn the engine could not play is recorded in the words the player is shown" do
    extension = Extension.new do |game, line, token, _block|
      Playthrough::Command.accept!(game, line, token).update!(status: "failed", error_kind: "error")
      { error: { kind: "unsupported", failure: nil, message: "this engine does not play an offer yet" } }
    end

    played = on_rust(extension) { Eval::RunTurn.play(@game, "give the key to the warden") }

    assert_nil played.scene
    assert_equal "turn_failed", played.failure[:kind]
    assert_equal "The engine could not play that turn: this engine does not play an offer yet", played.failure[:shown]
    assert_match "Playthrough::RustEngine::EngineError", played.failure[:error]
  end

  test "a crisis answer is recorded as the crisis notice" do
    extension = Extension.new do |game, line, token, _block|
      Playthrough::Command.accept!(game, line, token).update!(status: "failed", error_kind: "crisis")
      { error: { kind: "model", failure: "crisis", message: "a crisis answer was suppressed" } }
    end

    played = on_rust(extension) { Eval::RunTurn.play(@game, "talk to the warden") }

    assert_equal "crisis", played.failure[:kind]
    assert_equal Playthrough::SafetyNotice::HEADING, played.failure[:shown]
  end

  private

  def on_rust(extension, &)
    Playthrough::RustEngine.stub(:extension, extension) do
      Playthrough::RustEngine.stub(:unplayable, nil) do
        Playthrough::RustEngine.using(:rust, &)
      end
    end
  end
end
