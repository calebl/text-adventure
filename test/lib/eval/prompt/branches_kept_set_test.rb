require "test_helper"

class Eval::Prompt::BranchesKeptSetTest < ActiveSupport::TestCase
  test "kept requests and placed facts still match HEAD without buying calls" do
    captured = Eval::Prompt::Branches.capture
    assert_equal Eval::Prompt::Branches.identity(captured), kept.request_identity
    assert_equal Eval::Prompt.digest(Eval::Prompt.corpus("branches")), kept.corpus_digest
    assert_equal Eval::Noise::MIN_RUNS, kept.reps
    assert_equal [ "mistralai/mistral-medium-3.1" ], kept.arms
    assert_equal kept.arms, kept.answered_by
    assert kept.prompt_stable
    assert_equal "780ae0948949c3d9", kept.prompt_digest
    assert_equal captured.keys, kept.prompt_shapes.keys
    assert_equal Eval::Prompt.corpus("branches").size * kept.reps, kept.rows.size
    kept.rows.each do |row|
      designated = captured.fetch(row.fetch("shape"))
      assert_equal designated.fetch("request")[:user], row.fetch("prompt"), row.fetch("id")
      assert_equal Playthrough::PromptVersion.of(Scene::Narrator::INSTRUCTIONS), row.fetch("instructions_digest")
      assert_equal designated.fetch("facts"), row.fetch("facts").slice(*designated.fetch("facts").keys)
      assert_equal 1, row.fetch("calls")
      assert_nil row["error"]
      assert_nil row.fetch("human").fetch("truthfulness")
    end
  end

  test "all figures replay from the retained raw passages" do
    kept.passes.each do |pass|
      replay = Eval::Prompt::Result.figures_of(pass.rows)
      assert_equal pass.row.except("arm", "rep", "readings"), replay
      assert_equal 0, pass.failures
      assert_equal 0, pass.rotations
      assert_equal 0, pass.extra_calls
      Eval::Prompt::Branches::Predicates::CHECKS.each_key do |code|
        assert_operator pass.judgeable.fetch(code.to_s), :>, 0
        assert_equal 0, pass.flagged.fetch(code.to_s)
      end
    end
    table = Eval::Prompt::Board.new([ [ kept.name, kept ] ]).lines.join("\n")
    assert_includes table, "unlabelled (human-only)"
    assert_includes table, "`blow_contradicted`"
    comparison = Eval::Prompt::Comparison.new(kept, kept, io: nil)
    assert comparison.comparable_corpus?
    assert comparison.verdicts(kept.arms.sole).none? { |row| row.verdict.real? }
  end

  test "warmup and measured calls have token receipts inside the authorization" do
    receipts = JSON.parse(directory.join("receipts.json").read)
    rows = kept.rows + kept.warmups.map { |row| row.fetch("reading") }
    input = rows.sum { |row| row.fetch("input_tokens") }
    output = rows.sum { |row| row.fetch("output_tokens") }
    assert_equal rows.size, receipts.fetch("calls")
    assert_equal input, receipts.fetch("input_tokens")
    assert_equal output, receipts.fetch("output_tokens")
    actual = (input * receipts.fetch("input_per_million") + output * receipts.fetch("output_per_million")) / 1_000_000.0
    assert_equal actual, receipts.fetch("actual_usd")
    assert_operator actual, :>, 0
    assert_operator actual, :<=, receipts.fetch("authorized_usd")
    assert_operator receipts.fetch("estimate_usd"), :<=, receipts.fetch("authorized_usd")
    assert receipts.fetch("includes_warmup")
    assert_equal 0.0181444, actual
  end

  test "the manifest includes the producer instrumentation and kept evidence" do
    paths = %w[lib/eval/request_identity.rb lib/eval/prompt/branches.rb
               lib/eval/prompt/branches/stage.rb lib/eval/prompt/branches/bench.rb
               lib/eval/prompt/branches/predicates.rb test/fixtures/files/prompt_branches_corpus.yml]
    paths += %w[prompt.json receipts.json].map { |file| "db/eval/#{Eval::Prompt::Branches::BASELINE}/#{file}" }
    paths.each { |path| assert_includes Eval::MEASUREMENT_FILES, path }
  end

  private

  def directory = Eval.kept_root.join(Eval::Prompt::Branches::BASELINE)
  def kept = @kept ||= Eval::Prompt::Result.load(directory)
end
