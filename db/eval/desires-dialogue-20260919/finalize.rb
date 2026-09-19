# Promote the already complete desires dialogue recording without another paid
# call. The source result retains every request, answer, engine fact, receipt and
# budget entry; this script adds the package-level provenance and comparisons.
require "json"
require "digest"

module DesiresDialogueFinalize
  extend self

  NAME = "desires-dialogue-20260919".freeze
  ROOT = Rails.root.join("db/eval", NAME)
  SOURCE = Rails.root.join("db/eval/desires-after/dialogue.json")
  BEFORE = Rails.root.join("db/eval/physical-dialogue-20260910")
  MATCHED_BEFORE = Rails.root.join("db/eval/desires-before")
  SOURCE_FILES = %w[
    app/models/character.rb
    app/models/playthrough/moment.rb
    app/models/playthrough/npc_action.rb
    app/agents/InteractionAgent.rb
    app/agents/BaseAgent.rb
    lib/eval/dialogue.rb
    lib/eval/dialogue/bench.rb
    lib/eval/dialogue/result.rb
    lib/eval/dialogue/stage.rb
    lib/eval/dialogue/version.rb
    test/fixtures/files/dialogue_corpus.json
    Gemfile.lock
  ].freeze

  def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))

  def run
    data = JSON.parse(SOURCE.read)
    data.fetch("budget")["task_accounted_micros"] =
      data.dig("budget", "entries").sum { |entry| entry.fetch("accounted_micros") }
    result = Eval::Dialogue::Result.new(data)
    result.validate_complete!
    raise "Wrong model" unless data.fetch("model") == Eval::Dialogue.model
    raise "Wrong corpus" unless data.fetch("corpus_digest") == Eval::Dialogue.digest
    raise "Too few repetitions" if data.fetch("reps") < Eval::Noise::MIN_RUNS
    raise "Requests no longer replay" unless result.rows.all? { |row|
      rebuilt = Eval::Dialogue::Version.rebuild(row)
      rebuilt.fetch("requests") == row.fetch("requests") && rebuilt.fetch("facts") == row.fetch("facts")
    }

    FileUtils.mkdir_p(ROOT)
    ROOT.join("dialogue.json").write(JSON.pretty_generate(data) + "\n")
    old = Eval::Dialogue::Result.load(BEFORE)
    matched = Eval::Dialogue::Result.load(MATCHED_BEFORE)
    comparison = old.compare(result)
    ROOT.join("before-board.json").write(JSON.pretty_generate(old.board) + "\n")
    ROOT.join("after-board.json").write(JSON.pretty_generate(result.board) + "\n")
    ROOT.join("comparison.json").write(JSON.pretty_generate({
      "orientation" => "physical-dialogue-20260910 -> #{NAME}", "verdicts" => comparison
    }) + "\n")
    ROOT.join("matched-comparison.json").write(JSON.pretty_generate({
      "orientation" => "desires-before -> #{NAME}", "verdicts" => matched.compare(result)
    }) + "\n")

    calls = result.rows.flat_map { |row| row.fetch("calls") }
    budget = data.fetch("budget")
    receipts = {
      "price_basis" => "Per-call registry prices and provider-reported prices retained by the source recording; conservative budget accounting is separate.",
      "readings" => result.rows.size,
      "calls" => calls.size,
      "input_tokens" => calls.sum { |call| call.fetch("input_tokens") },
      "output_tokens" => calls.sum { |call| call.fetch("output_tokens") },
      "actual_models" => calls.map { |call| call.fetch("actual_model") }.uniq.sort,
      "registry_priced_usd" => calls.sum { |call| call.fetch("registry_cost_usd").to_f },
      "provider_reported_partial_usd" => calls.sum { |call| call.fetch("provider_cost_usd").to_f },
      "provider_cost_available_calls" => calls.count { |call| call["provider_cost_usd"] },
      "budget" => budget,
      "task_accounted_micros" => budget.fetch("entries").sum { |entry| entry.fetch("accounted_micros") }
    }
    ROOT.join("receipts.json").write(JSON.pretty_generate(receipts) + "\n")

    requests = result.rows.flat_map { |row| row.fetch("requests") }
    schemas = requests.filter_map { |request| request["schema"] }
    manifest = {
      "package_schema" => 1,
      "producer_commit" => `git rev-parse HEAD`.strip,
      "source_files" => SOURCE_FILES.to_h { |path| [ path, Digest::SHA256.file(Rails.root.join(path)).hexdigest ] },
      "source_measurement" => { "set" => "desires-after", "sha256" => Digest::SHA256.file(SOURCE).hexdigest },
      "corpus_digest" => data.fetch("corpus_digest"),
      "request_bundle_digest" => digest(requests),
      "prompt_digest" => digest(requests.map { |request| request.values_at("system", "user", "history") }),
      "schema_digest" => digest(schemas),
      "model_pin" => { "model" => data.fetch("model"), "provider" => "openrouter", "fallbacks" => false },
      "gems" => { "ruby" => RUBY_VERSION, "rails" => Rails.version,
        "ruby_llm" => Gem.loaded_specs.fetch("ruby_llm").version.to_s,
        "sqlite3" => Gem.loaded_specs.fetch("sqlite3").version.to_s }
    }
    ROOT.join("source-manifest.json").write(JSON.pretty_generate(manifest) + "\n")
    provenance = {
      "completed_at" => data.fetch("recorded_at"),
      "promoted_at" => Time.now.utc.iso8601,
      "producer_commit" => manifest.fetch("producer_commit"),
      "source_measurement_sha256" => manifest.dig("source_measurement", "sha256"),
      "repetitions" => data.fetch("reps"), "cases" => Eval::Dialogue.cases.size,
      "readings" => result.rows.size, "calls" => calls.size,
      "reused_paid_readings" => true,
      "new_model_calls" => 0,
      "limitations" => [
        "Contradiction remains unavailable because this recording has no signed human annotations.",
        "This corpus does not measure voice, memory fidelity across turns, long-term behavior or general realism.",
        "Promotion adds provenance around unchanged paid readings; it is not a second independent sample."
      ]
    }
    ROOT.join("run-provenance.json").write(JSON.pretty_generate(provenance) + "\n")
    puts JSON.pretty_generate(readings: result.rows.size, calls: calls.size, model_calls: 0,
      request_bundle_digest: manifest.fetch("request_bundle_digest"), comparison: comparison)
  end
end

DesiresDialogueFinalize.run
