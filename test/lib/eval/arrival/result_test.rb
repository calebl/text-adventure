require "test_helper"

class Eval::Arrival::ResultTest < ActiveSupport::TestCase
  test "annotations attach to exact response text and keep fields separate" do
    row = { "id" => "sample", "rep" => 1, "description" => "You find Maren dead.", "summary" => "Iri enters.",
      "facts" => { "required" => [ "body" ] } }
    data = { "rows" => [ row ], "model" => "sample", "corpus_digest" => "sample" }
    identity = Eval::Arrival::Result.response_identity(row)
    label = {
      "description" => { "contradiction" => false, "required_fact_acknowledged" => true,
        "reason" => "Explicit death", "supporting_quote" => "Maren dead" },
      "summary" => { "contradiction" => false, "required_fact_acknowledged" => false,
        "reason" => "Death omitted" }
    }
    result = Eval::Arrival::Result.new(data, annotations: { identity => label })
    assert_includes result.board.join("\n"), "Explicit death"
    assert_equal({ flagged: 0, judgeable: 1 }, result.counts([ row ]).fetch("description.fact_missing_strict"))
    assert_equal({ flagged: 1, judgeable: 1 }, result.counts([ row ]).fetch("summary.fact_missing_strict"))
    row["summary"] = "Iri finds Maren dead."
    assert_raises(ArgumentError) { Eval::Arrival::Result.new(data, annotations: { identity => label }) }
  end

  test "compare refuses a missing case or a mismatched corpus" do
    data = JSON.parse(Eval::Arrival::BASELINE.join(Eval::Arrival::RESULTS).read)
    complete = Eval::Arrival::Result.new(data.deep_dup)
    data.fetch("rows").pop
    assert_raises(ArgumentError) { complete.compare(Eval::Arrival::Result.new(data)) }
    data["corpus_digest"] = "different"
    assert_raises(ArgumentError) { complete.compare(Eval::Arrival::Result.new(data)) }
  end
end
