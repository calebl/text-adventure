require "test_helper"

class Lab::Realization::HitRateTest < ActiveSupport::TestCase
  # THE FIGURE HE ASKED FOR: *"I want to make sure it is picking what I think it
  # should MOST OF THE TIME."*
  test "a figure counts the samples whose pick was in the allowed set" do
    kind = create(:lab_realization_kind, :a_building, :expecting_a_cellar)
    2.times { create(:lab_realization_sample, :a_building, kind: kind) }
    create(:lab_realization_sample, :a_building_that_picked_nothing, kind: kind)

    figure = kind.hit_rate.figure("storeys_below")

    assert_equal 3, figure.answered
    assert_equal 2, figure.hits
    assert_equal "2 of 3", figure.fraction
  end

  # A PICK HE SAID NOTHING ABOUT HAS NO FIGURE AT ALL -- not a figure of nought.
  # `Eval::Realization::Corpus`' rule for `expects_inside`, one level up.
  test "a kind with no expectation has no figures" do
    kind = create(:lab_realization_kind, :a_building)
    create(:lab_realization_sample, :a_building, kind: kind)

    assert_empty kind.hit_rate.figures
    assert_nil kind.hit_rate.overall
  end

  # A FAILED CALL IS OUT OF EVERY DENOMINATOR, which is what stops a run of
  # refusals reading as a run with nothing wrong with it.
  test "a failed sample is in no denominator" do
    kind = create(:lab_realization_kind, :a_building, :expecting_a_cellar)
    create(:lab_realization_sample, :a_building, kind: kind)
    create(:lab_realization_sample, :failed, kind: kind)

    figure = kind.hit_rate.figure("storeys_below")

    assert_equal 2, kind.hit_rate.drawn
    assert_equal 1, kind.hit_rate.failed
    assert_equal 1, figure.answered
    assert_equal "1 of 1", figure.fraction
  end

  # AND SO IS A SAMPLE THE PICK WAS NEVER PUT TO. A room's draw cannot answer the
  # parameters block, so a rate over it would be a rate the figure never earned.
  test "a pick nothing has answered is judgeable on nothing" do
    kind = create(:lab_realization_kind, :expecting_a_cellar)
    create(:lab_realization_sample, :a_room, kind: kind)

    figure = kind.hit_rate.figure("storeys_below")

    assert_equal 0, figure.answered
    assert_not figure.judgeable?
    assert_not kind.answerable?(figure.pick), "and the kind can say so before anything is drawn"
  end

  # EVERY PICK MADE HAS TO BE IN THE SET, which is the whole of what a per-exit
  # expectation means: three exits given the word he wanted and a fourth given
  # one he did not is a miss.
  test "a per exit pick hits only when every named exit is in the allowed set" do
    kind = create(:lab_realization_kind, :expecting_no_insides)
    create(:lab_realization_sample, :a_room, kind: kind)
    mixed = create(:lab_realization_sample, :a_room, kind: kind)
    mixed.row["answers"]["exits"]["exits"] << {
      "name" => "The Keep", "inside" => "a warren of rooms", "population" => "a crowd"
    }
    mixed.save!

    figure = kind.hit_rate.figure("inside")

    assert_equal 2, figure.answered
    assert_equal 1, figure.hits
    assert_equal [ mixed.id ], figure.misses.map { |miss| miss.sample.id }
    assert_equal [ Location::Parameters::NO_INSIDE, "a warren of rooms" ], figure.misses.first.made
  end

  # A PICK NOBODY MADE IS A MISS AND NOT A PASS, and the population word is the
  # one field it can happen to -- there is no word for *I would rather not say*.
  test "a population pick nobody made misses any expectation" do
    kind = create(:lab_realization_kind, expects_population: "a crowd")
    sample = create(:lab_realization_sample, :a_room, kind: kind)
    sample.row["answers"]["exits"]["exits"].first.delete("population")
    sample.save!

    figure = kind.hit_rate.figure("population")

    assert_equal 1, figure.answered
    assert_equal 0, figure.hits
  end

  # THIRTY DRAWS, AND IT IS `Story::Scoreboard`'S THRESHOLD RATHER THAN ONE OF
  # THIS FILE'S OWN. Below it the fraction is still printed and the words are
  # printed with it, because dressing up n=3 is the one thing an instrument must
  # not do.
  test "a rate is not established below the scoreboards own threshold" do
    assert_equal Story::Scoreboard::MIN_VERDICTS, Lab::Realization::MIN_DRAWS

    kind = create(:lab_realization_kind, :a_building, :expecting_a_cellar)
    create(:lab_realization_sample, :a_building, kind: kind)

    assert_not kind.hit_rate.figure("storeys_below").established?

    (Lab::Realization::MIN_DRAWS - 1).times { create(:lab_realization_sample, :a_building, kind: kind) }

    assert kind.reload.hit_rate.figure("storeys_below").established?
  end

  # THE ONE FIGURE OVER ALL OF THEM, and its denominator is the samples where
  # EVERY declared pick was answered -- the only reading that needs no caveat.
  test "the overall figure counts the samples where every declared pick came back right" do
    kind = create(:lab_realization_kind, :a_building, :expecting_a_cellar,
                  expects_hazard: "flooded")
    create(:lab_realization_sample, :a_building, kind: kind)
    create(:lab_realization_sample, :a_building_that_picked_nothing, kind: kind)

    assert_equal "1 of 2", kind.hit_rate.overall.fraction
  end

  # THE ONE FIGURE THAT BELONGS TO NO PICK, and it has to print. A `#name` that
  # reached through the nil `pick` raised on exactly the figure a console or a
  # rake task is most likely to print, which is how this was found.
  test "the overall figure prints without a pick of its own" do
    kind = create(:lab_realization_kind, :a_building, :expecting_a_cellar)
    create(:lab_realization_sample, :a_building, kind: kind)

    overall = kind.hit_rate.overall

    assert_nil overall.pick
    assert_equal Lab::Realization::HitRate::EVERY, overall.name
    assert_equal "every declared pick: 1 of 1 -- not established", overall.to_s
    assert(kind.hit_rate.figures.all? { |figure| figure.to_s.present? })
  end

  test "an expectation spanning both calls can have no sample that answers all of it" do
    kind = create(:lab_realization_kind, :a_building, :expecting_a_cellar, :expecting_no_insides)
    create(:lab_realization_sample, :a_building, kind: kind)

    assert_not kind.hit_rate.overall.judgeable?
    assert_equal "1 of 1", kind.hit_rate.figure("storeys_below").fraction,
                 "and the per-pick figure that CAN be answered still reads"
  end

  # AN EXPECTATION DECLARED AFTER THE SAMPLES WERE BOUGHT SCORES THEM ANYWAY,
  # because the picks are already on the stored row. That is the property worth
  # spending deliberately: draw ten, look at them, THEN decide.
  test "declaring an expectation scores samples drawn before it existed" do
    kind = create(:lab_realization_kind, :a_building)
    create(:lab_realization_sample, :a_building, kind: kind)

    assert_empty kind.hit_rate.figures

    kind.declare(Lab::Realization.pick("hazard"), [ "flooded" ])
    kind.save!

    assert_equal "1 of 1", kind.hit_rate.figure("hazard").fraction
  end

  test "his verdicts are tallied beside the rate and never folded into it" do
    kind = create(:lab_realization_kind, :a_building, :expecting_a_cellar)
    create(:lab_realization_sample, :a_building, :good, kind: kind)
    create(:lab_realization_sample, :a_building, :bad, kind: kind)
    create(:lab_realization_sample, :a_building, kind: kind)

    assert_equal({ "good" => 1, "bad" => 1 }, kind.hit_rate.verdicts)
    assert_equal 2, kind.hit_rate.judged
    assert_equal "3 of 3", kind.hit_rate.figure("storeys_below").fraction
  end
end
