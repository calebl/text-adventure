require "test_helper"

class R06IndependentReviewTest < ActiveSupport::TestCase
  DETAIL = {
    "description" => "Sella works beside a brass token.", "lore" => "An old workshop.",
    "items" => [ { "name" => "brass token", "description" => "A brass disc." } ],
    "people" => [ { "fullname" => "Sella Reed", "nickname" => "Sella", "appearance" => "A patched apron.",
      "personality" => "Patient.", "backstory" => "A lifelong maker.", "likes" => "Work.", "dislikes" => "Waste.", "fears" => "Fire." } ]
  }.freeze
  EXITS = { "exits" => [ { "name" => "Back Lane", "teaser" => "A narrow lane.", "distance" => "adjacent", "travel_method" => "walking" } ] }.freeze

  setup do
    @story = create(:story)
    @location = create(:location, :stub, story: @story, name: "Workshop", population: "a person or two")
  end

  test "sanitized required NPC field poisons the durable detail receipt" do
    malformed = DETAIL.deep_dup
    malformed["people"].first["personality"] = "🙂"
    first = FakeAgent.new(malformed)
    failure = BaseAgent.stub(:new, first) do
      assert_raises(ActiveRecord::RecordInvalid) { Location::Generator.new(@location).realize! }
    end
    assert_includes failure.message, "Personality can't be blank"
    assert_equal "detail_pending", @location.reload.generation_checkpoint.fetch("phase")
    assert_empty @location.characters
    assert_empty @location.items

    corrected = FakeAgent.new(DETAIL, EXITS)
    BaseAgent.stub(:new, corrected) do
      assert_raises(ActiveRecord::RecordInvalid) { Location::Generator.new(Location.find(@location.id)).realize! }
    end
    assert_empty corrected.prompts
    assert_predicate @location.reload, :stub?
  end

  test "a generator whose cast was cached before another receipt ignores the saved slots" do
    waiting = Location::Generator.new(@location)
    old_age = waiting.cast_registry.slots.first.fetch(:age)
    owner = Location::Generator.new(Location.find(@location.id))
    owner.cast_registry.slots.each { |slot| slot[:age] = 99 }
    BaseAgent.stub(:new, FakeAgent.new(DETAIL)) do
      owner.cast_registry.stub(:admit!, ->(*) { raise IOError, "write failed" }) do
        assert_raises(IOError) { owner.realize! }
      end
    end
    assert_equal 99, @location.reload.generation_checkpoint.fetch("slots").first.fetch("age")
    BaseAgent.stub(:new, FakeAgent.new(EXITS)) { waiting.realize! }
    assert_equal old_age, @location.characters.sole.age
    assert_not_equal 99, @location.characters.sole.age
  end
end
