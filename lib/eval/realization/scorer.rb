# WHAT THE MODEL WROTE, AGAINST WHAT THE PROMPT TOLD IT, AND NOTHING ELSE.
#
# NEARLY EVERY CHECK IN HERE IS A SET COMPARISON, and that is the design rather
# than a limitation. The standing constraint (AGENTS.md) is that nothing may
# depend on a model obeying its prompt; the corollary for an instrument is that
# nothing may depend on a CHECKER understanding prose. So each of those reads a
# name the model wrote against a closed list of names the prompt handed it, or a
# count against a number the prompt stated. Both sides are records. A rate there
# is therefore the same kind of fact `rake game:sweep` produces -- something the
# app itself could have asserted -- rather than a reading.
#
# THE EXCEPTIONS ARE `KEYWORD_CHECKS`, AND EACH IS NAMED FOR WHAT IT CAN SEE.
# `race_not_named` can tell that the word "Nocturna-Blighted" is absent from a
# sheet written for a Nocturna-Blighted slot, and it cannot tell a compliant
# person described entirely in chitin and silence from a non-compliant one.
# `size_the_records_do_not_hold` compares numbers, but it has to READ them out
# of prose first. They are reported apart from the checks the records prove,
# with that stated, and their false-positive rate is unknown until a baseline is
# bought -- which is exactly the discipline two earlier prose-reading checks
# failed (`data/ta-model-bench`, and `Story::Scoreboard`'s header). That
# constant is the one list of them; do not count them in a sentence.
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
# THE PEOPLE HALF OF THAT HAZARD IS NOW THE SCHEMA'S, and it is the clearest
# example in this file of the difference between a rate and a guarantee. Since
# the captain's ruling of 2026-09-07 the count is EXACT -- the narrator picks a
# word, the engine rolls the number, `Location::DetailSchema.for_people`
# requires it -- so a room that answered with nobody where two were asked for is
# a FAILED CALL and not a good score. `people_short_of_the_pick` is the check
# that says whether that holds against a real provider, and
# `population_declined` is the one that says whether the pick was made at all:
# the way for that ruling to come to nothing is not a model answering `nobody`
# but a model answering nothing, which is `inside_declined`'s finding one field
# over.
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
  # are a number the prompt stated; then the names; then `KEYWORD_CHECKS`, last,
  # because those are the ones that read words.
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
    room_name_refused: "a room asked to name itself that kept its placeholder, read off the room's " \
                       "own name afterwards -- judgeable only on a room the engine laid out",
    room_name_already_taken: "a proposed room name the world had already given to somewhere, " \
                             "somebody or something",
    inside_declined: "an exit named with no `inside` pick at all, so the engine took the quietest " \
                     "option -- the field is optional and an absent one is a decision not made",
    inside_where_the_world_wanted_none: "a stub whose world plainly holds no building gave one an inside " \
                                        "-- judgeable only on a case labelled `expects_inside: false`",
    no_inside_where_the_world_wanted_one: "a stub whose world plainly holds a building gave none an inside " \
                                          "-- judgeable only on a case labelled `expects_inside: true`",
    population_declined: "an exit named with no `population` pick at all, so the engine rolled a word " \
                         "for the place instead -- the field asks and nothing rests on the asking",
    people_short_of_the_pick: "a room asked for an exact number of people that came back with fewer, so " \
                              "the room the prose describes is emptier than the word somebody picked for it",
    parameters_declined: "a building offered the `parameters` block that came back without one, so every " \
                         "pick fell to its quietest default",
    parameters_the_engine_narrowed: "a building whose picks the layout could not honour -- a warren on a " \
                                    "footprint that holds one room, a depth the storeys do not reach",
    race_not_named: "a person written for a MONSTROUS slot whose sheet never says the race -- " \
                    "a KEYWORD check, so it reads words rather than comparing records",
    size_the_records_do_not_hold: "the description stated a size in paces, or a storey, that is not this " \
                                  "room's -- a KEYWORD check, judgeable only on a room the engine laid out"
  }.freeze

  # THE CHECKS THAT ARE NOT RECORD COMPARISONS, named so a reader of the board
  # can weigh them differently from the ones above them.
  #
  # THE GEOMETRY CHECK IS HALFWAY BETWEEN, and it is worth saying which half is
  # which rather than filing it as either. What it COMPARES is a record and
  # nothing but: a number out of `Location::Box`, off the very `Location::Plan`
  # the prompt was built from. What it READS is prose --
  # `Story::Audit::Prose.size_claims` and `.storey_claims`, whose grammars are
  # narrow and whose measured detection counts are on those methods. A
  # description that contradicts its own floor plan in a sentence neither
  # grammar reads is a miss, so this is counted here with `race_not_named`
  # rather than beside the set comparisons.
  #
  # AND THE WALLS ARE NOT CHECKED AT ALL. Which wall the prose put a door in was
  # a check here and is now
  # `Eval::Realization::UNAVAILABLE_TO_A_REALIZATION`'s
  # `door_in_a_wall_the_records_do_not_hold` -- six measured grammars each
  # admitted a false-positive shape the one before it did not, and a rate off
  # any of them would have been a clean-looking lie. The PROMPT still states
  # every door's wall; what is gone is the claim to verify it afterwards.
  #
  # AND A CLAIM THAT ECHOES THE PROMPT IS NOT A DEFECT, which is why the
  # denominator is not simply the count of claims a grammar found:
  # `#judge_size_the_records_do_not_hold` and `#judgeable_storey_claims` carry
  # the two discounts and the prompt sentences that make them necessary.
  KEYWORD_CHECKS = %i[race_not_named size_the_records_do_not_hold].freeze

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

    # THE WAY BACK, and whether this row records one at all. A set stored before
    # `reached_from` was written down has no key -- not the same state as an
    # OPENING room, which has the key and nothing in it because it was never
    # walked into.
    def records_the_way_back? = facts.key?("reached_from")
    def reached_from = facts["reached_from"].to_s

    # WHAT THE PLAYER WILL READ ON ARRIVAL, which is the one field the geometry
    # checks are pointed at. Not the lore: a room's history is written about a
    # building over time and is where a wall that has since been knocked through
    # legitimately belongs, so a measurement in it is not a claim about the room
    # as it stands.
    def description = detail["description"].to_s

    # THE FLOOR PLAN THE PROMPT STATED, or nil for a room that had none. A set
    # stored before this was recorded has no key at all, which reads as no plan
    # and takes those rows out of both geometry checks -- the same rule
    # `#records_the_way_back?` follows, and for the same reason.
    def plan = facts["plan"]
    def planned? = plan.is_a?(Hash)

    # WHETHER THE DETAIL PROMPT ASKED THIS ROOM TO NAME ITSELF. A set stored
    # before the ask existed has no key and reads FALSE, which takes those rows
    # out of both name checks' denominators -- `#records_the_way_back?`'s rule,
    # and the reason it is a stored fact rather than `#planned?`: the before
    # side of a naming comparison must report those checks unavailable, not
    # report a model failing to answer a question nobody put to it.
    def asked_for_a_name? = facts["name_asked"] == true

    # THE NAME THE ANSWER PROPOSED, and the names the prompt showed as spoken
    # for. `#name_after` is the room's own name once the engine had decided --
    # the record, and the only thing that says whether the proposal was taken.
    def proposed_name = detail["name"].to_s
    def names_shown = Array(facts["name_taken"])
    def name_after = after["name"].to_s
    def room_paces = [ plan && plan["width"], plan && plan["depth"] ].map(&:to_i).sort

    # THE SAME TWO NUMBERS IN THE ORDER THE PROMPT STATED THEM, for evidence and
    # never for a comparison -- `Location::Plan#size_sentence` says width by
    # depth, and a flag an auditor reads beside that sentence has to agree with
    # it (`#judge_size_the_records_do_not_hold`).
    def room_extent = [ plan && plan["width"], plan && plan["depth"] ].map(&:to_i)
    def planned_storey = plan && plan["storey"]

    # THE OTHER PACE PAIR THE PROMPT STATED -- the PLACE's footprint, out of
    # `Location::Plan#storey_sentence`. Nil for a place with no extent and for a
    # set stored before the pair was recorded, where nothing can be said to have
    # been echoed.
    def place_paces
      pair = [ plan && plan["place_width"], plan && plan["place_depth"] ]
      return nil if pair.any?(&:nil?)

      pair.map(&:to_i).sort
    end

    # EVERY PACE PAIR THE PROMPT STATED, and `Location::Plan` is the one author
    # of that list: the room's own box (`#size_sentence`) and the place's
    # footprint (`#footprint_clause`). A number the prompt stated is never a
    # defect, so a claim in here contradicts nothing.
    def paces_stated = [ room_paces, place_paces ].compact

    # EVERY STOREY THE PROMPT STATED, from the same one author: the room's own
    # (`#storey_sentence`), the far storey of every stair (`#stair_clause`
    # writes one per stair), and 0, which that same sentence names as the ground
    # floor whatever storey the room is on. A sentence added to `Location::Plan`
    # is picked up here rather than opening another hole.
    def storeys_stated
      stairs = Array(plan && plan["stairs"]).filter_map { |stair| stair["storey"] }

      ([ planned_storey ] + stairs + [ 0 ]).compact.uniq
    end

    def people = Array(detail["people"])
    def items = Array(detail["items"])
    def exits = Array(exits_answer["exits"])
    def exit_names = exits.filter_map { |exit| exit["name"].presence }
    def asked_for_exits? = row["answers"].is_a?(Hash) && row["answers"].key?("exits")

    # THE LABEL, AND WHETHER THERE IS ONE. `nil` takes the reading out of both
    # inside checks' denominators, which is what a case that left the label out
    # asked for -- and it is also what a set stored before the label existed
    # reads, so such a set reports both checks unavailable rather than reporting
    # a model failing a question nobody put to it.
    def expects_inside = facts["expects_inside"]

    # WHETHER THE DETAIL PROMPT OFFERED THIS ROOM THE PARAMETERS BLOCK -- true
    # for a building with no inside yet, false for every other room in the game
    # and for every set stored before the block existed.
    def parameters_asked? = facts["parameters_asked"] == true
    def parameters = detail["parameters"] || {}

    # THE BUILDING THE PICKS PRODUCED, one entry per room the layout wrote.
    # Empty for every reading that is not a building and for every set stored
    # before it was recorded.
    def rooms = Array(after["rooms"])

    # HOW FAR DOWN THE LAYOUT ACTUALLY WENT, off the rows: the deepest storey it
    # wrote, as a count of floors below the ground one. Zero for a building with
    # no cellar and for a reading with no rooms at all.
    def storeys_below = -[ rooms.filter_map { |room| room["storey"] }.min.to_i, 0 ].min

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
    { "insides_given" => share(readings.sum { |r| inside_picks(r).count { |pick| inside?(pick) } },
                               readings.sum { |r| r.exit_names.size }),
      "rooms_laid_out" => Eval.mean(readings.select(&:parameters_asked?).map { |r| r.rooms.size }),
      "storeys_below_ground" => Eval.mean(readings.select(&:parameters_asked?).map { |r| r.storeys_below }),
      "hazard_on_the_ground_floor" => hazard_share(0..0),
      "hazard_below_ground" => hazard_share(..-1),
      "populations_given" => share(readings.sum { |r| population_picks(r).count(&:present?) },
                                   readings.sum { |r| r.exit_names.size }),
      "crowds_picked" => share(readings.sum { |r| population_picks(r).count { |pick| crowd?(pick) } },
                               readings.sum { |r| population_picks(r).count(&:present?) }),
      "people_named" => Eval.mean(readings.map { |r| r.people.size }),
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

  # THE CAPTAIN'S OWN FIGURE, CUT THE ONE WAY THAT SAYS WHETHER THE GRADIENT DID
  # ANYTHING: the share of rooms carrying a hazard, by storey. Two cuts and not a
  # table, because a board prints numbers -- the ground floor and everything
  # below it, which is the comparison `worse the deeper you go` is supposed to
  # move. It reads ROWS: `Location::Interior` wrote them and no column anywhere
  # records the pick.
  def hazard_share(storeys)
    rooms = readings.flat_map(&:rooms).select { |room| storeys.cover?(room["storey"].to_i) }

    share(rooms.count { |room| room["hazard"].present? }, rooms.size)
  end

  def inside_picks(reading) = reading.exits.map { |exit| exit["inside"] }

  # THE POPULATION WORDS ONE ANSWER PICKED, one per exit it named. A blank is an
  # answer that left the field out, which is `population_declined`.
  def population_picks(reading) = reading.exits.map { |exit| exit["population"] }

  # WHETHER A PICK ASKED FOR MORE THAN NOBODY. There is no quietest option on
  # this list -- `nobody` is a real answer somebody chose, not a default -- so
  # unlike `inside?` above this is a cut of the picks rather than a test of
  # whether one was made. Printed as `crowds_picked` beside
  # `population_declined`, because the cheapest way to clear every rate in this
  # file is still to write nobody, and a model that picked `nobody` everywhere
  # would have made the pick honestly and emptied the world anyway.
  def crowd?(pick) = pick.present? && pick != Location::Population::LABELS.first

  # WHETHER A PICK ASKED FOR AN INSIDE. `no inside` is the quietest option and
  # the default, and an ABSENT pick is not the same thing as that one -- the
  # first is a decision and the second is `inside_declined`.
  def inside?(pick) = pick.present? && pick != Location::Parameters::NO_INSIDE

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

  # ONE EXIT, AND IT IS THE WAY BACK, in a case that says the story stops here.
  #
  # THE WAY BACK AND NOT MERELY SOMEWHERE ALREADY REACHABLE, because those are
  # different on a stub with more than one edge and the prompt's sentence is
  # about the first: *"if the only way out is back the place the player came
  # from"*. A `two-ways-out` stub that answered with the OTHER neighbour and
  # nothing else did not give the answer the prompt asked for, and taking it out
  # of the denominator would hide the defect the shape exists to reach. An
  # OPENING room has no way back, so nothing it names can be one.
  #
  # AND A SET STORED BEFORE THE WAY BACK WAS RECORDED SCORES AS IT SCORED THEN.
  # Those rows have no `reached_from` key at all, so they keep the older test --
  # one exit, and it is somewhere the room could already reach. That is exact
  # for every single-edge case, which is every case those sets measured. A
  # rescorable set that quietly changed its numbers under a reader would be
  # worse than one that could not be rescored at all.
  def correct_dead_end?(reading)
    return false if reading.expects_new_ground? || !reading.exit_names.one?
    return reading.any_named?(reading.reachable, reading.exit_names.first) unless reading.records_the_way_back?

    reading.reached_from.present? && reading.same?(reading.exit_names.first, reading.reached_from)
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

  # ------------------------------------------------------------ the inside pick

  # A DECISION NOT MADE. The `inside` field is OPTIONAL, so an answer that omits
  # it is a legal answer and the engine takes the quietest option -- which means
  # the ordinary way for a world to end up with no buildings in it is not a
  # model saying `no inside` but a model saying nothing at all. Its own figure
  # for that reason, and the one figure a set stored before the field existed
  # can honestly report: those answers have no pick, so they read as declined,
  # which is exactly what they were.
  def judge_inside_declined
    flag_each(:inside_declined, ->(r) { r.asked_for_exits? ? r.exits.size : 0 }) do |reading|
      next [] unless reading.asked_for_exits?

      reading.exits.reject { |exit| exit["inside"].present? }
             .map { |exit| "named #{exit["name"].inspect} with no inside pick at all" }
    end
  end

  # AND THE TWO THAT READ THE PICK AGAINST A HAND LABEL, which is the only thing
  # in this file that is not a record on both sides -- there is no record of what
  # a world SHOULD have been. `expects_inside` is written by whoever wrote the
  # case and is LEFT OUT unless the answer is not a guess, so most cases are out
  # of both denominators: `Story::Audit#judgeable_for`'s rule, and the same one
  # `no_new_ground` stands on.
  def judge_inside_where_the_world_wanted_none
    flag_cases(:inside_where_the_world_wanted_none,
               ->(r) { r.asked_for_exits? && r.expects_inside == false }) do |reading|
      given = reading.exits.select { |exit| inside?(exit["inside"]) }
      next nil if given.empty?

      "gave an inside to #{given.map { |exit| "#{exit["name"]} (#{exit["inside"]})" }.join(", ")} " \
        "in a world that plainly holds no building"
    end
  end

  def judge_no_inside_where_the_world_wanted_one
    flag_cases(:no_inside_where_the_world_wanted_one,
               ->(r) { r.asked_for_exits? && r.expects_inside == true && r.exit_names.any? }) do |reading|
      next nil if reading.exits.any? { |exit| inside?(exit["inside"]) }

      "gave an inside to none of #{reading.exit_names.join(", ")} in a world that plainly holds one"
    end
  end

  # ------------------------------------------------------- the population pick

  # A DECISION NOT MADE, `judge_inside_declined`'s figure one field over and its
  # reason unchanged: `Location::ExitsSchema` asks for a `population` word per
  # exit and nothing rests on getting one -- an absent word leaves the stub with
  # none and `Location::Population.label_for` rolls one when somebody walks in.
  # So the ordinary way for the captain's ruling of 2026-09-07 to come to nothing
  # is not a model picking `nobody` but a model saying nothing at all, and this is
  # the figure for that.
  #
  # A SET STORED BEFORE THE FIELD EXISTED READS AS DECLINED EVERYWHERE, which is
  # exactly what those answers were: no pick was offered and none was made. That
  # is what makes it honest as the before side of this pair rather than
  # `unavailable`.
  def judge_population_declined
    flag_each(:population_declined, ->(r) { r.asked_for_exits? ? r.exits.size : 0 }) do |reading|
      next [] unless reading.asked_for_exits?

      reading.exits.reject { |exit| exit["population"].present? }
             .map { |exit| "named #{exit["name"].inspect} with no population pick at all" }
    end
  end

  # AND WHETHER THE ROOM GOT THE PEOPLE IT WAS ASKED FOR, which is the other half
  # of the ruling and the defect it was made for: a prompt that offered slots and
  # an answer that named nobody. The prompt now states an EXACT count and
  # `Location::DetailSchema.for_people` requires it, so a short answer should be
  # a failed call rather than a quiet emptying -- and this is the check that says
  # whether that is true of a real provider rather than of the JSON schema.
  #
  # JUDGED ONLY WHERE PEOPLE WERE ASKED FOR, so a room the pick called empty is
  # out of the denominator rather than counted as a success: nought people asked
  # and nought written is not the thing being measured. `people_take_up` beside
  # it is the same fact as a ratio.
  def judge_people_short_of_the_pick
    flag_cases(:people_short_of_the_pick, ->(r) { r.people_allowance.positive? }) do |reading|
      next nil unless reading.people.size < reading.people_allowance

      "was asked for #{reading.people_allowance} #{"person".pluralize(reading.people_allowance)} " \
        "and wrote #{reading.people.size}"
    end
  end

  # ----------------------------------------------------- the building's parameters

  # THE SAME DECISION-NOT-MADE FIGURE FOR THE BLOCK A BUILDING IS OFFERED. The
  # `parameters` object is optional for the reason every optional field in these
  # schemas is optional (`Location::DetailSchema`): an absent one and an empty
  # one mean the same thing, and a required object a model had nothing to say
  # about would fail the whole realization.
  def judge_parameters_declined
    flag_cases(:parameters_declined, ->(r) { r.parameters_asked? }) do |reading|
      next nil if reading.parameters.present?

      "was offered the parameters block and picked nothing, so #{reading.room} took every default"
    end
  end

  # AND WHAT THE ENGINE COULD NOT HONOUR, read off the ROWS the layout wrote and
  # never off the answer -- the picks have no column, so the building IS the
  # record (`Eval::Realization::Stage::Standing#rooms_laid_out`).
  #
  # TWO NARROWINGS AND NOT A GENERAL COMPARISON, because only two of the picks
  # can fail to arrive: a footprint too small to divide holds fewer rooms than
  # the band asked for, and a storey range is bounded by what the layout built.
  # Danger, gradient and hazard are RATES -- a die decides each room -- so a
  # place that picked `dangerous` and rolled quiet rooms was not narrowed, it was
  # unlucky, and flagging that would be flagging the dice.
  def judge_parameters_the_engine_narrowed
    flag_cases(:parameters_the_engine_narrowed, ->(r) { r.parameters_asked? && r.parameters.present? }) do |reading|
      complaints = []
      wanted = Location::Parameters::ROOMS_A_BAND_PROMISES[reading.parameters["inside"]]
      if wanted && reading.rooms.size < wanted
        complaints << "asked for #{reading.parameters["inside"]} and the footprint held #{reading.rooms.size}"
      end
      asked = Location::Parameters::STOREYS_BELOW[reading.parameters["storeys_below"]]
      if asked && reading.storeys_below < asked
        complaints << "asked for #{reading.parameters["storeys_below"]} and the layout went " \
                      "#{reading.storeys_below} down"
      end

      complaints.presence&.join("; ")
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

  # ---------------------------------------------------------------- the room's own name

  # WHETHER THE ROOM ENDED UP WITH A NAME OF ITS OWN, READ OFF THE ROOM.
  #
  # `Location::RoomName` refuses a proposal on several separate grounds -- blank
  # or cut off, a comma, the name the room already has, another of the place's
  # placeholders, the place's own name inside it, a name this world has already
  # spoken for -- and every one of them ends the same way: the placeholder
  # stays. So this check asks the RECORD what happened rather than re-deciding
  # it here. A checker that re-implemented those rules would be a second
  # implementation of the one thing that owns them, which is the failure this
  # whole file is written against; `#judge_room_name_already_taken` below reports the one reason that
  # is a set comparison, and this reports the outcome.
  #
  # JUDGEABLE ONLY WHERE THE PROMPT ASKED, which is a room of a laid-out place
  # and nothing else (`#asked_for_a_name?`). Every other room in the game
  # already has a name a neighbour or a seed file gave it and is not asked for
  # one, so counting it in would report a rate the check never earned --
  # `Story::Audit#judgeable_for`'s rule, and the same one that keeps a set
  # stored before the ask existed out of this entirely.
  #
  # AND THE FLAG IS THE ROOM AND NOT THE NAME, one per case: a room either came
  # away with a name or kept its number.
  def judge_room_name_refused
    flag_cases(:room_name_refused, ->(r) { r.asked_for_a_name? && r.name_after.present? }) do |reading|
      next nil unless reading.same?(reading.name_after, reading.room)

      "was asked to name itself, proposed #{reading.proposed_name.presence&.inspect || "nothing"}, " \
        "and kept the placeholder #{reading.room.inspect}"
    end
  end

  # A PROPOSED ROOM NAME THE WORLD HAD ALREADY GIVEN OUT, which is the one
  # refusal above that IS a set comparison -- the answer against the closed list
  # of names the world already held (`facts["all_names"]`, the very list
  # `Location::RoomName` refuses on). The rooms of the room's own place are in
  # that list, so "unique within the place" is judged here.
  #
  # THE EVIDENCE SAYS WHETHER THE PROMPT SHOWED IT, exactly as
  # `#judge_name_already_spoken_for` does and for the same reason: a collision
  # with a name the model was never shown is a defect in what
  # `Location::Generator#named_rooms_note` states rather than in the answer, and
  # a reader has to be able to tell the two apart without opening the set.
  #
  # IT READS `Reading#same?` AND NOT `WorldSeed.natural_key`, which is this
  # file's comparison for every other name check and is NARROWER than the
  # engine's -- a leading article is part of a name here and is not part of one
  # there. So a proposal refused only for its article reads clean HERE and still
  # reads flagged in `#judge_room_name_refused`, which is the check that counts
  # every refusal. Stated rather than left to be discovered: the outcome check
  # is the complete one, this one is the diagnosis.
  def judge_room_name_already_taken
    flag_cases(:room_name_already_taken, ->(r) { r.asked_for_a_name? && r.proposed_name.present? }) do |reading|
      # THE ROOM'S OWN PLACEHOLDER IS IN THAT LIST and is not this check's
      # collision: a model that hands the placeholder back has proposed nothing,
      # which is `#judge_room_name_refused`'s flag and reads far better there.
      # It stays in the denominator -- the model did propose a name.
      next nil if reading.same?(reading.proposed_name, reading.room)

      known = reading.facts["all_names"] || {}
      where = %w[people places things].find { |kind| reading.any_named?(known[kind], reading.proposed_name) }
      next nil if where.nil?

      "proposed #{reading.proposed_name.inspect}, which is already a #{where.singularize} in this world" \
        "#{" -- and the prompt never showed it" unless reading.any_named?(reading.names_shown, reading.proposed_name)}"
    end
  end

  # ------------------------------------------------------------ a sheet read for a word

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

  # ---------------------------------------------------- the room's own numbers

  # THE DESCRIPTION AGAINST THE FLOOR PLAN THE PROMPT HANDED IT.
  #
  # WHY THIS EXISTS AT ALL. A room inside a laid-out place is the first thing in
  # this game whose prose can be checked against a NUMBER the app owns: the
  # extent and the storey were decided by `Location::Interior` before anybody
  # typed a line, `Location::Plan` states them in the detail prompt, and the
  # answer either agrees with them or does not. Every other reading of prose
  # this project has tried to ship died for wanting a judgement
  # (`Story::Audit`'s header, and `Story::Scoreboard`'s); this wants a
  # comparison.
  #
  # AND THE WALLS ARE NOT HERE, though the plan states them. Which wall the
  # prose put a door in was a check on this board through six measured grammars,
  # and each of them read a DOORLESS wall named in the same sentence as a door as
  # a door claim of its own -- which is the prose
  # `Location::Plan#closed_walls_clause` invites. It is
  # `Eval::Realization::UNAVAILABLE_TO_A_REALIZATION`'s
  # `door_in_a_wall_the_records_do_not_hold` now, with the reason on it. The
  # prompt is unchanged and still states every door's wall as fact; what no
  # longer exists is the claim to verify that in prose afterwards.
  #
  # WHAT IS AT STAKE IS THE PROSE AND NOT THE MAP, which is why this is not a
  # gate on anything. The doors are `LocationConnection` rows and no answer here
  # can add one -- `Location::Generator#write_exits!` asks a room of an interior
  # for no exits at all -- so a description that invents a door in the south
  # wall cannot move the player through it. What it produces is a room whose
  # prose argues with its own map, every turn, for the rest of the game.
  #
  # JUDGEABLE ONLY WHERE THERE IS A PLAN, and the denominator is the CLAIMS the
  # prose made rather than the cases: a description that states no measurement
  # has broken no rule -- the prompt asks for a room, not for a survey -- so
  # counting it in would report a rate the check never earned.
  # `Story::Audit#judgeable_for`'s rule, kept here.

  # THE SAME COMPARISON FOR THE TWO NUMBERS THE PROMPT STATED. A size is
  # compared UNORDERED, because a room described from the doorway is as honestly
  # four by six as six by four (`Story::Audit::Prose.size_claims`), and a storey
  # is compared as the integer the plan carries.
  #
  # AND THE EVIDENCE QUOTES BOTH SIDES AS THEY WERE WRITTEN, never as the
  # comparison normalised them: the claim in the order the prose put it
  # (`Size#as_written`) and the room in the order the prompt stated it
  # (`Location::Plan#size_sentence` says width by depth, so `#room_extent` does
  # too). A flag has to be legible against the prompt without opening the set --
  # `Story::Scoreboard`'s rule -- and a sorted pair is a pair neither the model
  # nor the records ever wrote.
  #
  # A NUMBER THE PROMPT STATED IS NEVER A DEFECT, and that is the whole rule --
  # stated once here rather than as a discount per sentence somebody remembered.
  # `Location::Plan` hands the model MORE than the room's own box: the place's
  # footprint, the far storey of every stair, and the clause naming storey 0 the
  # ground floor. A claim is a defect only when it contradicts EVERY number of
  # its kind the plan stated, so the comparison is against
  # `Reading#paces_stated` and `Reading#storeys_stated` -- both read off the plan
  # hash, so a sentence added to `Location::Plan` is covered here by
  # construction.
  def judge_size_the_records_do_not_hold
    flag_each(:size_the_records_do_not_hold,
              ->(r) { size_claims(r).size + judgeable_storey_claims(r).size }) do |reading|
      size_claims(reading).reject { |claim| reading.paces_stated.include?(claim.paces) }
                          .map { |claim|
        "said the room is #{claim.as_written.join(" by ")} paces and it is " \
          "#{reading.room_extent.join(" by ")} -- #{claim.sentence.inspect}"
      } + judgeable_storey_claims(reading).reject { |claim| reading.storeys_stated.include?(claim.storey) }
                                          .map do |claim|
        "put the room on storey #{claim.storey} and it is on storey #{reading.planned_storey}" \
          " -- #{claim.sentence.inspect}"
      end
    end
  end

  # A STOREY THE PROMPT STATED OF SOMETHING OTHER THAN THIS ROOM IS UNJUDGEABLE,
  # and it is out of the DENOMINATOR rather than merely unflagged --
  # `#correct_dead_end?`'s doctrine in this same class: a rate the check did not
  # earn is worse than no rate. "Storey 0" cannot be told from an echo of
  # *"storey 0 is the ground floor"*, and "storey 1" on a room whose plan says a
  # stair climbs to storey 1 cannot be told from an echo of that stair's own
  # clause -- in both the passage may be saying something true about a thing
  # that is not this room, and no reading tells which.
  #
  # THE ROOM'S OWN STOREY IS THE EXCEPTION AND STAYS IN, because there the claim
  # was compared with the record it is about and it agreed. A storey the plan
  # names nowhere is judged exactly as it would be without any of this.
  def judgeable_storey_claims(reading)
    echoes = reading.storeys_stated - [ reading.planned_storey ]

    storey_claims(reading).reject { |claim| echoes.include?(claim.storey) }
  end

  # THE TWO GRAMMARS, ASKED ONCE PER READING. A denominator lambda and the
  # block both want them, and reading a passage twice for one figure is how a
  # scorer comes to disagree with itself about what a passage said.
  def size_claims(reading) = claimed(reading, :size_claims)
  def storey_claims(reading) = claimed(reading, :storey_claims)

  # KEYED ON THE PASSAGE ITSELF and not on the case's id: one case is read once
  # per repetition and every repetition is a different description, so an id
  # would hand the second reading the first one's claims.
  #
  # AND ON WHETHER THERE WAS A PLAN, because that is the third input to the
  # answer: an unplanned row's claims are `[]` whatever the passage says. Two
  # rows with the same description and different plan presence would otherwise
  # get each other's answer, and which one won would depend on the order the
  # rows were scored in.
  def claimed(reading, grammar)
    @claimed ||= {}
    @claimed[[ reading.description, grammar, reading.planned? ]] ||=
      reading.planned? ? Story::Audit::Prose.public_send(grammar, reading.description) : []
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
