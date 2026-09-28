require "test_helper"

# What somebody said unasked, held on a staged moment and narrated: the kept
# set is held to today's corpus and to the requests the engine builds for it,
# without buying a call.
class Eval::Prompt::SpeechKeptSetTest < ActiveSupport::TestCase
  test "kept requests and held facts still match HEAD without buying calls" do
    captured = Eval::Prompt::Speech.capture
    assert_equal Eval::Prompt::Speech.identity(captured), kept.request_identity
    shared = Eval::Prompt::RequestVersion.offline(Eval::Prompt.corpus("speech"))
    assert_equal kept.request_identity, shared.fetch(:request_identity)
    assert_equal kept.prompt_digest, shared.fetch(:prompt_digest)
    assert_equal Eval::Prompt.digest(Eval::Prompt.corpus("speech")), kept.corpus_digest
    assert_equal Eval::Noise::MIN_RUNS, kept.reps
    assert_equal [ "mistralai/mistral-medium-3.1" ], kept.arms
    assert_equal kept.arms, kept.answered_by
    assert_equal captured.keys, kept.prompt_shapes.keys
    assert_equal Eval::Prompt.corpus("speech").size * kept.reps, kept.rows.size
    kept.rows.each do |row|
      designated = captured.fetch(row.fetch("shape"))
      assert_equal designated.fetch("request")[:user], row.fetch("prompt"), row.fetch("id")
      assert_equal Playthrough::PromptVersion.narration_instructions, row.fetch("instructions_digest")
      # Less the token's id, which is the row id of the database a set was
      # staged in; the fact it names is compared whole.
      assert_equal held(designated.fetch("facts")), held(row.fetch("facts").slice(*designated.fetch("facts").keys))
      stated = row.fetch("prompt")[/^What else happened here, recorded by the game: (.*)$/, 1]
      assert_equal row.dig("facts", "acts").join(" "), stated, row.fetch("id")
      assert_includes stated, row.dig("facts", "speech", "fact")
      assert_equal 1, row.fetch("calls")
      assert_nil row["error"]
    end
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
    assert_in_delta actual, receipts.fetch("actual_usd"), 1e-12
    assert_operator actual, :<=, receipts.fetch("authorized_usd")
    assert receipts.fetch("includes_warmup")
  end

  test "the manifest includes the instrumentation and the kept evidence" do
    paths = %w[lib/eval/held_speech.rb lib/eval/prompt/speech.rb lib/eval/prompt/speech/stage.rb
               lib/eval/prompt/speech/bench.rb test/fixtures/files/prompt_speech_corpus.yml]
    paths += %w[prompt.json receipts.json].map { |file| "db/eval/#{Eval::Prompt::Speech::BASELINE}/#{file}" }
    paths.each { |path| assert_includes Eval::MEASUREMENT_FILES, path }
  end

  test "the corpus validates" do
    assert_empty Eval::Prompt.corpus("speech").problems
  end

  private

  def held(facts) = facts.merge("speech" => facts.fetch("speech").merge("token" => facts.dig("speech", "token").sub(/:\d+\z/, "")))

  def directory = Eval.kept_root.join(Eval::Prompt::Speech::BASELINE)
  def kept = @kept ||= Eval::Prompt::Result.load(directory)
end
