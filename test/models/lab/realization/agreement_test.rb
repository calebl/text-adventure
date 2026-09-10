require "test_helper"

# THE AGREEMENT FIGURE, AND EVERY WAY IT IS ALLOWED TO REFUSE TO REPORT ONE.
#
# `Lab::Realization::Agreement`'s header is the design. What is pinned here is
# the honesty: the per-check denominators, the threshold, the two disagreement
# lists, and the two sets that never pool.
class Lab::Realization::AgreementTest < ActiveSupport::TestCase
  # THE MAPPING HAS TO STAY COMPLETE. A check added to the scorer that nobody
  # files here would fall out of every denominator silently, which is exactly the
  # failure mode this instrument exists to prevent one level up.
  test "every check is filed by aspect whole sample or unavailable quality judgement" do
    filed = Lab::Realization::Agreement::AREAS.values.flatten.uniq +
            Lab::Realization::Agreement::GRADED_BY_THE_WHOLE_SAMPLE +
            Lab::Realization::Agreement::NOT_A_QUALITY_CHECK

    assert_equal Eval::Realization.checks.sort, filed.uniq.sort
  end

  test "an aspect may only name a check the scorer has" do
    stray = Lab::Realization::Agreement::AREAS.values.flatten.uniq - Eval::Realization.checks

    assert_empty stray
  end

  test "the aspects an area is keyed by are the aspects a sample can carry" do
    stray = Lab::Realization::Agreement::AREAS.keys - Lab::Realization::Sample::ASPECTS

    assert_empty stray
  end

  test "a good room may leave an optional quest target unbound" do
    sample = create(:lab_realization_sample, :a_room, verdict: "good")
    row = sample.row.deep_dup
    row["facts"]["quest_request"] = { "trigger_kind" => "hold_item" }
    row["after"] = { "quest_admitted" => false }
    sample.update!(row: row)
    reading = tuning_set.reading(:quest_target_not_admitted)
    assert_equal 1, reading.judgeable
    assert_equal 0, reading.eligible
    assert_empty reading.suspects
  end

  test "optional take-up does not conceal a prose verdict the checks missed" do
    sample = create(:lab_realization_sample, verdict: "bad", aspects: "prose", row: {
      "facts" => { "quest_request" => { "trigger_kind" => "hold_item" } },
      "answers" => { "detail" => { "description" => "An empty room." } },
      "after" => { "quest_admitted" => false }
    })
    assert_equal [ sample ], tuning_set.missed
  end

  # A VERDICT ONLY COUNTS TOWARDS A CHECK IF IT SAYS SOMETHING ABOUT IT. The
  # honesty requirement in one assertion: a room he faulted for its PROSE is in
  # no exit check's denominator, and it is in no people check's either.
  test "a bad verdict is eligible only for the checks its aspects name" do
    kind = create(:lab_realization_kind)
    create(:lab_realization_sample, :a_room, kind: kind, verdict: "bad", aspects: "prose")

    set = tuning_set

    assert_equal 0, set.reading(:people_short_of_the_pick).eligible
    assert_equal 0, set.reading(:exit_already_reachable).eligible
    assert_equal 1, set.reading(:people_short_of_the_pick).judgeable,
                 "the check could still be read on the row -- the two denominators are different questions"
  end

  test "a bad verdict on the people is eligible for the people checks and agrees when one fired" do
    kind = create(:lab_realization_kind)
    create(:lab_realization_sample, :a_room, kind: kind, verdict: "bad", aspects: "people")

    reading = tuning_set.reading(:people_short_of_the_pick)

    assert_equal 1, reading.eligible
    assert_equal 1, reading.agreed
    assert_equal 1, reading.on_bad
    assert_equal 0, reading.on_good
    assert_equal "1 of 1", reading.fraction
  end

  # THE ONE ASPECT THAT SUBSUMES THE OTHERS, which is `Lab::Realization::Sample`'s
  # own reading of it.
  test "not the place i meant is eligible for every check judgeable on the sample" do
    kind = create(:lab_realization_kind, :a_building)
    create(:lab_realization_sample, :a_building_that_picked_nothing, kind: kind,
                                    verdict: "bad", aspects: "not_the_place_i_meant")

    set = tuning_set

    assert_equal 1, set.reading(:parameters_declined).eligible, "no aspect names this check by itself"
    assert_equal 1, set.reading(:parameters_declined).agreed
    assert_equal 1, set.reading(:parameters_declined).on_bad
  end

  # A GOOD VERDICT SPEAKS TO EVERYTHING, so a check firing on one is a suspect
  # and the disagreement is reported with the sample rather than only counted.
  test "a check that fired on a sample he called good is a suspect and disagrees" do
    kind = create(:lab_realization_kind)
    sample = create(:lab_realization_sample, :a_room, kind: kind, verdict: "good")

    set = tuning_set
    reading = set.reading(:people_short_of_the_pick)

    assert_equal 1, reading.eligible
    assert_equal 0, reading.agreed
    assert_equal 1, reading.on_good
    assert_equal [ sample ], set.suspects.map(&:sample)
    assert_equal [ :people_short_of_the_pick ], set.suspects.map(&:code)
  end

  test "a check that stayed quiet on a sample he called good agrees" do
    kind = create(:lab_realization_kind, :a_building)
    create(:lab_realization_sample, :a_building, kind: kind, verdict: "good")

    reading = tuning_set.reading(:parameters_the_engine_narrowed)

    assert_equal 1, reading.eligible
    assert_equal 1, reading.agreed
    assert_equal 0, reading.fired
    assert_empty tuning_set.suspects
  end

  # THE OTHER HALF OF THE QUESTION, and the more useful half while the labels are
  # few: a room he did not want that nothing flagged is the next check to write.
  test "a weak or bad sample no check fired on is a miss, with no aspect needed" do
    kind = create(:lab_realization_kind, :a_building)
    missed = create(:lab_realization_sample, :a_building, kind: kind, verdict: "bad")
    create(:lab_realization_sample, :a_building, kind: kind, verdict: "good")

    assert_equal [ missed ], tuning_set.missed
  end

  test "a bad sample a check did fire on is not a miss" do
    kind = create(:lab_realization_kind)
    create(:lab_realization_sample, :a_room, kind: kind, verdict: "bad", aspects: "prose")

    assert_empty tuning_set.missed, "something flagged it, even though the aspect graded no check"
  end

  # UNAVAILABLE, NEVER NOUGHT. A check nothing drawn could be read on is reported
  # as having no evidence rather than as perfect agreement.
  test "a check nothing gave anything to read is unavailable rather than agreed" do
    kind = create(:lab_realization_kind, :a_building)
    create(:lab_realization_sample, :a_building, kind: kind, verdict: "good")

    reading = tuning_set.reading(:exit_already_reachable)

    assert_equal 0, reading.judgeable
    assert_not reading.available?
    assert_equal 0, reading.agreed
    assert_nil reading.percentage
  end

  # AND A *DON'T CARE* EXPECTATION IS THE SAME STATE, arrived at from the other
  # end: a lab sample carries no `expects_inside` hand label, so both inside
  # checks are out of both denominators rather than scored against a claim
  # nobody made.
  test "the inside checks are unavailable because a lab sample declares no expects_inside" do
    kind = create(:lab_realization_kind)
    create(:lab_realization_sample, :a_room, kind: kind, verdict: "good")

    set = tuning_set

    assert_equal 0, set.reading(:inside_where_the_world_wanted_none).judgeable
    assert_equal 0, set.reading(:no_inside_where_the_world_wanted_one).judgeable
    assert_equal 1, set.reading(:inside_declined).judgeable, "the check that needs no label still reads"
  end

  test "an unjudged sample is counted and is in no denominator" do
    kind = create(:lab_realization_kind)
    create(:lab_realization_sample, :a_room, kind: kind)

    set = tuning_set

    assert_equal 1, set.drawn
    assert_equal 1, set.unjudged
    assert_empty set.judged
    assert_equal 0, set.reading(:people_short_of_the_pick).eligible
    assert_empty set.missed
  end

  test "a failed sample is counted and is in no denominator" do
    kind = create(:lab_realization_kind)
    create(:lab_realization_sample, :failed, kind: kind, verdict: "bad", aspects: "exits")

    set = tuning_set

    assert_equal 1, set.failed
    assert_equal 0, set.reading(:exit_already_reachable).judgeable
    assert_empty set.missed, "a call that answered nothing is not a check this loop is missing"
  end

  # THE THRESHOLD, FROM BOTH SIDES OF IT. `Story::Scoreboard::MIN_VERDICTS` and
  # not a number of the lab's own.
  test "one verdict short of the threshold prints the fraction and no percentage" do
    stack_up(Story::Scoreboard::MIN_VERDICTS - 1)

    reading = tuning_set.reading(:parameters_the_engine_narrowed)

    assert_equal Story::Scoreboard::MIN_VERDICTS - 1, reading.eligible
    assert_not reading.established?
    assert_nil reading.percentage
    assert_includes reading.to_s, "not established"
  end

  test "at the threshold the percentage is published" do
    stack_up(Story::Scoreboard::MIN_VERDICTS)

    reading = tuning_set.reading(:parameters_the_engine_narrowed)

    assert reading.established?
    assert_in_delta 100.0, reading.percentage
    assert_not_includes reading.to_s, "not established"
  end

  # TUNING AND HELD OUT ARE TWO SETS AND ARE NEVER POOLED -- so a held-out world
  # can never carry a tuning figure over the line.
  test "held out samples are a set of their own and do not top up the tuning set" do
    tuning = create(:lab_realization_kind, :a_building, world: "The Quay House")
    held = create(:lab_realization_kind, :a_building, world: Eval::HELD_OUT)
    (Story::Scoreboard::MIN_VERDICTS - 1).times do
      create(:lab_realization_sample, :a_building, kind: tuning, verdict: "good")
    end
    create(:lab_realization_sample, :a_building, kind: held, verdict: "good")

    tuning_set, held_set = Lab::Realization::Agreement.sets

    assert_equal Lab::Realization::Agreement::TUNING, tuning_set.label
    assert_equal Lab::Realization::Agreement::HELD_OUT, held_set.label
    assert_equal Story::Scoreboard::MIN_VERDICTS - 1, tuning_set.drawn
    assert_equal 1, held_set.drawn
    assert_not tuning_set.reading(:parameters_the_engine_narrowed).established?
    assert_not held_set.reading(:parameters_the_engine_narrowed).established?
  end

  # HIS PROSE VERDICTS ARE KEPT AND REPORTED AND NEVER SCORED.
  test "the prose aspect grades no check and is reported as its own tally" do
    kind = create(:lab_realization_kind)
    create(:lab_realization_sample, :a_room, kind: kind, verdict: "bad", aspects: "prose")
    create(:lab_realization_sample, :a_room, kind: kind, verdict: "good")

    assert_empty Lab::Realization::Agreement::AREAS.fetch("prose")
    assert_equal 1, tuning_set.prose_verdicts
    assert_equal 2, tuning_set.judged.size
  end

  private

  def tuning_set = Lab::Realization::Agreement.sets.first

  # THE SAME BUILDING, DRAWN AND LIKED, `count` TIMES. Nothing rolls: every row
  # is the factory's fixed one, so the only thing moving across the threshold
  # boundary is the count.
  def stack_up(count)
    kind = create(:lab_realization_kind, :a_building)
    count.times { create(:lab_realization_sample, :a_building, kind: kind, verdict: "good") }
  end
end
