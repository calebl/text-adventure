# Record a complete four-repetition realization baseline with provider receipts.
# EVAL_PREFLIGHT=1 writes only offline identities. A live run requires an
# isolated database, EVAL_LIVE=1, EVAL_BUDGET_FILE and two sanitized OpenRouter
# credit snapshots supplied by the caller.
require "json"
require "zlib"
require "digest"
require Rails.root.join("db/eval/adversarial-20260909/eval-budget-streaming-v2")
require_relative "payload_gate"

module DesiresRealizationRun
  extend self

  NAME = "desires-realization-20260919".freeze
  ROOT = Rails.root.join("db/eval", NAME)
  MODEL = "mistralai/mistral-medium-3.1".freeze
  SOURCE_FILES = %w[
    app/models/location/generator.rb
    app/models/location/detail_schema.rb
    app/models/location/place_schema.rb
    app/models/location/exits_schema.rb
    app/models/character.rb
    app/models/character/schema.rb
    app/models/character/registry.rb
    app/models/item/registry.rb
    app/agents/BaseAgent.rb
    lib/eval/realization.rb
    lib/eval/realization/bench.rb
    lib/eval/realization/result.rb
    lib/eval/realization/scorer.rb
    lib/eval/realization/stage.rb
    lib/eval/realization/version.rb
    lib/eval/realization/request_version.rb
    lib/eval/realization/branch_requests.rb
    test/fixtures/files/realization_corpus.yml
    Gemfile.lock
  ].freeze

  def canonical(value) = JSON.parse(JSON.generate(value))

  def manifest
    offline = Eval::Realization::Version.offline
    request_identity = Eval::Realization::RequestVersion.offline
    branches = Eval::Realization::BranchRequests.offline
    {
      "package_schema" => 1,
      "producer_commit" => `git rev-parse HEAD`.strip,
      "source_files" => SOURCE_FILES.to_h { |path| [ path, Digest::SHA256.file(Rails.root.join(path)).hexdigest ] },
      "prompt_digest" => offline.fetch(:prompt_digest),
      "instructions_digest" => offline.fetch(:instructions_digest),
      "prompt_shapes" => offline.fetch(:prompt_shapes),
      "schema_request_identity" => request_identity,
      "branch_request_identity" => Eval::Realization::BranchRequests.identity(branches),
      "corpus_digest" => Eval::Realization.digest,
      "corpus_size" => Eval::Realization.corpus.size,
      "model_pin" => { "model" => MODEL, "provider" => "openrouter", "fallbacks" => false },
      "gems" => { "ruby" => RUBY_VERSION, "rails" => Rails.version,
        "ruby_llm" => Gem.loaded_specs.fetch("ruby_llm").version.to_s,
        "sqlite3" => Gem.loaded_specs.fetch("sqlite3").version.to_s },
      "source_measurement" => {
        "set" => "desires-after",
        "realization_sha256" => Digest::SHA256.file(Rails.root.join("db/eval/desires-after/realization.json")).hexdigest,
        "requests_sha256" => Digest::SHA256.file(Rails.root.join("db/eval/desires-after/requests.json")).hexdigest
      }
    }
  end

  def write_preflight!
    FileUtils.mkdir_p(ROOT)
    ROOT.join("source-manifest.json").write(JSON.pretty_generate(manifest) + "\n")
    Eval::Realization::BranchRequests.write!(ROOT, Eval::Realization::BranchRequests.offline)
    puts JSON.pretty_generate(offline: true, model_calls: 0,
      estimate_usd: Eval::Realization.estimate(cases: Eval::Realization.corpus.cases,
        reps: Eval::Noise::MIN_RUNS, models: [ MODEL ]),
      prompt_digest: manifest.fetch("prompt_digest"),
      schema_request_identity: manifest.fetch("schema_request_identity"),
      branch_request_identity: manifest.fetch("branch_request_identity"))
  end

  def verify_source!(source)
    current = manifest
    %w[prompt_digest instructions_digest prompt_shapes schema_request_identity branch_request_identity corpus_digest corpus_size model_pin gems].each do |field|
      raise "Preflight changed: #{field}" unless source.fetch(field) == current.fetch(field)
    end
    source.fetch("source_files").each do |path, digest|
      raise "Measured source changed: #{path}" unless Digest::SHA256.file(Rails.root.join(path)).hexdigest == digest
    end
    requests = JSON.parse(ROOT.join("requests.json").read)
    raise "Branch requests changed after preflight" unless requests.fetch("request_identity") == source.fetch("branch_request_identity")
  end

  def reading_from(row, instructions)
    kase = Eval::Realization.corpus.cases.find { |candidate| candidate.id == row.fetch("id") } or raise "Unknown case"
    values = (Eval::Realization::Bench::Reading.members - [ :kase, :instructions ]).to_h do |field|
      [ field, row.fetch(field.to_s) ]
    end
    Eval::Realization::Bench::Reading.new(kase: kase, instructions: instructions, **values)
  end

  def append(path, document)
    File.open(path, "a") { |file| file.puts(JSON.generate(document)) }
  end

  def run!
    raise "Need exactly four repetitions" unless Eval::Noise::MIN_RUNS == 4
    ReviewEvalBudget.assert_isolated_database!
    source = JSON.parse(ROOT.join("source-manifest.json").read)
    verify_source!(source)
    [ "CREDITS_BEFORE", "CREDITS_AFTER" ].each do |name|
      next if name == "CREDITS_AFTER"
      path = Pathname.new(ENV.fetch(name))
      raise "Missing sanitized OpenRouter credit snapshot" unless path.exist?
    end

    # Reuse the retained receipt helper with this task's stricter authorization.
    ReviewEvalBudget.send(:remove_const, :LIMIT_MICROS)
    ReviewEvalBudget.const_set(:LIMIT_MICROS, 1_500_000)
    ReviewEvalBudget.install!
    expected_system = JSON.parse(Rails.root.join("db/eval/desires-after/realization.json").read)
                          .fetch("passes").first.fetch("readings").first
                          .dig("facts", "requests", 0, "system")
    gate = DesiresRealizationPayload::Gate.new(expected_system: expected_system)
    DesiresRealizationPayload.gate = gate
    BaseAgent.prepend(DesiresRealizationPayload::BeforeBudget) unless BaseAgent.ancestors.include?(DesiresRealizationPayload::BeforeBudget)

    evidence = ROOT.join("provider-readings.jsonl")
    saved = evidence.exist? ? evidence.readlines.map { |line| JSON.parse(line) } : []
    all_labels = saved.map { |document| document.fetch("reading").values_at("id", "rep") }
    labels = saved.reject { |document| document.dig("reading", "error") }
                  .map { |document| document.fetch("reading").values_at("id", "rep") }
    raise "Duplicate successful reading" unless labels.uniq == labels
    permitted = [ [ Eval::Realization.corpus.cases.first.id, 0 ] ] +
      Eval::Realization.corpus.cases.map(&:id).product((1..Eval::Noise::MIN_RUNS).to_a)
    raise "Retained reading outside fixed corpus" unless (all_labels - permitted).empty?

    ledger = ReviewEvalBudget.ledger.snapshot
    attempted = ledger.fetch("entries").map do |entry|
      parts = entry.fetch("label").split(":")
      [ parts.fetch(1), Integer(parts.fetch(2)) ]
    end.uniq
    unresolved = attempted - all_labels
    raise "A charged unfinished reading needs review: #{unresolved.inspect}" if unresolved.any?

    arm = Eval::Classifier::Arm.parse(MODEL)
    bench = Eval::Realization::Bench.new(arms: [ MODEL ], io: nil)
    arm.pinned do
      permitted.each do |id, rep|
        next if labels.include?([ id, rep ])
        kase = Eval::Realization.corpus.cases.find { |candidate| candidate.id == id }
        gate.start!(id, rep)
        ReviewEvalBudget.calls = []
        attempt = all_labels.count([ id, rep ]) + 1
        ReviewEvalBudget.label = "#{NAME}:#{id}:#{rep}:attempt#{attempt}"
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        reading = bench.send(:read, kase, arm, rep)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        document = { "source_manifest_sha256" => Digest::SHA256.file(ROOT.join("source-manifest.json")).hexdigest,
          "reading" => reading.to_h, "instructions" => reading.instructions,
          "provider_calls" => canonical(ReviewEvalBudget.calls) }
        document["warmup"] = { "arm" => MODEL, "seconds" => elapsed, "residency" => arm.keep_resident!, "error" => reading.error } if rep.zero?
        append(evidence, document)
        gate.finish!
        raise "Failed or rotated reading #{id}:#{rep}" if reading.failed? || reading.rotated?
        raise "Receipt count differs for #{id}:#{rep}" unless reading.calls == document.fetch("provider_calls").size
        puts "#{id}:#{rep} recorded (#{reading.calls} call#{reading.calls == 1 ? '' : 's'})"
        $stdout.flush
      end
    end

    attempts = evidence.readlines.map { |line| JSON.parse(line) }
    documents = attempts.reject { |doc| doc.dig("reading", "error") }
    raise "Incomplete package" unless documents.map { |doc| doc.fetch("reading").values_at("id", "rep") }.sort == permitted.sort
    measured = documents.reject { |doc| doc.dig("reading", "rep").zero? }
    passes = measured.group_by { |doc| doc.dig("reading", "rep") }.sort.map do |rep, group|
      ordered = Eval::Realization.corpus.cases.map do |kase|
        doc = group.find { |candidate| candidate.dig("reading", "id") == kase.id }
        reading_from(doc.fetch("reading"), doc.fetch("instructions"))
      end
      Eval::Realization::Bench::Pass.new(arm: MODEL, rep: rep, readings: ordered)
    end
    warmup = documents.find { |doc| doc.dig("reading", "rep").zero? }.fetch("warmup")
    version = Eval::Realization::Version.of(passes)
    raise "Bought prompts differ from preflight" unless version.fetch(:prompt_digest) == source.fetch("prompt_digest") && version.fetch(:prompt_stable)
    result = Eval::Realization::Result.new(name: NAME, recorded_at: Time.now.utc.iso8601,
      corpus_size: Eval::Realization.corpus.size, corpus_digest: Eval::Realization.digest,
      request_identity: Eval::Realization::RequestVersion.offline, arms: [ MODEL ], reps: Eval::Noise::MIN_RUNS,
      passes: passes.map(&:stored), warmups: [ warmup ], **version)
    Zlib::GzipWriter.open(ROOT.join("readings.json.gz")) do |file|
      file.mtime = 0
      file.write(JSON.generate(result.to_h))
    end
    result.summary.write!(ROOT, name: NAME)
    puts JSON.pretty_generate(readings: measured.size, calls: documents.sum { |doc| doc.fetch("provider_calls").size },
      budget: ReviewEvalBudget.ledger.snapshot.slice("limit_micros", "entries"))
  ensure
    DesiresRealizationPayload.gate = nil
  end
end

if ENV["EVAL_PREFLIGHT"] == "1"
  DesiresRealizationRun.write_preflight!
else
  DesiresRealizationRun.run!
end
