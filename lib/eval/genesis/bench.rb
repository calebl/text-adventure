# SERIAL, PINNED, AND RECEIPTED BEFORE THE STAGE ROLLS BACK.
# BaseAgent still verifies each paid call. Capture the provider response before
# that verification, because BaseAgent rewinds a rejected exchange and a schema
# failure must not erase the answer or its cost from an instrument.
# No warm-up is bought or silently excluded: latency includes the first call.
class Eval::Genesis::Bench
  SPEND_CEILING = 2.0
  attr_reader :corpus, :arm, :reps, :passes, :reserved

  def initialize(corpus: Eval::Genesis.corpus, model: Eval::Cost.default_model,
                 reps: Eval::Noise::MIN_RUNS, io: $stdout)
    @corpus, @arm, @reps, @io = corpus, Eval::Classifier::Arm.parse(model), reps, io
    raise ArgumentError, "reps must be positive" unless reps.positive?
    @passes, @reserved = [], 0.0
  end

  def run(directory:)
    estimate = Eval::Genesis.estimate(cases: corpus.cases, reps: reps, models: [ arm ])
    raise ArgumentError, "estimate exceeds genesis spend ceiling" if estimate > SPEND_CEILING
    result = Eval::Genesis::Result.new("corpus_digest" => Eval::Genesis.digest(corpus), "request_digests" => Eval::Genesis::Version.offline(corpus.cases),
                        "name" => Pathname.new(directory).basename.to_s, "recorded_at" => Time.current.utc.iso8601,
                        "arms" => [ arm.id ], "reps" => reps, "estimate_usd" => estimate, "passes" => passes)
    result.write!(directory)
    Eval.without_provider_retries do
      arm.pinned do
        (1..reps).each do |rep|
          pass = { "arm" => arm.id, "rep" => rep, "readings" => [] }
          passes << pass
          corpus.cases.each do |kase|
            Eval::Genesis::Stage.open(kase) do |stage|
              stage.requests.each do |request|
                row = read(stage, request, rep)
                pass["readings"] << row
                result.write!(directory)
                @io&.puts "#{kase.id}/#{request.call} rep #{rep}: #{row['error'] || 'answered'}"
              end
            end
          end
        end
      end
    end
    result
  end

  def read(stage, request, rep)
    identity = request.identity
    output_limit = Eval::Genesis.output_allowance(identity.fetch("schema").fetch("schema"))
    allowance = arm.price.of(JSON.generate(identity).bytesize, output_limit)
    raise ArgumentError, "next request exceeds genesis spend ceiling" if reserved + allowance > SPEND_CEILING
    @reserved += allowance
    row = { "id" => stage.kase.id, "call" => request.call, "arm" => arm.id, "rep" => rep,
            "request" => identity, "request_digest" => Eval::Genesis::Version.digest(identity), "facts" => request.facts,
            "reserved_usd" => allowance }
    agent = BaseAgent.new.with_instructions(request.system).with_schema(request.schema)
    request.history.each { |message| agent.add_message(role: message.fetch("role"), content: message.fetch("content")) }
    # Bound output for budget accounting; schema bytes and production wording
    # are untouched. Record the operational limit beside the request identity.
    agent.chat.with_params(max_tokens: output_limit)
    row["max_tokens"] = output_limit
    provider_response = nil
    original = agent.chat.method(:ask)
    agent.chat.define_singleton_method(:ask) do |*args, **kwargs, &block|
      provider_response = original.call(*args, **kwargs, &block)
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      response = agent.ask(request.user)
      row["after"] = stage.apply(request, response.content)
    rescue StandardError => error
      row["error"] = "#{error.class}: #{error.message}"
    ensure
      row["seconds"] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      row.merge!(receipt(provider_response))
    end
    row
  end

  def receipt(response)
    return { "receipt_missing" => true } unless response

    input = response.input_tokens.to_i
    cached = response.respond_to?(:cached_tokens) ? response.cached_tokens.to_i : 0
    created = response.respond_to?(:cache_creation_tokens) ? response.cache_creation_tokens.to_i : 0
    output = response.output_tokens.to_i
    { "answer" => response.content, "answered_by" => response.model_id,
      "input_tokens" => input, "cached_tokens" => cached, "cache_creation_tokens" => created,
      "output_tokens" => output, "cost_usd" => arm.price.of(input + cached + created, output),
      "price" => arm.price.to_h.stringify_keys }
  end
end
