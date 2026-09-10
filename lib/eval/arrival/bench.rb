# Calls the production generator once, intercepting only provider answers for
# offline replay. Request capture occurs at ask, after with_schema; equality
# with Stage#request prevents the digest task from measuring a parallel builder.
class Eval::Arrival::Bench
  Response = Data.define(:content)

  def read(kase, rep:, replay: nil)
    Eval::Arrival::Stage.open(kase) do |stage|
      expected = stage.request
      facts = stage.facts
      generator = stage.generator
      agent = generator.agent
      original = agent.method(:ask)
      requests = []
      agent.define_singleton_method(:ask) do |prompt, **options, &block|
        request = { "system" => instructions, "user" => prompt,
          "schema" => JSON.parse(JSON.generate(schema.new.to_json_schema)),
          "history" => chat.messages.order(:id).reject { |m| m.role == "system" }.map { |m| { "role" => m.role, "content" => m.text } } }
        raise "Arrival request differs from offline builder" unless request == expected
        requests << request
        replay ? Response.new(content: replay) : original.call(prompt, **options, &block)
      end
      scene = nil
      error = nil
      begin
        scene = generator.generate!
      rescue StandardError => exception
        error = "#{exception.class}: #{exception.message}"
      end
      { "id" => kase.fetch("id"), "rep" => rep, "facts" => facts,
        "requests" => requests, "request_identity" => Eval::RequestIdentity.of(requests),
        "description" => scene&.description, "summary" => scene&.summary, "error" => error }
    end
  end

  def run(directory, reps: Eval::Noise::MIN_RUNS)
    raise ArgumentError, "reps must reach Eval::Noise::MIN_RUNS" if reps < Eval::Noise::MIN_RUNS
    Eval::Arrival::Budget.assert_isolated_database!
    estimate = Eval::Arrival.estimate(reps: reps)
    raise ArgumentError, "estimate exceeds budget" if estimate.fetch(:estimated_usd) > 2
    FileUtils.mkdir_p(directory)
    file = Pathname.new(directory).join(Eval::Arrival::RESULTS)
    raise ArgumentError, "set already exists: #{file}" if file.exist?
    data = { "model" => Eval::Arrival.model, "reps" => reps, "corpus_digest" => Eval::Arrival.digest,
      "recorded_at" => Time.now.utc.iso8601, "estimate" => estimate, "rows" => [] }
    Eval::Arrival::Budget.install!
    (1..reps).each do |rep|
      Eval::Arrival.cases.each do |kase|
        Eval::Arrival::Budget.label = "#{kase.fetch('id')}:#{rep}"
        Eval::Arrival::Budget.calls = []
        row = read(kase, rep: rep)
        row["calls"] = Eval::Arrival::Budget.calls
        data["rows"] << row
        data["budget"] = Eval::Arrival::Budget.ledger.snapshot
        File.write(file, JSON.pretty_generate(data) + "\n")
        puts "#{kase.fetch('id')}:#{rep} #{row['error'] || 'recorded'}"
        $stdout.flush
      end
    end
    data
  end
end
