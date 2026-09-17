# Assemble and rescore the unchanged paid legacy cases plus the newly purchased
# branches. Schemas/history on legacy rows are derived from paid receipts, never
# fabricated from today's classes. Offline fingerprints are labeled separately.
# No provider calls are allowed; an explicit isolated database serves staging.
require "json"
require "zlib"
require "digest"
require_relative "support"

module PhysicalRealizationReplay
  ROOT = Pathname.new(__dir__)
  ARM = "mistralai/mistral-medium-3.1".freeze
  NAME = "physical-realization-20260910".freeze

  def self.json(path) = JSON.parse(ROOT.join(path).read)
  def self.documents(path)
    Zlib::GzipReader.open(ROOT.join(path)) { |file| file.each_line.map { |line| JSON.parse(line) } }
  end

  def self.check_source!
    source = json("source-manifest.json")
    source.fetch("files").each do |path, sha|
      raise "Current producer/staging source changed: #{path}" unless Digest::SHA256.file(Rails.root.join(path)).hexdigest == sha
    end
    source.fetch("legacy_files").each do |path, sha|
      raise "Legacy evidence changed: #{path}" unless Digest::SHA256.file(ROOT.join(path)).hexdigest == sha
    end
    old = YAML.safe_load(ROOT.join("legacy/corpus.yml").read).fetch("cases")
    current = YAML.safe_load(File.read(Eval::Realization::CORPUS)).fetch("cases")
    raise "A reused case changed" unless old.all? { |kase| current.find { |now| now.fetch("id") == kase.fetch("id") } == kase }
    source
  end

  def self.request_records(document)
    row = document.fetch("reading")
    calls = document.fetch("provider_calls")
    raise "Missing call evidence" unless calls.size == row.fetch("calls")
    history = []
    calls.map do |call|
      name = row.fetch("prompts").key(call.fetch("prompt"))
      raise "Missing exact paid prompt" unless name
      raise "Mismatched system" unless call.fetch("instructions") == document.fetch("instructions")
      raise "Mismatched answer" unless call.fetch("raw_answer") == row.fetch("answers").fetch(name)
      raise "Provider rotated or failed" unless call.fetch("actual_model") == ARM && !call["error"]
      request = { "system" => call.fetch("instructions"), "user" => call.fetch("prompt"),
                  "schema" => call.fetch("schema"), "history" => history.deep_dup }
      history << { "role" => "user", "content" => call.fetch("prompt") }
      history << { "role" => "assistant", "content" => JSON.generate(call.fetch("raw_answer")) }
      Eval::Realization::BranchRequests.canonical(request)
    end
  end

  def self.reading(document, legacy:)
    row = document.fetch("reading").deep_dup
    raise "Failed or wrong-model reading" unless row["error"].nil? && row.fetch("answered_by") == ARM && row.fetch("arm") == ARM
    requests = request_records(document)
    if legacy
      row.fetch("facts")["requests"] = requests
      row.fetch("facts")["request_identity"] = Eval::Realization::BranchRequests.identity(requests)
      row.fetch("facts")["request_evidence"] = "Derived from paid provider receipts and Message#extract_content JSON serialization; not captured by the historical bench."
    else
      actual = row.fetch("facts").fetch("requests")
      raise "Missing captured branch request" unless actual.one? && requests.one?
      # Retry history was actually captured before asking exits. Its accepted
      # detail is a fixed fixture, not a new paid answer to reconstruct here.
      raise "Captured branch payload differs from provider receipt" unless actual.first.except("history") == requests.first.except("history")
      expected = json("requests.json").fetch("requests").fetch(row.fetch("id"))
      raise "First branch request differs from inspected bytes" unless actual.first == expected
    end
    kase = Eval::Realization.corpus.cases.find { |candidate| candidate.id == row.fetch("id") }
    raise "Unknown reading" unless kase
    values = (Eval::Realization::Bench::Reading.members - [ :kase, :instructions ]).to_h { |field| [ field, row.fetch(field.to_s) ] }
    Eval::Realization::Bench::Reading.new(kase: kase, instructions: document.fetch("instructions"), **values)
  end

  def self.check_legacy_execution!(documents)
    bench = Eval::Realization::Bench.new(arms: [ ARM ], io: nil)
    documents.each do |document|
      row = document.fetch("reading")
      next if row.fetch("rep").zero?
      kase = Eval::Realization.corpus.cases.find { |candidate| candidate.id == row.fetch("id") }
      Eval::Realization::Stage.open([ kase ], label: "paid evidence replay") do |stages|
        standing = stages.fetch(kase.id)
        generator = standing.generator
        slots = row.fetch("facts").fetch("slots").map do |slot|
          { race: standing.story.universe.races.find_by!(name: slot.fetch("race")),
            age: slot.fetch("age"), sex: slot.fetch("sex") }
        end
        generator.instance_variable_set(:@cast_registry, Character::Registry.new(standing.location, slots: slots))
        generator.singleton_class.prepend(Eval::Realization::Admissions::Capture)
        before = standing.story.locations.pluck(:name)
        paid = document.fetch("provider_calls").dup
        generator.define_singleton_method(:ask) do |schema, prompt|
          receipt = paid.shift || raise("Replay made an unpurchased call")
          raise "Current prompt differs from paid request: #{kase.id}" unless prompt == receipt.fetch("prompt")
          raise "Current schema differs from paid request: #{kase.id}" unless Eval::Realization::BranchRequests.canonical(schema.new.to_json_schema) == receipt.fetch("schema")
          raise "Current system differs from paid request" unless system_prompt == receipt.fetch("instructions")
          receipt.fetch("answer")
        end
        generator.realize!
        raise "Unused paid answer" unless paid.empty?
        observed = bench.send(:after, standing, before)
        # The earlier bench did not record quest observations; these cases have
        # no quest branch. Compare every field it did record without adding facts.
        raise "Current admissions differ from paid result: #{kase.id}" unless observed.slice(*row.fetch("after").keys) == row.fetch("after")
      end
    end
  end

  def self.write_gzip(path, value)
    Zlib::GzipWriter.open(ROOT.join(path)) do |file|
      file.mtime = 0
      file.write(JSON.generate(value))
    end
  end

  def self.run
    raise "Use an explicit isolated DATABASE_URL" unless ENV.fetch("DATABASE_URL", "").start_with?("sqlite3:/tmp/")
    source = check_source!
    legacy_docs = documents("legacy/provider-readings.jsonl.gz")
    raise "Wrong legacy source" unless legacy_docs.all? { |doc| doc.fetch("source") == source.fetch("legacy_source") }
    expected_legacy = YAML.safe_load(ROOT.join("legacy/corpus.yml").read).fetch("cases").map { |row| row.fetch("id") }
    expected_labels = expected_legacy.product((1..Eval::Noise::MIN_RUNS).to_a) + [ [ "hour-long-hallway", 0 ] ]
    labels = legacy_docs.map { |doc| doc.fetch("reading").values_at("id", "rep") }
    raise "Incomplete or duplicated legacy readings" unless labels.sort == expected_labels.sort
    legacy = legacy_docs.map { |doc| reading(doc, legacy: true) }
    PhysicalRealizationEvidence.offline do
      previous_key = RubyLLM.config.openrouter_api_key
      RubyLLM.config.openrouter_api_key ||= "offline-provenance-replay"
      begin
        Eval::Classifier::Arm.parse(ARM).pinned { check_legacy_execution!(legacy_docs) }
      ensure
        RubyLLM.config.openrouter_api_key = previous_key
      end
    end
    puts "88 paid legacy realizations replayed: current prompt/schema and recorded admissions match."
    return if ENV["LEGACY_ONLY"] == "1"

    branch_docs = documents("branch-provider-readings.jsonl.gz")
    raise "Wrong branch source" unless branch_docs.all? { |doc| doc.fetch("source") == source.fetch("source_sha256") }
    branches = branch_docs.map { |doc| reading(doc, legacy: false) }
    all = legacy.reject { |row| row.rep.zero? } + branches
    wanted = Eval::Realization.corpus.cases.map(&:id).product((1..Eval::Noise::MIN_RUNS).to_a)
    raise "Incomplete or duplicate combined corpus" unless all.map { |row| [ row.id, row.rep ] }.sort == wanted.sort
    passes = all.group_by(&:rep).sort.map do |rep, readings|
      ordered = Eval::Realization.corpus.cases.map { |kase| readings.find { |row| row.id == kase.id } }
      Eval::Realization::Bench::Pass.new(arm: ARM, rep: rep, readings: ordered)
    end
    offline = json("offline-identities.json")
    version = Eval::Realization::Version.of(passes)
    raise "Actual prompt version differs from offline scaffold" unless version.fetch(:prompt_digest) == offline.fetch("legacy").fetch("prompt_digest") && version.fetch(:prompt_stable)
    identities = PhysicalRealizationEvidence.offline do
      [ Eval::Realization::RequestVersion.offline, Eval::Realization::BranchRequests.offline ]
    end
    raise "Current schema scaffold changed" unless identities.first == offline.fetch("request_identity")
    raise "Current branch bytes changed" unless identities.last == json("requests.json").fetch("requests")
    old_result = Zlib::GzipReader.open(ROOT.join("legacy/full-result.json.gz")) { |file| JSON.parse(file.read) }
    result = Eval::Realization::Result.new(name: NAME, recorded_at: json("run-provenance.json").fetch("completed_at"),
      corpus_size: Eval::Realization.corpus.size, corpus_digest: Eval::Realization.digest,
      request_identity: identities.first, arms: [ ARM ], reps: Eval::Noise::MIN_RUNS,
      passes: passes.map(&:stored), warmups: old_result.fetch("warmups"), **version)
    write_gzip("readings.json.gz", result.to_h)
    result.summary.write!(ROOT)
    before = Eval::Realization::Result.load(Eval.kept_root.join("branches-to-corpus-after"))
    comparison = Eval::Realization::Comparison.new(before, result)
    raise "Mismatched comparison corpus" unless comparison.comparable_corpus?
    File.open(ROOT.join("comparison.txt"), "w") { |file| Eval::Realization::Comparison.new(before, result, io: file).print }
    verdicts = comparison.verdicts(ARM).map { |row| row.verdict.to_h.merge(direction: row.direction) }
    ROOT.join("verdicts.json").write(JSON.pretty_generate(verdicts) + "\n")
    admissions = PhysicalRealizationEvidence.offline do
      result.rows.select { |row| row.dig("facts", "quest_request") }.map do |row|
        replayed = Eval::Realization::Admissions.replay(row)
        raise "Quest admission changed" unless replayed == row.fetch("after").fetch("quest_admitted")
        { id: row.fetch("id"), rep: row.fetch("rep"), admitted: replayed, final_bound: row.fetch("after").fetch("quest_bound") }
      end
    end
    ROOT.join("admissions.json").write(JSON.pretty_generate({ source_sha256: source.fetch("source_sha256"), model_calls: 0, admissions: admissions }) + "\n")
    puts JSON.pretty_generate({ rooms: result.corpus_size, repetitions: result.reps,
      request_identity: result.request_identity, non_noise: verdicts.reject { |row| row.fetch(:outcome) == :noise } })
  end
end

PhysicalRealizationReplay.run
