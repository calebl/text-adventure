require "test_helper"

class Eval::Genesis::ResultTest < ActiveSupport::TestCase
  test "a partial pass cannot masquerade as a prompt comparison" do
    result = Eval::Genesis::Result.new("passes" => [], "arms" => [ Eval::Cost.default_model ],
      "reps" => Eval::Noise::MIN_RUNS, "request_stable" => true, "corpus_digest" => "fixed",
      "request_digests" => { "one" => { "story" => "digest" } })
    assert_raises(ArgumentError) { Eval::Genesis::Comparison.new(result, result) }
  end

  test "an absent answer is a failure and never a clean rate" do
    result = Eval::Genesis::Result.new("passes" => [ { "readings" => [ { "error" => "timeout", "receipt_missing" => true } ] } ])
    assert_equal [ 1 ], result.values(:failures)
    assert_equal [ nil ], result.values(:required_fields)
    assert_equal 1, result.receipt_missing
  end

  test "non-object rejected answers remain judgeable for schema shape" do
    row = { "answer" => "ignored JSON", "request" => { "schema" => { "schema" => { "type" => "object" } } } }
    assert_equal 1.0, Eval::Genesis::Scorer.new([ row ]).rate(:schema_shape)
  end
end
