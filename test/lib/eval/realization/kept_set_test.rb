require "test_helper"

# THE REALIZATION BASELINE THAT SURVIVES A CLEAN CLONE.
#
# `tmp/eval` is a working directory: it gets cleaned, it is gitignored, and on a
# fresh clone it does not exist. So the set the room naming block was
# re-baselined on is checked in under `db/eval`, and this is the test that it is
# still readable and still says what EVALUATION.md and the PR body say about it.
# `Eval::Prompt::KeptSetTest`'s argument, applied to the room builder's bench.
#
# NO KEY AND NO NETWORK, which is the point rather than a convenience: it is
# what makes the figures judgeable by somebody who has never paid for a call.
# The cost row is the one exception and degrades to `unpriced` rather than
# failing, because it reads the `models` registry.
#
# IT ASSERTS NO RATE, deliberately, and that is the difference between this and
# the prompt bench's kept-set test. That one pins the take/drop defect the bench
# was built for, because the whole point of that baseline is a number a later
# change is judged against. This bench's checked-in set is the AFTER side of a
# judged change: the numbers live in the file and are read with
# `rake eval:realization_board`, and a number copied into an assertion here
# would be a second place they were written down.
class Eval::Realization::KeptSetTest < ActiveSupport::TestCase
  # NAMED ONCE, IN THE APP, and read here. `Eval::Realization::BASELINE` is what
  # `rake eval:realization_digest` compares this tree against, so a second
  # spelling of the name would be a second answer to "what is the baseline".
  BASELINE = Eval::Realization::BASELINE

  ARM = "mistralai/mistral-medium-3.1".freeze

  test "the checked-in baseline loads off disk with its provenance in the file" do
    result = kept

    assert_equal BASELINE, result.name
    assert_equal [ ARM ], result.arms, "a set that does not say which model produced it is not a set"
    assert_equal [ ARM ], result.answered_by, "answered_by is the check on arms, and the pinning has to have held"
    assert_equal Eval::Noise::MIN_RUNS, result.reps, "fewer repetitions than the floor cannot be given a verdict"
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, result.recorded_at.to_s, "the date belongs in the file, not the filename")
    assert result.prompt_stable, "one case sending two prompts would make every figure in it suspect"
    assert_predicate result.prompt_digest, :present?
    assert_predicate result.instructions_digest, :present?
  end

  # THE CORPUS DIGEST IS WHAT MAKES A LATER RUN COMPARABLE WITH THIS ONE: it is
  # the claim that the cases did not move underneath the comparison. A corpus
  # that has moved makes `rake eval:realization_compare` a comparison between
  # two files rather than between two prompts.
  test "the baseline records the corpus it measured, and it is today's" do
    assert_equal Eval::Realization.digest, kept.corpus_digest,
                 "the corpus moved since the baseline was taken -- re-run it, or the comparison means nothing"
    assert_equal Eval::Realization.corpus.size, kept.corpus_size
  end

  # AND THE PROMPTS IT MEASURED ARE THE PROMPTS IN THIS TREE, which is the
  # corpus digest's argument said about the other half of what a run measures --
  # and the half that had no offline check at all until
  # `Eval::Realization::Version.offline`. The captain's standing rule of
  # 2026-09-06 is that a prompt change is judged against a baseline; this is the
  # assertion that makes shipping one without a baseline a failing test rather
  # than a thing nobody could see. A prompt edit re-baselines and moves
  # `Eval::Realization::BASELINE`, in that order.
  #
  # IT ASSEMBLES THE PROMPTS RATHER THAN READING THEM OFF THE SET, so what is
  # compared is what `Location::Generator` would send TODAY. No key, no network,
  # no spend.
  test "the baseline measured the prompts this tree would send" do
    assert_equal Eval::Realization::Version.offline[:prompt_digest], kept.prompt_digest,
                 "the realization prompts moved since the baseline was taken -- buy an after side and " \
                 "point Eval::Realization::BASELINE at it, or put the prompt back"
  end

  # THE NAMING ASK WAS IN THE PROMPT WHEN THIS WAS TAKEN, which is the one fact
  # about this set that makes it the AFTER side rather than a run beside it:
  # both name checks earned a denominator. Read off `name_asked`, the fact the
  # bench stores per row -- a set recorded before `Location::DetailSchema`
  # carried a `name` reports both checks `unavailable`, and that is what the
  # before side of this pair does.
  #
  # EACH CHECK AGAINST ITS OWN PREDICATE, AND THE TWO ARE NOT THE SAME ONE.
  # `Eval::Realization::Scorer#judge_room_name_refused` judges a room the prompt
  # asked whose name is on record afterwards -- which is every room it asked,
  # since a room always has a name. `#judge_room_name_already_taken` judges a
  # room the prompt asked THAT PROPOSED SOMETHING, and `name` is an optional
  # field, so a room that came back without one is in the first denominator and
  # not the second. The two figures are equal in this set because this arm
  # answered every time; that is a fact about the run and not a rule, so it is
  # not what is asserted here.
  test "the baseline was taken with the naming ask in the prompt" do
    judgeable = kept.passes.map { |pass| pass.judgeable.slice("room_name_refused", "room_name_already_taken") }

    judgeable.each do |pass|
      assert_operator pass["room_name_refused"].to_i, :>, 0,
                      "no room in this set was asked to name itself, so it is not a baseline for the naming block"
      assert_operator pass["room_name_already_taken"].to_i, :>, 0,
                      "no room the prompt asked proposed a name, so the collision check earned no rate"
    end
  end

  # A KEPT SET IS A SUMMARY: the rows are dropped so it can live in the repo,
  # and everything the board and the comparison read has to survive that.
  test "the baseline is a summary and still renders a board with no rows" do
    result = kept

    assert_empty result.rows, "a kept set holds no readings, on purpose"
    table = Eval::Realization::Board.new([ [ BASELINE, result ] ]).lines.join("\n")

    assert_includes table, "`#{ARM}`"
    assert_includes table, "`room_name_refused`"
    Eval::Realization::Result::REPORTED_METRICS.each_key do |figure|
      next if result.values(figure, arm: ARM).compact.empty?

      assert_not_includes Eval::Realization::Board.new([ [ BASELINE, result ] ]).lines
                                                  .grep(/`#{figure}` \(reported\)/).join, "not recorded",
                          "#{figure} is in this summary and the board printed it as missing"
    end
  end

  # AND A FIGURE THE SUMMARY DOES NOT HOLD SAYS SO. A kept set is frozen the day
  # it is written, so every check and figure added afterwards is one it was
  # never asked. The board must print `not recorded` and the checks
  # `unavailable` for those, and never 0.000, which would read as a set that
  # measured the question and cleared it. This is the same rule
  # `Eval::Realization::Report#checks` holds inside one run, applied across the
  # time between two.
  #
  # ASSERTED ON A FROZEN HISTORICAL SET AND NOT ON THE BASELINE, which is the
  # one thing that has to move when the baseline does. A freshly bought baseline
  # records every figure this tree has -- that is what buying one MEANS -- so
  # holding this rule to `BASELINE` would make it a test that passes only while
  # the baseline is stale, and it would fail on the day somebody did the right
  # thing. `kind-to-corpus-after` was bought before the captain's Call 7 of
  # 2026-09-08 added `insides_reaching` and
  # `inside_on_a_place_that_already_exists`, and it is kept as history and never
  # rewritten, so it is the honest subject.
  PREDATES_THE_REACH_FIGURES = "kind-to-corpus-after".freeze

  test "a figure written after a kept set was frozen reads as missing and never as nought" do
    older = Eval::Realization::Result.load(Eval.kept_root.join(PREDATES_THE_REACH_FIGURES))
    table = Eval::Realization::Board.new([ [ PREDATES_THE_REACH_FIGURES, older ] ]).lines

    older.passes.each do |pass|
      assert_nil pass.figure(:insides_reaching), "the summary predates the figure and must not invent one"
    end
    assert_match(/not recorded/, table.grep(/`insides_reaching`/).sole)
    assert_match(/unavailable/, table.grep(/`inside_on_a_place_that_already_exists`/).sole)
  end

  # AND THE BASELINE'S OWN SIDE OF THAT RULE: it was bought after those two
  # landed, so it really does hold them -- which is what makes it a baseline for
  # the checks this tree scores rather than a set with holes in it.
  test "the baseline holds the figures this tree measures" do
    kept.passes.each do |pass|
      assert_not_nil pass.figure(:insides_reaching),
                     "a baseline bought today measures every figure today's scorer reports"
      assert_operator pass.judgeable["inside_on_a_place_that_already_exists"].to_i, :>, 0
    end
  end

  # THE TWO INSIDE CHECKS EARNED A DENOMINATOR, which is what makes this set a
  # baseline for the captain's Call 6 of 2026-09-08 rather than a run beside it.
  # The corpus labels six cases -- three with a ceiling quantifier and three with
  # a floor -- so each check is judgeable on three and neither reports
  # `unavailable`. A rate is NOT asserted: this file pins no rate, for the reason
  # at the top of it.
  test "the baseline was taken with a quantifier on both sides of the inside pair" do
    kept.passes.each do |pass|
      assert_operator pass.judgeable["inside_where_the_world_wanted_none"].to_i, :>, 0,
                      "no case in this set carries a ceiling quantifier, so it is not a baseline for that check"
      assert_operator pass.judgeable["no_inside_where_the_world_wanted_one"].to_i, :>, 0,
                      "no case in this set carries a floor quantifier, so it is not a baseline for that check"
    end
  end

  test "branch requests match HEAD and the paid first requests without changing historical sets" do
    document = JSON.parse(File.read(Eval.kept_root.join(BASELINE, "requests.json")))
    requests = Eval::Realization::BranchRequests.offline
    assert_equal requests, document.fetch("requests")
    assert_equal Eval::Realization::BranchRequests.identity(requests), document.fetch("request_identity")
    rows = full_rows
    requests.each do |id, request|
      bought = rows.select { |row| row.fetch("id") == id }
      assert_equal Eval::Noise::MIN_RUNS, bought.size
      bought.each do |row|
        assert_nil row["error"], "#{id}: #{row['error']}"
        assert_equal request, row.fetch("facts").fetch("requests").first
      end
    end
  end

  test "branch receipts include warmup and price every purchased answer within authorization" do
    receipt = JSON.parse(File.read(Eval.kept_root.join(BASELINE, "receipts.json")))
    assert_operator receipt.fetch("actual"), :>, 0
    assert_operator receipt.fetch("actual"), :<=, 2
    assert_in_delta receipt.fetch("receipts").sum { |row| row.fetch("dollars") } +
                    receipt.fetch("previous_attempt").fetch("actual"), receipt.fetch("actual")
    assert_equal 1, receipt.fetch("receipts").count { |row| row.fetch("warmup") }
    assert receipt.fetch("receipts").all? { |row| row.fetch("model") == ARM }
    retries = full_rows.select { |row| row.dig("facts", "retry") }
    assert_equal Eval::Noise::MIN_RUNS, retries.size
    assert retries.all? { |row| row.fetch("answers").keys == [ "exits" ] && row.fetch("calls") == 1 }
  end

  test "the kept summary is recomputed from the full receipts" do
    kept.passes.each do |pass|
      rows = full_rows.select { |row| row.fetch("rep") == pass.rep && row.fetch("arm") == pass.arm }
      recomputed = Eval::Realization::Result.figures_of(rows)
      recomputed.each { |key, value| assert_equal value, pass.figures.fetch(key), key }
    end
  end

  test "quest receipts distinguish model admission from deadline placement" do
    rows = full_rows.select { |row| row.dig("facts", "quest_request") }
    rows.each do |row|
      assert_equal Eval::Realization::Admissions.replay(row), row.fetch("after").fetch("quest_admitted")
    end
  end

  def full_rows
    @full_rows ||= Zlib::GzipReader.open(Eval.kept_root.join(BASELINE, "readings.json.gz")) do |file|
      JSON.parse(file.read).fetch("passes").flat_map { |pass| pass.fetch("readings") }
    end
  end

  test "the baseline is small enough to belong in a repository" do
    file = Eval.kept_root.join(BASELINE, Eval::Realization::RESULTS)

    assert_operator File.size(file), :<, 100_000, "a kept set is figures, not rooms"
  end

  test "the manifest names the baseline, so deleting it is a failing test" do
    assert_includes Eval::MEASUREMENT_FILES, "db/eval/#{BASELINE}/#{Eval::Realization::RESULTS}"
  end

  private

  def kept = @kept ||= Eval::Realization::Result.load(Eval.kept_root.join(BASELINE))
end
