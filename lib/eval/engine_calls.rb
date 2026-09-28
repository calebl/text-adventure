# WHAT ANSWERS THE CALLS OF A CASE THE ENGINE PLAYS OR READS.
#
# A bench builds nothing it sends: the engine builds every request
# (`Playthrough::Requests`) and hands each call to a block as it reaches it.
# These are the two blocks a bench hands it, and both keep a receipt of every
# call, in order.
#
#   `Sender`  sends each call through `BaseAgent` -- the one door every chat
#             call goes through -- under whatever arm `Eval::Classifier::Arm`
#             has pinned, and answers with what came back. A call that fails
#             is answered as the failure it was, so the engine does with it
#             exactly what it does with a failed call in play -- its own words
#             where it has them, the turn's failure where it has not -- and
#             the exception itself is kept (`#failure`) for the bench to file
#             the reading under.
#   `Canned`  answers every call with fixed words and sends nothing, for the
#             offline digests: a prose call gets `PRELUDE`, a schema'd call an
#             answer with every required field set to it.
#
# A SCHEMA GOES OUT AS THE ENGINE WROTE IT, byte for byte, wrapped (`Schema`)
# so `BaseAgent` still checks every required field of the answer exactly as it
# checks any other schema'd call.
module Eval::EngineCalls
  PRELUDE = "The measured action is complete.".freeze

  # The engine's JSON schema (`{name, description, schema}`), as `BaseAgent`
  # and RubyLLM ask a schema for it.
  Schema = Data.define(:json) do
    def to_json_schema = json
    def required_properties = Array(json.dig("schema", "required")).map(&:to_s)
  end

  # One call, and what came of it. `raw` is the answer as the provider's
  # parsed JSON for a schema'd call; the tokens are the conversation's.
  Receipt = Data.define(:purpose, :system, :user, :schema, :content, :answered_by,
                        :input_tokens, :output_tokens, :raw) do
    def request = { system: system, user: user, schema: schema }
  end

  class Canned
    attr_reader :receipts

    def initialize = @receipts = []

    def call(request)
      raise ArgumentError, "a bench that reads no line with System One was asked System One" if request["kind"] == "system_one"

      schema = request["schema"]
      content = if schema
        Array(schema.dig("schema", "required")).to_h { |field| [ field.to_s, PRELUDE ] }
      else
        PRELUDE
      end
      @receipts << Receipt.new(purpose: request["purpose"], system: request["system"], user: request["user"],
                               schema: schema, content: content, answered_by: nil, input_tokens: 0,
                               output_tokens: 0, raw: schema && content)
      { "content" => content, "model" => nil }
    end

    def to_proc = method(:call).to_proc
  end

  class Sender
    attr_reader :receipts, :failure

    def initialize(playthrough, character: nil, chat: nil)
      @playthrough = playthrough
      @character = character
      @chat = chat
      @receipts = []
    end

    def call(request)
      raise ArgumentError, "this bench sends no System One call" if request["kind"] == "system_one"

      send_chat(request)
    rescue ArgumentError
      raise
    rescue StandardError => error
      @failure = error
      { "failure" => { "kind" => FAILURES.find { |klass, _| error.is_a?(klass) }&.last || "provider",
                       "message" => "#{error.class}: #{error.message}" } }
    end

    def to_proc = method(:call).to_proc

    # How the engine names each way `BaseAgent` fails.
    FAILURES = { BaseAgent::CrisisResponseError => "crisis", BaseAgent::RefusalError => "refused",
                 BaseAgent::SchemaIgnoredError => "schema_ignored", BaseAgent::UnauthorizedProviderError => "unauthorized",
                 BaseAgent::NoModelConfiguredError => "no_model" }.freeze

    private

    def send_chat(request)
      agent = BaseAgent.new(request["system"], purpose: request["purpose"], playthrough: @playthrough,
                            character: @character, chat: @chat)
      agent.with_schema(Schema.new(request["schema"])) if request["schema"]
      response = request["stream"] ? agent.ask(request["user"]) { |_chunk| } : agent.ask(request["user"])
      chat = agent.recorded_chat
      messages = chat ? chat.messages.order(:id).to_a : []
      kept = messages.reverse.find { |message| message.role.to_s == "assistant" }
      @receipts << Receipt.new(purpose: request["purpose"], system: request["system"], user: request["user"],
                               schema: request["schema"], content: response.content,
                               answered_by: kept&.answering_model_id || agent.current_model[:model],
                               input_tokens: messages.sum { |message| message.input_tokens.to_i },
                               output_tokens: messages.sum { |message| message.output_tokens.to_i },
                               raw: kept&.structured_content)
      { "content" => response.content, "model" => agent.current_model[:model] }
    end
  end
end
