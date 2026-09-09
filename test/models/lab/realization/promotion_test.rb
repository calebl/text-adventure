require "test_helper"

# A SCORED KIND, WRITTEN OUT AS A CORPUS CASE.
#
# THE ASSERTION THAT MATTERS MOST IS THE LAST ONE: what this class emits is fed
# back through `Eval::Realization::Corpus`'s own validator and STAGED. A promotion
# that emitted valid-looking YAML the bench then refused would be a promotion
# nobody could use, and the failure would land on whoever pasted it into a
# checked-in measurement input.
class Lab::Realization::PromotionTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 9, 8)

  test "the case carries the stub's own facts and nothing of the world's" do
    kind = create(:lab_realization_kind, :a_building, :dangerous, :crowded,
                  name: "The Drowned Counting House", world: WORLD,
                  teaser: "A counting house half-sunk at the river's edge.",
                  reached_from: "The Quay")

    case_of(kind).tap do |row|
      assert_equal "lab-the-drowned-counting-house", row["id"]
      assert_equal WORLD, row["story"]
      assert_equal "The Drowned Counting House", row["room"]
      assert_equal "A counting house half-sunk at the river's edge.", row["teaser"]
      assert_equal "The Quay", row["reached_from"]
      assert_equal "a few rooms", row["inside"]
      assert_equal "a crowd", row["population"]
      assert_equal "dangerous", row["danger"]
      assert row["expects_new_ground"], "a kind he typed is somewhere the story points into"
      assert_equal Lab::Realization::Promotion::SHAPE, row["shape"]
    end
  end

  # THE UNIVERSE, THE PREFACE AND THE PLACES THAT ALREADY EXIST ARE NEVER
  # EMITTED, which is the line `Eval::Realization::Corpus`'s header draws: a
  # realization prompt is four fifths world, and a case that hand-wrote its share
  # of it would drift from the app the first time a line was added to either.
  test "no world fact is written into the case" do
    kind = create(:lab_realization_kind, :dangerous, world: WORLD)

    assert_equal %w[id story room teaser danger expects_new_ground shape why].sort,
                 case_of(kind).keys.sort
  end

  test "his expectation is carried across, as a set per pick and a floor for the danger" do
    kind = create(:lab_realization_kind, :a_building, :dangerous, world: WORLD)
    kind.declare("hazard", %w[flooded])
    kind.declare("storeys_below", [ "a cellar", "deep" ])
    kind.declare("danger", %w[uneasy dangerous])
    kind.save!

    row = case_of(kind)

    assert_equal %w[flooded], row["expects_hazard"]
    assert_equal [ "a cellar", "deep" ], row["expects_storeys_below"]
    assert_equal "uneasy", row[Eval::Realization::Corpus::DANGER_FLOOR_KEY],
                 "the floor is the quietest rung he allowed, which is what `uneasy or worse` means"
  end

  # A PICK THE CALL NEVER OFFERS IS LEFT OUT AND NAMED IN WORDS. The five
  # parameter picks are offered only to a building and the two exit picks only
  # where an exits call is made, so a kind can carry an expectation nothing will
  # ever answer -- and a key emitted for one would be a rate that could never be
  # earned rather than a typo anybody could see.
  test "an expectation the call can never answer is left out of the case and said in a note" do
    kind = create(:lab_realization_kind, :a_building, :dangerous, :expecting_no_insides, world: WORLD)

    assert_not_includes case_of(kind).keys, "expects_exit_inside"
    assert_includes notes(kind).join(" "), "expects_exit_inside"
  end

  # THE CORPUS'S OWN HAND LABEL IS NOT THE LAB'S PICK, and confusing the two is
  # the trap `Lab::Realization::Pick`'s header names by name: the label is about
  # whether the world AROUND this stub plainly holds a building; the pick is the
  # band the model chose for each place it named as an exit.
  test "the corpus's `expects_inside` hand label is never emitted from the inside pick" do
    kind = create(:lab_realization_kind, world: WORLD)
    kind.declare("inside", [ "a few rooms" ])
    kind.save!

    row = case_of(kind)

    assert_equal [ "a few rooms" ], row["expects_exit_inside"]
    assert_not_includes row.keys, "expects_inside"
  end

  # THE ONE FACT THE EMITTER MAY HAVE TO ASK FOR. `Location::Danger.for_a_new_room`
  # is keyed on the story's id and a staged copy is issued a new one on every
  # load, so a promoted case that left its danger to the roll would move the
  # prompt digest between two runs of one tree.
  test "a kind that left its danger to the roll has its samples read instead" do
    kind = create(:lab_realization_kind, world: WORLD)
    2.times { create(:lab_realization_sample, :a_room, kind: kind, row: row_drawn_at("uneasy")) }

    assert_equal "uneasy", case_of(kind)["danger"]
    assert_empty notes(kind)
  end

  test "samples that disagree about the danger leave the key commented out and say so" do
    kind = create(:lab_realization_kind, world: WORLD)
    create(:lab_realization_sample, :a_room, kind: kind, row: row_drawn_at("safe"))
    create(:lab_realization_sample, :a_room, kind: kind, row: row_drawn_at("dangerous"))

    assert_nil case_of(kind)["danger"]
    assert_includes yaml_of(kind), "# danger:"
    assert_includes notes(kind).join(" "), "CHOOSE A DANGER"
  end

  test "a danger floor that widens a set with a hole in it says that it widened it" do
    kind = create(:lab_realization_kind, :a_building, :dangerous, world: WORLD)
    kind.declare("danger", [ Location::SAFE, "dangerous" ])
    kind.save!

    assert_equal Location::SAFE, case_of(kind)[Eval::Realization::Corpus::DANGER_FLOOR_KEY]
    assert_includes notes(kind).join(" "), "WIDENS"
  end

  # THE PROVENANCE, AND IT IS PROVENANCE RATHER THAN A CLAIM: nothing recomputes
  # the figures in a `why` and nothing compares against them. Call 5 is the other
  # half -- his prose verdict is in the tally and never becomes a check.
  test "the `why` carries the date, the draw count and the rate" do
    kind = create(:lab_realization_kind, :a_building, :dangerous, world: WORLD)
    kind.declare("hazard", %w[flooded])
    kind.save!
    2.times { create(:lab_realization_sample, :a_building, kind: kind) }
    create(:lab_realization_sample, :a_building, :good, kind: kind)

    why = case_of(kind)["why"]

    assert_includes why, "2026-09-08"
    assert_includes why, "Drawn 3 times"
    assert_includes why, "3 of 3"
    assert_includes why, "not established"
    assert_includes why, "1 good"
  end

  test "a kind with no expectation says it has no hit rate rather than printing a nought" do
    kind = create(:lab_realization_kind, world: WORLD)

    assert_includes case_of(kind)["why"], "No expectation was declared"
  end

  # THE ASSERTION THE REST OF THE FILE IS FOR: the emitted text is a case the
  # bench really accepts and really stages.
  test "the emitted case validates and stands its stub up in the world it names" do
    kind = create(:lab_realization_kind, :a_building, :dangerous, world: WORLD,
                  name: "The Drowned Counting House", reached_from: "The Quay")
    kind.declare("hazard", %w[flooded])
    kind.save!

    corpus = corpus_of(kind)

    assert_empty corpus.problems, corpus.problems.inspect
    Eval::Realization::Stage.open(corpus.cases) do |stages|
      standing = stages.fetch("lab-the-drowned-counting-house")

      assert_equal "The Drowned Counting House", standing.location.name
      assert_equal [ "The Quay" ], standing.reachable
      assert_equal WORLD, standing.story.title
    end
  end

  private

  # THE SWEEP'S OWN WORLD, which is `test/factories/lab_realization_kinds.rb`'s
  # default and the smallest of the five the bench builds rooms in.
  WORLD = "The Quay House".freeze

  def promotion(kind) = Lab::Realization::Promotion.new(kind, today: TODAY)

  def yaml_of(kind) = promotion(kind).to_yaml

  def notes(kind) = promotion(kind).notes

  def case_of(kind) = YAML.safe_load(yaml_of(kind)).sole

  # THE EMITTED TEXT, READ BACK THROUGH THE CORPUS ITSELF rather than through
  # `YAML.safe_load` -- so what is validated is what a person would have pasted,
  # comments and all.
  def corpus_of(kind)
    file = Tempfile.new([ "promoted", ".yml" ])
    file.write("cases:\n#{yaml_of(kind)}")
    file.close

    Eval::Realization::Corpus.load(file.path)
  end

  def row_drawn_at(danger)
    build(:lab_realization_sample, :a_room).row.deep_merge("facts" => { "danger" => danger })
  end
end
