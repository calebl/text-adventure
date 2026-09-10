require "test_helper"

# A SCORED VANTAGE, WRITTEN OUT AS A CORPUS CASE.
#
# THE ASSERTION THAT MATTERS MOST IS THE LAST ONE, and it is
# `Lab::Realization::PromotionTest`'s for the same reason: what this class emits
# is fed back through `Eval::Realization::Corpus`'s own validator AND STAGED. A
# promotion that emitted valid-looking YAML the bench then refused would be a
# promotion nobody could use, and the failure would land on whoever pasted it
# into a checked-in measurement input -- after paying for the baseline it moved.
#
# AND THE `absent` LIST IS UNDER TEST TWICE, because it is the one field this
# promotion has that the other does not: once as text, and once as the surgery
# the staged world really performs. A case promoted without it measures a
# different question from the one he scored (`Lab::Exits`'s header, four bought
# draws).
class Lab::Exits::PromotionTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 9, 9)

  test "the case carries the vantage's own facts, its absent list and its quantifier" do
    vantage = create(:lab_exits_vantage, :with_places_off_the_books, :reached_from_the_quay,
                     :dangerous, :expecting_a_building, name: "Harbour Steps",
                     teaser: "Wet stone steps down to the tide line.")

    case_of(vantage).tap do |row|
      assert_equal "exits-harbour-steps", row["id"]
      assert_equal WORLD, row["story"]
      assert_equal "Harbour Steps", row["room"]
      assert_equal "Wet stone steps down to the tide line.", row["teaser"]
      assert_equal "The Quay", row["reached_from"]
      assert_equal "dangerous", row["danger"]
      assert_equal [ "The Custom House", "The Bonded Cellar" ], row["absent"]
      assert_equal "at least one", row["expects_inside"]
      assert row["expects_new_ground"], "a vantage he typed is somewhere the story points into"
      assert_equal Lab::Exits::Promotion::SHAPE, row["shape"]
    end
  end

  # THE UNIVERSE, THE PREFACE AND THE PLACES THAT ALREADY EXIST ARE NEVER
  # EMITTED -- the line `Eval::Realization::Corpus`'s header draws, and a
  # realization prompt is four fifths world.
  test "no world fact is written into the case" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_no_insides)

    assert_equal %w[id story room teaser danger expects_new_ground expects_inside shape why].sort,
                 case_of(vantage).keys.sort
  end

  # EVERY ONE OF THE FOUR CLOSED QUANTIFIERS TRAVELS, spelled as he chose it.
  # Nothing here maps or re-words a label: the corpus reads the same table
  # (`Lab::Exits::QUANTIFIERS`), so a word added there arrives in a promoted case
  # with no edit either side.
  test "each of the four quantifiers is emitted as the word he chose" do
    Lab::Exits::QUANTIFIER_NAMES.each do |name|
      vantage = create(:lab_exits_vantage, :dangerous, expects_inside_quantifier: name)

      assert_equal name, case_of(vantage)["expects_inside"]
    end
  end

  # A VANTAGE WITH NO QUANTIFIER IS THE ONE PROMOTION WORTH REFUSING IN WORDS.
  # The case would carry no claim either inside check could be judged on, so it
  # would cost a re-baseline and measure nothing this lab was built for.
  test "a vantage with no quantifier emits no label and says what that costs" do
    vantage = create(:lab_exits_vantage, :dangerous)

    assert_not_includes case_of(vantage).keys, "expects_inside"
    assert_includes notes(vantage).join(" "), "declared no quantifier"
    assert_includes notes(vantage).join(" "), "BOTH of the scorer's inside checks"
  end

  # THE POPULATION SET COMES TOO, and it is the one expectation besides the
  # quantifier that may: a vantage-wide subset of a closed list, keyed on nothing
  # a model chose.
  test "the population expectation is carried under the corpus's own key" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_no_insides,
                     :expecting_an_empty_neighbourhood)

    assert_equal %w[nobody], case_of(vantage)["expects_exit_population"]
    assert_includes notes(vantage).join(" "), "nothing scores it yet"
  end

  # AND THE PER-NAME RECORDS DO NOT, WHICH IS THE HALF OF CALL 4 THAT STAYS IN
  # THE LAB. A bench label keyed on a name a model chose is a fact about what one
  # model said one month; 26 of 66 (case, name) pairs in the stored baseline
  # appeared in exactly one of four repetitions.
  test "a typed per-place expectation and a judgement are named in a note and never emitted" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_a_building)
    vantage.judge!("The Rust Market", expects: { "inside" => [ "a few rooms" ] })
    vantage.judge!("Tide Flats", verdict: "bad", aspects: [ "inside_wrong" ])

    row = case_of(vantage)

    assert_equal "at least one", row["expects_inside"]
    assert_not_includes row.keys, "expects_exit_inside"
    assert_not_includes yaml_of(vantage), "Rust Market"
    assert_includes notes(vantage).join(" "), "STAY IN THE LAB"
  end

  # THE ONE FACT THE EMITTER MAY HAVE TO ASK FOR, and the reason is the sharpest
  # in the corpus: `Location::Danger.for_a_new_room` is keyed on the story's id
  # and a staged copy is issued a new one on every load, so a promoted case that
  # left its danger to the roll would move the PROMPT digest between two runs of
  # one tree.
  test "a vantage that left its danger to the roll has its draws read instead" do
    vantage = create(:lab_exits_vantage, :expecting_no_insides)
    2.times { create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage, row: row_at("uneasy")) }

    assert_equal "uneasy", case_of(vantage)["danger"]
    assert_not_includes notes(vantage).join(" "), "CHOOSE A DANGER"
  end

  test "draws that disagree about the danger leave the key commented out and say so" do
    vantage = create(:lab_exits_vantage, :expecting_no_insides)
    create(:lab_exits_sample, vantage: vantage, row: row_at("safe"))
    create(:lab_exits_sample, vantage: vantage, row: row_at("dangerous"))

    assert_nil case_of(vantage)["danger"]
    assert_includes yaml_of(vantage), "# danger:"
    assert_includes notes(vantage).join(" "), "CHOOSE A DANGER"
  end

  # THE MEASURED WARNING. A vantage promoted with nothing off the books re-runs
  # the very draw the lab exists to stop him buying: four bought draws of such a
  # vantage opened zero new places and every pick was discarded.
  test "a vantage with nothing off the books is promoted with the finding beside it" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_no_insides)

    assert_not_includes case_of(vantage).keys, "absent"
    assert_includes notes(vantage).join(" "), "NOTHING IS OFF THE BOOKS"
  end

  # A NAME MAY HOLD A COMMA -- the corpus already stages a world holding
  # `Grenn's Boarding House, Room 3` -- so the list is one line per place and
  # never joined, and the quoting rule is `Lab::CaseYaml#scalar`'s.
  test "an absent place whose name holds a comma survives the round trip as one name" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_no_insides,
                     absent: "The Custom House room 1\nThe Custom House, room 2")

    assert_equal [ "The Custom House room 1", "The Custom House, room 2" ], case_of(vantage)["absent"]
  end

  # THE PROVENANCE, AND IT IS PROVENANCE RATHER THAN A CLAIM: nothing recomputes
  # the figures in a `why` and nothing compares against them. AGENTS.md's rule is
  # that a measured figure lives in a stored set or a test, and these are the
  # answer to *where did this case come from*.
  test "the `why` carries the date, the draws, the rate and the counter-figure" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_a_building)
    create(:lab_exits_sample, :one_building_and_open_ground, :good, vantage: vantage)
    create(:lab_exits_sample, :no_band_picked, vantage: vantage)

    why = case_of(vantage)["why"]

    assert_includes why, "2026-09-09"
    assert_includes why, "Drawn 2 times"
    assert_includes why, "2 of them different answers"
    assert_includes why, "1 of 2"
    assert_includes why, "not established"
    assert_includes why, "3 places named, 1 given an inside, 1 of those reaching"
    assert_includes why, "1 good"
  end

  test "a vantage no draw has answered says so rather than printing a rate" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_a_building)
    create(:lab_exits_sample, :failed, vantage: vantage)

    assert_not_predicate promotion(vantage), :evidenced?
    assert_includes case_of(vantage)["why"], "earned no denominator"
  end

  test "a vantage with a draw behind it is evidenced" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_a_building)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    assert_predicate promotion(vantage), :evidenced?
  end

  # THE ASSERTION THE REST OF THE FILE IS FOR: the emitted text is a case the
  # bench really accepts, really stages, and really performs the absent surgery
  # of.
  test "the emitted case validates and stands its stub up with the absent places gone" do
    vantage = create(:lab_exits_vantage, :with_places_off_the_books, :reached_from_the_quay,
                     :dangerous, :expecting_a_building, name: "Harbour Steps")

    corpus = corpus_of(vantage)

    assert_empty corpus.problems, corpus.problems.inspect
    Eval::Realization::Stage.open(corpus.cases) do |stages|
      standing = stages.fetch("exits-harbour-steps")

      assert_equal "Harbour Steps", standing.location.name
      assert_equal [ "The Quay" ], standing.reachable
      assert_equal WORLD, standing.story.title
      assert_not_includes standing.places.map { |place| place["name"] }, "The Custom House",
                          "the absent list is what gives the model a reason to invent"
      assert_not_includes standing.places.map { |place| place["name"] }, "The Bonded Cellar"
    end
  end

  # AND A CASE WHOSE DANGER IS STILL COMMENTED OUT IS REFUSED BY THE VALIDATOR
  # RATHER THAN BY THIS FILE, which is where that has to be noticed: the emitter
  # never invents a value nobody chose.
  test "a promoted case with no danger is refused by the corpus validator" do
    vantage = create(:lab_exits_vantage, :reached_from_the_quay, :expecting_a_building,
                     name: "Harbour Steps")

    assert_includes corpus_of(vantage).problems.join(" "), "needs a `danger`"
  end

  private

  # THE SWEEP'S OWN WORLD, which is `test/factories/lab_exits_vantages.rb`'s
  # default and the one world in the repository with a building in it.
  WORLD = "The Quay House".freeze

  def promotion(vantage) = Lab::Exits::Promotion.new(vantage, today: TODAY)

  def yaml_of(vantage) = promotion(vantage).to_yaml

  def notes(vantage) = promotion(vantage).notes

  def case_of(vantage) = YAML.safe_load(yaml_of(vantage)).sole

  # THE EMITTED TEXT, READ BACK THROUGH THE CORPUS ITSELF rather than through
  # `YAML.safe_load` -- so what is validated is what a person would have pasted,
  # comments and all.
  def corpus_of(vantage)
    file = Tempfile.new([ "promoted-vantage", ".yml" ])
    file.write("cases:\n#{yaml_of(vantage)}")
    file.close

    Eval::Realization::Corpus.load(file.path)
  end

  def row_at(danger)
    build(:lab_exits_sample, :one_building_and_open_ground).row.deep_merge("facts" => { "danger" => danger })
  end
end
