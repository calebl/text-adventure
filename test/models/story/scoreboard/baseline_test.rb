require "test_helper"

# The stored numbers, and the two ways a baseline file can be unusable: absent,
# which is the normal state of a fresh clone, and unreadable, which must not
# take the scoreboard down with it.
class Story::Scoreboard::BaselineTest < ActiveSupport::TestCase
  def setup
    @file = Rails.root.join("tmp/eval_baseline_test_#{SecureRandom.hex(4)}.json")
  end

  def teardown
    File.delete(@file) if File.exist?(@file)
  end

  def with_file(&block)
    Story::Scoreboard::Baseline.stub(:path, @file, &block)
  end

  test "a missing file is no baseline rather than an error" do
    with_file do
      assert_empty Story::Scoreboard::Baseline.all
      assert_nil Story::Scoreboard::Baseline.read("database")
    end
  end

  test "a snapshot written is a snapshot read back" do
    with_file do
      Story::Scoreboard::Baseline.write("corpus", { "scenes" => 92, "checks" => { "truncated_prose" => { "rate" => 0.04 } } })

      assert_equal 92, Story::Scoreboard::Baseline.read("corpus")["scenes"]
      assert_in_delta 0.04, Story::Scoreboard::Baseline.read("corpus").dig("checks", "truncated_prose", "rate")
    end
  end

  # Scoring one corpus must never discard the other's line -- `CORPUS=corpus
  # SAVE=1` is a normal thing to run.
  test "writing one corpus leaves the other alone" do
    with_file do
      Story::Scoreboard::Baseline.write("database", { "scenes" => 54 })
      Story::Scoreboard::Baseline.write("corpus", { "scenes" => 92 })

      assert_equal 54, Story::Scoreboard::Baseline.read("database")["scenes"]
      assert_equal 92, Story::Scoreboard::Baseline.read("corpus")["scenes"]
    end
  end

  test "an unreadable file is ignored rather than fatal" do
    File.write(@file, "{ this is not json")

    with_file do
      assert_empty Story::Scoreboard::Baseline.all
    end
  end

  test "the file is written sorted and newline-terminated, so its diffs read" do
    with_file do
      Story::Scoreboard::Baseline.write("database", { "scenes" => 54 })
      Story::Scoreboard::Baseline.write("corpus", { "scenes" => 92 })

      body = File.read(@file)

      assert body.end_with?("\n")
      assert_operator body.index("\"corpus\""), :<, body.index("\"database\"")
    end
  end

  # The one on file is the line the next run moves against, so it has to parse.
  #
  # It carries the checks that EXISTED when it was taken, which is not
  # necessarily all of them: a check added since reads as newly added and shows
  # no movement, which `Story::Scoreboard::Movement` is built for. What would
  # be wrong is the other direction -- a name in the file that no check answers
  # to any more, which is a stale line nothing will ever move.
  test "the checked-in baseline is readable and carries both corpora" do
    stored = Story::Scoreboard::Baseline.all

    assert_equal %w[corpus database], stored.keys.sort

    known = Story::Scoreboard::CHECKS.keys.map(&:to_s)
    stored.each do |corpus, snapshot|
      assert_not_empty snapshot["checks"], "#{corpus} baseline carries no checks"
      assert_empty snapshot["checks"].keys - known, "#{corpus} baseline names a check that no longer exists"
    end
  end
end
