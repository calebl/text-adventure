require "test_helper"

# The exchange with somebody standing by who spoke up unasked: every request
# the kept set sent is what today's engine builds from the stored answers, and
# the bystander's fact is in the exchange narrator's.
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
    end
  end

  test "every emitted request matches today's builders" do
    kept.rows.each do |row|
      rebuilt = Eval::Dialogue::Version.rebuild(row)
      assert_equal row.fetch("requests"), rebuilt.fetch("requests"), "#{row.fetch('id')}:#{row.fetch('rep')} changed"
    end
  end
end
