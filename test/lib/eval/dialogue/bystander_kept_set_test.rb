require "test_helper"

# The exchange with somebody standing by who spoke up unasked: every request
# the kept set sent is what today's engine builds from the stored answers, and
# the bystander's fact is in the exchange narrator's, with the paragraph that
# asks for it to be narrated.
class Eval::Dialogue::BystanderKeptSetTest < ActiveSupport::TestCase
  def kept = Eval::Dialogue::Result.load(Eval.kept_root.join(Eval::Dialogue::BYSTANDER_BASELINE))

  test "the set contains every repetition of the bystander corpus on the approved model" do
    result = kept
    result.validate_complete!
    assert_equal "bystander", result.data.fetch("corpus")
    assert_equal Eval::Dialogue.digest("bystander"), result.data.fetch("corpus_digest")
    assert_equal Eval::Dialogue.cases("bystander").size * result.data.fetch("reps"), result.rows.size
    result.rows.each do |row|
      assert_equal 2, row.fetch("calls").size
      said = row.dig("facts", "bystander_said").sole
      assert_includes row.fetch("requests").last.fetch("user"), "What else happened here, recorded by the game: #{said}"
      assert_includes row.fetch("requests").last.fetch("user"), "Tobin also spoke up unasked, as \"What else happened here\" above records."
    end
  end

  test "the narrator named Tobin in every exchange, and the earlier set in none" do
    assert_equal [ 1.0 ] * kept.data.fetch("reps"), kept.passes.map { |p| p["bystander_named"] }
    before = Eval::Dialogue::Result.load(Eval.kept_root.join("dialogue-bystander-2026-09-28"))
    assert_equal "real", before.compare(kept).dig("bystander_named", :outcome).to_s
  end

  test "every emitted request matches today's builders" do
    kept.rows.each do |row|
      rebuilt = Eval::Dialogue::Version.rebuild(row)
      assert_equal row.fetch("requests"), rebuilt.fetch("requests"), "#{row.fetch('id')}:#{row.fetch('rep')} changed"
    end
  end
end
