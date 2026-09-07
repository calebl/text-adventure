require "test_helper"

# A SET, WRITTEN AND READ BACK, AND THE THREE THINGS THAT READ IT.
#
# The whole point of storing every reading is that a check can be redefined and
# a paid-for set rescored for nothing, so what is pinned here is that a set
# loaded off disk answers exactly what the live one did -- and that a SUMMARY,
# which has no readings at all, answers the same again. A board that quietly
# read a different number off a kept set than off the run it came from would
# make every checked-in baseline a lie.
class Eval::Realization::ResultTest < ActiveSupport::TestCase
  def setup
    @directory = Pathname.new(Dir.mktmpdir)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  test "a set writes itself and reads back with the same figures" do
    written = result.write!(@directory, name: "a-set")
    loaded = Eval::Realization::Result.load(@directory)

    assert_equal Eval::Realization::RESULTS, written.basename.to_s
    assert_equal "a-set", loaded.name
    assert_equal [ "fake/model" ], loaded.arms
    assert_equal result.values(:no_new_ground), loaded.values(:no_new_ground)
    assert_equal result.values(:exits_named), loaded.values(:exits_named)
    assert_equal result.values(:output_tokens), loaded.values(:output_tokens)
  end

  # A KEPT SET IS A SUMMARY, and it has to print the same table as the run it
  # came from. That is what makes checking one in reasonable at all.
  test "a summary drops the readings and keeps every figure" do
    summary = result.summary
    summary.write!(@directory, name: "kept")
    loaded = Eval::Realization::Result.load(@directory)

    assert_empty loaded.rows, "a summary keeps no readings on purpose"
    Eval::Realization::Result.metrics.each_key do |metric|
      assert_equal result.values(metric), loaded.values(metric), metric
    end
    assert_equal result.corpus_digest, loaded.corpus_digest
  end

  test "a set that does not exist says how to make one" do
    error = assert_raises(ArgumentError) { Eval::Realization::Result.load(@directory) }

    assert_includes error.message, "rake eval:realization SET="
  end

  # THE REPORT AND THE BOARD ARE RUN, not merely constructed: a format string
  # with the wrong arity raises, and a board nobody printed in a test is a board
  # that raises the first time somebody pays for a run.
  test "the report prints every check, the unavailable ones and the reported counts" do
    printed = capture { |io| Eval::Realization::Report.new(result, io: io).print }

    Eval::Realization.checks.each { |code| assert_includes printed, code.to_s }
    Eval::Realization::UNAVAILABLE_TO_A_REALIZATION.each_key { |code| assert_includes printed, code.to_s }
    assert_includes printed, "UNAVAILABLE TO THIS BENCH -- reported, never scored as clean"
    assert_includes printed, "WHAT WAS ACTUALLY IN THE ROOM"
    assert_includes printed, "[KEYWORD]", "the one check that reads words is labelled"
    assert_includes printed, "[HELD OUT]"
  end

  test "the board tabulates a set and names what it cannot answer" do
    result.write!(@directory, name: "a-set")
    board = Eval::Realization::Board.new([ [ "a-set", Eval::Realization::Result.load(@directory) ] ])

    lines = board.lines.join("\n")
    assert_includes lines, "| `fake/model` |"
    assert_includes lines, "`no_new_ground`"
    assert_includes lines, "cost per 1,000 rooms"

    # AND THE TABLE MARKS THE CHECKS THAT READ WORDS, off the same constant the
    # note under it is written from -- a rate labelled in one place and not the
    # other is the misreading the note exists to prevent.
    Eval::Realization::Scorer::KEYWORD_CHECKS.each do |code|
      assert_includes lines, "`#{code}` **[KEYWORD]**"
    end
    (Eval::Realization.checks - Eval::Realization::Scorer::KEYWORD_CHECKS).each do |code|
      refute_includes lines, "`#{code}` **[KEYWORD]**", "#{code} compares records and is not a reading"
    end

    warnings = board.warnings.join("\n")
    assert_includes warnings, "unavailable rather than clean"

    # THE KEYWORD NOTE MUST NAME EVERY CHECK THAT READS WORDS AND NO OTHER,
    # because the table above it labels each of them `[KEYWORD]` off the same
    # constant -- a board that named one while printing two would tell the
    # captain to weigh a figure he cannot see.
    keyword = Eval::Realization::Scorer::KEYWORD_CHECKS
    keyword.each { |code| assert_includes warnings, "`#{code}`", "the note names every keyword check" }
    (Eval::Realization.checks - keyword).each do |code|
      refute_includes warnings, "`#{code}`", "#{code} compares records and is not weighed as a reading"
    end
    assert_includes warnings, keyword.one? ? "is a **keyword check**" : "are **keyword checks**"
  end

  test "the board says so out loud when two sets did not build the same rooms" do
    other = result(corpus_digest: "somethingelse")
    board = Eval::Realization::Board.new([ [ "a", result ], [ "b", other ] ])

    assert_includes board.warnings.join("\n"), "did not build the same rooms"
  end

  # A COMPARISON OF ONE SET WITH ITSELF IS THE NULL CHECK: same prompt digest,
  # same cases, and every verdict must read NOISE. If this ever prints REAL, the
  # protocol is manufacturing a result out of nothing.
  test "a set compared with itself reads NOISE on every figure" do
    comparison = Eval::Realization::Comparison.new(result, result, io: nil)
    verdicts = comparison.verdicts("fake/model")

    assert_equal Eval::Realization::Result.metrics.keys.sort, verdicts.map(&:metric).sort
    assert_empty verdicts.select { |row| row.verdict.real? },
                 "one set against itself cannot be a real difference"
    assert_includes capture { |io| Eval::Realization::Comparison.new(result, result, io: io).print },
                    "the null check"
  end

  test "a comparison across two prompt versions says which shape it is" do
    printed = capture do |io|
      Eval::Realization::Comparison.new(result, result(prompt_digest: "adifferentone"), io: io).print
    end

    assert_includes printed, "This is a PROMPT comparison on one model"
  end

  test "two sets with nothing in common refuse to be paired" do
    error = assert_raises(Eval::Realization::Comparison::Unpairable) do
      Eval::Realization::Comparison.new(result(arms: %w[a b]), result(arms: %w[c d]), io: nil).pairs
    end

    assert_includes error.message, "BEFORE_MODEL="
  end

  private

  def capture
    io = StringIO.new
    yield io
    io.string
  end

  # FOUR REPETITIONS, WHICH IS `Eval::Noise::MIN_RUNS`: fewer and every verdict
  # would be INCONCLUSIVE for want of runs and the null check above would prove
  # nothing.
  def result(corpus_digest: "acorpus", prompt_digest: "aprompt", arms: [ "fake/model" ])
    passes = arms.flat_map do |arm|
      (1..Eval::Noise::MIN_RUNS).map do |rep|
        Eval::Realization::Result::Stored.new(
          { "arm" => arm, "rep" => rep, "readings" => readings(arm, rep) }
        )
      end
    end

    Eval::Realization::Result.new(corpus_size: 2, corpus_digest: corpus_digest, prompt_digest: prompt_digest,
                                  instructions_digest: "aninstruction", arms: arms,
                                  reps: Eval::Noise::MIN_RUNS, passes: passes,
                                  warmups: [ { "arm" => arms.first, "seconds" => 4.0 } ])
  end

  # One tuning case and one held out, so the report's by-world split has both
  # sides to print.
  def readings(arm, rep)
    [ reading(arm, rep, "hallway", "The Unrecorded Hour"),
      reading(arm, rep, "hulk", Eval::HELD_OUT) ]
  end

  def reading(arm, rep, id, story)
    { "id" => id, "shape" => "written-neighbour", "story" => story, "arm" => arm, "rep" => rep,
      "facts" => { "room" => "A Room", "expects_new_ground" => true, "people_allowance" => 2,
                   "item_allowance" => 3, "exit_allowance" => 3,
                   "slots" => [ { "race" => "Ledger-Kept", "monstrous" => false, "age" => 40, "sex" => "man" } ],
                   "places" => [ { "name" => "Somewhere Written", "realized" => true, "connected" => false } ],
                   "reachable" => [ "The Way Back" ], "taken_names" => [],
                   "all_names" => { "people" => [], "places" => [ "Somewhere Written" ], "things" => [] } },
      "answers" => { "detail" => { "items" => [], "people" => [] },
                     "exits" => { "exits" => [ { "name" => "Somewhere Written" } ] } },
      "after" => { "people" => [], "items" => [], "exits" => [], "new_places" => [] },
      "seconds" => 2.0 + rep, "input_tokens" => 1_000, "output_tokens" => 200, "calls" => 2,
      "answered_by" => arm, "missing_fields" => [], "cap_hits" => [], "error" => nil }
  end
end
