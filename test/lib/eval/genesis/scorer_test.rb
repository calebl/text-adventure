require "test_helper"

class Eval::Genesis::ScorerTest < ActiveSupport::TestCase
  test "missing historical facts do not earn denominators" do
    scorer = Eval::Genesis::Scorer.new([ { "answer" => {} }, { "error" => "no answer" } ])
    Eval::Genesis::Scorer::CHECKS.each_key { |code| assert_equal 0, scorer.judgeable_for(code), code }
  end

  test "nested required booleans may be false but absent strings and extra stats fire" do
    schema = Quest::Schema.new.to_json_schema.deep_stringify_keys
    answer = { "title" => "A quest", "premise" => "A task.",
               "steps" => [ { "summary" => "Find it", "trigger" => "hold_item", "target" => "Key", "teaser" => "A key." } ] * Quest::Schema::STEPS.first,
               "outcomes" => [ { "name" => "won", "summary" => "You won.", "is_default" => true },
                               { "name" => "lost", "summary" => "You lost.", "is_default" => false } ] }
    row = { "answer" => answer, "request" => { "schema" => schema } }
    scorer = Eval::Genesis::Scorer.new([ row ])
    assert_equal 0.0, scorer.rate(:required_fields)
    assert_equal 0.0, scorer.rate(:schema_shape)
    answer["steps"].first.delete("teaser")
    answer["outcomes"].last["level"] = 9
    assert_equal 1.0, scorer.rate(:required_fields)
    assert_equal 1.0, scorer.rate(:outside_schema)
  end

  test "duplicate name retry and engine ownership are checked against the stored facts" do
    row = { "answer" => { "fullname" => "TAKEN NAME", "level" => 90 },
            "facts" => { "retry_name" => "Taken Name", "taken_names" => [ "Taken Name" ], "body" => { "level" => 3 } } }
    scorer = Eval::Genesis::Scorer.new([ row ])
    %i[retry_not_distinct name_taken engine_owned].each { |code| assert_equal 1.0, scorer.rate(code) }
    row["answer"] = { "fullname" => "Fresh Name" }
    assert_equal 0.0, scorer.rate(:retry_not_distinct)
    assert_nil scorer.rate(:engine_owned), "without an admitted body no comparison was made"
    row["after"] = { "body" => { "level" => 1 } }
    assert_equal 1.0, scorer.rate(:engine_owned)
  end

  test "an enum key and its stored label are the same engine pick" do
    facts = { "body" => { "level" => 3 }, "race" => "Human", "age" => 44,
              "sex" => "non-binary", "hostile" => false }
    row = { "answer" => {}, "facts" => facts, "after" => facts.merge("sex" => "non_binary") }
    assert_equal 0.0, Eval::Genesis::Scorer.new([ row ]).rate(:engine_owned)
    row["after"]["sex"] = "female"
    assert_equal 1.0, Eval::Genesis::Scorer.new([ row ]).rate(:engine_owned)
  end

  test "quest bounds defaults and normalized labels reject plausible looking broken arcs" do
    row = { "answer" => { "steps" => [], "outcomes" => [ { "name" => "Same ending", "is_default" => true },
                                                                            { "name" => "same-ending", "is_default" => true } ] },
            "facts" => { "step_bounds" => [ 3, 5 ], "outcome_bounds" => [ 2, 4 ] } }
    scorer = Eval::Genesis::Scorer.new([ row ])
    %i[quest_bounds quest_default quest_labels].each { |code| assert_equal 1.0, scorer.rate(code) }
  end
end
