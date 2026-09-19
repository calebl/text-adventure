# Live-run guard for the fixed realization corpus. The runner binds one case and
# repetition before each ask; this gate permits only the schemas and call order
# used by Location::Generator and runs before the budget wrapper.
module DesiresRealizationPayload
  MAX_CALLS = (Eval::Realization.corpus.size * Eval::Noise::MIN_RUNS + 1) * Eval::Realization::CALLS.size
  class Refused < ReviewEvalBudget::Halt; end

  class << self
    attr_accessor :gate
  end

  class Gate
    attr_reader :sent

    def initialize(expected_system:)
      @cases = Eval::Realization.corpus.cases.index_by(&:id)
      @expected_system = expected_system
      @allowed = @cases.keys.product((1..Eval::Noise::MIN_RUNS).to_a) + [ [ @cases.keys.first, 0 ] ]
      @sent = []
    end

    def start!(id, rep)
      @current = [ id, rep ]
      raise Refused, "Reading is outside the fixed corpus" unless @allowed.include?(@current)
      raise Refused, "Reading was already attempted" if sent.any? { |key| key.first(2) == @current }
    end

    def finish!
      @current = nil
    end

    def check!(agent, prompt)
      raise Refused, "No permitted current reading" unless @current
      raise Refused, "Unexpected agent purpose" unless agent.purpose.to_s == "location"
      raise Refused, "Unexpected realization instructions" unless agent.instructions == @expected_system

      kase = @cases.fetch(@current.first)
      sequence = if kase.staging.key?("retry_detail")
        [ "Location::ExitsSchema" ]
      elsif kase.shape.to_s == "place"
        [ "Location::PlaceSchema" ]
      elsif kase.shape.to_s == "interior-room"
        [ "Location::DetailSchema" ]
      else
        [ "Location::DetailSchema", "Location::ExitsSchema" ]
      end
      ordinal = sent.count { |key| key.first(2) == @current }
      expected = sequence[ordinal] or raise Refused, "Too many calls for one realization"
      actual = agent.schema&.new&.to_json_schema
      actual_name = actual && (actual[:name] || actual["name"])
      raise Refused, "Unexpected realization schema" unless actual_name == expected
      raise Refused, "Empty realization prompt" if prompt.blank?
      raise Refused, "Evaluation call cap reached" if sent.size >= MAX_CALLS

      sent << (@current + [ ordinal + 1 ])
    end
  end

  module BeforeBudget
    def ask(prompt, **options, &block)
      gate = DesiresRealizationPayload.gate or raise Refused, "No payload gate installed"
      gate.check!(self, prompt)
      super
    end
  end
end
