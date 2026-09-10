# WHETHER THE RECORD CHECKS AGREE WITH HIM, PER CHECK, OVER THE SAMPLES HE
# JUDGED.
#
# THE OTHER HALF OF THE LAB. `Lab::Realization::HitRate` asks whether the model
# picked what he said it should; this asks whether
# `Eval::Realization::Scorer`'s checks -- the things the realization bench
# reports a rate for -- fire on the samples he thinks are bad and stay quiet on
# the ones he thinks are good. Two directions of one calibration, and neither
# can stand in for the other: a check can be right about a room he hates for a
# reason the check cannot see.
#
# IT IS `Story::Scoreboard#agreements` AND `#missed_verdicts`, POINTED AT THE
# REALIZATION CHECKS. That class's header says what each half is for:
#
#   *"a turn he called `bad` that nothing here flags is a check this loop is
#   missing, and naming it is how the next check gets chosen."*
#
# So there are two readings here and they answer different questions:
#
#   A SUSPECT  a check that fired on a sample he called `good`. A false
#              positive, or a rule he does not actually want.
#   A MISS     a sample he called `weak` or `bad` that no check fired on at
#              all. The next check to write.
#
# WHAT AN ELIGIBLE VERDICT IS, and this is the whole of the honesty in this
# file. A verdict only counts towards a check if it SAYS SOMETHING ABOUT THAT
# CHECK:
#
#   `good`                  speaks to every check that was judgeable on the
#                           sample. He looked at the whole realization and found
#                           nothing wrong with it, so a check firing on it is a
#                           check disagreeing with him.
#   `weak` / `bad`          speaks only to the checks the ASPECTS he ticked name
#                           (`AREAS` below), because a sample he faulted for its
#                           prose says nothing whatever about
#                           `exit_already_reachable` -- and counting it in would
#                           report a rate the figure never earned, which is
#                           `Story::Audit#judgeable_for`'s rule and this
#                           project's rule everywhere.
#   `not_the_place_i_meant` speaks to every check, because
#                           `Lab::Realization::Sample`'s header makes it the one
#                           aspect that subsumes the others.
#   a bare `weak` / `bad`   speaks to no check in particular. It is still a MISS
#                           when nothing fired, which is the reading that does
#                           not need him to have said where the fault was.
#   no verdict at all       speaks to nothing. Counted and printed as unjudged,
#                           never as agreement and never as zero.
#
# AND THE CHECK HAS TO HAVE BEEN JUDGEABLE ON THE ROW BEFORE ANY OF THAT --
# `Eval::Realization::Scorer#judgeable_for`, asked of the one row. That is where
# a *don't care* expectation drops out: a lab sample carries no `expects_inside`
# hand label (`Lab::Realization::Runner#ad_hoc_case` says why), so both inside
# checks are judgeable on nothing here and are reported UNAVAILABLE rather than
# as agreement of nought. Same for a stored row written before a field the check
# reads existed: the gate says not judgeable, and missing evidence stays missing.
#
# THE THRESHOLD IS `Story::Scoreboard::MIN_VERDICTS` AND NOT A NUMBER OF THIS
# FILE'S OWN. It is the same question that class asks -- how many labelled
# things before a per-check cross-tab has more than a handful of cells with
# anything in them -- and a second threshold would be a second thing to argue
# about. Below it the counts and the fraction are printed and the PERCENTAGE IS
# NOT, because dressing up n=3 is the one thing an instrument must not do.
#
# TUNING AND HELD OUT ARE TWO SETS AND ARE NEVER POOLED, which is
# `Eval::Realization::Report`'s convention and the captain's Call 6 of
# 2026-09-08: the lab may build rooms in the held-out world, provided they are
# labelled and reported apart. Each set carries its own eligibility and crosses
# the threshold on its own verdicts or not at all -- `.sets` is two instances
# for exactly that reason, so there is no shape in which adding the held-out
# world's samples establishes a figure the tuning worlds could not.
#
# AND IT IS NOT THE CHECK'S RATE. A rate is flagged over judgeable and says how
# often the check fires; this says how often it was right to. They answer
# different questions and a combined number would be neither, so nothing here
# folds into `Eval::Realization::Report`'s table and nothing there folds into
# this one.
class Lab::Realization::Agreement
  # WHICH CHECKS EACH ASPECT GRADES.
  #
  # The left column is `Lab::Realization::Sample::ASPECTS` -- what he ticks --
  # and the right is `Eval::Realization::Scorer::CHECKS` -- what the records
  # read. A check is graded by an aspect when the two are looking at the same
  # part of the room, and `Lab::RealizationAgreementTest` holds every check to
  # appearing here or in `GRADED_BY_THE_WHOLE_SAMPLE` so that a check added to
  # the scorer has to be filed rather than quietly falling out of every
  # denominator.
  #
  # `prose` GRADES NOTHING, and that is a decision rather than an omission.
  # `Eval::Realization::UNAVAILABLE_TO_A_REALIZATION` names the absence of a
  # prose reader a refusal -- there is no deterministic reader of whether a
  # paragraph is worth reading and a judge model would be a second model to keep
  # honest -- so his prose verdict is ground truth for a check that does not
  # exist. It is reported as its own tally (`#prose_verdicts`) and never scored.
  #
  # `proposal_refused` IS IN TWO LISTS because the engine refuses people and
  # things through one gate. Eligibility is the union, so either aspect admits
  # it.
  AREAS = {
    "exits" => %i[exit_into_a_written_room exit_already_reachable exit_spelled_a_place_differently
                  exit_named_this_room exit_over_the_allowance no_new_ground inside_declined
                  inside_on_a_place_that_already_exists inside_where_the_world_wanted_none
                  no_inside_where_the_world_wanted_one population_declined],
    "people" => %i[person_over_the_allowance people_short_of_the_pick race_not_named proposal_refused],
    "things" => %i[item_over_the_allowance readable_without_words proposal_refused],
    "name" => %i[name_already_spoken_for room_name_refused room_name_already_taken],
    "prose" => []
  }.freeze

  # THE ASPECT THAT SPEAKS TO EVERY CHECK. `Lab::Realization::Sample`'s header:
  # *"the whole realization missed the teaser. The one judgement that subsumes
  # every other."*
  WHOLE_SAMPLE = "not_the_place_i_meant".freeze

  # THE CHECKS NO ASPECT NAMES, listed rather than left as a residue. Each is
  # about the building the engine BUILT rather than about a part of the room he
  # is offered a box for, so the only verdicts that speak to one are a `good` and
  # the whole-sample aspect. Named here so the test above can hold the mapping
  # complete, and so a reader can see that the gap is known.
  GRADED_BY_THE_WHOLE_SAMPLE = %i[parameters_declined parameters_the_engine_narrowed
                                  size_the_records_do_not_hold].freeze

  # Optional target take-up is not a quality verdict. A good room may correctly
  # leave the request for somewhere else, so no aspect grades this counter.
  NOT_A_QUALITY_CHECK = Eval::Realization::Scorer::OBSERVATIONS

  TUNING = "tuning".freeze
  HELD_OUT = "held out".freeze

  # ONE CHECK'S READING OVER ONE SET.
  #
  # `judgeable` and `eligible` are two different denominators and both are
  # printed: the first is how many samples the check could be read on at all,
  # the second how many of those carry a verdict that speaks to it. A check with
  # `judgeable` at nought is UNAVAILABLE -- nothing drawn gave it anything to
  # read -- and a check with samples but no eligible verdict has not been judged
  # yet. Neither is an agreement of nought.
  Reading = Data.define(:code, :judgeable, :eligible, :agreed, :on_good, :on_weak, :on_bad, :suspects) do
    def description = Eval::Realization::Scorer::CHECKS.fetch(code, code.to_s)
    def keyword? = Eval::Realization::Scorer::KEYWORD_CHECKS.include?(code)
    def available? = judgeable.positive?
    def judged? = eligible.positive?
    def fired = on_good + on_weak + on_bad
    def fraction = "#{agreed} of #{eligible}"
    def established? = eligible >= Story::Scoreboard::MIN_VERDICTS

    # THE PERCENTAGE, OR NOTHING. Nil below the threshold, and the caller prints
    # the fraction and the words "not established" instead -- there is no shape
    # in which a number comes out of this that a reader could mistake for an
    # established one.
    def percentage = established? ? (agreed.fdiv(eligible) * 100).round(1) : nil

    def to_s
      return "#{code}: unavailable -- nothing drawn gave the check anything to read" unless available?
      return "#{code}: no verdict speaks to it yet (#{judgeable} judgeable)" unless judged?

      "#{code}: #{fraction}#{established? ? " (#{percentage}%)" : " -- not established"}"
    end
  end

  # THE CHECKS THAT FIRED ON SOMETHING HE LIKED. Flattened across the checks
  # because that is how they are read -- he wants the samples, not the codes --
  # and each carries the check that fired so the disagreement can be opened.
  Suspect = Data.define(:sample, :code)

  attr_reader :label, :samples

  # THE TWO SETS, TUNING AND HELD OUT, IN THAT ORDER AND NEVER SUMMED. Split on
  # the KIND's world, because a sample's world is the kind's -- and through
  # `Eval::Realization.held_out?` rather than by comparing the string, so the one
  # spelling of which world is held out stays in `Eval`.
  def self.sets(samples = nil)
    drawn = (samples || Lab::Realization::Sample.in_draw_order.includes(:kind)).to_a
    tuning, held = drawn.partition { |sample| !Eval::Realization.held_out?(sample.kind.world) }

    [ new(tuning, label: TUNING), new(held, label: HELD_OUT) ]
  end

  def initialize(samples, label: TUNING)
    @samples = Array(samples)
    @label = label
  end

  def drawn = samples.size

  def failed = samples.count(&:failed?)

  # THE SAMPLES A CHECK COULD BE READ ON AND A VERDICT COULD ATTACH TO. A failed
  # call answered nothing, so it is out of every denominator here for the same
  # reason `Eval::Realization::Scorer#readings` rejects one.
  def scorable = @scorable ||= samples.reject(&:failed?)

  def judged = @judged ||= scorable.select(&:verdict?)

  # PRINTED, NEVER FOLDED IN. A sample nobody has looked at is missing evidence
  # and not evidence of agreement.
  def unjudged = scorable.count { |sample| !sample.verdict? }

  def verdicts = @verdicts ||= judged.filter_map(&:verdict).tally

  # HIS PROSE VERDICTS AS THEIR OWN TALLY -- *"of the room descriptions he
  # judged, this many good"* -- because no check reads prose and none is going to.
  # The one honest figure available for it, and the ground truth a prose check
  # would one day have to be measured against. It is a count of the samples he
  # FAULTED for their prose against the samples he judged at all; it is not a
  # rate over a check and must never be printed in the same table as one.
  def prose_verdicts = judged.count { |sample| sample.aspect?("prose") }

  def readings = @readings ||= Eval::Realization.checks.map { |code| reading_for(code) }

  def reading(code) = readings.find { |entry| entry.code == code.to_sym }

  # EVERY SUSPECT IN THE SET, flattened across the checks because that is how it
  # is read: he wants the samples, not the codes.
  def suspects = readings.flat_map(&:suspects)

  # THE VERDICTS NO CHECK CAUGHT: a sample he called `weak` or `bad` that
  # nothing flagged. `Story::Scoreboard#missed_verdicts`' half of the question,
  # and the more useful half while the labels are few.
  #
  # IT DOES NOT ASK ABOUT ELIGIBILITY, deliberately. A bare `bad` with no aspect
  # ticked grades no particular check and so appears in no denominator above --
  # but it is still a room he did not want that this loop said nothing about,
  # which is exactly what this list is for.
  def missed
    scorable.select do |sample|
      sample.verdict? && sample.verdict != "good" &&
        sample.flags.none? { |flag| !NOT_A_QUALITY_CHECK.include?(flag.code) }
    end
  end

  # WHETHER ANY CHECK IN THIS SET HAS ENOUGH ELIGIBLE VERDICTS TO REPORT. Asked
  # per check rather than over the set, because the denominators are per check
  # and one established check beside twenty unestablished ones is the ordinary
  # state of this instrument for a long time.
  def established? = readings.any?(&:established?)

  def headline
    return "#{label}: nothing drawn" if drawn.zero?

    "#{label}: #{drawn} sample#{"s" unless drawn == 1}, #{judged.size} judged, " \
      "#{readings.count(&:established?)} of #{readings.size} checks established"
  end

  private

  def reading_for(code)
    judgeable = scorable.select { |sample| sample.judges?(code) }
    eligible = judgeable.select { |sample| eligible?(sample, code) }
    fired, quiet = eligible.partition { |sample| sample.flagged?(code) }
    by_verdict = fired.map(&:verdict).tally

    Reading.new(code: code.to_sym, judgeable: judgeable.size, eligible: eligible.size,
                # AGREEMENT IS CONCURRENCE IN BOTH DIRECTIONS: the check fired on
                # a sample he faulted, or stayed quiet on one he liked. Counting
                # only the first would make a check that never fires read as
                # perfect.
                agreed: fired.count { |sample| sample.verdict != "good" } +
                        quiet.count { |sample| sample.verdict == "good" },
                on_good: by_verdict["good"].to_i, on_weak: by_verdict["weak"].to_i,
                on_bad: by_verdict["bad"].to_i,
                suspects: fired.select { |sample| sample.verdict == "good" }
                               .map { |sample| Suspect.new(sample: sample, code: code.to_sym) })
  end

  # WHETHER HIS VERDICT ON THIS SAMPLE SAYS ANYTHING ABOUT THIS CHECK. The
  # class header is the argument; this is the whole of the rule.
  def eligible?(sample, code)
    return false if NOT_A_QUALITY_CHECK.include?(code.to_sym)
    return false unless sample.verdict?
    return true if sample.verdict == "good"
    return true if sample.aspect?(WHOLE_SAMPLE)

    sample.aspect_names.any? { |aspect| AREAS.fetch(aspect, []).include?(code.to_sym) }
  end
end
