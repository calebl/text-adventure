require "test_helper"
require Rails.root.join("db/eval/physical-classifier-20260910/evaluate")
require Rails.root.join("db/eval/adversarial-20260909/eval-budget-streaming-v2")

class Eval::Classifier::PhysicalStudyTest < ActiveSupport::TestCase
  test "a revised study has an independent journal namespace without changing its payload manifest" do
    original = PhysicalClassifierStudy.manifest(concurrency: 2)
    revised = PhysicalClassifierStudy.manifest(concurrency: 2, set: "independent-revision")
    assert_equal "physical-classifier-20260910", original.fetch("set")
    assert_equal "independent-revision", revised.fetch("set")
    assert_equal original.except("set"), revised.except("set")
    Dir.mktmpdir do |dir|
      PhysicalClassifierStudy::Journal.new(dir, original)
      assert_raises(RuntimeError) { PhysicalClassifierStudy::Journal.new(dir, revised) }
    end
  end

  test "the pre-send gate rejects added text, schema, history, changed record IDs and repeated calls" do
    expected = { "system" => "Fixed instructions", "user" => "use:offer:12:13:0:0: Offer apple to Maren",
      "schema" => { "enum" => [ "use:offer:12:13:0:0" ] }, "history" => [] }
    PhysicalClassifierStudy.verify_payload!(expected.deep_dup, expected, used: false)
    %w[system user schema history].each do |field|
      changed = expected.deep_dup
      changed[field] = "different"
      assert_raises(ReviewEvalBudget::Halt) { PhysicalClassifierStudy.verify_payload!(changed, expected, used: false) }
    end
    changed_id = expected.deep_dup
    changed_id["user"] = changed_id["user"].sub(":12:", ":99:")
    assert_raises(ReviewEvalBudget::Halt) { PhysicalClassifierStudy.verify_payload!(changed_id, expected, used: false) }
    assert_raises(ReviewEvalBudget::Halt) { PhysicalClassifierStudy.verify_payload!(expected, expected, used: true) }
  end

  test "a resumed journal retains failures and rejects changed protocols and duplicate readings" do
    Dir.mktmpdir do |dir|
      journal = PhysicalClassifierStudy::Journal.new(dir, { "corpus" => "fixed" })
      journal.append("rep" => 1, "id" => "failed", "error" => "ProviderError", "answer" => nil)
      resumed = PhysicalClassifierStudy::Journal.new(dir, { "corpus" => "fixed" })
      assert resumed.include?(1, "failed")
      assert_equal "ProviderError", resumed.rows.sole.fetch("error")
      assert_raises(RuntimeError) { resumed.append("rep" => 1, "id" => "failed") }
      assert_raises(RuntimeError) { PhysicalClassifierStudy::Journal.new(dir, { "corpus" => "changed" }) }
      assert_equal 1, File.readlines(File.join(dir, "readings.jsonl")).size
    end
  end

  test "overlapping receipt labels and buffers remain tied to their own readings" do
    holder = Object.new.extend(PhysicalClassifierStudy::ThreadReceipts)
    ready = Queue.new
    release = Queue.new
    workers = 4.times.map do |index|
      Thread.new do
        holder.label = "case-#{index}"
        holder.calls = [ index ]
        ready << true
        release.pop
        [ holder.label, holder.calls ]
      end
    end
    4.times { ready.pop }
    4.times { release << true }
    assert_equal 4.times.map { |index| [ "case-#{index}", [ index ] ] }, workers.map(&:value)
  end

  test "the historical view rescored against its own labels preserves the intentional give miss" do
    current = Eval::Classifier.corpus.subset { |line| line.id == "real-give-him-the-index" }
    line = current.lines.sole
    historical = Eval::Classifier::Corpus.new(path: current.path, positions: current.positions,
      lines: [ line.with(intent: :drop, shape: "unresolved-drop") ])
    Dir.mktmpdir do |dir|
      journal = PhysicalClassifierStudy::Journal.new(dir, {})
      (0..4).each do |rep|
        row = Eval::Classifier::Bench::Reading.new(line: line, arm: PhysicalClassifierStudy::MODEL,
          rep: rep, answer: Eval::Classifier::Corpus::Answer.new(intent: :use),
          answered_by: PhysicalClassifierStudy::MODEL, raw: { "intent" => "use", "target" => "nothing", "also_named" => "nothing" },
          seconds: 0.2, error: nil)
        journal.append(PhysicalClassifierStudy.serialize(row, calls: [], request: {}))
      end
      latest = PhysicalClassifierStudy.result(journal, corpus: current, identity: {}, name: "current", concurrency: 4)
      old_labels = PhysicalClassifierStudy.result(journal, corpus: historical, identity: {}, name: "projection", concurrency: 4)
      assert_equal [ 1.0 ] * 4, latest.values(:accuracy)
      assert_equal [ 0.0 ] * 4, old_labels.values(:accuracy)
      refute_equal latest.corpus_digest, old_labels.corpus_digest
      journal.rows.pop
      assert_raises(RuntimeError) { PhysicalClassifierStudy.result(journal, corpus: current, identity: {}, name: "incomplete", concurrency: 4) }
    end
  end
end
