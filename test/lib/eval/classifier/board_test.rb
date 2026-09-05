require "test_helper"

# THE CROSS-MODEL TABLE, OUT OF THE STORED SCORES AND NOTHING ELSE.
#
# The captain's instruction of 2026-09-04 has two halves and this class is where
# they meet: *"a set should record which model produced it, and comparing model
# A's set against model B's set must work from the stored scores alone."* So the
# test builds sets the way a run does, writes them, and reads them back through
# `Result.load` -- never off the live objects. A figure a set failed to record
# has to read as "not recorded" and never as a zero.
class Eval::Classifier::BoardTest < ActiveSupport::TestCase
  setup do
    @root = Pathname.new(Dir.mktmpdir)
  end

  teardown do
    FileUtils.remove_entry(@root)
  end

  test "one column per arm, whether a set holds one arm or two" do
    stored("hosted", arms: [ "mistralai/mistral-medium-3.1", "minimax/minimax-m3" ])
    stored("local", arms: [ "ollama:qwen3:4b+nothink" ], seconds: 3.5)

    board = board_for("hosted", "local")

    assert_equal [ "mistralai/mistral-medium-3.1", "minimax/minimax-m3", "ollama:qwen3:4b+nothink" ],
                 board.columns.map(&:arm)
    assert_equal %w[hosted hosted local], board.columns.map(&:set)
  end

  test "a local arm is labelled as one, because free and slow is not the same comparison" do
    stored("local", arms: [ "ollama:qwen3:8b" ], seconds: 7.0)
    stored("hosted", arms: [ "minimax/minimax-m3" ])

    assert_match(/local/, board_for("local").columns.first.label)
    assert_no_match(/local/, board_for("hosted").columns.first.label)
  end

  test "every figure is a band with its median, and a figure that never moved is one number" do
    stored("hosted", arms: [ "m" ], accuracies: [ 0.90, 0.92, 0.94, 0.96 ], seconds: 1.0)

    printed = board_for("hosted").lines.join("\n")

    assert_match(/`accuracy` \| 0\.900\.\.0\.960 \(0\.930\)/, printed)
    assert_match(/latency median \(warm\) \| 1\.00s/, printed, "four identical passes is one number, not a range")
  end

  # THE SET THAT PREDATES THE MEASUREMENT. The first 2,400-call baseline was
  # taken before latency was recorded, and a table that printed 0.00s for it
  # would be inventing a fast model out of a missing field.
  test "a figure the set never recorded reads as not recorded and never as zero" do
    stored("old", arms: [ "m" ], seconds: nil, warmup: false)

    printed = board_for("old").lines.join("\n")

    assert_match(/latency median \(warm\) \| not recorded/, printed)
    assert_match(/first call \(cold, excluded\) \| not recorded/, printed)
    assert_no_match(/0\.00s/, printed)
  end

  test "the warm-up is reported beside the arm and says whether the daemon kept the model" do
    stored("local", arms: [ "ollama:qwen3:4b+nothink" ], seconds: 3.0, cold: 61.4, residency: "resident")

    assert_match(/first call \(cold, excluded\) \| 61\.4s \(resident\)/, board_for("local").lines.join("\n"))
  end

  # A HOSTED PROVIDER HAS NO MODEL TO KEEP IN MEMORY, so `not_local` in the
  # cold-start cell is noise in the column that matters least.
  test "a hosted arm's cold start is a time and not a residency answer" do
    stored("hosted", arms: [ "minimax/minimax-m3" ], cold: 0.6, residency: "not_local")

    printed = board_for("hosted").lines.join("\n")

    assert_match(/first call \(cold, excluded\) \| 0\.6s/, printed)
    assert_no_match(/not_local/, printed)
  end

  # TWO SETS SCORED ON DIFFERENT LABELS ARE NOT COMPARABLE, and a table is the
  # easiest place to forget it -- the same rule `Comparison` follows.
  test "a corpus digest mismatch is said out loud above nothing and below the table" do
    stored("one", arms: [ "a" ], digest: "aaaaaaaaaaaaaaaa")
    stored("two", arms: [ "b" ], digest: "bbbbbbbbbbbbbbbb")

    assert_match(/not scored on the same corpus/, board_for("one", "two").warnings.join("\n"))
    assert_empty board_for("one").warnings, "one set cannot disagree with itself"
  end

  # THE FIGURE THAT MAKES A CHEAPER MODEL WORTH ASKING ABOUT, and the one row
  # that reads the registry rather than the stored file -- so a model the
  # registry has never heard of has to read `unpriced` and never as free.
  test "cost per 1,000 calls is priced off the registry, and an unknown model says so" do
    create(:model)   # the registry row `mistralai/mistral-medium-3.1` is priced off
    stored("hosted", arms: [ "mistralai/mistral-medium-3.1", "nobody/never-heard-of-it" ])

    printed = board_for("hosted").lines.join("\n")

    assert_match(/cost per 1,000 calls \| \$[0-9]/, printed)
    assert_match(/unpriced/, printed)
    assert_no_match(/\$0\.00/, printed, "an unpriced model must not read as a free one")
  end

  test "a local arm's calls are free, which is not the same as unpriced" do
    stored("local", arms: [ "ollama:qwen3:4b+nothink" ], seconds: 3.0)

    assert_match(/cost per 1,000 calls \| free/, board_for("local").lines.join("\n"))
  end

  test "a rotation is named in the cell, because the arm's figures are then impure" do
    stored("hosted", arms: [ "m" ], rotations: 3)

    assert_match(/another model answered/, board_for("hosted").lines.join("\n"))
  end

  test "it gives no verdicts, which is eval:classifier_compare's job and not a table's" do
    stored("hosted", arms: [ "m" ])

    printed = board_for("hosted").lines.join("\n")

    %w[REAL NOISE INCONCLUSIVE BETTER WORSE].each do |word|
      assert_no_match(/#{word}/, printed)
    end
  end

  test "asked for no sets it reads every one it can find, and says so when there are none" do
    Eval.stub(:root, @root) do
      error = assert_raises(ArgumentError) { Eval::Classifier::Board.for_sets(nil) }
      assert_match(/no bench sets/, error.message)
    end
  end

  private
    # A SET WRITTEN THE WAY A RUN WRITES ONE, then read back off disk.
    def stored(name, arms: [ "m" ], accuracies: [ 0.9, 0.9, 0.9, 0.9 ], seconds: 1.0,
               cold: nil, residency: nil, digest: "1111111111111111", rotations: 0, warmup: true)
      passes = arms.flat_map do |arm|
        accuracies.each_with_index.map do |accuracy, index|
          { "arm" => arm, "rep" => index + 1, "accuracy" => accuracy, "strict_accuracy" => accuracy,
            "intent_accuracy" => 0.98, "refusal_agreement" => 0.95, "closed_set_misses" => 10,
            "latency_median" => seconds, "latency_p95" => seconds && seconds * 2,
            "rotations" => rotations, "failures" => 0, "readings" => [ reading(arm) ] }
        end
      end
      warmups = warmup ? arms.map { |arm| { "arm" => arm, "seconds" => cold, "residency" => residency } } : []

      directory = @root.join(name)
      FileUtils.mkdir_p(directory)
      File.write(directory.join(Eval::Classifier::RESULTS),
                 JSON.pretty_generate("name" => name, "corpus_size" => 300, "corpus_digest" => digest,
                                      "arms" => arms, "reps" => accuracies.size, "warmups" => warmups,
                                      "passes" => passes))
      true
    end

    def reading(arm)
      { "id" => "a-take", "shape" => "take", "right" => true, "intent_right" => true,
        "closed_set_miss" => false, "refusal_right" => true, "arguable" => false,
        "also_expected" => true, "also_answered" => true, "also_tp" => true, "also_fp" => false,
        "also_fn" => false, "also_omitted" => false, "answered_by" => arm, "error" => nil }
    end

    def board_for(*names)
      Eval.stub(:root, @root) { Eval::Classifier::Board.for_sets(names) }
    end
end
