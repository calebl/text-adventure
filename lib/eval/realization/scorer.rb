# WHAT THE MODEL WROTE, AGAINST WHAT THE PROMPT TOLD IT, AND NOTHING ELSE.
#
# EVERY CHECK IN HERE IS A SET COMPARISON, and that is the design rather than a
# limitation. The standing constraint (AGENTS.md) is that nothing may depend on
# a model obeying its prompt; the corollary for an instrument is that nothing
# may depend on a CHECKER understanding prose. So each check below reads a name
# the model wrote against a closed list of names the prompt handed it, or a
# count against a number the prompt stated. Both sides are records. A rate here
# is therefore the same kind of fact `rake game:sweep` produces -- something the
# app itself could have asserted -- rather than a reading.
#
# THE ONE EXCEPTION IS NAMED FOR WHAT IT CAN SEE. `race_not_named` is a keyword
# check: it can tell that the word "Nocturna-Blighted" is absent from a sheet
# written for a Nocturna-Blighted slot, and it cannot tell a compliant person
# described entirely in chitin and silence from a non-compliant one. It is
# reported apart from the checks the records prove, with that stated, and its
# false-positive rate is unknown until a baseline is bought -- which is exactly
# the discipline two earlier prose-reading checks failed
# (`data/ta-model-bench`, and `Story::Scoreboard`'s header).
#
# OFFLINE, FROM THE STORED ROWS AND NOTHING ELSE. It touches no table, so a set
# can be scored again after the calls are paid for -- the rule `Eval::RunSet`
# follows by keeping the run databases and `Eval::Prompt::Scorer` by keeping the
# facts beside the passage.
#
# THE HAZARD THIS IS BUILT AGAINST, and it is `Eval::Richness`'s exactly: THE
# CHEAPEST WAY TO CLEAR EVERY RATE BELOW IS TO WRITE ONE EXIT AND NOBODY. A room
# that names only the way back cannot restate a place it should not have, cannot
# open a door into a written room and cannot exceed its allowance; a room with
# nobody in it cannot reuse a name or fail to write a monster. That is not an
# edge case, it is the dominant strategy for anything optimising these numbers.
# So `exits_named`, `new_places_opened`, `people_named` and `items_named` are
# printed BESIDE the rates, are never folded into them, and have no better
# direction -- a prompt change that cleared every rate and halved those bought
# its numbers with emptier rooms.
#
# AND THE DENOMINATOR IS PER CHECK, exactly as `Story::Audit#judgeable_for`
# makes it: `readable_without_words` can only be judged on a case that named
# something readable, and counting every case into it would report a rate the
# check never earned.
#
# ONE FINDING FOR A LATER PROMPT ITEM, RECORDED HERE BECAUSE THIS IS WHERE IT
# WAS FOUND AND NOT ACTED ON: `Location::Generator`'s exits prompt carries two
# sentences that contradict each other on a dead end. The instructions say *"if
# the only way out is back the place the player came from, list that place and
# nothing else"*, and `#already_reachable_note` says the places this room
# already leads to *"do not need naming again"* -- so on a room with one edge
# the prompt asks for the way back and forbids it in the same breath. THIS FILE
# DOES NOT FIX THAT, because this bench measures those prompts and a bench that
# edited its own subject would be measuring itself. What it does instead is
# refuse to score the ambiguity: see `#correct_dead_end?`, which takes a case
# that named only the way back and declared no new ground OUT OF
# `exit_already_reachable`'s denominator rather than flagging it. A prompt item
# that resolves the contradiction should re-baseline and then delete the gate.
class Eval::Realization::Scorer
  # THE CHECKS, IN TRUST ORDER: the exits the engine itself refuses first,
  # because those have a cost the records can prove; then the allowances, which
  # are a number the prompt stated; then the names; then the one keyword check,
  # last, because it is the only one that reads words.
  CHECKS = {
    exit_into_a_written_room: "an exit named a place already WRITTEN that this room cannot reach -- " \
                              "the prompt marks those and the engine drops the edge",
    exit_already_reachable: "an exit named a place this room can already reach, which the prompt " \
                            "lists and says does not need naming again",
    exit_named_this_room: "an exit named the room it leads out of",
    exit_over_the_allowance: "more ways out than the prompt said were left",
    no_new_ground: "a room the story points into whose every exit was a place the world already had",
    person_over_the_allowance: "more people than the prompt said this world had room for",
    item_over_the_allowance: "more things than the prompt said this room had room for",
    name_already_spoken_for: "a name the world had already given to somebody, somewhere or something",
    proposal_refused: "a person or a thing the engine would not admit, so the room lost it",
    readable_without_words: "a thing marked readable with nothing written on it, which costs a " \
                            "later round trip to Item::Inscriber",
    race_not_named: "a person written for a MONSTROUS slot whose sheet never says the race -- " \
                    "a KEYWORD check, and the one figure here that reads words"
  }.freeze

  # THE CHECK THAT IS NOT A RECORD COMPARISON, named so a reader of the board
  # can weigh it differently from the ten above it.
  KEYWORD_CHECKS = %i[race_not_named].freeze

  # ONE SCORED REALIZATION, off a stored row and nothing else.
  Reading = Data.define(:row) do
    def id = row["id"]
    def shape = row["shape"]
    def story = row["story"]
    def held_out? = Eval::Realization.held_out?(story)
    def failed? = !row["error"].nil?
    def scored? = !failed? && detail.present?
    def error = row["error"]
    def calls = row["calls"].to_i

    # WHY A CALL FAILED, as a class name -- `BaseAgent::RefusalError` reads
    # differently from a timeout and a count cannot tell them apart. The ONE
    # spelling of it: `Eval::Realization::Result.figures_of` asks through here
    # rather than matching the stored string's prefix, because a prefix match
    # would count a `BaseAgent::RefusalErrorSomething` as a refusal. Split on
    # colon-space, not on a colon: the class is usually namespaced.
    def error_class = error&.split(": ")&.first

    # THE MODEL DECLINED TO BUILD THE ROOM. With an arm of one there is nothing
    # to rotate to, so it arrives as a failure of a nameable class rather than
    # as an answer. Its own figure because it is the one failure about the
    # PROMPT.
    def refused? = error_class == "BaseAgent::RefusalError"

    # THE PROVIDER ANSWERED WITH REAL-WORLD CRISIS RESOURCES. Never persisted,
    # never rotated, counted apart -- see `BaseAgent::CrisisResponseError`.
    def crisis? = error_class == "BaseAgent::CrisisResponseError"

    # ONE REALIZATION, TWO CALLS, AND NOT ONE MORE. A third would mean something
    # else was bought -- and the corpus validator refuses the one case shape
    # that could buy fewer (a stub already at its exit cap makes only one).
    def extra_calls = [ calls - Eval::Realization::CALLS.size, 0 ].max

    def facts = row["facts"] || {}
    def answers = row["answers"] || {}
    def detail = answers["detail"] || {}
    def exits_answer = answers["exits"] || {}
    def after = row["after"] || {}

    def room = facts["room"].to_s
    def expects_new_ground? = facts["expects_new_ground"] == true

    def people = Array(detail["people"])
    def items = Array(detail["items"])
    def exits = Array(exits_answer["exits"])
    def exit_names = exits.filter_map { |exit| exit["name"].presence }
    def asked_for_exits? = row["answers"].is_a?(Hash) && row["answers"].key?("exits")

    def slots = Array(facts["slots"])
    def places = Array(facts["places"])
    def reachable = Array(facts["reachable"])

    def people_allowance = facts["people_allowance"].to_i
    def item_allowance = facts["item_allowance"].to_i
    def exit_allowance = facts["exit_allowance"].to_i

    # EVERY NAME THIS ANSWER PROPOSED that the engine had to decide about: both
    # of a person's names and every thing's.
    def proposed_names
      people.flat_map { |person| [ person["fullname"], person["nickname"] ] }.compact_blank +
        items.filter_map { |item| item["name"].presence }
    end

    def admitted_people = Array(after["people"])
    def admitted_items = Array(after["items"])

    # WHO WAS ALREADY STANDING IN THE STUB BEFORE THIS CALL. A seed file puts
    # people in a room and `Eval::Realization::Stage` deliberately leaves them
    # there, so `after["people"]` is not a list of who this call wrote -- it is
    # everybody in the room afterwards, the occupants included. Absent on a set
    # stored before this was recorded, which reads as nobody and scores such a
    # set exactly as it scored then.
    def already_present = Array(facts["present"])

    # THE PLACES THAT CAME INTO EXISTENCE, off the records `Bench#after` wrote
    # rather than off the answer. Not the same list as the new names the answer
    # carried: `Location::Generator#write_exits!` stops connecting at the
    # allowance, so a room that named five and was allowed three opened three.
    def new_places = Array(after["new_places"])

    def same?(left, right) = left.to_s.strip.casecmp?(right.to_s.strip)
    def any_named?(list, name) = Array(list).any? { |entry| same?(entry, name) }

    def place_for(name) = places.find { |place| same?(place["name"], name) }
  end

  # ONE FLAGGED THING, with the evidence a reader needs to see whether the check
  # was right. `Story::Scoreboard`'s rule: the captain's attention goes only to
  # what a check caught, so what it caught has to be legible without opening the
  # set.
  Flag = Data.define(:code, :reading, :evidence) do
    def id = reading.id
    def held_out? = reading.held_out?
    def to_s = "#{id} #{code}: #{evidence}"
  end

  attr_reader :rows

  def initialize(rows)
    @rows = Array(rows).map { |row| row.transform_keys(&:to_s) }
  end

  # EVERY ROW WRAPPED, THE FAILURES INCLUDED. `#readings` below is the SCORED
  # subset and the one every check is judged over -- a failed call is out of
  # every denominator, which is what stops a run of refusals reading as a run
  # with nothing wrong with it. The operational counts want the other list, so
  # `Eval::Realization::Result.figures_of` reads its refusals, its crises and
  # its extra calls through here instead of re-deriving them off the row
  # strings. One object, one spelling of each predicate.
  def all_readings
    @all_readings ||= rows.map { |row| Reading.new(row) }
  end

  def readings
    @readings ||= all_readings.reject(&:failed?)
  end

  def scanned = readings.count(&:scored?)

  def flags
    @flags ||= CHECKS.keys.flat_map { |code| flagged_for(code) }
  end

  def flagged_for(code) = judgement(code).fetch(:flagged)

  def judgeable_for(code) = judgement(code).fetch(:judgeable)

  def rate(code)
    found = judgement(code)
    found[:judgeable].zero? ? 0.0 : found[:flagged].size.fdiv(found[:judgeable])
  end

  # THE FIGURES WITH NO BETTER DIRECTION, computed here beside the rates because
  # they are the check on the rates. See this class's header.
  def reported
    { "people_named" => Eval.mean(readings.map { |r| r.people.size }),
      "people_offered" => Eval.mean(readings.map { |r| r.people_allowance }),
      "people_take_up" => share(readings.sum { |r| r.people.size }, readings.sum { |r| r.people_allowance }),
      "items_named" => Eval.mean(readings.map { |r| r.items.size }),
      "exits_named" => Eval.mean(readings.select(&:asked_for_exits?).map { |r| r.exit_names.size }),
      "new_places_opened" => Eval.mean(readings.select(&:asked_for_exits?).map { |r| r.new_places.size }),
      "new_places_named" => Eval.mean(readings.select(&:asked_for_exits?).map { |r| new_ground(r).size }),
      "exits_restating" => share(readings.sum { |r| restated(r).size },
                                 readings.sum { |r| r.exit_names.size }) }
  end

  private

  def share(part, whole) = whole.to_i.zero? ? 0.0 : part.fdiv(whole)

  def judgement(code)
    @judgements ||= {}
    @judgements[code.to_sym] ||= send("judge_#{code}")
  end

  # ---------------------------------------------------------------- the exits

  # A PLACE THE STORY ALREADY HAD. The scout's figure and the shape every other
  # exit check is cut out of -- reported as a rate with no better direction,
  # because the prompt asks for reuse when an exit leads somewhere already
  # known. What is a DEFECT is the three narrower shapes below it.
  def restated(reading)
    reading.exit_names.select { |name| reading.place_for(name) }
  end

  def new_ground(reading)
    reading.exit_names.reject { |name| reading.place_for(name) || reading.same?(name, reading.room) }
  end

  def judge_exit_into_a_written_room
    flag_each(:exit_into_a_written_room, ->(r) { r.exit_names.size }) do |reading|
      reading.exit_names.select { |name|
        place = reading.place_for(name)
        place && place["realized"] && !place["connected"]
      }.map { |name| "named #{name.inspect}, which is written and not reachable from #{reading.room}" }
    end
  end

  # GATED THE WAY `no_new_ground` IS GATED, and for the same reason: a case that
  # declared the story does NOT point onward and came back with the way back and
  # nothing else gave the answer the exits prompt asks a dead end for, so it is
  # UNJUDGEABLE here -- out of the denominator, not merely unflagged, because a
  # rate this check did not earn is worse than no rate. A room that named the
  # way back alongside anything else, or that was declared to point onward, is
  # judged exactly as before. See this class's header for the prompt
  # contradiction that makes the gate necessary.
  def judge_exit_already_reachable
    flag_each(:exit_already_reachable, ->(r) { correct_dead_end?(r) ? 0 : r.exit_names.size }) do |reading|
      next [] if correct_dead_end?(reading)

      reading.exit_names.select { |name| reading.any_named?(reading.reachable, name) }
             .map { |name| "named #{name.inspect}, which #{reading.room} already leads to" }
    end
  end

  # ONE EXIT, AND IT IS ONE THE ROOM COULD ALREADY REACH, in a case that says
  # the story stops here.
  def correct_dead_end?(reading)
    !reading.expects_new_ground? && reading.exit_names.one? &&
      reading.any_named?(reading.reachable, reading.exit_names.first)
  end

  def judge_exit_named_this_room
    flag_each(:exit_named_this_room, ->(r) { r.exit_names.size }) do |reading|
      reading.exit_names.select { |name| reading.same?(name, reading.room) }
             .map { |name| "named #{name.inspect}, which is this room" }
    end
  end

  # A COUNT AGAINST A NUMBER THE PROMPT STATED, and the case is the unit: a room
  # asked for at most two that named four is one defect, not two.
  def judge_exit_over_the_allowance
    flag_cases(:exit_over_the_allowance, ->(r) { r.asked_for_exits? }) do |reading|
      next nil unless reading.exit_names.size > reading.exit_allowance

      "named #{reading.exit_names.size} ways out of at most #{reading.exit_allowance}"
    end
  end

  # THE ONE CHECK THAT IS ABOUT THE WORLD RATHER THAN THE ROOM. A dead end that
  # names only the way back is a CORRECT answer -- the prompt asks for exactly
  # that -- so this is judgeable only where the case has declared that the story
  # points onward from here. `Eval::Realization::Corpus` refuses a case that
  # does not say which it is.
  # A ROOM THAT NAMED NO WAY OUT AT ALL IS FLAGGED TOO, and that is deliberate:
  # a story that points onward from here and a room that opened onto nothing is
  # the descent stopping just as surely as one whose every door led back. The
  # evidence line says which of the two it was.
  def judge_no_new_ground
    flag_cases(:no_new_ground, ->(r) { r.asked_for_exits? && r.expects_new_ground? }) do |reading|
      next nil unless new_ground(reading).empty?
      next "#{reading.room} named no way out at all" if reading.exit_names.empty?

      "every way out of #{reading.room} was a place the world already had: " \
        "#{reading.exit_names.join(", ")}"
    end
  end

  # --------------------------------------------------------- the cast and the floor

  def judge_person_over_the_allowance
    flag_cases(:person_over_the_allowance, ->(_r) { true }) do |reading|
      next nil unless reading.people.size > reading.people_allowance

      "named #{reading.people.size} people where the prompt allowed #{reading.people_allowance}"
    end
  end

  def judge_item_over_the_allowance
    flag_cases(:item_over_the_allowance, ->(_r) { true }) do |reading|
      next nil unless reading.items.size > reading.item_allowance

      "named #{reading.items.size} things where the prompt allowed #{reading.item_allowance}"
    end
  end

  # A NAME THE WORLD HAD ALREADY GIVEN TO SOMETHING. Checked against every name
  # in the world and not only against the twenty of each the prompt showed --
  # because the engine refuses on the full list, so a collision outside the
  # truncation costs the room its furniture just the same. The evidence line
  # says which it was, since a collision the model was never shown is a defect
  # in `Location::Generator#known_names_note` rather than in the answer.
  def judge_name_already_spoken_for
    flag_each(:name_already_spoken_for, ->(r) { r.proposed_names.size }) do |reading|
      shown = Array(reading.facts["taken_names"])
      known = reading.facts["all_names"] || {}

      reading.proposed_names.filter_map do |name|
        where = %w[people places things].find { |kind| reading.any_named?(known[kind], name) }
        next if where.nil?

        "#{name.inspect} is already a #{where.singularize} in this world" \
          "#{" -- and the prompt never showed it" unless reading.any_named?(shown, name)}"
      end
    end
  end

  # WHAT THE ROOM ACTUALLY LOST, read off the records after the admission rather
  # than inferred from the answer. The superset of every name collision above,
  # plus the caps, plus a sheet that arrived cut off -- every reason
  # `Item::Registry` and `Character::Registry` drop a proposal.
  #
  # COUNTED PER NAME AND NOT BY MEMBERSHIP, which is the difference between this
  # figure and a reading of the answer. A proposal off `Location::DetailSchema`
  # is a HASH, and `Character::Registry#resolve` matches a non-`Character`
  # candidate on `candidate.to_s` -- so a proposal never resolves to an existing
  # person by name. It goes to `#create_one` instead, where `#creation_refusal`
  # asks `#person_named?` and refuses it outright: *a person in this story is
  # already called that*. An answer that names one person twice therefore gets
  # ONE row and loses the other, and an answer naming somebody the story already
  # has gets none. Asking only whether the name appears in the records would
  # call every one of those admitted and report a room that lost somebody as
  # clean.
  #
  # SO EACH ROW SEATS ONE PROPOSAL, in the order the answer made them, and what
  # is left standing is what the room lost. A SELF-COLLISION is a refusal of the
  # SECOND occurrence; the denominator stays every proposal the answer made, so
  # a room that named one person twice and got one reads one of two.
  #
  # AND A SEAT IS A ROW THIS CALL PRODUCED, which is why the people already in
  # the stub are taken out of the tally first. `Eval::Realization::Stage` leaves
  # a seeded room's cast standing on purpose -- Neb Halloran is in the tide post
  # before anything is written -- so `after["people"]` holds the occupants as
  # well as the new arrivals. Seating a refused proposal against the very
  # occupant whose name refused it would report the room that lost somebody as
  # the room that kept them. ITEMS NEED NO SUCH SUBTRACTION: `Stage#wind_back!`
  # destroys what is lying in the room, so every thing in the records afterwards
  # is one this call put there.
  def judge_proposal_refused
    flag_each(:proposal_refused, ->(r) { r.people.size + r.items.size }) do |reading|
      unseated(reading.people.map { |person| person["fullname"] },
               reading.admitted_people, "an unnamed person", already: reading.already_present) +
        unseated(reading.items.map { |item| item["name"] }, reading.admitted_items, "an unnamed thing")
    end
  end

  # THE PROPOSALS NO RECORD ANSWERS FOR. Each admitted row is a seat, taken by
  # the first proposal of that name; every proposal left standing is one the
  # room lost. A proposal with no name at all never takes a seat -- the
  # registries refuse it (`Character::Registry#create_one`), and matching it
  # against a blank would be matching two different absences.
  def unseated(proposed, admitted, unnamed, already: [])
    seats = admitted.each_with_object(Hash.new(0)) { |name, tally| tally[key_for(name)] += 1 }
    already.each { |name| seats[key_for(name)] -= 1 }

    proposed.filter_map do |name|
      seat = key_for(name)
      if seat.present? && seats[seat].positive?
        seats[seat] -= 1
        next
      end

      "the engine would not admit #{name.presence || unnamed}"
    end
  end

  # The same comparison `Reading#same?` makes, as a hash key: a name is one name
  # however it was spaced or cased.
  def key_for(name) = name.to_s.strip.downcase

  def judge_readable_without_words
    flag_each(:readable_without_words, ->(r) { r.items.count { |item| item["readable"] == true } }) do |reading|
      reading.items.select { |item| item["readable"] == true && item["inscription"].to_s.strip.empty? }
             .map { |item| "#{item["name"].inspect} is readable with nothing written on it" }
    end
  end

  # ------------------------------------------------------------ the one keyword check

  # THE SLOT'S RACE, AND WHETHER THE PERSON WRITTEN FOR IT SAYS SO.
  #
  # WHAT IT CAN SEE: the prompt states, per slot, `the 1st is <race>, about
  # <age>, <sex>`, and the engine writes that race onto the row whatever the
  # model answers (`Character::Registry#create_one`). So the RECORD is never
  # wrong and the PROSE can be: a Nocturna-Blighted slot described as a nervous
  # clerk is a person the room is wrong about, and every later conversation
  # inherits it.
  #
  # WHAT IT CANNOT SEE, stated because the rate is only readable next to it: a
  # compliant person written entirely in chitin and silence, never naming the
  # race, reads here as a miss. The rule is deliberately the loosest one that is
  # still deterministic -- the race name, or the race name without a trailing
  # `s`, appearing anywhere in the three sheet fields the player ever sees.
  # Judged ONLY on a monstrous slot the model actually filled, which is where
  # getting it wrong costs something.
  def judge_race_not_named
    flag_each(:race_not_named, ->(r) { monstrous_pairs(r).size }) do |reading|
      monstrous_pairs(reading).reject { |slot, person| names_race?(person, slot["race"]) }
                              .map { |slot, person|
        "#{person["fullname"].inspect} was written for a #{slot["race"]} slot and never says so"
      }
    end
  end

  # The people the model wrote into a slot the engine had already decided was
  # one of the world's monsters. Index for index: `Character::Registry#admit_one`
  # reads slot `n` for the `n`th entry of the answer, so the pairing here is the
  # engine's own.
  def monstrous_pairs(reading)
    reading.slots.each_with_index.filter_map do |slot, index|
      person = reading.people[index]
      next if person.nil? || !slot["monstrous"] || slot["race"].blank?

      [ slot, person ]
    end
  end

  SHEET_FIELDS = %w[appearance personality backstory].freeze

  def names_race?(person, race)
    sheet = SHEET_FIELDS.map { |field| person[field].to_s }.join(" ").downcase
    stem = race.to_s.downcase.delete_suffix("s")

    stem.present? && sheet.include?(stem)
  end

  # ---------------------------------------------------------------- plumbing

  # A CHECK COUNTED PER THING NAMED -- one flag per exit, per name, per person.
  # `judgeable` is what the check could have been judged on, summed over the
  # readings, so a rate is flags over opportunities.
  def flag_each(code, denominator)
    flagged = []
    judgeable = 0

    readings.each do |reading|
      judgeable += denominator.call(reading).to_i
      yield(reading).each { |evidence| flagged << Flag.new(code: code, reading: reading, evidence: evidence) }
    end

    { flagged: flagged, judgeable: judgeable }
  end

  # A CHECK COUNTED PER CASE -- a room either exceeded its allowance or it did
  # not, however many it named over.
  def flag_cases(code, judgeable_when)
    flagged = []
    judgeable = 0

    readings.each do |reading|
      next unless judgeable_when.call(reading)

      judgeable += 1
      evidence = yield(reading)
      flagged << Flag.new(code: code, reading: reading, evidence: evidence) if evidence
    end

    { flagged: flagged, judgeable: judgeable }
  end
end
