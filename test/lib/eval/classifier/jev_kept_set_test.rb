require "test_helper"
require "zlib"

class Eval::Classifier::JevKeptSetTest < ActiveSupport::TestCase
  SET = "jev-classifier-20260917".freeze
  JEV = Eval::Classifier::JevAgent::ARM_ID
  CURRENT = BaseAgent::REMOTE_MODEL_IDS.first

  test "the kept set is a matched four-repetition measurement on the current corpus" do
    result = kept

    assert_equal Eval::Classifier.digest, result.corpus_digest
    assert_equal Eval::Classifier.corpus.size, result.corpus_size
    assert_equal [ JEV, CURRENT ], result.arms
    assert_equal Eval::Noise::MIN_RUNS, result.reps
    assert_equal 2, result.concurrency
    assert_equal %w[jev-latest mistralai/mistral-medium-3.1], result.answered_by.sort
    assert_empty result.rows, "the compact board file keeps figures; full-result.json.gz keeps every row"
  end

  test "the measured bands and actual System One bill remain reproducible offline" do
    result = kept

    assert_in_delta 0.936, result.spread(:strict_accuracy, arm: JEV).median, 0.0005
    assert_in_delta 0.945, result.spread(:strict_accuracy, arm: CURRENT).median, 0.0005
    assert_in_delta 0.974, result.spread(:refusal_agreement, arm: JEV).median, 0.0005
    assert_in_delta 0.953, result.spread(:refusal_agreement, arm: CURRENT).median, 0.0005
    assert_in_delta 0.48, result.spread(:latency_p95, arm: JEV).median, 0.01
    assert_in_delta 1.07, result.spread(:latency_p95, arm: CURRENT).median, 0.01
    assert_equal({ input_tokens: 3_580_581, output_tokens: 377_269 }, result.actual_usage(JEV))
    assert_in_delta 0.1503844, result.actual_billed_cost(JEV), 0.00000001
  end

  test "every Jev call keeps its exact key-free request and provider receipt" do
    rows = receipts
    expected = 1 + Eval::Noise::MIN_RUNS * Eval::Classifier.corpus.size

    assert_equal expected, rows.size
    assert_equal 1, rows.count { |row| row.fetch("kind") == "warmup" }
    readings = rows.select { |row| row.fetch("kind") == "reading" }
    assert_equal expected - 1, readings.size
    assert_equal readings.size, readings.map { |row| row.values_at("rep", "id") }.uniq.size
    assert readings.all? { |row| row.dig("receipt", "status") == 200 }
    assert readings.all? { |row| row.dig("receipt", "request_id").present? }
    assert readings.all? { |row| row.key?("expected") && row.key?("got") && row.key?("raw") && row.key?("right") }
    assert rows.all? { |row| JSON.generate(row).exclude?("Authorization") }

    manifest = JSON.parse(root.join("run.json").read)
    receipt_usage = rows.each_with_object({ "input_tokens" => 0, "output_tokens" => 0 }) do |row, total|
      usage = row.dig("receipt", "body", "usage")
      total.each_key { |key| total[key] += usage.fetch(key) }
    end
    assert_equal manifest.fetch("jev_calls_in_matched_run"), rows.size,
                 "a dropped receipt must make the kept evidence fail"
    assert_equal manifest.fetch("jev_actual_usage_including_warmup"), receipt_usage,
                 "billable usage must be the sum of the exact provider receipts"
    expected_cost = Eval::Classifier::JevAgent::PRICE.of(receipt_usage.fetch("input_tokens"),
                                                         receipt_usage.fetch("output_tokens"))
    assert_in_delta manifest.fetch("jev_actual_billed_cost_usd"), expected_cost, 0.00000001,
                    "the declared bill must agree with the receipt usage"
    assert_equal 61, rows.map { |row| row.dig("request", "questions", "reading", "criteria")&.size.to_i }.max,
                 "the practical option maximum was accepted and stays below the adapter's 64-choice guard"
  end

  test "the full matched rows, frozen labels and run sources survive beside the compact score" do
    full = Zlib::GzipReader.open(root.join("full-result.json.gz")) { |gzip| JSON.parse(gzip.read) }
    source = Eval::Classifier::Corpus.load(root.join("source/classifier_corpus.yml"))
    manifest = JSON.parse(root.join("run.json").read)

    assert_equal kept.corpus_digest, Eval::Classifier.digest(source)
    assert_equal Eval::Noise::MIN_RUNS * Eval::Classifier.corpus.size * 2,
                 full.fetch("passes").sum { |pass| pass.fetch("readings").size }
    assert_equal kept.arms, full.fetch("arms")
    source_archive = root.join(manifest.fetch("run_source_archive"))
    manifest.fetch("run_source_sha256").each do |path, digest|
      assert_equal digest, Digest::SHA256.file(source_archive.join(path)).hexdigest, path
    end
    manifest.fetch("artifact_sha256").each do |path, digest|
      assert_equal digest, Digest::SHA256.file(root.join(path)).hexdigest, path
    end
  end

  private
    def root = Eval.kept_root.join(SET)
    def kept = Eval::Classifier::Result.load(root)

    def receipts
      Zlib::GzipReader.open(root.join(Eval::Classifier::Result::JEV_RECEIPTS)) do |gzip|
        gzip.each_line.map { |line| JSON.parse(line) }
      end
    end
end
