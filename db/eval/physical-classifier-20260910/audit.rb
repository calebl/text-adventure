# Offline diagnosis, separate from either standing corpus. The historical run
# retained scored rows in tmp/eval; its exact bytes are kept compressed here.
# Adapt those recorded flags to the existing Bench::Pass arithmetic, validate
# every full-pass metric against the unchanged kept summary, then exclude the
# same five amended labels on both sides. No scoring rule is added or changed.
require_relative "evaluate"
require "zlib"

module PhysicalClassifierStudy
  module Audit
    HistoricalReading = Data.define(:row) do
      def failed? = !row["error"].nil?
      def right? = row.fetch("right")
      def intent_right? = row.fetch("intent_right")
      def arguable? = row.fetch("arguable")
      def refusal_right? = row.fetch("refusal_right")
      def closed_set_miss? = row.fetch("closed_set_miss")
      def seconds = row["seconds"]
    end

    def self.run(root: Pathname.new(__dir__), after_root: root)
      old_bytes = Zlib::GzipReader.open(root.join("historical-before-full.json.gz"), &:read)
      old = JSON.parse(old_bytes)
      kept = JSON.parse(Eval.kept_root.join("classifier-2026-09-10/classifier.json").read)
      raise "Historical metadata changed" unless old.except("passes") == kept.except("passes")
      historical = Eval::Classifier::Corpus.load(root.join("historical-339-corpus.yml"))
      current = Eval::Classifier::Corpus.load(after_root.join("source/classifier_corpus.yml"))
      labels = historical.lines.index_by(&:id)
      changed = labels.values.select { |line| line.answers != current.lines.find { |item| item.id == line.id }.answers }.map(&:id).sort
      ids = labels.keys.sort - changed
      raw = Zlib::GzipReader.open(after_root.join("readings.jsonl.gz")) { |file| file.each_line.map { |line| JSON.parse(line) } }
      after = raw.reject { |row| row.fetch("rep").zero? }.map { |row| PhysicalClassifierStudy.reading(row, current) }
      before_passes = old.fetch("passes").map do |pass|
        rows = pass.fetch("readings")
        raise "Incomplete historical pass" unless rows.map { |row| row.fetch("id") }.sort == labels.keys.sort
        rows.each do |row|
          line = labels.fetch(row.fetch("id"))
          raise "Historical line changed" unless row.fetch("typed") == line.typed && row.fetch("expected") == line.answers.map(&:to_s)
        end
        rebuilt = Eval::Classifier::Bench::Pass.new(arm: pass.fetch("arm"), rep: pass.fetch("rep"),
          readings: rows.map { |row| HistoricalReading.new(row) })
        summary = kept.fetch("passes").find { |entry| entry.fetch("rep") == pass.fetch("rep") }
        Eval::Classifier::Result::METRICS.each_key do |metric|
          raise "Historical #{metric} changed" unless rebuilt.public_send(metric).round(4) == summary.fetch(metric.to_s)
        end
        Eval::Classifier::Bench::Pass.new(arm: pass.fetch("arm"), rep: pass.fetch("rep"),
          readings: rebuilt.readings.select { |reading| ids.include?(reading.row.fetch("id")) })
      end
      after_passes = (1..REPS).map do |rep|
        selected = after.select { |reading| reading.rep == rep && ids.include?(reading.id) }
        raise "Incomplete unchanged after pass" unless selected.map(&:id).sort == ids
        Eval::Classifier::Bench::Pass.new(arm: MODEL, rep: rep, readings: selected)
      end
      shared = { corpus_size: ids.size, arms: [ MODEL ], reps: REPS, corpus_digest: "unchanged-#{ids.size}" }
      before_result = Eval::Classifier::Result.new(**shared, passes: before_passes, concurrency: old.fetch("concurrency"))
      after_result = Eval::Classifier::Result.new(**shared, passes: after_passes, concurrency: JSON.parse(after_root.join("classifier.json").read).fetch("concurrency"))
      comparison = Eval::Classifier::Comparison.new(before_result, after_result, io: nil)
      old_rows = old.fetch("passes").flat_map { |pass| pass.fetch("readings") }
      misses = after.reject(&:right?).group_by(&:id).sort_by { |id, rows| [ -rows.size, id ] }.map do |id, rows|
        prior = old_rows.select { |row| row.fetch("id") == id }
        { "id" => id, "typed" => rows.first.line.typed, "current_expected" => rows.first.line.answers.map(&:to_s),
          "current_misses" => rows.size, "current_wrong_answers" => rows.map { |row| row.answer.to_s }.tally,
          "label_changed" => changed.include?(id), "before_right" => prior.count { |row| row.fetch("right") },
          "before_answers" => prior.map { |row| row.fetch("got") }.tally }
      end
      { "historical_source" => "/home/calebl/.treehouse/text-adventure-b5f921/1/text-adventure/tmp/eval/classifier-2026-09-10/classifier.json",
        "source_discovered_in" => "doc/evidence/ta-bench-rebaseline-stale/classifier-run.log",
        "historical_sha256" => Digest::SHA256.hexdigest(old_bytes),
        "historical_full_metrics_match_kept_summary" => true,
        "excluded_label_ids" => changed, "unchanged_cases" => ids.size,
        "before_unarguable_cases" => before_passes.map { |pass| pass.unarguable.size },
        "after_unarguable_cases" => after_passes.map { |pass| pass.unarguable.size },
        "before_values" => comparison.judged_metrics.index_with { |metric| before_result.values(metric) },
        "after_values" => comparison.judged_metrics.index_with { |metric| after_result.values(metric) },
        "suppressed_metrics" => Eval::Classifier::Result::METRICS.keys - comparison.judged_metrics,
        "unchanged_verdicts" => comparison.verdicts(MODEL).map { |row| { "metric" => row.metric, "direction" => row.direction, "verdict" => row.verdict.to_h } },
        "current_label_misses" => misses }
    end
  end
end

if ENV["PHYSICAL_CLASSIFIER_MODE"] == "audit"
  EngineSweep.without_a_model do
    result = PhysicalClassifierStudy::Audit.run
    File.write(File.join(__dir__, "audit.json"), JSON.pretty_generate(result) + "\n")
    puts "Historical complete pass metrics validated; unchanged #{result.fetch('unchanged_cases')} cases compared without new calls."
  end
end
