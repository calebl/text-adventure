require "test_helper"
require "zlib"

class Eval::Classifier::JevResultTest < ActiveSupport::TestCase
  test "System One evidence, actual cost and exact receipts survive persistence" do
    right_line = line(id: "right", intent: :move, target: "Hall")
    wrong_line = line(id: "wrong", intent: :talk, target: "Maren Vale")
    pass = Eval::Classifier::Bench::Pass.new(
      arm: Eval::Classifier::JevAgent::ARM_ID, rep: 1,
      readings: [
        reading(right_line, answer: answer(:move, "Hall"), confidence: 0.91, input: 2_000, right_key: "choice_1"),
        reading(wrong_line, answer: answer(:other), confidence: 0.72, input: 3_000, right_key: "choice_2")
      ]
    )
    warmup = Eval::Classifier::Bench::Warmup.new(
      arm: Eval::Classifier::JevAgent::ARM_ID, seconds: 0.4, residency: :not_local, error: nil,
      usage: { "input_tokens" => 100, "output_tokens" => 10 }, billed_cost: 0.0000042,
      request: { "model" => "jev-latest" }, receipt: { "status" => 200, "body" => { "model" => "jev" } }
    )
    result = Eval::Classifier::Result.new(
      corpus_size: 2, corpus_digest: "digest", arms: [ Eval::Classifier::JevAgent::ARM_ID ],
      reps: 1, passes: [ pass ], warmups: [ warmup ], concurrency: 1
    )

    evidence = pass.jev_evidence
    assert_equal 0.5, evidence.dig(:floors, "0.6", :wrong_rate)
    assert_equal 1, evidence.dig(:floors, "0.6", :wrong)
    assert_equal 0.0, evidence[:low_confidence_fallback_rate]
    assert_equal({ input_tokens: 5_100, output_tokens: 30 }, result.actual_usage(Eval::Classifier::JevAgent::ARM_ID))
    assert_in_delta 0.0002142, result.actual_billed_cost(Eval::Classifier::JevAgent::ARM_ID)

    Dir.mktmpdir do |directory|
      result.write!(directory, name: "jev-test")
      loaded = Eval::Classifier::Result.load(directory)
      assert_equal evidence.deep_stringify_keys, loaded.jev_evidence(Eval::Classifier::JevAgent::ARM_ID).sole

      receipt_path = Pathname.new(directory).join(Eval::Classifier::Result::JEV_RECEIPTS)
      receipts = Zlib::GzipReader.open(receipt_path) { |gzip| gzip.each_line.map { |row| JSON.parse(row) } }
      assert_equal 3, receipts.size, "one warm-up and both scored calls are durable"
      assert_equal %w[warmup reading reading], receipts.map { |row| row.fetch("kind") }
      assert receipts.all? { |row| JSON.generate(row).exclude?("Authorization") }
    end

    Dir.mktmpdir do |directory|
      result.write_summary!(directory, name: "jev-kept")
      compact = Eval::Classifier::Result.load(directory)
      assert_empty compact.rows
      kept_receipts = Zlib::GzipReader.open(Pathname.new(directory).join(Eval::Classifier::Result::JEV_RECEIPTS)) do |gzip|
        gzip.each_line.to_a
      end
      assert_equal 3, kept_receipts.size, "compacting must not discard the evidence needed to rescore"
    end

    printed = Eval::Classifier::Board.new([ [ "jev-test", result ] ]).lines.join("\n")
    assert_includes printed, "Jev confidence distribution"
    assert_includes printed, "Jev coverage by floor"
    assert_includes printed, "Jev wrong at confidence ≥0.6"
    assert_includes printed, "Jev actual billed cost"
  end

  test "failed billable readings contribute their usage cost and receipt" do
    usage = { "input_tokens" => 700, "output_tokens" => 20 }
    failed = Eval::Classifier::Bench::Reading.new(
      line: line(id: "failed", intent: :other), arm: Eval::Classifier::JevAgent::ARM_ID, rep: 1,
      answer: nil, answered_by: nil, raw: nil, seconds: nil,
      error: "Eval::Classifier::JevAgent::MalformedResponse: invalid choice", usage:,
      billed_cost: Eval::Classifier::JevAgent::PRICE.of(700, 20),
      request: { "model" => "jev-latest" },
      receipt: { "status" => 200, "body" => { "answers" => {}, "usage" => usage } }
    )
    pass = Eval::Classifier::Bench::Pass.new(
      arm: Eval::Classifier::JevAgent::ARM_ID, rep: 1, readings: [ failed ]
    )
    result = Eval::Classifier::Result.new(
      corpus_size: 1, corpus_digest: "digest", arms: [ Eval::Classifier::JevAgent::ARM_ID ],
      reps: 1, passes: [ pass ], warmups: [], concurrency: 1
    )

    assert_equal({ input_tokens: 700, output_tokens: 20 }, result.actual_usage(Eval::Classifier::JevAgent::ARM_ID))
    assert_in_delta Eval::Classifier::JevAgent::PRICE.of(700, 20),
                    result.actual_billed_cost(Eval::Classifier::JevAgent::ARM_ID)

    Dir.mktmpdir do |directory|
      result.write!(directory, name: "jev-failed")
      receipts = Zlib::GzipReader.open(Pathname.new(directory).join(Eval::Classifier::Result::JEV_RECEIPTS)) do |gzip|
        gzip.each_line.map { |row| JSON.parse(row) }
      end
      assert_equal usage, receipts.sole.fetch("usage")
      assert_equal 200, receipts.sole.dig("receipt", "status")
    end
  end

  private
    def line(id:, intent:, target: nil)
      Eval::Classifier::Corpus::Line.new(id:, position: "office", typed: id, intent:, target:,
                                         refusal: :none, shape: "test")
    end

    def answer(intent, target = nil)
      Eval::Classifier::Corpus::Answer.new(intent:, target:)
    end

    def reading(line, answer:, confidence:, input:, right_key:)
      probabilities = { right_key => confidence, "other" => 1.0 - confidence }
      usage = { "input_tokens" => input, "output_tokens" => 10 }
      Eval::Classifier::Bench::Reading.new(
        line:, arm: Eval::Classifier::JevAgent::ARM_ID, rep: 1, answer:, answered_by: "jev-latest",
        raw: { "intent" => answer.intent.to_s, "target" => answer.target || "nothing", "also_named" => "nothing" },
        seconds: 0.3, error: nil, confidence:, probabilities:, usage:,
        billed_cost: Eval::Classifier::JevAgent::PRICE.of(input, 10),
        request: { "model" => "jev-latest", "case" => line.id },
        receipt: { "status" => 200, "body" => { "answers" => { "reading" => { "choice" => right_key } }, "usage" => usage } }
      )
    end
end
