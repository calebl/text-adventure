# Sends the engine's own arrival request once (`Eval::Arrival::Stage#request`,
# the request a turn walking into the room sends), intercepting only provider
# answers for offline replay, and keeps the description and summary the way a
# written arrival keeps them.
class Eval::Arrival::Bench
  include SanitizesGeneratedText

  def read(kase, rep:, replay: nil)
    Eval::Arrival::Stage.open(kase) do |stage|
      request = stage.request
      facts = stage.facts
      requests = [ request ]
      answer = nil
      error = nil
      begin
        answer = replay || send_arrival(stage, request)
      rescue StandardError => exception
        error = "#{exception.class}: #{exception.message}"
      end
      { "id" => kase.fetch("id"), "rep" => rep, "facts" => facts,
        "requests" => requests, "request_identity" => Eval::RequestIdentity.of(requests),
        "description" => answer && sanitize_string(answer["description"]),
        "summary" => answer && sanitize_string(answer["summary"]), "error" => error }
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

  private

  def send_arrival(stage, request)
    sender = Eval::EngineCalls::Sender.new(stage.game)
    answered = sender.call(request.merge("kind" => "chat", "purpose" => "arrival", "stream" => false))
    raise sender.failure if sender.failure

    answered.fetch("content")
  end
end
