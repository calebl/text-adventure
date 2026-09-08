require "test_helper"

# THE ENDING PROMPT'S OWN BASELINE, AND THE DIAGNOSIS OF THE ONE RATE THAT MOVED.
#
# `Eval::Prompt::KeptSetTest` one file over does this for the 2026-09-05
# baseline of the ninety-case corpus. This is the pair `ta-quest-ending` bought
# and checked in -- both sides, so the verdict replays offline and free -- plus
# the two lines that show why `item_not_held` reads WORSE on the after side and
# is not about the prose.
#
# NO DATABASE, NO KEY, NO NETWORK. That is the point rather than a convenience:
# forty calls were paid for once and the numbers are judgeable for ever by
# somebody who never paid for one.
class Eval::Prompt::EndingKeptSetTest < ActiveSupport::TestCase
  BEFORE = "prompt-ending-before-2026-09-08".freeze

  AFTER = "prompt-ending-after-2026-09-08".freeze

  ARM = "mistralai/mistral-medium-3.1".freeze

  # THE DIRECTORY IS DATED AND THE FILE SAYS WHICH RUN IT CAME FROM, which is
  # `Eval::Prompt::Result#write!`'s own rule: a set that was named once keeps
  # that name when it is summarised and kept.
  RUNS = { BEFORE => "ending-before", AFTER => "ending-after" }.freeze

  test "both sides load off disk with their provenance in the file" do
    [ BEFORE, AFTER ].each do |name|
      result = kept(name)

      assert_equal RUNS.fetch(name), result.name
      assert_equal [ ARM ], result.arms, "a set that does not say which model produced it is not a set"
      assert_equal [ ARM ], result.answered_by, "answered_by is the check on arms, and the pinning has to have held"
      assert_equal 4, result.reps, "four is Eval::Noise::MIN_RUNS -- fewer cannot be given a verdict"
      assert_equal 5, result.corpus_size
      assert_match(/\A2026-09-08/, result.recorded_at.to_s, "the date belongs in the file, not the filename")
    end
  end

  # THE DIGESTS ARE THE WHOLE POINT OF A KEPT PAIR. Same corpus both sides --
  # the cases did not move underneath the comparison -- and DIFFERENT prompts,
  # which is what makes it a before and an after rather than two runs.
  test "the pair scored one corpus and two prompts, and the corpus is today's" do
    assert_equal Eval::Prompt.digest(Eval::Prompt.corpus("ending")), kept(BEFORE).corpus_digest,
                 "the ending corpus moved since the baseline was taken -- re-run it, or the comparison " \
                 "is between two files"
    assert_equal kept(BEFORE).corpus_digest, kept(AFTER).corpus_digest
    assert_not_equal kept(BEFORE).prompt_digest, kept(AFTER).prompt_digest
  end

  # WHAT "BEFORE" MEANS HERE, and it is not a different wording of the same
  # prompt: the pass did not exist. The before side was played with the one line
  # in `Playthrough::Turn#play` that calls `Scene::Ending` disabled, so its
  # readings are the turn's OWN prose -- which is what the player used to read
  # last -- and no ending instructions were sent at all.
  test "the before side sent no ending instructions and the after side sent today's" do
    assert_nil kept(BEFORE).instruction_passes["ending"],
               "before the change there was no ending pass to send instructions for"
    assert_predicate kept(BEFORE).instruction_passes["narration"], :present?

    assert_equal Playthrough::PromptVersion.of(Scene::Ending::INSTRUCTIONS),
                 kept(AFTER).instruction_passes["ending"],
                 "the ending instructions moved since the baseline was taken, so this is a baseline for " \
                 "a prompt the app no longer sends -- re-run it"
  end

  # THE ONE SET IN THE REPOSITORY THAT IS DELIBERATELY NOT PROMPT-STABLE, and it
  # cannot be: the ending prompt carries `What just happened:`, which on this
  # pass is the prose the FIRST call of the same turn wrote. So the designated
  # case's whole prompt differs between repetitions by construction, and
  # `Eval::Prompt::Version`'s check says so. The facts the ENGINE owns in that
  # prompt are as fixed as any other case's; the corpus file says which they are.
  test "the after side records an unstable prompt, and that is what a second-call pass is" do
    assert_not kept(AFTER).prompt_stable,
               "if this is ever true, the ending prompt has stopped carrying the turn it followed"
    assert kept(BEFORE).prompt_stable, "the turn's own prose is a first call and is fixed"
  end

  # THE FIGURES THE PR WAS JUDGED ON, pinned so a later reader is comparing with
  # the same numbers. `words` and `commitments` are richness and are never
  # folded into a rate: the two sides score DIFFERENT PASSAGES of one turn (no
  # ending prose existed before), so the honest reading of a shorter paragraph
  # that names more records is the one the board prints.
  test "the after side wrote an ending for every case, and the prose named more of the records" do
    assert_equal 0, kept(AFTER).spread(:refusals, arm: ARM).max, "not one call declined to write an ending"
    assert_equal 0, kept(AFTER).spread(:failures, arm: ARM).max, "and not one failed, so no case fell back"
    assert_equal 0.0, kept(AFTER).spread(:truncated_prose, arm: ARM).max, "and none stopped mid-sentence"
    assert_operator kept(AFTER).spread(:commitments, arm: ARM).median, :>,
                    kept(BEFORE).spread(:commitments, arm: ARM).median,
                    "the ending names more rooms, exits, items and people the records know than the turn's " \
                    "own prose did"
  end

  # THE ONE RATE THAT MOVED, AND WHY IT IS THE CHECK RATHER THAN THE PROSE.
  #
  # `Story::Audit::Prose.place_names` aliases a name by its last word of at
  # least `Story::Audit::MIN_NAME_LENGTH` characters. "key" is three, so the
  # only alias `iron key` can have is **iron** -- and this world's central place
  # is the IRON GATE, which is in the engine's own outcome sentence. Every
  # flagged passage says the signet ring is in the player's hand, which the
  # records agree with, and names the gate within the check's window; not one of
  # them mentions a key.
  #
  # PINNED AS A TEST RATHER THAN WRITTEN IN A PR BODY, because it is a measured
  # claim about a check. The fix belongs to the check -- an item alias that is a
  # word of a `Location` name in the same story is not an item alias -- and that
  # is a measurement-file change with its own before/after over the pinned
  # corpora.
  test "item_not_held on the after side is the iron key aliased to iron" do
    assert_equal 4, Story::Audit::MIN_NAME_LENGTH, "the alias rule below is arithmetic on this number"
    assert_equal [ "iron key", "iron" ], Story::Audit::Prose.item_names("iron key")

    claimed = "You hold the signet ring, and the iron gate groans open behind you."

    assert_not claimed.match?(/\bkeys?\b/i), "the sentence names no key at all"
    assert Story::Audit.allocate.send(:possession_claimed?, claimed, "iron"),
           "and the check reads it as the player claiming the iron key"

    assert_operator kept(AFTER).spread(:item_not_held, arm: ARM).median, :>, 0.0,
                    "which is why the after side reads WORSE on this one rate"
  end

  # A KEPT SET IS A SUMMARY: the rows are dropped so it can live in the repo,
  # and everything the board and the comparison read has to survive that.
  test "the pair is a summary and still renders a comparison with no rows" do
    assert_empty kept(AFTER).rows, "a kept set holds no readings, on purpose"

    comparison = Eval::Prompt::Comparison.new(kept(BEFORE), kept(AFTER), io: nil)
    verdicts = comparison.verdicts(ARM)

    assert comparison.comparable_corpus?, "one corpus, both sides"
    assert comparison.cross_prompt?, "and two prompt versions, which is what makes it a before and an after"
    assert_predicate verdicts, :any?, "the checked-in pair is what replays the verdict offline"
    assert_includes verdicts.map(&:metric), :item_not_held
  end

  test "the manifest names both sides, so deleting one is a failing test" do
    assert_includes Eval::MEASUREMENT_FILES, "db/eval/#{BEFORE}/#{Eval::Prompt::RESULTS}"
    assert_includes Eval::MEASUREMENT_FILES, "db/eval/#{AFTER}/#{Eval::Prompt::RESULTS}"
    assert_includes Eval::MEASUREMENT_FILES, "test/fixtures/files/prompt_ending_corpus.yml"
  end

  private

  def kept(name) = (@kept ||= {})[name] ||= Eval::Prompt::Result.load(Eval.kept_root.join(name))
end
