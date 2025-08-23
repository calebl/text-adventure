require "test_helper"

class UniverseTest < ActiveSupport::TestCase
  def setup
    @universe = build(:universe)
  end

  test "should be valid with valid attributes" do
    assert @universe.valid?
  end

  test "should require physics" do
    @universe.physics = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:physics], "can't be blank"
  end

  test "should require technology" do
    @universe.technology = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:technology], "can't be blank"
  end

  test "should require weapons" do
    @universe.weapons = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:weapons], "can't be blank"
  end

  test "should require races" do
    @universe.races = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:races], "can't be blank"
  end

  test "should require civilizations" do
    @universe.civilizations = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:civilizations], "can't be blank"
  end

  test "should require geographies" do
    @universe.geographies = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:geographies], "can't be blank"
  end

  test "should require history" do
    @universe.history = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:history], "can't be blank"
  end

  test "should require economics" do
    @universe.economics = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:economics], "can't be blank"
  end

  test "should require politics" do
    @universe.politics = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:politics], "can't be blank"
  end

  test "should require religion" do
    @universe.religion = nil
    assert_not @universe.valid?
    assert_includes @universe.errors[:religion], "can't be blank"
  end

  test "should have many stories" do
    @universe.save!
    story = create(:story, universe: @universe, title: "Test Story")
    assert_includes @universe.stories, story
  end
end
