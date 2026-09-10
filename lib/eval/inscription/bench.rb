# Run the real first-read writer in a rolled-back stage. Capture responses at
# RubyLLM's additive after_message callback, BEFORE BaseAgent's verification can
# rewind a rejected answer. A failure still has a receipt and is never scored as
# clean prose. Network failures without usage are explicitly unpriced failures.
class Eval::Inscription::Bench
  def initialize(model: Eval::Cost.default_model, reps: Eval::Noise::MIN_RUNS, io: $stdout)
    @arm = Eval::Classifier::Arm.parse(model)
    @reps = Integer(reps)
    raise ArgumentError, "reps must be positive" unless @reps.positive?
    @io = io
  end

  def run(path)
    raise ArgumentError, "set already exists: #{path}" if path.exist?
    estimate = Eval::Inscription.estimate(model: @arm.id, reps: @reps)
    raise ArgumentError, "estimate exceeds spend ceiling" if estimate.fetch(:dollars) > 2.0
    raise ArgumentError, "OPENROUTER_API_KEY required" if ENV["OPENROUTER_API_KEY"].blank?

    requests = Eval::Inscription.requests
    data = { "recorded_at" => Time.now.utc.iso8601, "model" => @arm.id, "reps" => @reps,
             "corpus_digest" => Eval::Inscription.digest, "estimate" => estimate,
             "request_identity" => Eval::RequestIdentity.of(requests),
             "case_identities" => requests.transform_values { |request| Eval::RequestIdentity.of(request) },
             "rows" => [] }
    FileUtils.mkdir_p(path.dirname)
    @arm.pinned do
      (1..@reps).each do |rep|
        Eval::Inscription.cases.each do |kase|
          row = Eval::Inscription.stage(kase) { |inscriber| read(inscriber, kase, rep) }
          data.fetch("rows") << row
          File.write(path, JSON.pretty_generate(data) + "\n")
          @io&.puts "rep #{rep} #{kase.fetch('id')}: #{row['error'] || 'recorded'}"
          # Unreported usage cannot be budgeted honestly; keep evidence and stop.
          raise "missing receipt; stopping spend" if row.fetch("receipts").empty?
          raise "spend ceiling reached" if data.fetch("rows").sum { |r| r.fetch("dollars") } + estimate.fetch(:dollars) / (@reps * requests.size) > 2.0
        end
      end
    end
    data
  end

  def read(inscriber, kase, rep)
    row = { "id" => kase.fetch("id"), "story" => kase.fetch("story"), "rep" => rep,
            "description" => inscriber.item.description, "request" => Eval::Inscription.request(inscriber),
            "actual_prompt" => inscriber.send(:prompt), "receipts" => [], "human_fit" => nil, "human_note" => nil }
    inscriber.agent.chat.to_llm.after_message do |message|
      next unless message.role.to_s == "assistant"

      row["raw"] = message.content
      row.fetch("receipts") << { "model" => message.model_id, "input_tokens" => message.input_tokens.to_i,
                                 "output_tokens" => message.output_tokens.to_i, "cached_tokens" => message.cached_tokens.to_i,
                                 "cache_creation_tokens" => message.cache_creation_tokens.to_i }
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      row["text"] = inscriber.inscribe!
      row["template_text"] = inscriber.item.template.reload.inscription
      raise "pinning failed" unless row.fetch("receipts").all? { |receipt| receipt.fetch("model") == @arm.model }
    rescue StandardError => error
      row["error"] = "#{error.class}: #{error.message}"
    ensure
      row["seconds"] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      # Price cached tokens as full input: conservative and reproducible from
      # the stored registry price, even where the message table drops them.
      row["dollars"] = row.fetch("receipts").sum do |receipt|
        @arm.price.of(receipt.values_at("input_tokens", "cached_tokens", "cache_creation_tokens").sum,
                      receipt.fetch("output_tokens"))
      end
    end
    row
  end
end
