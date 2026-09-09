# The browser's real orchestration with fixed provider answers or failures.
# This reaches boundaries Mechanics intentionally omits: the scene fallback,
# per-command journal, time, riposte and a duplicate background delivery. It
# Supplies no engine state: realization replies pass through the real noun and
# exit gates. Every declared call must be consumed in order, so retrying a paid
# detail call fails a walk even when its second answer would look the same.
class EngineSweep::BrowserTurn
  class RenderingUnavailable < StandardError; end

  attr_reader :shown

  class Agent
    Response = Struct.new(:content)

    def initialize(purpose, calls, replies)
      @purpose, @calls, @replies = purpose, calls, replies
    end

    def with_instructions(*) = self
    def with_schema(*) = self
    def with_temperature(*) = self
    def attribute_to!(*) = nil
    def recorded_chat = nil
    def add_message(**) = nil

    def ask(*)
      @calls << @purpose
      expected = @replies.shift
      unless expected && @purpose == expected.fetch("purpose")
        raise EngineSweep::ModelCalled, "browser step unexpectedly called #{@purpose.inspect}"
      end
      raise RenderingUnavailable, "the sweep's provider is unavailable" if expected["unavailable"]

      Response.new(expected.fetch("content"))
    end
  end

  def initialize(mechanics)
    @mechanics = mechanics
  end

  def run(step)
    game = @mechanics.playthrough
    before = game.current_scene_id
    calls = []
    replies = step.browser["replies"] || [ step.browser["fail"] ].compact.map do |purpose|
      { "purpose" => purpose, "unavailable" => true }
    end
    expected_calls = replies.map { |reply| reply.fetch("purpose") }
    raised = false
    outcome = without_provider(calls, replies: replies.dup) do
      Playthrough::Turn.new(game).play(step.typed, request_token: step.browser.fetch("token"))
    rescue RenderingUnavailable
      raise unless step.browser["raises"]

      raised = true
      nil
    end
    if step.browser["raises"] && !raised
      raise EngineSweep::ModelCalled, "browser step expected an unavailable provider to interrupt submission"
    end
    unless calls == expected_calls
      raise EngineSweep::ModelCalled, "browser step expected #{expected_calls.inspect} rendering calls, got #{calls.inspect}"
    end

    game.reload
    @shown = visible_notices(game) if step.expectation.document.key?("shown")
    scene = outcome if outcome.is_a?(Scene)
    target = scene&.acted_on_record
    understood = "#{scene.resolved_action} -> #{Playthrough::Classifier.label_for(target)}" if target
    Playthrough::Mechanics::Report.new(
      command: step.typed, understood: understood,
      change: ("The browser turn completed." if before != game.current_scene_id),
      refusal: (outcome.text if outcome.is_a?(Playthrough::Refusal)),
      note: [ game.commands.find_by!(request_token: step.browser.fetch("token")).status ],
      resolved_by: scene&.resolved_by, state: @mechanics.state
    )
  end

  private

  # Read the actual player-facing entries, with the debug instrument off. Only
  # the engine notices are asserted: model prose is still outside this sweep.
  def visible_notices(game)
    original = Playthrough::Debug.method(:enabled?)
    Playthrough::Debug.define_singleton_method(:enabled?) { false }
    html = ApplicationController.render(partial: "turns/turn", collection: game.turn_log, as: :turn,
                                        locals: { playthrough: game })
    Nokogiri::HTML.fragment(html).css(".said > .notice").map { |notice| notice.text.squish }
  ensure
    Playthrough::Debug.define_singleton_method(:enabled?, original)
  end

  def without_provider(calls, replies:)
    original = BaseAgent.method(:new)
    BaseAgent.singleton_class.send(:define_method, :new) do |*_args, **options|
      Agent.new(options[:purpose], calls, replies)
    end
    yield
  ensure
    BaseAgent.singleton_class.send(:define_method, :new, original)
  end
end
