# Offline check: the kept summary recomputes from readings.json.gz, and the
# prompts/schemas this tree would send still match the package manifest.
# No provider call is allowed.
require "json"
require "zlib"
require "digest"

module DesiresScaleReplay
  extend self

  ROOT = Pathname.new(__dir__)
  MODEL = "mistralai/mistral-medium-3.1".freeze

  def result_from(document)
    Eval::Realization::Result.new(
      name: document["name"], recorded_at: document["recorded_at"],
      corpus_size: document["corpus_size"], corpus_digest: document["corpus_digest"],
      request_identity: document["request_identity"],
      prompt_digest: document["prompt_digest"], prompt_shapes: document["prompt_shapes"],
      prompt_stable: document.fetch("prompt_stable", true),
      instructions_digest: document["instructions_digest"],
      arms: document.fetch("arms"), reps: document["reps"],
      warmups: document["warmups"].to_a, answered_by: document["answered_by"],
      passes: document.fetch("passes").map { |row| Eval::Realization::Result::Stored.new(row) }
    )
  end

  def full_result
    document = Zlib::GzipReader.open(ROOT.join("readings.json.gz")) { |file| JSON.parse(file.read) }
    result_from(document)
  end

  def check_source!
    source = JSON.parse(ROOT.join("source-manifest.json").read)
    source.fetch("source_files").each do |path, expected|
      raise "Producer source changed: #{path}" unless Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    raise "Corpus changed" unless source.fetch("corpus_digest") == Eval::Realization.digest
    offline = Eval::Realization::Version.offline
    raise "Prompt changed" unless source.fetch("prompt_digest") == offline.fetch(:prompt_digest)
    raise "Instructions changed" unless source.fetch("instructions_digest") == offline.fetch(:instructions_digest)
    raise "Schema identity changed" unless source.fetch("schema_request_identity") == Eval::Realization::RequestVersion.offline
    source
  end

  def run
    raise "Use an explicit isolated DATABASE_URL" unless ENV.fetch("DATABASE_URL", "").start_with?("sqlite3:/tmp/")
    check_source!
    full = full_result
    raise "Unexpected model pin" unless full.arms == [ MODEL ]
    raise "Incomplete readings" unless full.rows.size == Eval::Realization.corpus.size * Eval::Noise::MIN_RUNS

    kept = Eval::Realization::Result.load(ROOT)
    raise "Kept set is not a summary" unless kept.rows.empty?

    full.passes.each do |pass|
      recomputed = Eval::Realization::Result.figures_of(pass.rows)
      kept_pass = kept.passes.find { |candidate| candidate.rep == pass.rep && candidate.arm == pass.arm }
      recomputed.each do |key, value|
        unless kept_pass.figures.fetch(key) == value
          raise "Figure drifted for #{key} on rep #{pass.rep}: #{kept_pass.figures[key].inspect} vs #{value.inspect}"
        end
      end
    end

    requests = JSON.parse(ROOT.join("requests.json").read)
    raise "Branch requests drifted" unless requests.fetch("requests") == Eval::Realization::BranchRequests.offline
    raise "Branch request identity drifted" unless requests.fetch("request_identity") ==
      Eval::Realization::BranchRequests.identity(Eval::Realization::BranchRequests.offline)

    puts JSON.pretty_generate(ok: true, readings: full.rows.size, summary_figures: kept.passes.size)
  end
end

DesiresScaleReplay.run
