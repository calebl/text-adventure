require "test_helper"

# EVERY CHECK, AGAINST A ROW BUILT BY HAND.
#
# The scorer never touches a table -- it reads the stored answer against the
# stored facts -- so the whole of it is testable from a literal, which is the
# point of storing the facts beside the answer in the first place. What each
# test pins is the DENOMINATOR as much as the flag: a check that fired on the
# right row and counted the wrong opportunities reports a rate nobody can read.
class Eval::Realization::ScorerTest < ActiveSupport::TestCase
  # A world with three places, one of them written and out of reach, one of them
  # already reachable from the room being built.
  FACTS = {
    "room" => "The Long Hallway",
    "danger" => "safe",
    "danger_share" => 0,
    "expects_new_ground" => true,
    "people_allowance" => 2,
    "item_allowance" => 3,
    "exit_allowance" => 3,
    "slots" => [ { "race" => "Ledger-Kept", "monstrous" => false, "age" => 40, "sex" => "man" },
                 { "race" => "Copyists' Line", "monstrous" => false, "age" => 31, "sex" => "woman" } ],
    "places" => [ { "name" => "Ward Office 12", "realized" => true, "connected" => true },
                  { "name" => "The Supply Closet", "realized" => true, "connected" => false },
                  { "name" => "The Cellar Stair", "realized" => false, "connected" => false } ],
    "reachable" => [ "Ward Office 12" ],
    "reached_from" => "Ward Office 12",
    "taken_names" => [ "Halkett Rowe", "ward stamp" ],
    "all_names" => { "people" => [ "Halkett Rowe" ], "places" => [ "Ward Office 12", "The Supply Closet",
                                                                   "The Cellar Stair", "The Long Hallway" ],
                     "things" => [ "ward stamp" ] },
    "present" => [],
    "monstrous_races" => []
  }.freeze

  test "an exit into a written room this room cannot reach is flagged, and one it can reach is not" do
    scorer = scored(exits: [ "The Supply Closet", "The Cellar Stair" ])

    assert_equal 1, scorer.flagged_for(:exit_into_a_written_room).size
    assert_equal 2, scorer.judgeable_for(:exit_into_a_written_room), "every exit named is an opportunity"
    assert_includes scorer.flagged_for(:exit_into_a_written_room).first.evidence, "The Supply Closet"
    assert_empty scorer.flagged_for(:exit_already_reachable), "The Cellar Stair is a stub nobody can reach yet"
  end

  test "an exit the room can already reach is flagged" do
    scorer = scored(exits: [ "Ward Office 12", "The Cellar Stair" ])

    assert_equal [ "Ward Office 12" ], scorer.flagged_for(:exit_already_reachable).map { |flag|
      flag.evidence[/"(.+?)"/, 1]
    }
    assert_empty scorer.flagged_for(:exit_into_a_written_room),
                 "the office is written AND reachable, which is the way back and not a new door"
  end

  # THE DEAD END THE EXITS PROMPT ASKS FOR. `Location::Generator`'s instructions
  # tell a room whose only way out is the way back to list that place and nothing
  # else, so scoring that answer as a defect would report a rate this check never
  # earned -- it is out of the DENOMINATOR, not merely unflagged.
  test "a dead end that named only the way back is unjudgeable, not clean and not flagged" do
    dead_end = scored(exits: [ "Ward Office 12" ],
                      facts: FACTS.merge("expects_new_ground" => false,
                                         "reached_from" => "Ward Office 12"))

    assert_empty dead_end.flagged_for(:exit_already_reachable)
    assert_equal 0, dead_end.judgeable_for(:exit_already_reachable)
  end

  # THE WAY BACK IS NOT THE SAME AS "ANYWHERE ALREADY REACHABLE" ON A STUB WITH
  # TWO EDGES, and the prompt's sentence is about the first: *if the only way out
  # is back the place the player came from*. A room that answered with its OTHER
  # neighbour did not give that answer, so it stays judged -- gating it out would
  # hide the defect the `two-ways-out` shape exists to reach.
  test "a room that named its other neighbour and nothing else is judged, not gated out" do
    facts = FACTS.merge("expects_new_ground" => false, "reached_from" => "Ward Office 12",
                        "reachable" => [ "Ward Office 12", "The Cellar Stair" ])
    scorer = scored(exits: [ "The Cellar Stair" ], facts: facts)

    assert_equal 1, scorer.flagged_for(:exit_already_reachable).size
    assert_equal 1, scorer.judgeable_for(:exit_already_reachable)
    assert_includes scorer.flagged_for(:exit_already_reachable).first.evidence, "The Cellar Stair"
  end

  # A SET STORED BEFORE THE WAY BACK WAS RECORDED SCORES AS IT SCORED THEN: no
  # `reached_from` key at all falls back to "one exit, and it is already
  # reachable", which is exact for every single-edge case those sets measured.
  test "a stored row with no `reached_from` keeps the older dead-end test" do
    facts = FACTS.except("reached_from").merge("expects_new_ground" => false)
    dead_end = scored(exits: [ "Ward Office 12" ], facts: facts)

    assert_empty dead_end.flagged_for(:exit_already_reachable)
    assert_equal 0, dead_end.judgeable_for(:exit_already_reachable)
  end

  # AN OPENING ROOM HAS NO WAY BACK, so nothing it names can be one and the gate
  # never opens. The key is recorded and empty, which is not the same state as a
  # row that never recorded it at all.
  test "an opening room, which records no way back, is judged like any other room" do
    facts = FACTS.merge("expects_new_ground" => false, "reached_from" => nil)
    scorer = scored(exits: [ "Ward Office 12" ], facts: facts)

    assert_equal 1, scorer.flagged_for(:exit_already_reachable).size
    assert_equal 1, scorer.judgeable_for(:exit_already_reachable)
  end

  test "the dead-end gate does not cover a room that named the way back alongside anything else" do
    pair = scored(exits: [ "Ward Office 12", "The Cellar Stair" ],
                  facts: FACTS.merge("expects_new_ground" => false,
                                     "reached_from" => "Ward Office 12"))

    assert_equal 1, pair.flagged_for(:exit_already_reachable).size
    assert_equal 2, pair.judgeable_for(:exit_already_reachable)
  end

  test "a room the story points onward from is judged on the way back like any other exit" do
    onward = scored(exits: [ "Ward Office 12" ])

    assert_equal 1, onward.flagged_for(:exit_already_reachable).size
    assert_equal 1, onward.judgeable_for(:exit_already_reachable)
  end

  test "an exit that names the room it leads out of is flagged" do
    scorer = scored(exits: [ "the long hallway" ])

    assert_equal 1, scorer.flagged_for(:exit_named_this_room).size, "and the comparison is case-insensitive"
  end

  test "more ways out than the prompt allowed is one flag for the case, not one per exit" do
    scorer = scored(exits: [ "A", "B", "C", "D" ])

    assert_equal 1, scorer.flagged_for(:exit_over_the_allowance).size
    assert_equal 1, scorer.judgeable_for(:exit_over_the_allowance)
    assert_includes scorer.flagged_for(:exit_over_the_allowance).first.evidence, "4 ways out of at most 3"
  end

  # THE CHECK THAT STARTED THIS BENCH. A room the story points into whose every
  # way out was a place the world already had.
  test "a room that opened onto nowhere new is flagged, and only where the case expects new ground" do
    scorer = scored(exits: [ "Ward Office 12", "The Supply Closet" ])
    assert_equal 1, scorer.flagged_for(:no_new_ground).size
    assert_equal 1, scorer.judgeable_for(:no_new_ground)

    dead_end = scored(exits: [ "Ward Office 12" ],
                      facts: FACTS.merge("expects_new_ground" => false, "reached_from" => "Ward Office 12"))
    assert_empty dead_end.flagged_for(:no_new_ground)
    assert_equal 0, dead_end.judgeable_for(:no_new_ground),
                 "a dead end naming the way back is the RIGHT answer, so it is unjudgeable and never clean"
  end

  test "a room that opened onto somewhere new is not flagged" do
    assert_empty scored(exits: [ "Ward Office 12", "The Boiler Landing" ]).flagged_for(:no_new_ground)
  end

  # A ROOM THAT NAMED NOTHING AT ALL IS THE SAME DEFECT, and it must not read as
  # clean: the story points onward and the room opened onto nowhere.
  test "a room the story points into that named no way out at all is flagged" do
    scorer = scored(exits: [])

    assert_equal 1, scorer.flagged_for(:no_new_ground).size
    assert_equal 1, scorer.judgeable_for(:no_new_ground)
    assert_includes scorer.flagged_for(:no_new_ground).first.evidence, "named no way out at all"
  end

  test "more people or things than the prompt allowed is flagged per case" do
    people = scored(people: [ person("A Aa"), person("B Bb"), person("C Cc") ])
    assert_equal 1, people.flagged_for(:person_over_the_allowance).size

    things = scored(items: Array.new(4) { |index| { "name" => "thing #{index}" } })
    assert_equal 1, things.flagged_for(:item_over_the_allowance).size
  end

  # A NAME THE WORLD HAD ALREADY GIVEN TO SOMETHING, and the evidence says
  # whether the prompt had shown it -- because a collision outside the
  # truncation is a defect in `known_names_note` and not in the answer.
  test "a reused name is flagged against every closed set, and says when the prompt never showed it" do
    scorer = scored(people: [ person("Halkett Rowe") ],
                    items: [ { "name" => "The Cellar Stair" } ])

    evidence = scorer.flagged_for(:name_already_spoken_for).map(&:evidence)
    assert_equal 2, evidence.size
    assert_includes evidence.first, "already a person in this world"
    assert_includes evidence.last, "already a place in this world"
    assert_includes evidence.last, "the prompt never showed it",
                    "The Cellar Stair is not in taken_names, which only carries people and things"
  end

  test "what the engine would not admit is read off the records and not off the answer" do
    scorer = scored(people: [ person("Vessa Kirn") ], items: [ { "name" => "a folder" } ],
                    after: { "people" => [], "items" => [ "a folder" ], "exits" => [], "new_places" => [] })

    assert_equal 1, scorer.flagged_for(:proposal_refused).size
    assert_equal 2, scorer.judgeable_for(:proposal_refused), "one person and one thing were proposed"
    assert_includes scorer.flagged_for(:proposal_refused).first.evidence, "Vessa Kirn"
  end

  # A ROOM THAT NAMED ONE PERSON TWICE GOT ONE PERSON. A proposal is a Hash, so
  # `Character::Registry#resolve` -- which matches a non-`Character` on
  # `candidate.to_s` -- never finds the row the first occurrence just wrote; the
  # second goes to `#create_one` and `#creation_refusal` refuses it because a
  # person in this story is already called that. Asking only whether the NAME is
  # in the records would call both admitted and report a room that lost somebody
  # as clean. Each record seats one proposal; the second is the one refused.
  test "a name the answer proposed twice against one record is one refusal, not none" do
    scorer = scored(people: [ person("Vessa Kirn"), person("Vessa Kirn") ],
                    after: { "people" => [ "Vessa Kirn" ], "items" => [], "exits" => [], "new_places" => [] })

    assert_equal 1, scorer.flagged_for(:proposal_refused).size
    assert_equal 2, scorer.judgeable_for(:proposal_refused), "the denominator is every proposal made"
    assert_includes scorer.flagged_for(:proposal_refused).first.evidence, "Vessa Kirn"
  end

  test "a thing the answer proposed twice against one record is one refusal, and the case is ignored" do
    scorer = scored(items: [ { "name" => "a folder" }, { "name" => "A Folder" } ],
                    after: { "people" => [], "items" => [ "a folder" ], "exits" => [], "new_places" => [] })

    assert_equal 1, scorer.flagged_for(:proposal_refused).size
    assert_equal 2, scorer.judgeable_for(:proposal_refused)
  end

  test "two of a name with two records behind them is no refusal at all" do
    scorer = scored(items: [ { "name" => "a folder" }, { "name" => "a folder" } ],
                    after: { "people" => [], "items" => [ "a folder", "a folder" ],
                             "exits" => [], "new_places" => [] })

    assert_empty scorer.flagged_for(:proposal_refused)
    assert_equal 2, scorer.judgeable_for(:proposal_refused)
  end

  # SOMEBODY ALREADY STANDING IN THE STUB IS NOT A SEAT THIS CALL WON. The tide
  # post is seeded with Neb Halloran in it and the staging leaves him there, so
  # an answer that names him is refused by `Character::Registry#creation_refusal`
  # and the room keeps the man it had -- while the records afterwards still
  # carry his name. Counting that as an admission would report the room that
  # lost the person the answer wrote as clean.
  test "a proposal naming somebody already in the room is refused, not seated by the occupant" do
    facts = FACTS.merge("present" => [ "Neb Halloran" ])
    scorer = scored(facts: facts, people: [ person("Neb Halloran") ],
                    after: { "people" => [ "Neb Halloran" ], "items" => [],
                             "exits" => [], "new_places" => [] })

    assert_equal 1, scorer.flagged_for(:proposal_refused).size
    assert_equal 1, scorer.judgeable_for(:proposal_refused)
    assert_includes scorer.flagged_for(:proposal_refused).first.evidence, "Neb Halloran"
  end

  test "an occupant takes one seat and no more, so a person this call really wrote is clean" do
    facts = FACTS.merge("present" => [ "Neb Halloran" ])
    scorer = scored(facts: facts, people: [ person("Vessa Kirn") ],
                    after: { "people" => [ "Neb Halloran", "Vessa Kirn" ], "items" => [],
                             "exits" => [], "new_places" => [] })

    assert_empty scorer.flagged_for(:proposal_refused)
    assert_equal 1, scorer.judgeable_for(:proposal_refused)
  end

  # A SET STORED BEFORE `present` WAS RECORDED SCORES AS IT SCORED THEN. The key
  # is absent from those rows, and a missing one is nobody already there.
  test "a stored row with no `present` at all is scored exactly as before" do
    facts = FACTS.except("present")
    scorer = scored(facts: facts, people: [ person("Vessa Kirn") ],
                    after: { "people" => [ "Vessa Kirn" ], "items" => [],
                             "exits" => [], "new_places" => [] })

    assert_empty scorer.flagged_for(:proposal_refused)
    assert_equal 1, scorer.judgeable_for(:proposal_refused)
  end

  test "a readable thing with nothing written on it is flagged, and judged only on readable things" do
    scorer = scored(items: [ { "name" => "a docket", "readable" => true, "inscription" => "" },
                             { "name" => "a chair leg", "readable" => false } ])

    assert_equal 1, scorer.flagged_for(:readable_without_words).size
    assert_equal 1, scorer.judgeable_for(:readable_without_words)
  end

  # THE ONE KEYWORD CHECK. Judged only on a MONSTROUS slot the model actually
  # filled, which is the only place getting it wrong costs anything.
  test "a person written for a monstrous slot who never says the race is flagged" do
    slots = [ { "race" => "Nocturna-Blighted", "monstrous" => true, "age" => 50, "sex" => "man" },
              { "race" => "Lunar Sovereigns", "monstrous" => false, "age" => 30, "sex" => "woman" } ]
    facts = FACTS.merge("slots" => slots)

    silent = scored(facts: facts, people: [ person("Marek Sollen"), person("Isbet Marrow") ])
    assert_equal 1, silent.flagged_for(:race_not_named).size
    assert_equal 1, silent.judgeable_for(:race_not_named), "only the monstrous slot is an opportunity"

    named = scored(facts: facts,
                   people: [ person("Marek Sollen").merge(
                     "appearance" => "A Nocturna-Blighted in a bellringer's coat, still climbing."
                   ) ])
    assert_empty named.flagged_for(:race_not_named)
  end

  test "a plural race name is matched by its singular in the sheet" do
    facts = FACTS.merge("slots" => [ { "race" => "Goblins", "monstrous" => true, "age" => 20, "sex" => "man" } ])
    scorer = scored(facts: facts,
                    people: [ person("Grask Nine").merge("backstory" => "Grask Nine is a goblin of the Blackfang.") ])

    assert_empty scorer.flagged_for(:race_not_named)
  end

  # THE CHECK ON THE CHECKS. The cheapest way to clear every rate above is to
  # write one exit and nobody, and these are what makes that visible.
  test "the reported counts are what the room actually held" do
    scorer = scored(exits: [ "Ward Office 12", "The Boiler Landing" ],
                    people: [ person("Vessa Kirn") ],
                    items: [ { "name" => "a folder" } ],
                    after: { "people" => [ "Vessa Kirn" ], "items" => [ "a folder" ],
                             "exits" => [], "new_places" => [ "The Boiler Landing" ] })

    assert_equal 1.0, scorer.reported["people_named"]
    assert_equal 2.0, scorer.reported["people_offered"]
    assert_in_delta 0.5, scorer.reported["people_take_up"]
    assert_equal 1.0, scorer.reported["items_named"]
    assert_equal 2.0, scorer.reported["exits_named"]
    assert_equal 1.0, scorer.reported["new_places_opened"]
    assert_equal 1.0, scorer.reported["new_places_named"]
    assert_in_delta 0.5, scorer.reported["exits_restating"], 0.001
  end

  # THE TWO NEW-PLACE FIGURES ARE NOT THE SAME FIGURE, and this is the case that
  # separates them: `Location::Generator#write_exits!` stops connecting when the
  # allowance runs out, so a room that named more places than it had room for
  # OPENED fewer than it NAMED. `new_places_opened` is the record; the other is
  # a reading of the answer, and the board says which is which.
  test "places opened is read off the records and does not follow the answer over the allowance" do
    scorer = scored(exits: [ "A Cistern", "A Boiler Landing", "A Stair Head", "A Coal Chute" ],
                    after: { "people" => [], "items" => [], "exits" => [],
                             "new_places" => [ "A Cistern", "A Boiler Landing", "A Stair Head" ] })

    assert_equal 3.0, scorer.reported["new_places_opened"], "the allowance was three, so three stubs exist"
    assert_equal 4.0, scorer.reported["new_places_named"], "and the answer named four"
  end

  # A FAILED CALL IS NOT A CLEAN ONE. It is out of every denominator, which is
  # what stops a run of refusals reading as a run with nothing wrong with it.
  test "a failed reading is scored on nothing at all" do
    scorer = Eval::Realization::Scorer.new([ row.merge("error" => "BaseAgent::RefusalError: no") ])

    assert_equal 0, scorer.scanned
    assert_empty scorer.flags
    Eval::Realization.checks.each { |code| assert_equal 0, scorer.judgeable_for(code), code }
  end

  # WHY A CALL FAILED IS THE ERROR'S CLASS AND NOT A PREFIX OF ITS MESSAGE.
  # `Eval::Realization::Result.figures_of` counts refusals and crises through
  # these, so a check that matched a prefix would count a differently named
  # error class as a refusal it is not.
  test "a failure is classified by the error class, not by a prefix of the message" do
    readings = Eval::Realization::Scorer.new(
      [ row.merge("error" => "BaseAgent::RefusalError: I can't help with that"),
        row.merge("error" => "BaseAgent::CrisisResponseError: here is a helpline"),
        row.merge("error" => "BaseAgent::RefusalErrorSomethingElse: not the same class"),
        row.merge("error" => "Net::ReadTimeout: gave up"),
        row ]
    ).all_readings

    assert_equal 4, readings.count(&:failed?), "the clean row is not a failure"
    assert_equal 1, readings.count(&:refused?)
    assert_equal 1, readings.count(&:crisis?)
    assert_equal [ "Net::ReadTimeout" ], readings.select(&:failed?).map(&:error_class).last(1)

    figures = Eval::Realization::Result.figures_of(readings.map(&:row))
    assert_equal 4, figures["failures"]
    assert_equal 1, figures["refusals"], "a differently named error class is a failure and not a refusal"
    assert_equal 1, figures["crises"]
  end

  test "a third call is counted as an extra one and two are not" do
    scorer = Eval::Realization::Scorer.new([ row.merge("calls" => 3), row, row.merge("calls" => 1) ])

    assert_equal [ 1, 0, 0 ], scorer.all_readings.map(&:extra_calls)
  end

  # --- the description against the floor plan --------------------------------
  #
  # THE FIRST CHECKS IN THIS FILE THAT READ PROSE RATHER THAN A LIST, and they
  # are judgeable only on a room the engine laid out: the plan is what the
  # detail prompt stated, so the comparison is with a record either way.

  PLAN = {
    "room" => "The Custom House room 3", "place" => "The Custom House", "storey" => 0,
    "place_width" => 14, "place_depth" => 10,
    "width" => 7, "depth" => 6,
    "doors" => [ { "wall" => "north", "to" => "The Custom House room 2" },
                 { "wall" => "west", "to" => "The Custom House room 4" } ],
    "stairs" => [], "other_ways_out" => []
  }.freeze

  test "a door in a wall the plan does not hold is flagged" do
    scorer = planned("A door in the south wall opens onto the quay, and the damp comes in with it.")

    assert_equal 1, scorer.flagged_for(:door_the_records_do_not_hold).size
    assert_includes scorer.flagged_for(:door_the_records_do_not_hold).first.evidence,
                    "put a door in the south wall, and the plan has north and west"
  end

  test "a door in a wall the plan does hold is not flagged, and is still an opportunity" do
    scorer = planned("The door in the north wall is the one they use, and the west wall has another.")

    assert_empty scorer.flagged_for(:door_the_records_do_not_hold)
    assert_equal 2, scorer.judgeable_for(:door_the_records_do_not_hold),
                 "both walls the prose named were compared"
  end

  # A DESCRIPTION THAT SAYS NOTHING ABOUT ITS WALLS HAS BROKEN NO RULE: the
  # prompt asks for a room, not for a measurement, so silence is out of the
  # denominator rather than clean.
  test "a description that names no wall is not judgeable" do
    scorer = planned("Ledgers to the ceiling, and a smell of tar that never leaves the plaster.")

    assert_equal 0, scorer.judgeable_for(:door_the_records_do_not_hold)
    assert_equal 0, scorer.judgeable_for(:size_the_records_do_not_hold)
  end

  # AND A ROOM WITH NO PLAN IS OUT OF BOTH CHECKS ALTOGETHER, which is every
  # room in every flat world -- including a stored set from before a plan was
  # ever recorded.
  test "a room the engine laid out nothing for is judged on neither" do
    scorer = scored(exits: [ "The Cellar Stair" ],
                    people: [], items: [])

    assert_equal 0, scorer.judgeable_for(:door_the_records_do_not_hold)
    assert_equal 0, scorer.judgeable_for(:size_the_records_do_not_hold)
    assert_empty scorer.flags.select { |flag| flag.code == :size_the_records_do_not_hold }
  end

  test "a size that is not the room's is flagged, and the plan's own size is not" do
    assert_equal 1, planned("Seven paces by six, and every one of them cold.")
      .judgeable_for(:size_the_records_do_not_hold)
    assert_empty planned("Seven paces by six, and every one of them cold.")
      .flagged_for(:size_the_records_do_not_hold)

    wrong = planned("A long room, 9 by 4 paces, running back from the door.")
    assert_equal 1, wrong.flagged_for(:size_the_records_do_not_hold).size
    assert_includes wrong.flagged_for(:size_the_records_do_not_hold).first.evidence,
                    "said the room is 4 by 9 paces and it is 6 by 7"
  end

  test "a storey that is not the room's is flagged" do
    wrong = planned("Storey 2 is where the ledgers are kept, and this is it.")

    assert_equal 1, wrong.flagged_for(:size_the_records_do_not_hold).size
    assert_includes wrong.flagged_for(:size_the_records_do_not_hold).first.evidence,
                    "put the room on storey 2 and it is on storey 0"
  end

  test "the storey the plan states is not flagged" do
    assert_empty planned("You are on storey 0 and the water is not far below it.")
      .flagged_for(:size_the_records_do_not_hold)
  end

  # THE PLACE'S OWN FOOTPRINT IS A NUMBER THE PROMPT STATED.
  # `Location::Plan#storey_sentence` says how big the BUILDING is in paces, so
  # prose repeating that pair is repeating a fact it was handed -- compared, and
  # it agreed, so it counts and does not flag.
  test "a pace pair that is the place's footprint agrees rather than flags" do
    echoed = planned("The custom house is fourteen by ten paces of ledgers, and this room is a corner of it.")

    assert_empty echoed.flagged_for(:size_the_records_do_not_hold)
    assert_equal 1, echoed.judgeable_for(:size_the_records_do_not_hold),
                 "the pair was compared with the plan and agreed, so it stays an opportunity"
  end

  # AND A STOREY 0 ON A ROOM THAT IS NOT ON STOREY 0 CANNOT BE TOLD FROM AN ECHO
  # of the plan's closing clause, *"storey 0 is the ground floor"* -- so it is
  # out of the DENOMINATOR and not merely unflagged.
  test "a storey 0 claim on an upper-storey room is unjudgeable, not clean and not flagged" do
    upstairs = planned("Storey 0 is the ground floor, and the stair up from it ends here.",
                       plan: PLAN.merge("storey" => 1))

    assert_empty upstairs.flagged_for(:size_the_records_do_not_hold)
    assert_equal 0, upstairs.judgeable_for(:size_the_records_do_not_hold)
  end

  test "a storey number that is not 0 is judged on an upper-storey room as it always was" do
    upstairs = planned("Everything on storey 3 smells of tar.", plan: PLAN.merge("storey" => 1))

    assert_equal 1, upstairs.judgeable_for(:size_the_records_do_not_hold)
    assert_includes upstairs.flagged_for(:size_the_records_do_not_hold).first.evidence,
                    "put the room on storey 3 and it is on storey 1"
  end

  # AND THE DISCOUNT IS NOT A HOLE IN THE CHECK ON THE GROUND FLOOR: there the
  # claim agrees with the plan, so it is compared and counted.
  test "a storey 0 claim on a ground-floor room is still an opportunity" do
    assert_equal 1, planned("Storey 0 is the ground floor, and you are standing on it.")
      .judgeable_for(:size_the_records_do_not_hold)
  end

  # THE TWO GEOMETRY CHECKS READ WORDS, and the board is told so.
  test "both geometry checks are counted as keyword checks" do
    assert_includes Eval::Realization::Scorer::KEYWORD_CHECKS, :door_the_records_do_not_hold
    assert_includes Eval::Realization::Scorer::KEYWORD_CHECKS, :size_the_records_do_not_hold
  end

  private

  # A ROW OFF AN INTERIOR-ROOM CASE: one call, no exits answer at all, and the
  # floor plan the prompt stated stored beside the description.
  def planned(description, plan: PLAN)
    facts = FACTS.merge("plan" => plan, "room" => plan["room"], "exit_allowance" => 0)
    built = row(facts: facts)
    built["answers"] = { "detail" => { "description" => description, "people" => [], "items" => [] } }
    built["calls"] = 1

    Eval::Realization::Scorer.new([ built ])
  end

  def scored(**overrides) = Eval::Realization::Scorer.new([ row(**overrides) ])

  def row(facts: FACTS, exits: [], people: [], items: [], after: nil)
    { "id" => "a-case", "shape" => "written-neighbour", "story" => "The Unrecorded Hour",
      "facts" => facts,
      "answers" => { "detail" => { "people" => people, "items" => items },
                     "exits" => { "exits" => exits.map { |name| { "name" => name } } } },
      "after" => after || { "people" => people.map { |person| person["fullname"] },
                            "items" => items.map { |item| item["name"] },
                            "exits" => [], "new_places" => [] },
      "seconds" => 1.0, "input_tokens" => 100, "output_tokens" => 20, "calls" => 2,
      "missing_fields" => [], "cap_hits" => [], "error" => nil }
  end

  def person(fullname)
    { "fullname" => fullname, "nickname" => fullname.split.first,
      "appearance" => "Stooped over an armful of folders.", "personality" => "Brisk.",
      "backstory" => "#{fullname} was sent up from filing an hour ago.",
      "likes" => "quiet", "dislikes" => "bells", "fears" => "questions" }
  end
end
