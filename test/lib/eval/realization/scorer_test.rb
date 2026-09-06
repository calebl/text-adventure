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

    dead_end = scored(exits: [ "Ward Office 12" ], facts: FACTS.merge("expects_new_ground" => false))
    assert_empty dead_end.flagged_for(:no_new_ground)
    assert_equal 0, dead_end.judgeable_for(:no_new_ground),
                 "a dead end naming the way back is the RIGHT answer, so it is unjudgeable and never clean"
  end

  test "a room that opened onto somewhere new is not flagged" do
    assert_empty scored(exits: [ "Ward Office 12", "The Boiler Landing" ]).flagged_for(:no_new_ground)
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
                    items: [ { "name" => "a folder" } ])

    assert_equal 1.0, scorer.reported["people_named"]
    assert_equal 2.0, scorer.reported["people_offered"]
    assert_in_delta 0.5, scorer.reported["people_take_up"]
    assert_equal 1.0, scorer.reported["items_named"]
    assert_equal 2.0, scorer.reported["exits_named"]
    assert_equal 1.0, scorer.reported["new_places_opened"]
    assert_in_delta 0.5, scorer.reported["exits_restating"], 0.001
  end

  # A FAILED CALL IS NOT A CLEAN ONE. It is out of every denominator, which is
  # what stops a run of refusals reading as a run with nothing wrong with it.
  test "a failed reading is scored on nothing at all" do
    scorer = Eval::Realization::Scorer.new([ row.merge("error" => "BaseAgent::RefusalError: no") ])

    assert_equal 0, scorer.scanned
    assert_empty scorer.flags
    Eval::Realization.checks.each { |code| assert_equal 0, scorer.judgeable_for(code), code }
  end

  private

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
