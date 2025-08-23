require "test_helper"

class ItemTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @character = create(:character, :elrond, story: @story)
    @item = build(:item, :vilya, character: @character)
  end

  test "should be valid with valid attributes" do
    assert @item.valid?
  end

  test "should require name" do
    @item.name = nil
    assert_not @item.valid?
    assert_includes @item.errors[:name], "can't be blank"
  end

  test "should require description" do
    @item.description = nil
    assert_not @item.valid?
    assert_includes @item.errors[:description], "can't be blank"
  end

  test "should belong to character" do
    assert_equal @character, @item.character
  end

  test "should parse properties hash" do
    @item.save!
    properties = @item.properties_hash

    assert_equal "preservation", properties["power"]
    assert_equal "gold", properties["material"]
    assert_equal "sapphire", properties["gem"]
    assert_equal true, properties["magical"]
  end

  test "should set properties hash" do
    @item.properties_hash = {
      "damage" => 15,
      "material" => "steel",
      "enchanted" => true
    }

    expected_json = '{"damage":15,"material":"steel","enchanted":true}'
    assert_equal expected_json, @item.properties
  end

  test "should add property" do
    @item.save!
    @item.add_property("cursed", false)

    properties = @item.properties_hash
    assert_equal false, properties["cursed"]
  end

  test "should get property" do
    @item.save!
    assert_equal "preservation", @item.get_property("power")
    assert_nil @item.get_property("nonexistent")
  end

  test "should check if has property" do
    @item.save!
    assert @item.has_property?("power")
    assert_not @item.has_property?("nonexistent")
  end

  test "should handle empty properties" do
    @item.properties = nil
    assert_equal({}, @item.properties_hash)

    @item.properties = ""
    assert_equal({}, @item.properties_hash)
  end

  test "should scope for character" do
    @item.save!

    other_character = create(:character, story: @story, fullname: "Gandalf")
    other_item = create(:item, character: other_character, name: "Staff")

    character_items = Item.for_character(@character)
    assert_includes character_items, @item
    assert_not_includes character_items, other_item
  end

  test "should scope by name" do
    @item.save!

    similar_item = create(:item,
      character: @character,
      name: "Vilya",
      description: "Another ring of the same name"
    )

    different_item = create(:item,
      character: @character,
      name: "Narya",
      description: "A different ring"
    )

    vilya_items = Item.by_name("Vilya")
    assert_includes vilya_items, @item
    assert_includes vilya_items, similar_item
    assert_not_includes vilya_items, different_item
  end
end
