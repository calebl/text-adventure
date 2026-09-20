# Replay every paid answer through today's generator, then verify the compact
# baseline was recomputed from those full readings. No provider call is allowed.
require "json"
require "zlib"
require "digest"

module DesiresRealizationReplay
  extend self

  ROOT = Pathname.new(__dir__)
  MODEL = "mistralai/mistral-medium-3.1".freeze

  def documents
    Zlib::GzipReader.open(ROOT.join("provider-readings.jsonl.gz")) do |file|
      file.each_line.map { |line| JSON.parse(line) }
    end
  end

  def offline
    original = Chat.instance_method(:ask)
    Chat.define_method(:ask) { |*| raise "Offline replay attempted a provider call" }
    yield
  ensure
    Chat.define_method(:ask, original)
  end

  def check_source!
    source = JSON.parse(ROOT.join("source-manifest.json").read)
    source.fetch("source_files").each do |path, expected|
      raise "Producer source changed: #{path}" unless Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    raise "Corpus changed" unless source.fetch("corpus_digest") == Eval::Realization.digest
    raise "Prompt changed" unless source.fetch("prompt_digest") == Eval::Realization::Version.offline.fetch(:prompt_digest)
    raise "Schema identity changed" unless source.fetch("schema_request_identity") == Eval::Realization::RequestVersion.offline
    source
  end

  def run
    raise "Use an explicit isolated DATABASE_URL" unless ENV.fetch("DATABASE_URL", "").start_with?("sqlite3:/tmp/")
    check_source!
    attempts = documents
    paid = attempts.reject { |doc| doc.dig("reading", "error") }
    expected = [ [ Eval::Realization.corpus.cases.first.id, 0 ] ] +
      Eval::Realization.corpus.cases.map(&:id).product((1..Eval::Noise::MIN_RUNS).to_a)
    raise "Incomplete readings" unless paid.map { |doc| doc.fetch("reading").values_at("id", "rep") }.sort == expected.sort
    bench = Eval::Realization::Bench.new(arms: [ MODEL ], io: nil)
    request_differences = []

    offline do
      previous_key = RubyLLM.config.openrouter_api_key
      RubyLLM.config.openrouter_api_key ||= "offline-realization-replay"
      begin
        Eval::Classifier::Arm.parse(MODEL).pinned do
          paid.each do |document|
            row = document.fetch("reading")
            kase = Eval::Realization.corpus.cases.find { |candidate| candidate.id == row.fetch("id") }
            Eval::Realization::Stage.open([ kase ], label: "paid desires evidence replay") do |stages|
              standing = stages.fetch(kase.id)
              generator = standing.generator
              slots = row.fetch("facts").fetch("slots").map do |slot|
                { race: standing.story.universe.races.find_by!(name: slot.fetch("race")),
                  age: slot.fetch("age"), sex: slot.fetch("sex") }
              end
              generator.instance_variable_set(:@cast_registry, Character::Registry.new(standing.location, slots: slots))
              generator.singleton_class.prepend(Eval::Realization::BranchRequests::Capture)
              generator.singleton_class.prepend(Eval::Realization::Admissions::Capture)
              requested_step = generator.send(:open_step)
              generator.measured_quest_step = requested_step
              before = standing.story.locations.pluck(:name)
              calls = document.fetch("provider_calls").dup
              generator.define_singleton_method(:ask) do |schema, prompt|
                receipt = calls.shift or raise "Replay made an unpurchased call"
                raise "Current prompt differs from paid request: #{kase.id}" unless prompt == receipt.fetch("prompt")
                current_schema = JSON.parse(JSON.generate(schema.new.to_json_schema))
                recorded_schema = JSON.parse(JSON.generate(receipt.fetch("schema")))
                raise "Current schema differs from paid request: #{kase.id}" unless current_schema == recorded_schema
                raise "Current system differs from paid request: #{kase.id}" unless system_prompt == receipt.fetch("instructions")
                receipt.fetch("answer")
              end
              generator.realize!
              raise "Unused paid answer: #{kase.id}" unless calls.empty?
              captured = generator.measured_requests
              recorded = row.fetch("facts").fetch("requests")
              raise "Captured request count changed: #{kase.id}" unless captured.size == recorded.size
              captured.zip(recorded).each_with_index do |(current, paid_request), index|
                # The provider is deliberately absent, so its assistant message
                # is not appended to this replay chat. Prompt, system and schema
                # still come from today's builders; retained history is the live
                # capture made immediately before the paid call.
                # Live rows crossed JSON before being frozen, while this
                # in-memory replay still has schema symbol keys. Canonicalize
                # exactly as BranchRequests.identity does before comparison.
                left = Eval::Realization::BranchRequests.canonical(current.except("history"))
                right = Eval::Realization::BranchRequests.canonical(paid_request.except("history"))
                next if left == right

                keys = (left.keys | right.keys).select { |key| left[key] != right[key] }
                first = keys.first
                request_differences << { id: kase.id, rep: row.fetch("rep"), call: index + 1, keys: keys }
                puts "REQUEST DIFFERENCE #{kase.id}:#{row.fetch('rep')}:#{index + 1} keys=#{keys.join(',')}"
                puts "  current #{first}: #{JSON.generate(left[first])[0, 300]}"
                puts "  paid    #{first}: #{JSON.generate(right[first])[0, 300]}"
              end
              observed = bench.send(:after, standing, before, requested_step: requested_step)
              raise "Admissions changed: #{kase.id}" unless observed == row.fetch("after")
            end
          end
        end
      ensure
        RubyLLM.config.openrouter_api_key = previous_key
      end
    end

    if request_differences.any?
      summary = request_differences.flat_map { |difference| difference.fetch(:keys) }.tally
      puts "REQUEST DIFFERENCE SUMMARY #{summary.sort.to_h.to_json}"
      raise "Captured requests differ across #{request_differences.size} calls"
    end

    full = Zlib::GzipReader.open(ROOT.join("readings.json.gz")) { |file| JSON.parse(file.read) }
    result = Eval::Realization::Result.load(ROOT)
    recomputed = result.passes.each_with_index.map do |pass, index|
      rows = full.fetch("passes").fetch(index).fetch("readings")
      Eval::Realization::Result.figures_of(rows)
    end
    result.passes.zip(recomputed).each do |pass, figures|
      figures.each { |key, value| raise "Summary changed: #{key}" unless pass.figures.fetch(key) == value }
    end
    puts JSON.pretty_generate(offline: true, provider_calls: 0, budget_writes: 0,
      readings: paid.size, repetitions: result.reps, prompt_digest: result.prompt_digest,
      schema_request_identity: result.request_identity)
  end
end

DesiresRealizationReplay.run
