require "test_helper"

class Eval::Arrival::ScorerTest < ActiveSupport::TestCase
  test "precision and misses against retained independent annotations stay visible" do
    key = JSON.parse(Eval::Arrival::STUDY.join("arrival-reading-key.json").read)
    annotations = JSON.parse(Eval::Arrival::STUDY.join("arrival-independent-annotations.json").read).fetch("annotations").index_by { |r| r.fetch("id") }
    counts = Hash.new { |h, k| h[k] = { total: 0, false_missing: 0, missed_missing: 0 } }
    %w[before after].each do |arm|
      JSON.parse(Eval::Arrival::STUDY.join("arrival-#{arm}.json").read).fetch("rows").each do |row|
        id = key.find { |_id, v| v == { "arm" => arm, "case" => row.fetch("case"), "rep" => row.fetch("rep") } }.first
        fact = Eval::Arrival.cases.find { |k| k["id"] == row["case"] }.fetch("facts").first
        %w[description summary].each do |field|
          %w[strict inclusive].each do |mode|
            label = annotations.fetch(id).fetch(field).fetch("required_fact_acknowledged")
            missing = mode == "strict" ? label != true : label == false
            predicted = Eval::Arrival::Scorer.fact_missing?(row.fetch(field), fact, inclusive: mode == "inclusive")
            c = counts["#{field}.#{mode}"]
            c[:total] += 1
            c[:false_missing] += 1 if predicted && !missing
            c[:missed_missing] += 1 if !predicted && missing
          end
        end
      end
    end
    assert_equal({
      "description.strict" => { total: 24, false_missing: 0, missed_missing: 1 },
      "description.inclusive" => { total: 24, false_missing: 0, missed_missing: 3 },
      "summary.strict" => { total: 24, false_missing: 0, missed_missing: 0 },
      "summary.inclusive" => { total: 24, false_missing: 1, missed_missing: 0 }
    }, counts)
  end
end

class Eval::Arrival::LexicalLimitsTest < ActiveSupport::TestCase
  test "placed facts have positive detections and explicit paraphrase and attribution limits" do
    {
      "body" => [ "Maren is dead.", "Maren speaks.", "Maren is motionless." ],
      "wound" => [ "Maren has a wound.", "Maren smiles.", "Maren limps." ],
      "key" => [ "You carry the brass key.", "A brass key lies on the desk.", "Your brass key gleams." ],
      "toll" => [ "The water crossing cost Iri hit points.", "Water wets your boots.", "Your legs ache from the water." ],
      "floor" => [ "The blue ledger lies on the desk.", "You read a blue ledger.", "A blue ledger sits beside Maren." ]
    }.each do |fact, (explicit, absent, implied)|
      refute Eval::Arrival::Scorer.fact_missing?(explicit, fact)
      assert Eval::Arrival::Scorer.fact_missing?(absent, fact)
      refute Eval::Arrival::Scorer.fact_missing?(implied, fact, inclusive: true)
    end
    # Cues cannot resolve negation or which person's hand holds the key.
    refute Eval::Arrival::Scorer.fact_missing?("Maren is not dead.", "body")
    refute Eval::Arrival::Scorer.fact_missing?("Maren holds the brass key.", "key")
    assert Eval::Arrival::Scorer.fact_missing?("The metal teeth press against your palm.", "key")
  end

  test "summary third person is required while description uses the existing third person predicate" do
    row = { "id" => "sample", "description" => "Iri enters the room.", "summary" => "Iri enters the room.",
      "facts" => { "required" => [], "protagonist" => [ "Iri" ], "moved" => true } }
    readings = Eval::Arrival::Scorer.read(row)
    assert readings.dig("description", "second_person_cue_missing")
    refute readings.dig("summary", "third_person_cue_missing")
    assert_nil readings.dig("summary", "third_person_protagonist")
    assert_nil readings.dig("description", "unrecorded_departure")
    assert_nil readings.dig("description", "fact_missing_strict")
    row["error"] = "failed"
    row["facts"]["required"] = [ "body" ]
    assert Eval::Arrival::Scorer.read(row).dig("description", "fact_missing_strict")
  end
end
