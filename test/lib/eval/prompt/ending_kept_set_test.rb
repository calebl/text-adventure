require "test_helper"

# THE ENDING PROMPT'S OWN BASELINE, RE-BOUGHT SO THE FIGURE IS LIVE AGAIN.
#
# `Eval::Prompt::KeptSetTest` one file over does this for the 2026-09-05
# baseline of the ninety-case corpus. This is the pair the ending prompt is
# judged against -- both sides, so the verdict replays offline and free.
#
# WHY THERE ARE TWO PAIRS ON DISK AND THIS FILE PINS THE SECOND ONE. The pair
# `ta-quest-ending` bought (PR 162) read `item_not_held` 0.000 -> 0.200 REAL,
# and the diagnosis was the CHECK: `Story::Audit::Prose.item_names` aliased
# `iron key` to **iron**, which is a word of this world's central place, the
# IRON GATE. PR 164 fixed that -- an item's alias is its own last word and never
# an earlier one -- but **a kept set is a summary and holds no prose**
# (`Eval::Prompt::Result#summary`), so the fix could not re-score the figure it
# invalidated. It could only be re-bought. The captain authorized that on
# 2026-09-08 and this is it: same corpus, same model, same four repetitions a
# side, the before side staged the same way, and NOTHING model-facing changed
# between the two pairs -- the `ending` instructions digest is identical across
# both after sides, which is asserted below.
#
# THE 2026-09-08 PAIR STAYS ON DISK AS HISTORY and keeps its place in
# `Eval::MEASUREMENT_FILES`; the test at the bottom of this file is what says
# what it is and why nothing may be concluded from its rates any more.
#
# NO DATABASE, NO KEY, NO NETWORK. That is the point rather than a convenience:
# the calls were paid for once and the numbers are judgeable for ever by
# somebody who never paid for one.
class Eval::Prompt::EndingKeptSetTest < ActiveSupport::TestCase
  BEFORE = "prompt-ending-before-2026-09-08-2".freeze

  AFTER = "prompt-ending-after-2026-09-08-2".freeze

  # THE SUPERSEDED PAIR, pinned only so that deleting it is a failing test and
  # so that a reader who finds its rates knows what they are reading.
  SUPERSEDED = %w[prompt-ending-before-2026-09-08 prompt-ending-after-2026-09-08].freeze

  ARM = "mistralai/mistral-medium-3.1".freeze

  test "both sides load off disk with their provenance in the file" do
    [ BEFORE, AFTER ].each do |name|
      result = kept(name)

      assert_equal name, result.name, "a set is named for the directory it was kept in"
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
  # last -- and no ending instructions were sent at all. The re-take was staged
  # by disabling that same line and reverting it, which is why the two before
  # sides agree on every digest a prompt has.
  test "the before side sent no ending instructions and the after side sent today's" do
    assert_nil kept(BEFORE).instruction_passes["ending"],
               "before the change there was no ending pass to send instructions for"
    assert_predicate kept(BEFORE).instruction_passes["narration"], :present?

    assert_equal Playthrough::PromptVersion.of(Scene::Ending::INSTRUCTIONS),
                 kept(AFTER).instruction_passes["ending"],
                 "the ending instructions moved since the baseline was taken, so this is a baseline for " \
                 "a prompt the app no longer sends -- re-run it"
  end

  # THE RE-TAKE MEASURED THE SAME PROMPT, which is what makes it a re-take of
  # one measurement rather than a second experiment. If this ever fails, the
  # ending prompt moved between the two pairs and the older one is no longer a
  # thing this one can be read beside.
  test "the two after sides sent byte-identical ending instructions" do
    assert_equal Eval::Prompt::Result.load(Eval.kept_root.join(SUPERSEDED.last)).instruction_passes["ending"],
                 kept(AFTER).instruction_passes["ending"],
                 "nothing model-facing changed in the re-buy, and this is the assertion that says so"
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

  # THE FIGURES THE PAIR WAS JUDGED ON, pinned so a later reader is comparing
  # with the same numbers. `words` and `commitments` are richness and are never
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

  # THE FIGURE THE RE-BUY WAS FOR, AND IT IS LIVE RATHER THAN FROZEN NOW.
  #
  # Under the fixed check `item_not_held` is 0.000 on the before side and reads
  # 0.000 on half the after side's repetitions, so the verdict is **NOISE** --
  # where the 2026-09-08 pair, read by the aliasing check, called the same
  # comparison REAL at p=0.0286. That reversal is the whole result of the
  # re-buy and it is asserted rather than described, because a paragraph
  # claiming it would be exactly the thing this file exists to replace.
  #
  # THE RESIDUAL READINGS ARE NOT THE PROMPT EITHER, and this is reported and
  # NOT fixed here: the audit is somebody else's slice, and a measurement
  # predicate is never bent to improve the run that found it. Both flagged
  # passages put the iron key *in the mud*, and the check still fires because a
  # real claim about the ring (`in your grip`) precedes the key in the same
  # clause list -- so the possession window carries the first item's claim onto
  # the second. `#a possession phrase still reaches across a comma` below is
  # that class, isolated offline and for free.
  test "item_not_held is NOISE across the re-bought pair, which is what the fixed check reads" do
    verdict = Eval::Prompt::Comparison.new(kept(BEFORE), kept(AFTER), io: nil)
                                      .verdicts(ARM).find { |row| row.metric == :item_not_held }.verdict

    assert_equal 0.0, kept(BEFORE).spread(:item_not_held, arm: ARM).max,
                 "the turn's own prose never claimed an item somebody else holds"
    assert_not verdict.real?,
               "the aliasing check called this REAL; the fixed one cannot, and if it does again the ending " \
               "prose has really started handing the player things the records do not give it"
    assert_includes kept(AFTER).spread(:item_not_held, arm: ARM).values, 0.0,
                    "half the repetitions are clean, which is what a band spanning zero is made of"
  end

  # THE REGRESSION FOR THE FIX THAT FORCED THE RE-BUY. The alias that flagged
  # five clean passages is gone, and the sentence that convicted the player of
  # holding a key it never mentions no longer matches any name the item has.
  test "the iron key no longer aliases to the world's iron gate" do
    assert_equal 4, Story::Audit::MIN_NAME_LENGTH, "the alias rule below is arithmetic on this number"

    assert_equal [ "iron key" ], Story::Audit::Prose.item_names("iron key"),
                 "an item's alias is its own last word, and \"key\" is under MIN_NAME_LENGTH"
    assert_equal [ "iron gate", "gate" ], Story::Audit::Prose.place_names("iron gate"),
                 "the place keeps its alias -- that change was to items only"

    claimed = "You hold the signet ring, and the iron gate groans open behind you."

    assert_not claimed.match?(/\bkeys?\b/i), "the sentence names no key at all"
    assert Story::Audit.allocate.send(:possession_claimed?, claimed, "iron"),
           "the possession grammar is untouched: it still reads \"iron\" as a claim"
    assert_empty Story::Audit::Prose.item_names("iron key")
                                    .select { |name| Story::Audit.allocate.send(:possession_claimed?, claimed, name) },
                 "but no name the iron key answers to is in that sentence, so the check cannot fire on it"
  end

  # THE FALSE-POSITIVE CLASS THE RE-BOUGHT AFTER SIDE STILL CARRIES, pinned as a
  # test so the next reader of that 0.100 is not left guessing, and pinned as
  # what it is rather than argued about in a PR. Both sentences are the real
  # prose, trimmed; both say the key is on the ground.
  #
  # NOT FIXED HERE. `Story::Audit` is a measurement file and this run is what
  # found the class, so closing it belongs in a slice with its own before and
  # after over the pinned corpora -- the same rule that kept the alias fix out
  # of PR 162.
  test "a possession phrase still reaches across a comma onto the next item named" do
    audit = Story::Audit.allocate

    assert_not audit.send(:possession_claimed?, "the iron key discarded in the mud beside his corpse", "iron key"),
               "on its own the sentence is read correctly: nobody is holding it"
    assert audit.send(:possession_claimed?,
                      "the prince's signet ring heavy in your grip, the iron key discarded in the mud",
                      "iron key"),
           "but a true claim about the RING carries onto the key, which is the class and the whole of the " \
           "after side's residual rate"
  end

  # THE INVERSE, because a check that has stopped firing looks exactly like a
  # check that has been fixed. A thing whose noun is long enough still aliases,
  # and a real claim about a thing the records give to somebody else still
  # convicts -- on this world's OTHER item, whose name the ending prose really
  # does write.
  test "an item the records place elsewhere still fires on its own alias" do
    names = Story::Audit::Prose.item_names("prince's signet ring")

    assert_equal [ "prince's signet ring", "ring" ], names, "a four-letter noun still earns its alias"

    claimed = "You carry the ring in your fist as the iron gate groans open behind you."

    assert names.any? { |name| Story::Audit.allocate.send(:possession_claimed?, claimed, name) },
           "the player is told they have it, which is what the check reads"
    assert_not Story::Audit::Prose.item_names("Ward Office 12 daybook")
                                  .any? { |name| Story::Audit.allocate.send(:possession_claimed?, claimed, name) },
               "and it is the named thing that fires, not any item in the story"
  end

  # A KEPT SET IS A SUMMARY: the rows are dropped so it can live in the repo,
  # and everything the board and the comparison read has to survive that. It is
  # also the reason this pair had to be re-bought at all, which is worth knowing
  # before keeping the next one.
  test "the pair is a summary and still renders a comparison with no rows" do
    assert_empty kept(AFTER).rows, "a kept set holds no readings, on purpose"

    comparison = Eval::Prompt::Comparison.new(kept(BEFORE), kept(AFTER), io: nil)
    verdicts = comparison.verdicts(ARM)

    assert comparison.comparable_corpus?, "one corpus, both sides"
    assert comparison.cross_prompt?, "and two prompt versions, which is what makes it a before and an after"
    assert_predicate verdicts, :any?, "the checked-in pair is what replays the verdict offline"
    assert_includes verdicts.map(&:metric), :item_not_held
  end

  # THE SUPERSEDED PAIR IS HISTORY AND IS LABELLED AS HISTORY. Its rates were
  # computed by the aliasing check while the calls were being paid for, and a
  # summary carries no prose to re-score -- so that 0.200 is a record of what
  # the OLD check read on prose nobody kept, and nothing about the prompt may be
  # concluded from it. It stays on disk because deleting the evidence a ruling
  # was made on is not a tidy-up.
  test "the 2026-09-08 pair is still on disk, and its item_not_held is the old check's reading" do
    superseded = Eval::Prompt::Result.load(Eval.kept_root.join(SUPERSEDED.last))

    assert_operator superseded.spread(:item_not_held, arm: ARM).median, :>,
                    kept(AFTER).spread(:item_not_held, arm: ARM).median,
                    "the aliasing check read this worse than the fixed one does, which is why it was re-bought"
    assert_equal kept(AFTER).instruction_passes, superseded.instruction_passes,
                 "and it measured the same prompt, so the only difference between the pairs is the check"
  end

  test "the manifest names both pairs, so deleting one is a failing test" do
    ([ BEFORE, AFTER ] + SUPERSEDED).each do |name|
      assert_includes Eval::MEASUREMENT_FILES, "db/eval/#{name}/#{Eval::Prompt::RESULTS}"
    end
    assert_includes Eval::MEASUREMENT_FILES, "test/fixtures/files/prompt_ending_corpus.yml"
  end

  private

  def kept(name) = (@kept ||= {})[name] ||= Eval::Prompt::Result.load(Eval.kept_root.join(name))
end
