# THE BENCH-ONLY SYSTEM ONE ADAPTER.
#
# This is deliberately under `Eval`, not `app/`: no turn, controller, job or
# model can reach it without crossing into the measurement namespace. It is a
# `BaseAgent` subclass so the repository still has one model-call abstraction,
# but it speaks System One's typed HTTP contract instead of pretending that Jev
# is an OpenAI-compatible chat model. `Eval::Classifier::Bench` is its only
# caller, selected explicitly by the `typesafe:jev-latest` arm. The live
# `Playthrough::Classifier` remains byte-for-byte on its RubyLLM path.
#
# ONE CHOICE HOLDS THE WHOLE ANSWER. System One evaluates separate questions in
# parallel and isolation, and its documented composition pattern lets application
# code combine them. Complete tuples remain here because the parallel encodings
# measured on 2026-09-18 were worse classifiers: twelve-question composition had
# 0.892..0.895 all-line accuracy against this tuple's 0.924..0.933, and no tested
# parallel second-record mechanism approached the tuple's 1.000 precision / 0.914
# recall as a one-line-one-act detector (the alternatives measured 0.696 / 0.625,
# 0.737 / 0.328, and 0.872 / 0.906 respectively).
#
# Each opaque choice therefore means one complete, engine-valid
# `(intent, target, also_named)` tuple. Tuples come only from
# `Playthrough::Classifier#offered_for`; a chosen key cannot name an out-of-set
# record. Pairs of distinct records carry `also_named`, unordered because the
# engine refuses the whole two-act line and the corpus scores the pair as a set.
# `use` keeps a physical action as its primary target and may pair it with the
# other records the shipped classifier's `build_intent` accepts as evidence.
#
# REJECTED ENCODINGS:
# - parallel questions and application-side composition: materially worse
#   whole-answer quality and second-record detection in the measured shapes;
# - one Choice for only `(intent, target)`: it cannot detect the two-name lines
#   whose refusal is load-bearing;
# - one Choice per arbitrary cross-product entry: most entries describe records
#   that action can never resolve, weakening the closed-set guarantee.
#
# OPTION LIMIT. System One's published schema declares no maximum. This adapter
# accepts at most 64 complete tuples and fails before the network above that.
# That is an application limit, not a claim about the service: it bounds request
# size, is comfortably above every current corpus position, and makes a future
# room whose combinatorics changed the experiment stop loudly. The kept run's
# receipts prove the largest shape the service actually accepted.
#
# CONFIDENCE DOES NOT ALTER THE BENCH'S STANDARD SCORE. The raw choice is scored
# so Jev can be compared as a classifier; coverage and fallback at candidate
# floors are recorded separately. A runtime experiment, if ever authorized,
# must fall back to the current classifier on low confidence, timeout, malformed
# response or missing key. None of those outcomes is an engine refusal.
class Eval::Classifier::JevAgent < BaseAgent
  ENDPOINT = "https://api.typesafe.ai/v1/systemone".freeze
  MODEL = "jev-latest".freeze
  ARM_ID = "typesafe:#{MODEL}".freeze
  TIMEOUT = 5
  MAX_OPTIONS = 64
  CONFIDENCE_FLOORS = [ 0.5, 0.6, 0.7, 0.8, 0.9 ].freeze
  FALLBACK_FLOOR = 0.6
  # Published by typesafe.ai as $42 / billion billable input tokens; System
  # One's response marks output tokens free. Receipts carry actual token usage.
  PRICE = Eval::Cost::Price.new(model: MODEL, input_per_million: 0.042, output_per_million: 0.0)

  class MissingKey < StandardError; end
  class ReceiptError < StandardError
    attr_reader :receipt

    def initialize(message, receipt:)
      @receipt = receipt
      super(message)
    end
  end
  class HttpError < ReceiptError; end
  class MalformedResponse < ReceiptError; end
  class TooManyOptions < StandardError; end

  Option = Data.define(:key, :intent, :target, :also_named, :criterion)
  TransportReceipt = Data.define(:status, :request_id, :body)
  Result = Data.define(:answer, :raw, :confidence, :probabilities, :usage, :request, :receipt, :billed_cost)

  class Transport
    def post(payload, api_key:, timeout: TIMEOUT)
      uri = URI(ENDPOINT)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{api_key}"
      request.body = JSON.generate(payload)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: timeout, read_timeout: timeout,
                                 write_timeout: timeout) { |http| http.request(request) }
      body = JSON.parse(response.body)
      receipt = TransportReceipt.new(status: response.code.to_i,
                                     request_id: response["x-typesafe-request-id"], body: body)
      unless response.is_a?(Net::HTTPSuccess)
        raise HttpError.new("System One returned HTTP #{receipt.status}", receipt:)
      end

      receipt
    rescue JSON::ParserError
      receipt = TransportReceipt.new(status: response.code.to_i,
                                     request_id: response["x-typesafe-request-id"], body: response.body)
      raise MalformedResponse.new("System One returned non-JSON", receipt:)
    end
  end

  attr_reader :classifier, :timeout, :transport, :recorded_request, :transport_receipt

  def initialize(classifier:, api_key: ENV["TYPESAFE_API_KEY"], timeout: TIMEOUT, transport: Transport.new)
    super(Playthrough::Classifier::INSTRUCTIONS, nil, model_options: [], purpose: "classifier-benchmark")
    @classifier = classifier
    @api_key = api_key.to_s
    @timeout = timeout
    @transport = transport
  end

  def classify(command)
    raise MissingKey, "TYPESAFE_API_KEY is not set for the Jev benchmark arm" if @api_key.empty?

    options = options_for
    request = request_for(command, options)
    @recorded_request = request
    receipt = transport.post(request, api_key: @api_key, timeout: timeout)
    @transport_receipt = receipt
    answer = validate(receipt.body, options)
    option = options.fetch(answer.fetch("choice"))
    usage = receipt.body.fetch("usage")
    normalized = {
      "intent" => option.intent.to_s,
      "target" => option.target || Playthrough::IntentSchema::NOTHING,
      "also_named" => option.also_named || Playthrough::IntentSchema::NOTHING
    }

    Result.new(
      answer: Eval::Classifier::Corpus::Answer.new(intent: option.intent, target: option.target,
                                                    also_named: option.also_named),
      raw: normalized,
      confidence: answer.fetch("confidence").to_f,
      probabilities: answer.fetch("probabilities"),
      usage: usage,
      request: request,
      receipt: recorded_receipt,
      billed_cost: PRICE.of(usage.fetch("input_tokens"), usage.fetch("output_tokens"))
    )
  rescue ReceiptError => error
    @transport_receipt = error.receipt
    raise
  end

  def recorded_receipt
    return if transport_receipt.nil?

    { "status" => transport_receipt.status, "request_id" => transport_receipt.request_id,
      "body" => transport_receipt.body }
  end

  def recorded_usage
    raw = transport_receipt&.body.is_a?(Hash) ? transport_receipt.body["usage"] : nil
    return unless raw.is_a?(Hash)

    %w[input_tokens output_tokens].each_with_object({}) do |key, usage|
      value = raw[key]
      usage[key] = value if value.is_a?(Integer) && value >= 0
    end.presence
  end

  def recorded_billed_cost
    input = recorded_usage&.fetch("input_tokens", nil)
    return unless input

    PRICE.of(input, recorded_usage.fetch("output_tokens", 0))
  end

  def options_for
    tuples = Playthrough::IntentSchema::INTENTS.map(&:to_sym).flat_map do |intent|
      options_for_intent(intent)
    end
    tuples = tuples.uniq { |row| [ row.fetch(:intent), *row.values_at(:target, :also_named).compact.map(&:downcase).sort ] }
    if tuples.size > MAX_OPTIONS
      raise TooManyOptions, "System One classifier shape has #{tuples.size} choices; limit is #{MAX_OPTIONS}"
    end

    tuples.each_with_index.to_h do |tuple, index|
      key = format("choice_%03d", index + 1)
      option = Option.new(key: key, criterion: criterion_for(**tuple), **tuple)
      [ key, option ]
    end
  end

  def request_for(command, options = options_for)
    {
      model: MODEL,
      state: {
        instructions: instructions,
        situation: classifier.command_prompt(command, classifier.exits_here, classifier.characters_here,
                                             classifier.items_here, classifier.items_carried)
      },
      questions: {
        reading: {
          type: "choice",
          instructions: "Choose the ONE engine-valid complete interpretation that best reads the player line. " \
                        "The opaque key has no meaning; judge its criterion. Keep the requested intent when " \
                        "its target is absent, and never substitute an available record.",
          criteria: options.transform_values(&:criterion)
        }
      }
    }
  end

  private
    def options_for_intent(intent)
      return [ { intent: intent, target: nil, also_named: nil } ] if intent == :other
      return use_options if intent == :use

      names = unique_records(classifier.offered_for(intent)).map { |record| label(record) }
      rows = [ { intent: intent, target: nil, also_named: nil } ]
      names.each { |name| rows << { intent: intent, target: name, also_named: nil } }
      names.combination(2) do |target, also_named|
        rows << { intent: intent, target: target, also_named: also_named }
      end
      rows
    end

    def use_options
      physical = unique_records(classifier.offered_for(:use))
      rows = [ { intent: :use, target: nil, also_named: nil } ]
      physical.each do |choice|
        target = label(choice)
        rows << { intent: :use, target: target, also_named: nil }
        secondary_for_use(choice, physical).each do |other|
          rows << { intent: :use, target: target, also_named: label(other) }
        end
      end
      rows
    end

    # Mirrors the special `use` branch in `Playthrough::Classifier#build_intent`:
    # another physical token may be evidence, then an ordinary record not
    # already bound into the selected physical attempt may be evidence.
    def secondary_for_use(choice, physical)
      ordinary = classifier.exits_here + classifier.characters_here +
                 classifier.items_here + classifier.items_carried
      unique_records((physical - [ choice ]) + ordinary.reject { |record| choice.records.include?(record) })
    end

    def unique_records(records)
      records.uniq { |record| [ record.class.name, label(record).to_s.downcase ] }
    end

    def label(record)
      return record.name if record.is_a?(Playthrough::PhysicalAction::Choice)

      Playthrough::Classifier.label_for(record)
    end

    def criterion_for(intent:, target:, also_named:)
      return "The line requests none of the listed engine actions; classify it as `other` with no target." if intent == :other
      if target.nil?
        return "The player is trying to `#{intent}`, but the thing named is absent from that action's exact " \
               "engine-supplied set. Choose `#{intent}` with `nothing`; do not substitute."
      end
      if also_named
        return "The line requests `#{intent}` and explicitly names BOTH `#{target}` and `#{also_named}` from " \
               "that action's engine-supplied set. This is one act naming two distinct records."
      end

      "The line requests `#{intent}` aimed at exactly the engine-supplied choice `#{target}`, and names no " \
      "second record for that act."
    end

    def validate(body, options)
      answer = body.dig("answers", "reading")
      usage = body["usage"]
      keys = options.keys.sort
      probabilities = answer.is_a?(Hash) ? answer["probabilities"] : nil
      valid = body["model"].is_a?(String) && answer.is_a?(Hash) && answer["type"] == "choice" &&
              options.key?(answer["choice"]) && number_between_zero_and_one?(answer["confidence"]) &&
              probabilities.is_a?(Hash) && probabilities.keys.sort == keys &&
              probabilities.values.all? { |value| number_between_zero_and_one?(value) } &&
              probabilities.values.sum.between?(0.99, 1.01) && usage.is_a?(Hash) &&
              usage["input_tokens"].is_a?(Integer) && usage["output_tokens"].is_a?(Integer)
      unless valid
        raise MalformedResponse.new("System One response did not match the requested Choice", receipt: transport_receipt)
      end

      answer
    end

    def number_between_zero_and_one?(value)
      value.is_a?(Numeric) && value.between?(0, 1)
    end
end
