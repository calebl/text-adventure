require "test_helper"

class Lab::Realization::KindTest < ActiveSupport::TestCase
  test "a kind names a world the lab has a file for" do
    kind = build(:lab_realization_kind, world: "The Drowned Compact")

    assert_not kind.valid?
    assert_match(/not a world the lab has a file for/, kind.errors[:world].to_sentence)
  end

  test "every world the bench builds rooms in is a world a kind may name" do
    Eval::Realization::STORIES.each do |world|
      assert build(:lab_realization_kind, world: world).valid?, "#{world} should be nameable"
      assert Eval::Realization.world_file(world), "#{world} should have a file"
    end
  end

  # THE THREE FACTS ARE HELD TO THE SAME CLOSED LISTS THE MODEL PICKS FROM. A
  # band the table has no footprint for would give the stub an extent nobody can
  # build in.
  test "a kind refuses a band, a population word and a danger the tables do not hold" do
    assert_not build(:lab_realization_kind, inside: "a whole city").valid?
    assert_not build(:lab_realization_kind, population: "teeming").valid?
    assert_not build(:lab_realization_kind, danger: "peckish").valid?

    assert build(:lab_realization_kind, inside: "a warren of rooms").valid?
    assert build(:lab_realization_kind, population: "a crowd").valid?
    assert build(:lab_realization_kind, danger: "dangerous").valid?
  end

  # `deadly` IS THE ONE THAT MATTERS OF THE THREE, and it is worth its own
  # assertion: it is a real `Location::DANGERS` key, so the kind ACCEPTS it as a
  # fact about the stub, and `Location::Parameters::DANGER` deliberately does not
  # offer it -- so an expectation may never name it.
  test "deadly is a danger a kind may declare and never one it may expect" do
    assert build(:lab_realization_kind, danger: "deadly").valid?

    kind = build(:lab_realization_kind, expects_danger: "deadly")

    assert_not kind.valid?
    assert_match(/not on the list the model picks from/, kind.errors[:expects_danger].to_sentence)
  end

  test "an expectation may only name a label the model is offered" do
    kind = build(:lab_realization_kind, expects_hazard: "flooded, on fire")

    assert_not kind.valid?
    assert_match(/"on fire"/, kind.errors[:expects_hazard].to_sentence)
  end

  # *DON'T CARE* IS THE DEFAULT AND IT HAS TO BE TELLABLE FROM AN EMPTY SET, or a
  # kind he emptied would read as one that allows nothing and every sample of it
  # would be a miss.
  test "a pick with nothing declared is out of the figures entirely" do
    kind = create(:lab_realization_kind)

    assert_nil kind.expects(Lab::Realization.pick("hazard"))
    assert_empty kind.declared
    assert_not kind.expectation?

    kind.declare(Lab::Realization.pick("hazard"), [])
    kind.save!

    assert_nil kind.reload.expects(Lab::Realization.pick("hazard"))
  end

  test "declaring a pick stores the labels and reads them back as a set" do
    kind = create(:lab_realization_kind)
    kind.declare(Lab::Realization.pick("storeys_below"), [ "a cellar", "deep", "a cellar" ])
    kind.save!

    assert_equal [ "a cellar", "deep" ], kind.reload.expects(Lab::Realization.pick("storeys_below"))
    assert_equal [ "storeys_below" ], kind.declared.map(&:name)
  end

  test "the declared picks come back in the pick tables own order" do
    kind = create(:lab_realization_kind,
                  expects_inside: Location::Parameters::NO_INSIDE,
                  expects_danger: "uneasy")

    assert_equal %w[danger inside], kind.declared.map(&:name)
  end

  # WHETHER A PICK CAN EVER BE ANSWERED IS NOT WHETHER HE DECLARED IT, and the
  # two calls are on opposite sides of it: a building is offered the parameters
  # block and makes no exits call, and a room is the mirror image.
  test "a room can answer the exit picks and a building can answer the parameter picks" do
    room = build(:lab_realization_kind)
    building = build(:lab_realization_kind, :a_building)

    assert_not room.place?
    assert room.answerable?(Lab::Realization.pick("inside"))
    assert_not room.answerable?(Lab::Realization.pick("hazard"))

    assert building.place?
    assert_not building.answerable?(Lab::Realization.pick("inside"))
    assert building.answerable?(Lab::Realization.pick("hazard"))
  end

  test "a kind reports the expectations nothing will ever answer" do
    kind = create(:lab_realization_kind, :a_building, :expecting_a_cellar, :expecting_no_insides)

    assert_equal [ "inside" ], kind.unanswerable.map(&:name)
  end

  test "deleting a kind takes its samples with it" do
    kind = create(:lab_realization_kind)
    create(:lab_realization_sample, :a_room, kind: kind)

    assert_difference -> { Lab::Realization::Sample.count }, -1 do
      kind.destroy!
    end
  end
end
