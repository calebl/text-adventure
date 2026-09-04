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
  # --- where it is --------------------------------------------------------

  # An item is in exactly one of THREE places, and that is what makes `take`
  # answerable: `Item#playthrough` is the app's answer to "does the player have
  # it", `Item#character` is what one of the world's own people is holding, and
  # `Item#location` is what puts it on the floor to be picked up.

  test "an item lying in a location is valid and takeable" do
    room = create(:location, story: @story)
    item = build(:item, :lying, location: room)

    assert_predicate item, :valid?
    assert_predicate item, :lying?
    assert_not_predicate item, :held?
  end

  test "an item a party is carrying is valid, and is neither held nor lying" do
    playthrough = create(:playthrough, story: @story)
    item = build(:item, :carried, playthrough: playthrough)

    assert_predicate item, :valid?
    assert_predicate item, :carried?
    assert_not_predicate item, :held?
    assert_not_predicate item, :lying?
  end

  test "an item in nobody's hands and nowhere at all is not a state the world has" do
    item = build(:item, character: nil, location: nil)

    assert_not_predicate item, :valid?
    assert_includes item.errors[:base],
                    "must be lying in a location, held by a character or carried by a playthrough"
  end

  # Two at once would be an item that is takeable and already taken.
  test "an item cannot be held and lying somewhere at the same time" do
    room = create(:location, story: @story)
    item = build(:item, character: @character, location: room)

    assert_not_predicate item, :valid?
    assert_includes item.errors[:base], "is in 2 places at once (character_id, location_id); it may only be in one"
  end

  test "an item cannot be carried by a party and lying in a room at the same time" do
    room = create(:location, story: @story)
    item = build(:item, :carried, playthrough: create(:playthrough, story: @story), location: room)

    assert_not_predicate item, :valid?
    assert_includes item.errors[:base], "is in 2 places at once (location_id, playthrough_id); it may only be in one"
  end

  # THE STATE THE OLD SHARED INVENTORY PRODUCED, refused now: a thing cannot be
  # the story's starting inventory and in one player's hands at the same time.
  test "an item cannot be held by a character and carried by a party at once" do
    item = build(:item, character: @character, playthrough: create(:playthrough, story: @story))

    assert_not_predicate item, :valid?
    assert_includes item.errors[:base], "is in 2 places at once (character_id, playthrough_id); it may only be in one"
  end

  test "lying_in offers only what is on the floor of that room" do
    room = create(:location, story: @story)
    elsewhere = create(:location, story: @story)
    on_the_floor = create(:item, :lying, location: room, name: "Brass Key")
    create(:item, :lying, location: elsewhere, name: "Iron Ledger")
    create(:item, character: @character, name: "Vilya")

    assert_equal [ on_the_floor ], Item.lying_in(room).to_a
  end

  test "held is every item in anybody's hands" do
    room = create(:location, story: @story)
    create(:item, :lying, location: room)
    carried = create(:item, character: @character)

    assert_equal [ carried ], Item.held.to_a
  end

  test "carried_by offers only what that one party holds" do
    playthrough = create(:playthrough, story: @story)
    other = create(:playthrough, story: @story)
    mine = create(:item, :carried, playthrough: playthrough, name: "Brass Key")
    create(:item, :carried, playthrough: other, name: "Iron Ledger")
    create(:item, character: @character, name: "Vilya")

    assert_equal [ mine ], Item.carried_by(playthrough).to_a
    assert_equal [ mine ], playthrough.carried.to_a
  end

  # THERE IS NO `items.story_id` -- an item is reached through whoever has it --
  # so a leg missing from this query is an item the registry caps cannot see.
  test "in_story finds an item on all three sides of the one-place rule" do
    room = create(:location, story: @story)
    playthrough = create(:playthrough, story: @story)
    held = create(:item, character: @character, name: "Vilya")
    lying = create(:item, :lying, location: room, name: "Brass Key")
    carried = create(:item, :carried, playthrough: playthrough, name: "Iron Ledger")

    elsewhere = create(:story)
    create(:item, character: create(:character, story: elsewhere), name: "Narya")

    assert_equal [ held, lying, carried ].map(&:id).sort, Item.in_story(@story).pluck(:id).sort
  end

  test "whereabouts says where it is in one sentence" do
    room = create(:location, story: @story, name: "Ward Office 12")
    playthrough = create(:playthrough, story: @story)

    assert_equal "held by #{@character.fullname}", create(:item, character: @character).whereabouts
    assert_equal "lying in Ward Office 12", create(:item, :lying, location: room).whereabouts
    assert_equal "carried by playthrough ##{playthrough.id}",
                 create(:item, :carried, playthrough: playthrough).whereabouts
  end

  # A PLAYTHROUGH'S ITEMS ARE THAT PLAYER'S PROGRESS, like their chats, so they
  # go with it. Putting them down instead would leave a shared world littered
  # with one starting-inventory copy per deleted game.
  test "what a party was carrying goes when the playthrough does" do
    playthrough = create(:playthrough, story: @story)
    item = create(:item, :carried, playthrough: playthrough)

    assert_difference -> { Item.count }, -1 do
      playthrough.destroy!
    end
    assert_not Item.exists?(item.id)
  end

  # Picking something up is the app moving one row, and the row has to end up in
  # exactly one place.
  test "taking an item off the floor empties its location" do
    room = create(:location, story: @story)
    item = create(:item, :lying, location: room)

    item.update!(character: @character, location: nil)

    assert_predicate item.reload, :held?
    assert_nil item.location_id
  end

  test "an item lying in a location goes when the location does" do
    room = create(:location, story: @story)
    create(:item, :lying, location: room)

    assert_difference "Item.count", -1 do
      room.destroy!
    end
  end
end
