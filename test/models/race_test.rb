require "test_helper"

class RaceTest < ActiveSupport::TestCase
  def setup
    @race = build(:race)
  end

  test "should be valid with valid attributes" do
    assert @race.valid?
  end

  test "should require a name" do
    @race.name = nil
    assert_not @race.valid?
    assert_includes @race.errors[:name], "can't be blank"
  end

  test "should require a description" do
    @race.description = nil
    assert_not @race.valid?
    assert_includes @race.errors[:description], "can't be blank"
  end

  test "should belong to a universe" do
    @race.universe = nil
    assert_not @race.valid?
    assert_includes @race.errors[:universe], "must exist"
  end

  test "should require a name unique within its universe" do
    existing = create(:race, name: "Tidewalker")
    duplicate = build(:race, universe: existing.universe, name: "Tidewalker")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "should treat names as case insensitive within a universe" do
    existing = create(:race, name: "Tidewalker")
    duplicate = build(:race, universe: existing.universe, name: "tidewalker")

    assert_not duplicate.valid?
  end

  test "should allow the same name in a different universe" do
    create(:race, name: "Tidewalker")

    assert build(:race, universe: create(:universe), name: "Tidewalker").valid?
  end

  # ------------------------------------------------------------------------
  # THE MONSTROUS HALF OF A UNIVERSE'S OWN RACE LIST.

  test "a race is a people unless a world says otherwise" do
    assert_not build(:race).monstrous?
    assert_predicate build(:race, :monstrous), :monstrous?
  end

  test "the two pools are the whole race list and never overlap" do
    universe = create(:universe)
    universe.races.destroy_all
    people = create(:race, universe: universe, name: "Ledger-Kept")
    monster = create(:race, :monstrous, universe: universe, name: "Chime-Rot")

    assert_equal [ monster ], universe.races.monstrous.to_a
    assert_equal [ people ], universe.races.peoples.to_a
    assert_equal universe.races.order(:id).to_a, (universe.races.peoples + universe.races.monstrous).sort_by(&:id)
  end

  test "should have many characters" do
    assert_respond_to @race, :characters
  end

  # Destroying a race out from under a character would leave it invalid, so the
  # association refuses rather than cascading.
  test "should refuse to be destroyed while characters reference it" do
    character = create(:character)
    race = character.race

    assert_not race.destroy
    assert_includes race.errors[:base], "Cannot delete record because dependent characters exist"
  end
end
