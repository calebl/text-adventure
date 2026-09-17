# The only live payloads allowed by this runner are its inspected, fixed branch
# requests. This wrapper is prepended AFTER the budget helper, so validation
# precedes both its reservation and the provider call. One request per reading,
# and only the absent members of seven cases x four repetitions may be bought.
module PhysicalRealizationPayload
  MAX_READINGS = 28
  class Refused < ReviewEvalBudget::Halt; end

  class << self
    attr_accessor :gate
  end

  class Gate
    attr_accessor :current
    attr_reader :sent

    def initialize(requests:, allowed:)
      raise Refused, "Too many permitted readings" if allowed.size > MAX_READINGS
      raise Refused, "Duplicate permitted reading" unless allowed.uniq == allowed

      @requests = requests
      @allowed = allowed
      @sent = []
    end

    def check!(agent, prompt)
      raise Refused, "No permitted current reading" unless @allowed.include?(current)
      raise Refused, "This reading already attempted its one call" if sent.include?(current)

      expected = @requests.fetch(current.first)
      actual = Eval::Realization::BranchRequests.canonical({
        "system" => agent.instructions, "user" => prompt,
        "schema" => agent.schema&.new&.to_json_schema,
        "history" => agent.chat.messages.order(:id).reject { |message| message.role == "system" }.map { |message|
          { "role" => message.role, "content" => message.to_llm.content }
        }
      })
      raise Refused, "Payload differs from inspected preflight request: #{current.inspect}" unless actual == expected

      sent << current.dup
    end
  end

  module BeforeBudget
    def ask(prompt, **options, &block)
      raise Refused, "No payload allowlist installed" unless PhysicalRealizationPayload.gate

      PhysicalRealizationPayload.gate.check!(self, prompt)
      super
    end
  end
end
