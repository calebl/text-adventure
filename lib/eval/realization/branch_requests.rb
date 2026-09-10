# Full requests in the shared request_identity v1 shape: system, user, emitted
# schema, plus ordered history. Until the shared module lands, canonicalization
# is explicit here, as in the dialogue and genesis benches. No instruction
# scrub is used. The live capture keeps generated history for every case; the
# offline designation is the first purchased call of each fixed branch case.
# For a retry that means exits WITH its restored accepted detail, not detail
# purchased again. Other exits inherit variable generated history and are
# retained as receipts, never claimed identical to an offline scaffold.
module Eval::Realization::BranchRequests
  extend self

  module Capture
    attr_reader :measured_requests

    def ask(schema, prompt)
      @measured_requests ||= []
      @measured_requests << Eval::Realization::BranchRequests.request(self, schema, prompt) if agent.is_a?(BaseAgent)
      super
    end
  end

  def request(generator, schema, prompt)
    agent = generator.agent
    { "system" => agent.instructions, "user" => prompt,
      "schema" => schema.new.to_json_schema,
      "history" => agent.chat.messages.order(:id).reject { |message| message.role == "system" }.map { |message|
        { "role" => message.role, "content" => message.to_llm.content }
      } }
  end

  def canonical(value)
    case value
    when Hash then value.stringify_keys.sort.to_h.transform_values { |part| canonical(part) }
    when Array then value.map { |part| canonical(part) }
    when Symbol then value.to_s
    else value
    end
  end

  def identity(requests)
    { "version" => 1, "digest" => Digest::SHA256.hexdigest(JSON.generate(canonical(requests))).first(16) }
  end

  def write!(directory, requests)
    FileUtils.mkdir_p(directory)
    File.write(Pathname.new(directory).join("requests.json"),
               "#{JSON.pretty_generate({ request_identity: identity(requests), requests: requests })}\n")
  end

  def offline(corpus = Eval::Realization.corpus)
    previous = RubyLLM.config.openrouter_api_key
    RubyLLM.config.openrouter_api_key ||= "offline-request-identity"
    Eval::Classifier::Arm.parse(BaseAgent::REMOTE_MODEL_IDS.first).pinned do
      corpus.cases.select { |kase| kase.staging.present? }.to_h do |kase|
        Eval::Realization::Stage.open([ kase ]) do |stages|
          generator = stages.fetch(kase.id).generator
          retrying = kase.staging.key?("retry_detail")
          schema = retrying ? Location::ExitsSchema : generator.detail_schema
          prompt = retrying ? generator.exits_prompt : generator.detail_prompt
          [ kase.id, canonical(request(generator, schema, prompt)) ]
        end
      end
    end
  ensure
    RubyLLM.config.openrouter_api_key = previous
  end
end
