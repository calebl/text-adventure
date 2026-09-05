# THE SAME CHECKS `rake game:score` RUNS, OVER PROSE THIS BENCH ASKED FOR.
#
# Nothing here re-implements a check. Every predicate is `Story::Audit::Prose`'s
# -- the module that exists so "the live database and the frozen corpora read
# them through the same code" -- and every list of records is the one
# `Story::Audit` itself would read, captured beside the passage when the case
# was played (`Eval::Prompt::Bench#facts_after`). This is the third reader of
# that module, after `Story::Scoreboard::Corpus` and
# `Story::Scoreboard::Transitions`, and it is written the same way for the same
# reason: a check that had two implementations would sooner or later have two
# answers.
#
# OFFLINE, FROM THE STORED ROWS AND NOTHING ELSE. It touches no table, so a set
# can be scored again after the calls are paid for -- which is what makes a
# redefinition of a rate cost nothing, the same rule `Eval::RunSet` follows by
# keeping the run databases.
#
# WHAT IT REPORTS AS UNAVAILABLE, AND NEVER AS CLEAN: the four checks a single
# turn cannot answer. `Eval::Prompt::UNAVAILABLE_TO_A_CASE` states each with its
# reason, and the board prints them under the rates rather than beside them. A
# zero there would be the most dangerous number this instrument could print.
#
# AND THE DENOMINATOR IS PER CHECK, exactly as `Story::Audit#judgeable_for`
# makes it: `take_denied` can only be judged on a turn that took something, and
# counting every case into it would report a rate the check never earned.
class Eval::Prompt::Scorer
  # ONE SCORED PASSAGE. It answers enough of `Scene` for a `Story::Audit::Flag`
  # and a report to hold it, on the same terms `Story::Scoreboard::Corpus::Passage`
  # does -- `location` is nil because there is no `Location` row behind a stored
  # row, and `room` is its name.
  Passage = Data.define(:id, :label, :arm, :rep, :story, :shape, :act, :typed, :text, :facts) do
    def description = text
    def location = nil
    def follows_a_turn? = true
    def held_out? = Eval::Prompt.held_out?(story)

    def room = facts["room"]
    def moved? = facts["moved"] == true
    def item = facts["item"]
    def inscription = facts["inscription"]
    def protagonist = Array(facts["protagonist"])
    def places = (facts["places"] || {})
    def elsewhere = Array(facts["elsewhere"])
    def scored? = text.to_s.strip.present?

    # The four figures `Eval::Richness` reads, out of the same facts -- the
    # check on the checks, printed beside the defect rates and never folded in.
    def vocabulary
      Eval::Richness::Vocabulary.new(room: room, exits: Array(facts["exits"]),
                                     items: Array(facts["floor"]) + Array(facts["carried"]),
                                     characters: Array(facts["present"]))
    end
  end

  attr_reader :rows

  def initialize(rows)
    @rows = Array(rows).map { |row| row.transform_keys(&:to_s) }
  end

  def passages
    @passages ||= rows.reject { |row| row["error"] }.map do |row|
      Passage.new(id: row["id"], label: "#{row["arm"]}/rep#{row["rep"]}/#{row["id"]}",
                  arm: row["arm"], rep: row["rep"], story: row["story"], shape: row["shape"],
                  act: row["act"], typed: row["typed"], text: row["text"].to_s,
                  facts: (row["facts"] || {}))
    end
  end

  # The same readers `Story::Audit` offers, so a report can hold one shape.
  def scenes = passages
  def scanned = passages.count(&:scored?)
  def unjudged = []
  def verdicts = {}

  def available_checks = Eval::Prompt.checks

  def judgeable_for(code)
    return 0 unless available_checks.include?(code.to_sym)

    scored = passages.select(&:scored?)

    case code.to_sym
    when :take_denied then scored.count { |passage| passage.act == "take" && passage.item.present? }
    when :pickup_invented then scored.count { |passage| passage.act == "drop" && passage.item.present? }
    when :third_person_protagonist then scored.count { |passage| passage.protagonist.any? }
    when :inscription_misquoted then scored.count { |passage| passage.inscription.present? }
    when :item_not_held then scored.count { |passage| passage.elsewhere.any? }
    when :unrecorded_arrival then scored.count { |passage| passage.places.any? }
    else scored.size
    end
  end

  def flags
    @flags ||= passages.select(&:scored?).flat_map { |passage| check(passage) }
  end

  def flagged_for(code) = flags.select { |flag| flag.code == code.to_sym }

  def rate(code)
    judgeable = judgeable_for(code)
    return 0.0 if judgeable.zero?

    flagged_for(code).size.fdiv(judgeable)
  end

  # THE RICHNESS OF WHAT CAME BACK, printed beside the defect rates and NEVER
  # folded into them. `Eval::Richness`'s header has the argument: prose that
  # says less cannot contradict the records, so a prompt change that bought a
  # lower flag rate with blander prose has to show up as a loss somewhere, and
  # this is where. Read through the module rather than recounted here.
  def richness
    Eval::Richness.summarize(
      passages.select(&:scored?).map { |passage| Eval::Richness.read(passage.text, passage.vocabulary) }
    )
  end

  private

  def check(passage)
    truncation(passage) + third_person(passage) + departure(passage) + arrival(passage) +
      take(passage) + drop(passage) + inscription(passage) + custody(passage)
  end

  def truncation(passage)
    return [] unless Story::Audit::Prose.truncated?(passage.text)

    [ flag(:truncated_prose, passage, "the prose the model wrote stops mid-sentence",
           claim: "…#{passage.text.rstrip.last(80)}",
           "last character" => Story::Audit::Prose.sentence_ending(passage.text).inspect) ]
  end

  def third_person(passage)
    names = passage.protagonist
    return [] if names.empty?

    Story::Audit::Prose.third_person_references(passage.text, names).map do |reference|
      flag(:third_person_protagonist, passage,
           "the narration writes #{reference.name.inspect} as a third person, and that is the player " \
           "(#{names.first}), who is only ever \"you\"",
           grammar: reference.kind, name: reference.name, claim: reference.sentence.truncate(220))
    end
  end

  # A CASE THAT MOVED IS NOT JUDGED HERE, exactly as `Story::Audit#check_departure`
  # is not: a door closing at the player's back is correct prose on the one turn
  # they walked through it.
  def departure(passage)
    return [] if passage.moved?

    Story::Audit::Prose.departure_claims(passage.text).map do |claim|
      flag(:unrecorded_departure, passage,
           "the narration closes a door behind the player, and the records have them still in " \
           "#{passage.room.inspect}",
           claim: claim.truncate(220), "records say" => "still in #{passage.room}")
    end
  end

  def arrival(passage)
    return [] if passage.places.empty?

    Story::Audit::Prose.arrival_claims(passage.text, passage.places.keys).filter_map do |claimed|
      canonical = passage.places.fetch(claimed.name, claimed.name)
      next if canonical == passage.room

      flag(:unrecorded_arrival, passage,
           "the narration walks the player into #{canonical.inspect}, " \
           "and the records have them in #{passage.room.inspect}",
           claim: claimed.sentence.truncate(220), "named as" => claimed.name,
           "records say" => "in #{passage.room}")
    end
  end

  def take(passage)
    return [] unless passage.act == "take" && passage.item.present?

    claim = Story::Audit::Prose.prior_possession_claims(passage.text,
                                                        Story::Audit::Prose.item_names(passage.item)).first
    return [] if claim.nil?

    [ flag(:take_denied, passage,
           "this turn picked the #{passage.item} up, and the narration tells the player they already had it",
           item: passage.item, "named as" => claim.name,
           "the turn did" => "take #{passage.item}",
           "so before it" => "the #{passage.item} was lying in #{passage.room}, not held",
           claim: claim.sentence.truncate(220)) ]
  end

  def drop(passage)
    return [] unless passage.act == "drop" && passage.item.present?

    claim = Story::Audit::Prose.invented_pickup_claims(passage.text,
                                                       Story::Audit::Prose.item_names(passage.item)).first
    return [] if claim.nil?

    [ flag(:pickup_invented, passage,
           "this turn put the #{passage.item} down, and the narration has the player pick it up first",
           item: passage.item, "named as" => claim.name,
           "the turn did" => "drop #{passage.item}",
           "so before it" => "the #{passage.item} was in the player's hands, not lying anywhere",
           claim: claim.sentence.truncate(220)) ]
  end

  def inscription(passage)
    return [] if passage.inscription.blank?

    Story::Audit::Prose.inscription_quotes(passage.text).filter_map do |quote|
      next if Story::Audit::Prose.same_written_words?(quote.text, passage.inscription)

      flag(:inscription_misquoted, passage,
           "the narration quotes what is written on the #{passage.item}, and the records hold different words",
           item: passage.item, "the records say" => passage.inscription.to_s.truncate(220),
           "the narration says" => quote.text.truncate(220), claim: quote.sentence.truncate(220))
    end
  end

  # THE ONE PREDICATE THAT IS NOT IN `Story::Audit::Prose`, reached the way the
  # project already reaches it: `Story::Audit.allocate.send(:possession_claimed?)`
  # is what `Story::Audit::ItemCustodyTest` does, because the method reads three
  # constants and no instance state. Moving it into `Prose` would be the right
  # home for it and is a change to a measurement file this PR does not make --
  # see `Eval::MEASUREMENT_FILES`.
  #
  # `custody_only` drops the bare-possessive grammar when the thing is lying in
  # the room the player is standing in, exactly as `Story::Audit#check_items`
  # does: "your daybook lies open on your desk" is true of a daybook on that
  # desk.
  def custody(passage)
    passage.elsewhere.filter_map do |row|
      names = Story::Audit::Prose.item_names(row["name"])
      claim = names.find do |name|
        Story::Audit.allocate.send(:possession_claimed?, passage.text, name, custody_only: row["here"] == true)
      end
      next if claim.nil?

      flag(:item_not_held, passage,
           "the player is told they have the #{row["name"]}, which the records say is #{row["whereabouts"]}",
           item: row["name"], "named as" => claim, "records say" => row["whereabouts"],
           claim: excerpt(passage.text, claim))
    end
  end

  # The sentence a claim sits in, so a flag can be judged without opening a
  # console -- the same job `Story::Audit#excerpt` does.
  def excerpt(text, name)
    Story::Audit::Prose.sentences(text).find { |sentence| sentence.match?(/\b#{Regexp.escape(name)}\b/i) } ||
      text.truncate(220)
  end

  def flag(code, passage, headline, **evidence)
    Story::Audit::Flag.new(
      code: code, scene: passage, headline: headline,
      evidence: { source: passage.label, where: passage.room, typed: passage.typed }.compact.merge(evidence)
    )
  end
end
