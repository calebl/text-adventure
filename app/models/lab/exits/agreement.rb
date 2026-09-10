# WHETHER THE RECORD CHECKS AGREE WITH HIS PER-NAME JUDGEMENTS.
#
# `Lab::Realization::Agreement` owns the verdict grammar and the scoreboard's
# threshold. Here the subject is (vantage, name_key), the captain's Call 3 of
# 2026-09-08: one click judges every draw naming that place. Each subject counts
# ONCE, however often drawn; repeats cannot manufacture MIN_VERDICTS labels.
# A check fires on that subject if it fires on any of its judgeable draws.
# Suspects open every offending draw; misses open every draw of a weak/bad name
# on which no attributable check fired anywhere. Duplicate names within a draw
# likewise cannot multiply a verdict. Unnamed expectations and failed calls are
# outside the instrument; unjudged names are counted, never eligible.
#
# ATTRIBUTION USES THE SCORER, NOT ITS EVIDENCE STRINGS. For the per-exit checks
# in AREAS, project the answer to exits with this natural key, retaining the
# original facts and after records. Ask Scorer#judgeable_for and #flagged_for on
# that projection. No rule is reimplemented and no prose evidence is parsed.
# Reachability's dead-end gate must first read the WHOLE answer: projecting a
# multi-exit answer to its way back must not manufacture a correct dead end.
# After that gate, suppress the projected dead-end exemption for this check only.
#
# JUDGEABILITY: written-room and spelling checks need the stored places list;
# reachability needs reachable; self-naming needs room. The discarded-inside
# check needs places AND after.new_places, and the scorer additionally requires
# an inside pick. Declined inside/population need only the answered exits call:
# missing picks are exactly what they measure, including historical rows.
# Missing record fields are unavailable, never a quiet check counted as agreement.
#
# WHOLE-ANSWER AND DETAIL CHECKS ARE UNAVAILABLE TO A NAME JUDGEMENT even when
# the full sample can answer them. A good chandlery cannot grade how many other
# exits were named, the vantage's furniture, or its description. Those checks
# are explicitly filed in GRADED_BY_THE_WHOLE_SAMPLE, not silently dropped.
# In particular the runner deliberately stores no expects_inside; neither a
# vantage quantifier nor a per-name expectation is injected into the scorer.
# This measures existing checks, not HitRate under another spelling.
#
# Good speaks to every judgeable per-name check. Weak/bad speaks only through
# AREAS; shouldnt_exist is this lab's whole-subject aspect and speaks to all of
# them. Bare weak/bad grades no check but still identifies a miss. Teaser/name
# prose faults are tallied separately: no check reads their quality. A spelling
# collision is a record comparison, not a reader of whether a name fits a world.
#
# Tuning and held out follow the vantage's existing world label, reported apart
# (Call 6). Reading is the realization twin's own value object: both denominators,
# the fraction, and no percentage below Story::Scoreboard::MIN_VERDICTS. There
# is no overall agreement and no change to Alignment's both-shapes refusal.
class Lab::Exits::Agreement
  AREAS = {
    "inside_wrong" => %i[inside_declined inside_on_a_place_that_already_exists],
    "band_wrong" => %i[inside_declined inside_on_a_place_that_already_exists],
    "population_wrong" => %i[population_declined],
    "name_wrong" => %i[exit_spelled_a_place_differently],
    "distance_wrong" => [],
    "teaser_wrong" => [],
    "shouldnt_exist" => %i[exit_into_a_written_room exit_already_reachable exit_named_this_room]
  }.freeze
  # Optional quest take-up cannot be graded by a verdict on an exit name.
  NOT_A_QUALITY_CHECK = Lab::Realization::Agreement::NOT_A_QUALITY_CHECK
  WHOLE_SAMPLE = "shouldnt_exist".freeze
  GRADED_BY_THE_WHOLE_SAMPLE = %i[
    exit_over_the_allowance no_new_ground person_over_the_allowance item_over_the_allowance
    name_already_spoken_for proposal_refused readable_without_words room_name_refused
    room_name_already_taken inside_where_the_world_wanted_none no_inside_where_the_world_wanted_one
    people_short_of_the_pick parameters_declined parameters_the_engine_narrowed race_not_named
    size_the_records_do_not_hold
  ].freeze
  Reading = Lab::Realization::Agreement::Reading
  TUNING = Lab::Realization::Agreement::TUNING
  HELD_OUT = Lab::Realization::Agreement::HELD_OUT
  Suspect = Data.define(:sample, :code, :name)
  Miss = Data.define(:sample, :name, :verdict, :aspect_names)
  Subject = Data.define(:name, :judgement, :draws) do
    def verdict = judgement&.verdict
    def verdict? = verdict.present?
    def aspect_names = judgement&.aspect_names || []
    def aspect?(aspect) = aspect_names.include?(aspect)
  end

  # One name's evidence on one draw. The original row is never mutated.
  class Draw
    attr_reader :sample, :key

    def initialize(sample, key)
      @sample, @key = sample, key
    end

    def judges?(code)
      return false unless AREAS.values.flatten.include?(code)
      return false unless evidence?(code)
      return false if code == :exit_already_reachable && original.judgeable_for(code).zero?

      scorer(code).judgeable_for(code).positive?
    end

    def flagged?(code) = judges?(code) && scorer(code).flagged_for(code).any?

    private

    def original = @original ||= Eval::Realization::Scorer.new([ sample.row ])

    def evidence?(code)
      facts = sample.reading.facts
      case code
      when :exit_into_a_written_room, :exit_spelled_a_place_differently
        facts["places"].is_a?(Array)
      when :inside_on_a_place_that_already_exists
        facts["places"].is_a?(Array) && sample.reading.after["new_places"].is_a?(Array)
      when :exit_already_reachable then facts["reachable"].is_a?(Array)
      when :exit_named_this_room then facts["room"].present?
      else true
      end
    end

    def scorer(code)
      @scorers ||= {}
      @scorers[code] ||= begin
        row = sample.row.deep_dup
        row["answers"]["exits"]["exits"] = sample.reading.exits.select do |exit|
          Lab::Exits.key_for(exit["name"]) == key
        end
        row["facts"]["expects_new_ground"] = true if code == :exit_already_reachable
        Eval::Realization::Scorer.new([ row ])
      end
    end
  end

  attr_reader :vantages, :label

  def self.sets(vantages = nil)
    drawn = (vantages || Lab::Exits::Vantage.newest_first.includes(:samples, :judgements)).to_a
    tuning, held = drawn.partition { |vantage| !Eval::Realization.held_out?(vantage.world) }
    [ new(tuning, label: TUNING), new(held, label: HELD_OUT) ]
  end

  def initialize(vantages, label: TUNING)
    @vantages, @label = Array(vantages), label
  end

  def samples = @samples ||= vantages.flat_map(&:samples)
  def drawn = samples.size
  def failed = samples.count(&:failed?)
  def judged = subjects.select(&:verdict?)
  def unjudged = subjects.count { |subject| !subject.verdict? }
  def verdicts = judged.map(&:verdict).tally
  def prose_verdicts = judged.count { |subject| (subject.aspect_names & %w[teaser_wrong name_wrong]).any? }
  def readings = @readings ||= Eval::Realization.checks.map { |code| reading_for(code) }
  def reading(code) = readings.find { |entry| entry.code == code.to_sym }
  def suspects = readings.flat_map(&:suspects)
  def established? = readings.any?(&:established?)

  def subjects
    @subjects ||= vantages.flat_map do |vantage|
      draws = vantage.samples.select(&:answered?).flat_map do |sample|
        sample.named_places.uniq(&:key).map { |place| [ place, Draw.new(sample, place.key) ] }
      end
      draws.group_by { |place, _draw| place.key }.map do |_key, named|
        place = named.first.first
        Subject.new(name: place.name, judgement: vantage.judgement_for(place.name), draws: named.map(&:last))
      end
    end
  end

  def missed
    judged.select { |subject| subject.verdict != "good" &&
      readings.none? { |reading| subject.draws.any? { |draw| draw.flagged?(reading.code) } } }.flat_map do |subject|
      subject.draws.map do |draw|
        Miss.new(sample: draw.sample, name: subject.name, verdict: subject.verdict, aspect_names: subject.aspect_names)
      end
    end
  end

  private

  def reading_for(code)
    judgeable = subjects.select { |subject| subject.draws.any? { |draw| draw.judges?(code) } }
    eligible = judgeable.select { |subject| eligible?(subject, code) }
    fired, quiet = eligible.partition { |subject| subject.draws.any? { |draw| draw.flagged?(code) } }
    tally = fired.map(&:verdict).tally
    Reading.new(code: code, judgeable: judgeable.size, eligible: eligible.size,
                agreed: fired.count { |subject| subject.verdict != "good" } +
                        quiet.count { |subject| subject.verdict == "good" },
                on_good: tally["good"].to_i, on_weak: tally["weak"].to_i, on_bad: tally["bad"].to_i,
                suspects: fired.select { |subject| subject.verdict == "good" }.flat_map { |subject|
                  subject.draws.select { |draw| draw.flagged?(code) }.map { |draw|
                    Suspect.new(sample: draw.sample, code: code, name: subject.name)
                  }
                })
  end

  def eligible?(subject, code)
    return false unless subject.verdict?
    return true if subject.verdict == "good" || subject.aspect?(WHOLE_SAMPLE)

    subject.aspect_names.any? { |aspect| AREAS.fetch(aspect, []).include?(code) }
  end
end
