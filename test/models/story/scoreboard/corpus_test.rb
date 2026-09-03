require "test_helper"

# THE PRECISION OF THE CHECKS, MEASURED ON 92 REAL PASSAGES AND PINNED HERE.
#
# `test/fixtures/files/eval_corpus.json` is every stored `Scene` description and
# `Interaction` action from the two worlds the captain has actually played --
# 68 passages -- plus the 24 narrations `narration_corpus.json` already holds,
# which two remote models wrote against six commands designed to break a world's
# laws. Nothing in it was written for this test.
#
# THE MEASUREMENT, as it stands:
#
#   passages                              92   (68 played, 24 from the lab sweep)
#   flags raised                          19
#   false positives                        0   -- every one read and signed for below
#   passages from the lab sweep flagged    0   -- the hardest negative case there is
#   turns the captain judged                3   -- and all three are caught, each by
#                                              a different check
#
# WHY IT IS A TEST AND NOT A LINE IN A PULL REQUEST, in the words
# `Story::AuditPrecisionTest` already uses: a false-positive rate that lives in
# a commit message decays the first time somebody widens a regex to catch one
# more case. Here, widening one until it flags "The name is stitched into the
# strap... but it is yours" fails the build.
#
# IF THIS TEST FAILS, read every flag that changed and judge it sentence by
# sentence before touching the fixture. A flag that cannot be defended is the
# change being wrong, not the test.
class Story::Scoreboard::CorpusTest < ActiveSupport::TestCase
  def setup
    @corpus = Story::Scoreboard::Corpus.load
  end

  test "the corpus is what it claims to be" do
    assert_equal 92, @corpus.passages.size
    assert_equal 24, @corpus.passages.count { |passage| passage.label.start_with?("lab/") }
    assert_equal 68, @corpus.passages.count { |passage| !passage.label.start_with?("lab/") }
    assert(@corpus.passages.all? { |passage| passage.text.present? })
    assert_equal @corpus.passages.size, @corpus.passages.map(&:label).uniq.size
  end

  # THE HEADLINE. Every flag the checks raise on the corpus is a flag written
  # down in the fixture and read by a person.
  test "the flags raised are exactly the flags the corpus expects" do
    expected = @corpus.passages.flat_map { |passage| passage.expect.map { |code| [ passage.label, code ] } }
    raised = @corpus.flags.map { |flag| [ flag.scene.label, flag.code ] }.uniq

    assert_equal expected.sort, raised.sort, <<~MESSAGE
      The set of flags on the frozen corpus changed.

      Read every new one and judge it before changing the fixture.

      #{@corpus.flags.map { |flag| "  [#{flag.code}] #{flag.scene.label}\n      #{flag.evidence[:claim]}" }.join("\n")}
    MESSAGE
  end

  test "the flags divide the way the measurement says they do" do
    assert_equal({ third_person_protagonist: 12, truncated_prose: 4, still_run: 2, unrecorded_departure: 1 },
                 @corpus.flags.group_by(&:code).transform_values(&:size))
  end

  # THE NEGATIVE CASE THAT MATTERS MOST: 24 narrations two models really wrote,
  # in the same two worlds, about weapons, memory, a locked door and a fire --
  # and not one of them is flagged. Prose that argues at length about things it
  # does not have is exactly what killed the two heuristics recorded in
  # `Story::Audit`'s header.
  test "not one of the twenty-four lab narrations is flagged" do
    flagged = @corpus.flags.select { |flag| flag.scene.label.start_with?("lab/") }

    assert_empty flagged, flagged.map { |flag| "#{flag.scene.label}: #{flag.headline}" }.join("\n")
  end

  # THE VALIDATION THE WHOLE THING RESTS ON. The captain marked three turns
  # while playing; a scoreboard that cannot catch the errors he noticed unaided
  # would be measuring something else.
  test "every turn the captain judged is caught, each by a different check" do
    judged = @corpus.passages.select { |passage| passage.verdict.present? }
    by_label = @corpus.flags.group_by { |flag| flag.scene.label }

    assert_equal 3, judged.size

    caught = judged.to_h { |passage| [ passage.label, by_label.fetch(passage.label, []).map(&:code) ] }

    assert_equal({ "unrecorded/scene-59" => [ :truncated_prose ],
                   "unrecorded/scene-63" => [ :still_run ],
                   "unrecorded/scene-64" => [ :unrecorded_departure ] }, caught)
  end

  test "the three verdicts are his, with the note that explains each" do
    verdicts = @corpus.verdicts.transform_keys(&:label)

    assert_equal({ "unrecorded/scene-59" => "bad", "unrecorded/scene-63" => "weak",
                   "unrecorded/scene-64" => "bad" }, verdicts)
    assert_equal "truncated", @corpus.passages.find { |p| p.label == "unrecorded/scene-59" }.note
  end

  # A CHECK THE CORPUS CANNOT ANSWER IS UNAVAILABLE, NOT CLEAN. Five of the
  # eleven read records a frozen passage does not carry, and reporting them as
  # zero would be a lie that reads like good news. `take_denied` and
  # `pickup_invented` are the newest two and the clearest case: a passage here
  # carries the state around the prose and never the CHANGE the turn made, so
  # they belong to `Story::Scoreboard::Transitions` and are unavailable here.
  test "the checks that need records around the passage are reported unavailable" do
    assert_equal %i[truncated_prose third_person_protagonist unrecorded_departure still_run],
                 @corpus.available_checks

    %i[unreachable_transition item_not_held reached_for_nothing take_denied pickup_invented].each do |code|
      assert_equal 0, @corpus.judgeable_for(code), "#{code} has no denominator on a corpus that cannot run it"
    end
  end

  # THE TRANSITION CORPUS ANSWERS EXACTLY THE TWO AND NOTHING ELSE, which is
  # the same honesty from the other side: 119 real take and drop turns with the
  # transition each one made frozen beside the prose, and no graph, no drift
  # rows, no protagonist names and no still-run length. The rates are pinned in
  # `Story::Audit::TransitionTest`; what is pinned here is the shape.
  test "the transition corpus answers the two transition checks and nothing else" do
    transitions = Story::Scoreboard::Transitions.load

    assert_equal 119, transitions.scanned
    assert_equal %i[take_denied pickup_invented], transitions.available_checks
    assert_equal 59, transitions.judgeable_for(:take_denied)
    assert_equal 60, transitions.judgeable_for(:pickup_invented)

    (Story::Scoreboard::CHECKS.keys - transitions.available_checks).each do |code|
      assert_equal 0, transitions.judgeable_for(code), "#{code} has no denominator on a corpus of transitions"
    end
  end

  # And the whole file's flags, pinned the way the frozen corpus's 19 are: 47
  # denied takes and 5 invented pickups over 119 real turns, of which the
  # 480-turn baseline set contributes 28 and 4.
  test "the transition corpus raises exactly the flags it is pinned at" do
    transitions = Story::Scoreboard::Transitions.load

    assert_equal({ take_denied: 47, pickup_invented: 5 },
                 transitions.flags.group_by(&:code).transform_values(&:size))
    assert(transitions.flags.all? { |flag| flag.evidence[:claim].present? },
           "a flag nobody can read the sentence of is a flag nobody can judge")
  end

  test "reading the transition corpus touches no table and needs no database" do
    ActiveRecord::Base.connection.stub(:execute, ->(*) { raise "the frozen corpus must not query" }) do
      assert_equal 52, Story::Scoreboard::Transitions.load.flags.size
    end
  end

  # Each denominator is the passages carrying the facts that check reads, not
  # every passage: an `Interaction#action` declares no protagonist and has no
  # turn before it.
  test "each check is scored out of the passages that could have answered it" do
    assert_equal 92, @corpus.judgeable_for(:truncated_prose)
    assert_equal 78, @corpus.judgeable_for(:third_person_protagonist)
    assert_equal 74, @corpus.judgeable_for(:unrecorded_departure)
    assert_equal 74, @corpus.judgeable_for(:still_run)
  end

  # THE THRESHOLD, RE-DERIVED RATHER THAN TRUSTED. `Story::Audit::STILL_RUN` is
  # 4 because 4 is the LONGEST run that still catches the one turn the captain
  # marked `weak` with *"this has stretch on too long"*. Five catches nothing;
  # three and two catch it along with four and eight unlabelled turns. If a
  # change makes a different threshold the right answer, this fails and the
  # constant gets re-argued rather than nudged.
  test "four is the longest still run that still catches the turn he called weak" do
    his_turn = @corpus.passages.find { |passage| passage.verdict == "weak" }
    sensitivity = (2..6).to_h do |threshold|
      runs = @corpus.passages.select { |passage| passage.still_run >= threshold && passage.present.any? }
      [ threshold, runs ]
    end

    assert_equal({ 2 => 10, 3 => 5, 4 => 2, 5 => 0, 6 => 0 }, sensitivity.transform_values(&:size))
    assert_includes sensitivity.fetch(Story::Audit::STILL_RUN), his_turn
    assert_empty sensitivity.fetch(Story::Audit::STILL_RUN + 1),
                 "a longer run than #{Story::Audit::STILL_RUN} catches nothing, so it cannot be the threshold"
  end

  test "reading the corpus touches no table and needs no database" do
    ActiveRecord::Base.connection.stub(:execute, ->(*) { raise "the frozen corpus must not query" }) do
      assert_equal 19, Story::Scoreboard::Corpus.load.flags.size
    end
  end

  test "the corpus never calls a model" do
    BaseAgent.stub(:new, ->(*) { raise "the corpus must not call a model" }) do
      assert_predicate @corpus.flags, :any?
    end
  end

  test "it has no unjudged checks, because a passage either carries a fact or the check is unavailable" do
    assert_empty @corpus.unjudged
  end
end
