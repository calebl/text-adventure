require "test_helper"

class Eval::Inscription::ScorerTest < ActiveSupport::TestCase
  def checks(words, **extra)
    Eval::Inscription::Scorer.checks({ "raw" => { "inscription" => words }, "description" => "A folded note." }.merge(extra.stringify_keys))
  end

  test "bounded signals detect their constructed positives" do
    assert checks(" ").fetch("empty")
    assert checks("You unfold the note and read the words.").fetch("narration_framing")
    assert checks("The inscription says: return at dawn.").fetch("narration_framing")
    assert checks("The office will reopen when the").fetch("truncated_prose")
    assert checks("x" * (Item::INSCRIPTION_LIMIT + 1)).fetch("length_bound")
    assert checks("A folded note.").fetch("description_repeated")
    assert checks("words", error: "Rejected").fetch("failed")
  end

  test "letters and notices may address a reader and labels need no full stop" do
    [ "I have left the key with the porter.", "You must return this by dawn.", "Return at dawn", "WARD XII", "12 / 4 / 8" ].each do |text|
      refute checks(text).fetch("narration_framing")
      refute checks(text).fetch("truncated_prose")
    end
    assert_nil checks("WARD XII").fetch("truncated_prose")
    refute checks("The office will reopen at dawn.").fetch("truncated_prose")
  end

  test "absent answers are failures not clean scores" do
    values = Eval::Inscription::Scorer.checks("error" => "Network failed")
    assert values.fetch("failed")
    assert_nil values.fetch("empty")
    assert_nil values.fetch("truncated_prose")
  end

  test "comparison refuses different cases and gives noise for identical repetitions" do
    row = { "raw" => { "inscription" => "The office will reopen at dawn." }, "story" => "Tuning", "id" => "one" }
    rows = (1..Eval::Noise::MIN_RUNS).map { |rep| row.merge("rep" => rep) }
    data = { "rows" => rows, "model" => "pinned", "corpus_digest" => "fixed", "request_identity" => {}, "case_identities" => { "one" => {} }, "reps" => Eval::Noise::MIN_RUNS }
    assert_raises(ArgumentError) { Eval::Inscription::Report.compare(data, data.merge("rows" => rows.drop(1))) }
    assert_includes Eval::Inscription::Report.compare(data, data).join("\n"), "NOISE"
    assert_raises(ArgumentError) { Eval::Inscription::Report.compare(data, data.merge("corpus_digest" => "changed")) }
  end
end
