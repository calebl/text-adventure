# Both passes run InteractionAgent#ask, including sanitization, engine validation
# and narration fallback. Replay substitutes only BaseAgent's provider answer;
# it rebuilds each request with today's application and the stored first-pass
# response. Thus nondeterministic reactions do not prevent a byte-level check
# of the narrator request. Full history (even empty) and emitted schemas remain
# in every receipt; no normalization erases IDs or descriptor changes.
class Eval::Dialogue::Bench
  Response = Data.define(:content)

  def read(kase, rep:, replay: nil)
    Eval::Dialogue::Stage.open(kase) do |stage|
      exchange = InteractionAgent.new(stage.npc, playthrough: stage.game)
      requests = []
      answers = replay&.fetch("calls")&.map { |call| call.fetch("raw_answer", call["answer"]) }
      [ exchange.character_agent, exchange.narrator_agent ].each do |agent|
        original = agent.method(:ask)
        agent.define_singleton_method(:ask) do |prompt, **options, &block|
          request = Eval::Dialogue::Version.request(self, prompt)
          requests << request
          if answers
            content = answers.shift
            options[:verify]&.call(content)
            response = Response.new(content: content)
          else
            response = original.call(prompt, **options, &block)
          end
          stage.after_character! if purpose == Chat::CHARACTER
          response
        end
      end
      error = nil
      result = nil
      begin
        result = exchange.ask(kase.fetch("line"))
      rescue StandardError => exception
        error = "#{exception.class}: #{exception.message}"
      end
      immediate = stage.facts(effect: result&.effect)
      stage.after_exchange!
      facts = stage.facts(effect: result&.effect)
      { "id" => kase.fetch("id"), "rep" => rep, "expected" => kase.fetch("expected"),
        "requests" => requests, "request_digest" => Eval::Dialogue::Version.digest(requests),
        "reaction" => result&.reaction&.stringify_keys, "narration" => result&.narration,
        "effect" => result&.effect&.to_h&.stringify_keys, "immediate" => immediate, "facts" => facts,
        "error" => error || result&.rendering_error&.class&.name, "fallback" => result&.fallback? || false }
    end
  end

  def run(directory, reps: Eval::Noise::MIN_RUNS)
    raise ArgumentError, "reps must reach Eval::Noise::MIN_RUNS" if reps < Eval::Noise::MIN_RUNS
    Eval::Dialogue::Budget.assert_isolated_database!
    estimate = Eval::Dialogue.estimate(reps: reps)
    raise ArgumentError, "estimate exceeds budget" if estimate.fetch(:estimated_usd) > Eval::Dialogue::Budget::LIMIT_MICROS / 1_000_000.0
    FileUtils.mkdir_p(directory)
    file = Pathname.new(directory).join(Eval::Dialogue::RESULTS)
    raise ArgumentError, "set already exists: #{file}" if file.exist?
    data = { "model" => Eval::Dialogue.model, "reps" => reps, "corpus_digest" => Eval::Dialogue.digest,
      "recorded_at" => Time.now.utc.iso8601, "estimate" => estimate, "rows" => [] }
    File.write(file, JSON.pretty_generate(data))
    Eval::Dialogue::Budget.install!
    (1..reps).each do |rep|
      Eval::Dialogue.cases.each do |kase|
        Eval::Dialogue::Budget.label = "#{kase.fetch('id')}:#{rep}"
        Eval::Dialogue::Budget.calls = []
        row = read(kase, rep: rep)
        row["calls"] = Eval::Dialogue::Budget.calls
        data["rows"] << row
        data["budget"] = Eval::Dialogue::Budget.ledger.snapshot
        File.write(file, JSON.pretty_generate(data) + "\n")
        puts "#{kase.fetch('id')}:#{rep} #{row['error'] || 'recorded'}"
        $stdout.flush
      end
    end
    data
  end
end
