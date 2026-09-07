require "test_helper"

# THE PRECISION OF THE CHECKS, MEASURED ON REAL PASSAGES AND PINNED HERE.
#
# `test/fixtures/files/eval_corpus.json` is real prose out of the captain's own
# database with the records around it written down, plus the 24 narrations
# `narration_corpus.json` already holds, which two remote models wrote against
# six commands designed to break a world's laws. Nothing in it was written for
# this test. `rake game:corpus` (`Story::Scoreboard::Capture`) is what grows it,
# and its header is the rule for how.
#
# THE MEASUREMENT, as it stands:
#
#   passages                             149   (125 played, 24 from the lab sweep)
#   flags raised                          29
#   false positives                        0   -- every one read and signed for below
#   passages from the lab sweep flagged    0   -- the hardest negative case there is
#   turns the captain judged              43   -- 7 of them caught
#
# WHAT THE REFRESH OF 2026-09-07 ADDED, and it is the whole reason the counts
# above are not the ones this file was born with: 57 passages, taken from his
# 43 verdicts and the turns either side of them. They earned 10 new flags, all
# `third_person_protagonist`, over 5 turns -- and each turn earns two because
# the same sentence trips both readings, the name as a sentence subject and the
# short form as a coreference:
#
#   unrecorded/scene-65   "Odile Vance stands halfway along the hall, her back
#                         to you" -- he marked it `bad`, and his note says
#                         "protagonist is referred to in the 3rd person".
#   unrecorded/scene-66   "Odile Vance stands at the far table, her back to
#                         you" -- `bad`, "more 3rd person protagonist".
#   unrecorded/scene-105  "Odile Vance stands near the door to Ward Office 12
#                         ... as though she has been waiting for you to
#                         return" -- `bad`, "3rd person protagonist".
#   unrecorded/scene-108  "Odile Vance stands by the shelves, her back to you"
#                         -- `bad`, "protagonist 3rd person".
#   unrecorded/scene-109  "Odile Vance stands near the table ... the creak of
#                         the floorboards under your feet" -- unjudged, and the
#                         same sentence as the four he did judge: the narration
#                         puts the player in the room opposite herself.
#
# Every one of them is the error the check was built for, in the most literal
# form it takes, and four of the five carry his own words saying so.
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
    assert_equal 149, @corpus.passages.size
    assert_equal 24, @corpus.passages.count { |passage| passage.label.start_with?("lab/") }
    assert_equal 125, @corpus.passages.count { |passage| !passage.label.start_with?("lab/") }
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
    assert_equal({ third_person_protagonist: 22, truncated_prose: 4, still_run: 2, unrecorded_departure: 1 },
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

  # THE VALIDATION THE WHOLE THING RESTS ON, AND THE HALF OF IT THAT IS STILL
  # MISSING. He judged 43 turns while playing; 7 of them are caught, each by the
  # check the error belongs to. A scoreboard that caught none of the errors he
  # noticed unaided would be measuring something else.
  #
  # THE OTHER 36 ARE NOT A FAILURE OF THIS FIXTURE AND MUST NOT BE EDITED AWAY.
  # 16 of them he called `good`, and a check firing on those would be the bad
  # outcome. Most of the rest are one complaint in his own words -- *"I just
  # picked it up. Why does it say I already hold it?"* -- which is
  # `take_denied`, a check this corpus CANNOT ANSWER because a frozen passage
  # carries the state around the prose and never the change the turn made. It
  # is answered on `Story::Scoreboard::Transitions`, and that split is pinned
  # below. `Story::Scoreboard#missed_verdicts` is where a reader sees the rest.
  test "the turns the captain judged that a check catches, each by the check the error belongs to" do
    judged = @corpus.passages.select { |passage| passage.verdict.present? }
    by_label = @corpus.flags.group_by { |flag| flag.scene.label }

    assert_equal 43, judged.size
    assert_equal({ "good" => 16, "bad" => 24, "weak" => 3 }, judged.map(&:verdict).tally)

    caught = judged.filter_map do |passage|
      flags = by_label[passage.label]
      [ passage.label, flags.map(&:code).uniq ] if flags
    end.to_h

    assert_equal({ "unrecorded/scene-59" => [ :truncated_prose ],
                   "unrecorded/scene-63" => [ :still_run ],
                   "unrecorded/scene-64" => [ :unrecorded_departure ],
                   "unrecorded/scene-65" => [ :third_person_protagonist ],
                   "unrecorded/scene-66" => [ :third_person_protagonist ],
                   "unrecorded/scene-105" => [ :third_person_protagonist ],
                   "unrecorded/scene-108" => [ :third_person_protagonist ] }, caught)
  end

  # NOTHING A CHECK CATCHES IS A TURN HE LIKED. The figure that would discredit
  # the board outright, pinned on its own so it cannot be lost inside the map
  # above: every verdict on a flagged turn is `bad` or `weak`.
  test "no check fires on a turn the captain called good" do
    flagged = @corpus.flags.map(&:scene).uniq.select { |passage| passage.verdict.present? }

    assert_equal({ "bad" => 6, "weak" => 1 }, flagged.map(&:verdict).tally)
  end

  # HIS VERDICTS, ALL OF THEM, KEYED BY THE TURN THEY ARE ON -- the ground truth
  # the whole instrument is measured against, written out in full so a capture
  # that dropped or reassigned one fails here rather than quietly moving a rate.
  # `rake game:corpus` writes these and never `expect`; see its header.
  HIS_VERDICTS = {
    "iron/scene-123" => "good",
    "iron/scene-124" => "good",
    "iron/scene-126" => "good",
    "iron/scene-127" => "good",
    "iron/scene-128" => "bad",
    "iron/scene-129" => "bad",
    "iron/scene-131" => "good",
    "lunar/scene-70" => "weak",
    "lunar/scene-73" => "bad",
    "lunar/scene-74" => "good",
    "lunar/scene-75" => "good",
    "lunar/scene-77" => "bad",
    "lunar/scene-78" => "bad",
    "lunar/scene-79" => "bad",
    "lunar/scene-80" => "bad",
    "lunar/scene-82" => "bad",
    "lunar/scene-83" => "bad",
    "lunar/scene-84" => "bad",
    "lunar/scene-118" => "good",
    "lunar/scene-119" => "good",
    "unrecorded/scene-19" => "good",
    "unrecorded/scene-59" => "bad",
    "unrecorded/scene-63" => "weak",
    "unrecorded/scene-64" => "bad",
    "unrecorded/scene-65" => "bad",
    "unrecorded/scene-66" => "bad",
    "unrecorded/scene-69" => "bad",
    "unrecorded/scene-87" => "good",
    "unrecorded/scene-88" => "bad",
    "unrecorded/scene-89" => "bad",
    "unrecorded/scene-91" => "bad",
    "unrecorded/scene-92" => "bad",
    "unrecorded/scene-93" => "weak",
    "unrecorded/scene-94" => "bad",
    "unrecorded/scene-96" => "good",
    "unrecorded/scene-98" => "good",
    "unrecorded/scene-99" => "good",
    "unrecorded/scene-100" => "bad",
    "unrecorded/scene-103" => "bad",
    "unrecorded/scene-105" => "bad",
    "unrecorded/scene-106" => "good",
    "unrecorded/scene-107" => "good",
    "unrecorded/scene-108" => "bad"
  }.freeze

  test "the verdicts are his, and the notes that explain them come with them" do
    assert_equal HIS_VERDICTS, @corpus.verdicts.transform_keys(&:label)

    assert_equal "truncated", @corpus.passages.find { |p| p.label == "unrecorded/scene-59" }.note
    assert_equal "3rd person protagonist", @corpus.passages.find { |p| p.label == "unrecorded/scene-105" }.note
  end

  # THIRTY IS WHERE `Story::Scoreboard` STOPS SAYING UNESTABLISHED and starts
  # printing agreement as figures. It was 3 verdicts until the refresh of
  # 2026-09-07 and the threshold had never been crossed; this pins that it now
  # is, so a capture that lost verdicts shows up as the report going quiet again
  # rather than as nothing at all.
  test "the corpus carries enough verdicts for agreement to be printed as figures" do
    board = Story::Scoreboard.corpus

    assert_operator board.labelled, :>=, Story::Scoreboard::MIN_VERDICTS
    assert_predicate board, :agreement_established?
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
    assert_equal 149, @corpus.judgeable_for(:truncated_prose)
    assert_equal 133, @corpus.judgeable_for(:third_person_protagonist)
    assert_equal 128, @corpus.judgeable_for(:unrecorded_departure)
    assert_equal 128, @corpus.judgeable_for(:still_run)
  end

  # THE THRESHOLD, RE-DERIVED RATHER THAN TRUSTED. `Story::Audit::STILL_RUN` is
  # 4 because 4 is the LONGEST run that still catches the one turn the captain
  # marked `weak` with *"this has stretch on too long"*. Five catches nothing;
  # three and two catch it along with four and eight unlabelled turns. If a
  # change makes a different threshold the right answer, this fails and the
  # constant gets re-argued rather than nudged.
  test "four is the longest still run that still catches the turn he called weak" do
    his_turn = @corpus.passages.find { |passage| passage.label == "unrecorded/scene-63" }
    sensitivity = (2..6).to_h do |threshold|
      runs = @corpus.passages.select { |passage| passage.still_run >= threshold && passage.present.any? }
      [ threshold, runs ]
    end

    assert_equal({ 2 => 11, 3 => 6, 4 => 2, 5 => 0, 6 => 0 }, sensitivity.transform_values(&:size))
    assert_includes sensitivity.fetch(Story::Audit::STILL_RUN), his_turn
    assert_empty sensitivity.fetch(Story::Audit::STILL_RUN + 1),
                 "a longer run than #{Story::Audit::STILL_RUN} catches nothing, so it cannot be the threshold"
  end

  test "reading the corpus touches no table and needs no database" do
    ActiveRecord::Base.connection.stub(:execute, ->(*) { raise "the frozen corpus must not query" }) do
      assert_equal 29, Story::Scoreboard::Corpus.load.flags.size
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
