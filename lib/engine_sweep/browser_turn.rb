# The browser's real orchestration with fixed provider answers or failures.
# This reaches boundaries Mechanics intentionally omits: the scene fallback,
# per-command journal, time, riposte and a duplicate background delivery. It
# Supplies no engine state: realization replies pass through the real noun and
# exit gates. Every declared call must be consumed in order, so retrying a paid
# detail call fails a walk even when its second answer would look the same.
class EngineSweep::BrowserTurn
  class RenderingUnavailable < StandardError; end
  class WorkerStopped < Interrupt; end

  attr_reader :shown

  class Agent
    Response = Struct.new(:content)

    def initialize(purpose, calls, replies, prompt_failures)
      @purpose, @calls, @replies, @prompt_failures = purpose, calls, replies, prompt_failures
    end

    def with_instructions(*) = self
    def with_schema(*) = self
    def with_temperature(*) = self
    def attribute_to!(*) = nil
    def recorded_chat = nil
    def add_message(**) = nil

    def ask(prompt, verify: nil, **)
      @calls << @purpose
      expected = @replies.shift
      unless expected && @purpose == expected.fetch("purpose")
        raise EngineSweep::ModelCalled, "browser step unexpectedly called #{@purpose.inspect}"
      end
      # These assertions inspect the generated request delivered at the real
      # agent boundary. A canned answer alone cannot prove the NPC was informed.
      # Keep failures until after the turn: narration may legitimately rescue a
      # provider exception, but it must never hide a broken sweep assertion.
      Array(expected["prompt_includes"]).each do |text|
        @prompt_failures << "#{@purpose} prompt omitted #{text.inspect}" unless prompt.include?(text)
      end
      Array(expected["prompt_excludes"]).each do |text|
        @prompt_failures << "#{@purpose} prompt disclosed #{text.inspect}" if prompt.include?(text)
      end
      raise RenderingUnavailable, "the sweep's provider is unavailable" if expected["unavailable"]

      content = expected.fetch("content")
      verify.call(content) if verify
      Response.new(content)
    end
  end

  # THE SECOND PROVIDER, WHICH IS NOT A `BaseAgent` AND NEVER GOES THROUGH ONE.
  # A System One request is a state object and a map of typed questions, so this
  # fixture answers `#ask_questions` rather than `#ask` -- and it builds a REAL
  # `SystemOneAgent::Answers`, so a reply a script writes is one the shipped
  # verification accepted: an option outside the criteria that were sent is
  # refused here exactly as it would be live.
  #
  # A reply names only the answers it cares about. Everything else the request
  # asked is filled with the uninteresting answer -- `nothing` for a Choice, 0.0
  # for a Noul -- because a provider answers every question it was sent and a
  # script should not have to restate ten of them to vary one.
  class TypedAgent
    PURPOSE = "system_one".freeze

    def initialize(calls, replies, prompt_failures)
      @calls, @replies, @prompt_failures = calls, replies, prompt_failures
    end

    def ask_questions(state:, questions:)
      @calls << PURPOSE
      expected = @replies.shift
      unless expected && expected.fetch("purpose") == PURPOSE
        raise EngineSweep::ModelCalled, "browser step unexpectedly called #{PURPOSE.inspect}"
      end

      sent = JSON.generate(state)
      Array(expected["prompt_includes"]).each do |text|
        @prompt_failures << "#{PURPOSE} state omitted #{text.inspect}" unless sent.include?(text)
      end
      Array(expected["prompt_excludes"]).each do |text|
        @prompt_failures << "#{PURPOSE} state disclosed #{text.inspect}" if sent.include?(text)
      end
      raise SystemOneAgent::Unavailable, "the sweep's System One provider is unavailable" if expected["unavailable"]

      SystemOneAgent::Answers.new(body(expected.fetch("content"), questions), questions)
    end

    private

    def body(named, questions)
      answers = questions.to_h do |id, question|
        [ id, named.key?(id) ? answer(named.fetch(id)) : filler(question) ]
      end
      { "answers" => answers, "usage" => { "input_tokens" => 0, "output_tokens" => 0 } }
    end

    def filler(question)
      question["type"] == "noul" ? answer(0.0) : answer(Playthrough::IntentSchema::NOTHING)
    end

    def answer(value)
      return { "type" => "noul", "noul" => value } if value.is_a?(Numeric)

      { "type" => "choice", "choice" => value.to_s, "probabilities" => { value.to_s => 1.0 }, "confidence" => 1.0 }
    end
  end

  def initialize(mechanics)
    @mechanics = mechanics
  end

  def run(step)
    game = @mechanics.playthrough
    before = game.current_scene_id
    # What the player typed while the previous turn was still running: accepted
    # and enqueued, with no job delivered. Delivering the LATER job first is the
    # race three worker threads and a non-FIFO flock make reachable, and the
    # only thing that proves the earlier line still goes first.
    earlier = Array(step.browser["accepted_first"]).map do |queued|
      Playthrough::Command.accept!(game, queued.fetch("type"), queued.fetch("token"))
    end
    calls = []
    prompt_failures = []
    replies = step.browser["replies"] || [ step.browser["fail"] ].compact.map do |purpose|
      { "purpose" => purpose, "unavailable" => true }
    end
    expected_calls = replies.map { |reply| reply.fetch("purpose") }
    raised = false
    outcome = without_provider(calls, replies: replies.dup, prompt_failures: prompt_failures) do
      interrupt_after(step.browser["interrupt_after"]) do
        Playthrough::Turn.new(game).play(step.typed, request_token: step.browser.fetch("token"))
      end
    rescue WorkerStopped
      raise unless step.browser["interrupt_after"]

      raised = true
      nil
    rescue RenderingUnavailable
      raise unless step.browser["raises"]

      raised = true
      nil
    end
    if (step.browser["raises"] || step.browser["interrupt_after"]) && !raised
      raise EngineSweep::ModelCalled, "browser step expected an unavailable provider to interrupt submission"
    end
    raise EngineSweep::ModelCalled, prompt_failures.join("; ") if prompt_failures.any?

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
      note: (earlier + [ game.commands.find_by!(request_token: step.browser.fetch("token")) ])
              .map { |row| "#{row.request_token}: #{row.reload.status}" },
      resolved_by: scene&.resolved_by, state: @mechanics.state
    )
  end

  private

  # Stop AFTER an atomic receipt, bypassing StandardError recovery as a killed
  # worker does. The next script line runs a fresh Turn against the saved rows.
  def interrupt_after(boundary)
    return yield unless boundary

    original = Playthrough::Command::Journal.method(:commit)
    Playthrough::Command::Journal.define_singleton_method(:commit) do |key, &work|
      result = original.call(key, &work)
      raise WorkerStopped, "the sweep stopped the worker" if key == boundary

      result
    end
    yield
  ensure
    Playthrough::Command::Journal.define_singleton_method(:commit, original) if original
  end

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

  # BOTH PROVIDERS, OFF ONE QUEUE. The replies are consumed in the order a script
  # declares them whichever provider asks, which is what lets a step pin that an
  # escalated line asked System One FIRST and the model call second.
  #
  # THE KEY IS THE SWITCH, AND HERE THE DECLARED REPLY IS THE KEY. A step with no
  # `system_one` reply leaves `SystemOneAgent.configured?` answering NO, so the
  # line walks the keyless path -- which is both the offline case and exactly
  # what a missing or rotted key produces in production.
  def without_provider(calls, replies:, prompt_failures:)
    original = BaseAgent.method(:new)
    typed = SystemOneAgent.method(:new)
    switch = SystemOneAgent.method(:configured?)
    keyed = replies.any? { |reply| reply["purpose"] == TypedAgent::PURPOSE }

    BaseAgent.singleton_class.send(:define_method, :new) do |*_args, **options|
      Agent.new(options[:purpose], calls, replies, prompt_failures)
    end
    if keyed
      SystemOneAgent.singleton_class.send(:define_method, :new) do |*_args, **_options|
        TypedAgent.new(calls, replies, prompt_failures)
      end
      SystemOneAgent.singleton_class.send(:define_method, :configured?) { true }
    end
    yield
  ensure
    BaseAgent.singleton_class.send(:define_method, :new, original)
    SystemOneAgent.singleton_class.send(:define_method, :new, typed)
    SystemOneAgent.singleton_class.send(:define_method, :configured?, switch)
  end
end
