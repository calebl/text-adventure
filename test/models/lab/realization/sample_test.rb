require "test_helper"

class Lab::Realization::SampleTest < ActiveSupport::TestCase
  test "a sample reads its picks through the engines own interpreter of the answer" do
    sample = create(:lab_realization_sample, :a_building)

    assert_equal [ "a cellar" ], sample.picks_for(Lab::Realization.pick("storeys_below"))
    assert_equal [ "flooded" ], sample.picks_for(Lab::Realization.pick("hazard"))
    assert_equal [ "worse the deeper you go" ], sample.picks_for(Lab::Realization.pick("gradient"))
  end

  # A DECLINED BLOCK IS THE DEFAULT AND NOT AN ABSENCE, because the default is
  # what the place BECAME -- `Location::Parameters`' every-field-optional rule,
  # read here rather than re-derived.
  test "a building that picked nothing reads as the quietest option on every pick" do
    sample = create(:lab_realization_sample, :a_building_that_picked_nothing)

    assert_equal [ "none" ], sample.picks_for(Lab::Realization.pick("storeys_below"))
    assert_equal [ Location::Parameters::NO_HAZARD ], sample.picks_for(Lab::Realization.pick("hazard"))
    assert_equal [ Location::SAFE ], sample.picks_for(Lab::Realization.pick("danger"))
    assert sample.answered?(Lab::Realization.pick("hazard")),
           "the block was offered, so the pick is judgeable however empty the answer was"
  end

  # THE TWO EXIT PICKS ARE ANSWERED ONCE PER NAMED EXIT, which is what makes them
  # a list and what decides what a hit means.
  test "the exit picks come back one per named exit" do
    sample = create(:lab_realization_sample, :a_room)

    assert_equal [ Location::Parameters::NO_INSIDE ], sample.picks_for(Lab::Realization.pick("inside"))
    assert_equal [ "a person or two" ], sample.picks_for(Lab::Realization.pick("population"))
  end

  # THE POPULATION WORD IS THE ONE FIELD WITH NO QUIETEST OPTION, so a declined
  # one is reported as nothing at all rather than as a word.
  test "a population pick nobody made reads as nothing rather than as a word" do
    sample = create(:lab_realization_sample, :a_room)
    sample.row["answers"]["exits"]["exits"].first.delete("population")
    sample.save!

    assert_equal [ nil ], sample.reload.picks_for(Lab::Realization.pick("population"))
  end

  # THE DENOMINATOR'S GATE, AND IT IS ASKED OF THE SAMPLE. A pick the call that
  # would have answered it never made is out of that figure entirely --
  # `Eval::Realization::Scorer`'s rule: a rate a check never earned is worse than
  # no rate.
  test "a pick the call never answered is not judgeable on that sample" do
    room = create(:lab_realization_sample, :a_room)
    building = create(:lab_realization_sample, :a_building)

    assert room.answered?(Lab::Realization.pick("inside"))
    assert_not room.answered?(Lab::Realization.pick("hazard"))

    assert building.answered?(Lab::Realization.pick("hazard"))
    assert_not building.answered?(Lab::Realization.pick("inside")),
              "a laid-out place makes no exits call, so nothing picked an inside"
  end

  test "a failed sample answers nothing and picks nothing" do
    sample = create(:lab_realization_sample, :failed)

    assert sample.failed?
    assert sample.reading.refused?
    Lab::Realization.picks.each do |pick|
      assert_not sample.answered?(pick), "#{pick.name} cannot be answered by a call that failed"
      assert_empty sample.picks_for(pick)
    end
  end

  # THE ROW IS READ THROUGH THE BENCH'S OWN OBJECT, so the lab and
  # `rake eval:realization` cannot come to different readings of one call.
  test "a sample scores itself with the benchs own checks" do
    sample = create(:lab_realization_sample, :a_room)

    assert_kind_of Eval::Realization::Scorer::Reading, sample.reading
    assert(sample.flags.all? { |flag| Eval::Realization.checks.include?(flag.code) })
  end

  test "a verdict is recorded, amended and cleared on the same row" do
    sample = create(:lab_realization_sample, :a_room)

    sample.record!(verdict: "bad", aspects: %w[prose exits], note: "  the ways out restated the world  ")

    assert_equal "bad", sample.verdict
    assert_equal %w[prose exits], sample.aspect_names
    assert_equal "the ways out restated the world", sample.note

    sample.record!(verdict: "weak")

    assert_equal "weak", sample.verdict
    assert_equal %w[prose exits], sample.aspect_names, "the aspects survive a change of verdict"
    assert_equal "the ways out restated the world", sample.note, "and so does the note"

    sample.record!(verdict: "", aspects: [], note: "")

    assert_nil sample.reload.verdict
    assert_empty sample.aspect_names
    assert_nil sample.note
  end

  test "a sample refuses a verdict and an aspect nothing can read" do
    sample = build(:lab_realization_sample, verdict: "excellent")

    assert_not sample.valid?

    sample = build(:lab_realization_sample, aspects: "prose, vibes")

    assert_not sample.valid?
    assert_match(/"vibes"/, sample.errors[:aspects].to_sentence)
  end

  # THE SCORER'S TWO QUESTIONS, ASKED OF ONE ROW. A check can be read on this
  # sample, and did it fire -- the two the agreement figure stands on, and both
  # answered by the bench's own scorer rather than by a second reading of the
  # row.
  test "a sample says which checks could be read on it and which of them fired" do
    sample = create(:lab_realization_sample, :a_room)

    assert sample.judges?(:people_short_of_the_pick)
    assert sample.flagged?(:people_short_of_the_pick)
    assert sample.judges?(:exit_already_reachable)
    assert_not sample.flagged?(:exit_already_reachable)
  end

  test "a failed call could be read for nothing" do
    sample = create(:lab_realization_sample, :failed)

    assert_empty Eval::Realization.checks.select { |code| sample.judges?(code) }
    assert_empty sample.flags
  end

  # THE THREE WORDS ARE THE PLAY PAGE'S, and one spelling of them is the point:
  # a second table here would be a second ordering to keep in step with his
  # verdicts on turns.
  test "the verdicts are the ones he already uses on a turn" do
    assert_equal Playthrough::Feedback::VERDICTS, Lab::Realization::Sample::VERDICTS
  end
end
