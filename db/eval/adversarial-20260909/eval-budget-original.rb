# Shared, offline-readable budget for the prepared R01/R03 evaluators. All
# participating processes MUST use the same EVAL_BUDGET_FILE. No provider call
# occurs in this file except through the existing BaseAgent/Chat implementation.
#
# Reservations use deliberately conservative rate bounds, NOT a claim about
# today's price: $5/M input tokens and $20/M output tokens. Registry pricing
# must fit those bounds before a request. Returned provider charges are kept
# separately from registry-priced usage and conservative budget accounting.
# This is a local spending guard; an upstream billing error cannot be undone.
require "json"
require "securerandom"
require "bigdecimal"

module ReviewEvalBudget
  MODEL = "mistralai/mistral-medium-3.1".freeze
  PROVIDER = "openrouter".freeze
  LIMIT_MICROS = 3_000_000
  INPUT_RATE = 5
  OUTPUT_RATE = 20
  MAX_INPUT_BYTES = 65_536
  MESSAGE_OVERHEAD_TOKENS = 4_096
  MAX_OUTPUT_TOKENS = 2_048

  # Bypass gameplay's rendering-fallback rescue: exhausted budget or an impure
  # arm must terminate an evaluation, never turn into a successful prose case.
  class Halt < Exception; end

  class Ledger
    def initialize(path)
      raise ArgumentError, "EVAL_BUDGET_FILE must name a shared ledger" if path.to_s.empty?
      @path = File.expand_path(path)
    end

    def reserve!(label:, input_cap:, output_cap: MAX_OUTPUT_TOKENS)
      unless input_cap.is_a?(Integer) && input_cap.positive? && output_cap.is_a?(Integer) && output_cap.positive? && output_cap <= MAX_OUTPUT_TOKENS
        raise Halt, "Invalid evaluation reservation bounds"
      end
      reservation = input_cap * INPUT_RATE + output_cap * OUTPUT_RATE
      token = SecureRandom.uuid
      edit do |data|
        charged = data.fetch("entries").sum { |entry| entry.fetch("accounted_micros") }
        raise Halt, "Shared $3 evaluation budget cannot reserve the next call" if charged + reservation > LIMIT_MICROS
        data["entries"] << { "id" => token, "label" => label, "state" => "reserved",
                             "input_cap" => input_cap, "output_cap" => output_cap,
                             "reserved_micros" => reservation, "accounted_micros" => reservation }
      end
      token
    end

    def settle!(token, receipt)
      edit do |data|
        entry = data.fetch("entries").find { |row| row.fetch("id") == token }
        raise Halt, "Unknown evaluation reservation" unless entry
        raise Halt, "Evaluation reservation already settled" unless entry.fetch("state") == "reserved"
        billed = receipt[:provider_cost_usd]
        upper = receipt[:usage_upper_micros]
        accounted = billed.nil? ? upper : (BigDecimal(billed.to_s) * 1_000_000).ceil
        accounted ||= entry.fetch("reserved_micros")
        entry.merge!("state" => billed.nil? && upper.nil? ? "unknown" : "settled",
                     "accounted_micros" => accounted, "receipt" => receipt)
        # Save the actual charge even when it violates a stated bound. The
        # ledger then refuses all further work, rather than hiding an overrun.
        if accounted > entry.fetch("reserved_micros")
          data["halt_reason"] = "A provider charge exceeded its conservative reservation"
        end
      end
    end

    def snapshot
      edit { |data| Marshal.load(Marshal.dump(data)) }
    end

    private

    def edit
      File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        raw = file.read
        data = raw.empty? ? { "limit_micros" => LIMIT_MICROS, "model" => MODEL,
                             "input_rate_bound" => INPUT_RATE, "output_rate_bound" => OUTPUT_RATE,
                             "entries" => [] } : JSON.parse(raw)
        unless data.fetch("limit_micros") == LIMIT_MICROS && data.fetch("model") == MODEL &&
               data.fetch("input_rate_bound") == INPUT_RATE && data.fetch("output_rate_bound") == OUTPUT_RATE
          raise Halt, "Shared ledger has a different ceiling or model"
        end
        raise Halt, data["halt_reason"] if data["halt_reason"]
        result = yield data
        file.rewind
        file.write(JSON.pretty_generate(data))
        file.truncate(file.pos)
        file.flush
        file.fsync
        result
      end
    end
  end

  class << self
    attr_accessor :calls, :label, :ledger

    def assert_isolated_database!
      raise Halt, "Use an explicit isolated DATABASE_URL" if ENV["DATABASE_URL"].to_s.empty?
      path = File.expand_path(ActiveRecord::Base.connection_db_config.database.to_s)
      temporary_roots = [ "/tmp/", "#{Rails.root.join('tmp')}/" ]
      raise Halt, "Evaluation databases must be under /tmp or the checkout's tmp directory" unless temporary_roots.any? { |root| path.start_with?(root) }
    end

    def install!
      raise Halt, "External evaluation is disabled; use EVAL_PREFLIGHT=1 for offline inspection" unless ENV["EVAL_LIVE"] == "1"
      raise Halt, "OPENROUTER_API_KEY is required" if ENV["OPENROUTER_API_KEY"].to_s.empty?
      self.ledger = Ledger.new(ENV.fetch("EVAL_BUDGET_FILE"))
      self.calls = []
      # The arm itself must be singular. BaseAgent#with_model only reconfigures
      # an already-built Chat and does not remove its fallback model_options.
      BaseAgent.define_singleton_method(:default_model_options) do
        [ { model: MODEL, provider: :openrouter, assume_model_exists: false } ]
      end
      RubyLLM.config.max_retries = 0
      BaseAgent.prepend(AgentCalls) unless BaseAgent.ancestors.include?(AgentCalls)
      Chat.prepend(ChatCalls) unless Chat.ancestors.include?(ChatCalls)
    end

    def usage(response)
      body = response.raw&.body if response.respond_to?(:raw)
      body = JSON.parse(body) if body.is_a?(String)
      cost = body.is_a?(Hash) ? body.dig("usage", "cost") : nil
      cost = Float(cost) unless cost.nil?
      raise Halt, "Invalid provider charge" if cost && (!cost.finite? || cost.negative?)
      fields = { input_tokens: :input_tokens, output_tokens: :output_tokens,
                 cached_tokens: :cached_tokens, cache_creation_tokens: :cache_creation_tokens,
                 thinking_tokens: :thinking_tokens }
      tokens = fields.transform_values { |method| response.public_send(method) if response.respond_to?(method) }
      if tokens.values.compact.any? { |count| !count.is_a?(Integer) || count.negative? }
        raise Halt, "Invalid provider token accounting"
      end
      known = !tokens[:input_tokens].nil? && !tokens[:output_tokens].nil?
      input = tokens.values_at(:input_tokens, :cached_tokens, :cache_creation_tokens).sum(&:to_i)
      output = tokens.values_at(:output_tokens, :thinking_tokens).sum(&:to_i)
      { **tokens, actual_model: response.respond_to?(:model_id) ? response.model_id : nil,
        provider: PROVIDER, provider_cost_usd: cost,
        registry_cost_usd: response.respond_to?(:cost) ? response.cost.total : nil,
        usage_upper_micros: known ? input * INPUT_RATE + output * OUTPUT_RATE : nil }
    end
  end

  module AgentCalls
    def ask(prompt, **options, &block)
      unless model_options.one? && model_options.first[:model] == MODEL && model_options.first[:provider].to_s == PROVIDER
        raise Halt, "Evaluation agent is not pinned to the approved single arm"
      end
      conversation = chat
      price = conversation.model.pricing&.dig("text_tokens", "standard")
      input_rate = Float(price&.fetch("input_per_million", nil)) rescue nil
      output_rate = Float(price&.fetch("output_per_million", nil)) rescue nil
      unless input_rate&.positive? && output_rate&.positive? && input_rate <= INPUT_RATE && output_rate <= OUTPUT_RATE
        raise Halt, "Pinned model has missing pricing or exceeds the reservation rate bounds"
      end
      conversation.with_params(max_tokens: MAX_OUTPUT_TOKENS,
                               provider: { allow_fallbacks: false })
      schema_json = schema&.new&.to_json_schema
      request = { prompt: prompt, instructions: instructions, schema: schema_json,
                  history: conversation.messages.order(:id).map { |message| { role: message.role, content: message.text } } }
      bytes = JSON.generate(request).bytesize
      raise Halt, "Evaluation request exceeds its text input bound" if bytes > MAX_INPUT_BYTES
      input_cap = bytes + MESSAGE_OVERHEAD_TOKENS
      context = conversation.model.context_window
      raise Halt, "Evaluation request exceeds the pinned model's context window" if context && input_cap + MAX_OUTPUT_TOKENS > context
      receipt = { purpose: purpose, prompt: prompt, instructions: instructions, schema: schema_json,
                  requested_model: MODEL, provider: PROVIDER, input_cap: input_cap,
                  output_cap: MAX_OUTPUT_TOKENS, registry_rates: price }
      ticket = ReviewEvalBudget.ledger.reserve!(label: "#{ReviewEvalBudget.label}:#{purpose}", input_cap: input_cap)
      ReviewEvalBudget.calls << receipt
      Thread.current[:review_eval_receipt] = receipt
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        result = super
        receipt[:answer] = result.content
        result
      rescue Exception => error
        receipt[:error] = error.class.name
        receipt[:error_message] = error.message
        raise
      ensure
        receipt[:seconds] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        Thread.current[:review_eval_receipt] = nil
        ReviewEvalBudget.ledger.settle!(ticket, receipt)
      end
    end
  end

  module ChatCalls
    def ask(*args, **options, &block)
      result = super
      receipt = Thread.current[:review_eval_receipt]
      if receipt
        receipt.merge!(ReviewEvalBudget.usage(result))
        receipt[:raw_answer] = result.content
        raise Halt, "Provider answered with an unexpected model" unless receipt[:actual_model] == MODEL
      end
      result
    end
  end
end
