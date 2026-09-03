require "test_helper"

# The one thing in the app that creates an `Item`, tested on the answers a
# model really gives it: the ordinary one, the empty one, and every one of the
# collisions it exists to refuse.
#
# Nothing here calls a model. `admit!` is handed the array a realization call
# came back with, which is the whole of its input.
class Item::RegistryTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story, name: "Ward Office 12")
  end

  def admit(*candidates, location: @room)
    Item::Registry.new(location).admit!(candidates)
  end

  def candidate(name, description: "Something a person could carry.")
    { "name" => name, "description" => description }
  end

  test "writes a row lying in the room for each thing named" do
    created = admit(candidate("ward stamp"), candidate("blank ward form"))

    assert_equal [ "ward stamp", "blank ward form" ], created.map(&:name)
    assert created.all?(&:lying?), "an item the registry writes is on the floor, not in anybody's hands"
    assert_equal [ @room ], created.map(&:location).uniq
  end

  # WHOLE, NOT STUBBED. An item is a name and one line riding on a call already
  # being made; there is no second realization for it to wait on, so a row this
  # writes is complete and valid the moment it exists.
  test "the row it writes is complete" do
    item = admit(candidate("ward stamp", description: "Her own ward stamp, the ink still wet.")).sole

    assert item.persisted?
    assert item.valid?
    assert_equal "Her own ward stamp, the ink still wet.", item.description
  end

  # An empty list and an absent one both mean the same thing, and a room
  # containing nothing is the ordinary case. See Location::DetailSchema.
  test "an empty answer furnishes nothing and raises nothing" do
    assert_empty Item::Registry.new(@room).admit!([])
    assert_empty Item::Registry.new(@room).admit!(nil)
    assert_equal 0, @room.items.count
  end

  test "strips emoji out of what the model wrote" do
    item = admit(candidate("ward stamp 🖋", description: "Still wet. ✨")).sole

    assert_equal "ward stamp", item.name
    assert_equal "Still wet.", item.description
  end

  test "refuses a thing with no name and a thing with no description" do
    created = admit(candidate("", description: "Something."), candidate("a thing", description: ""))

    assert_empty created
    assert_equal 0, @room.items.count
  end

  # THE ROOM'S CAP IS ON THE ROOM, not on one answer -- the same distinction
  # Location::ExitsSchema::MAX_EXITS documents. A seeded room can arrive at it
  # before anybody walks in.
  test "stops at what the room may hold, counting what is already lying there" do
    create(:item, :lying, location: @room, name: "seeded ledger")
    create(:item, :lying, location: @room, name: "seeded key")

    created = admit(candidate("first"), candidate("second"), candidate("third"))

    assert_equal [ "first" ], created.map(&:name)
    assert_equal Item::Registry::MAX_PER_ROOM, Item.lying_in(@room).count
  end

  test "furnishes nothing at all into a room already at its cap" do
    Item::Registry::MAX_PER_ROOM.times { |n| create(:item, :lying, location: @room, name: "seeded #{n}") }

    assert_empty admit(candidate("one more"))
    assert_equal 0, Item::Registry.new(@room).room_for_items
  end

  # THE WORLD'S CAP is the one that bounds the ontology: three per room is
  # three times however far the player walked, so the per-room cap alone bounds
  # nothing.
  test "stops at what the world may hold, across every room and every pair of hands" do
    filler = create(:location, story: @story, name: "The Long Corridor")
    holder = create(:character, story: @story)
    (Item::Registry::MAX_PER_STORY - 1).times do |n|
      n.even? ? create(:item, :lying, location: filler, name: "world item #{n}") : create(:item, character: holder, name: "world item #{n}")
    end

    created = admit(candidate("the last one"), candidate("one past the last"))

    assert_equal [ "the last one" ], created.map(&:name)
    assert_equal Item::Registry::MAX_PER_STORY, Item::Registry.new(@room).story_items.count
  end

  test "counts items held by people in this story against the world cap" do
    holder = create(:character, story: @story)
    create(:item, character: holder, name: "carried thing")

    assert_equal Item::Registry::MAX_PER_STORY - 1, Item::Registry.new(@room).world_for_items
  end

  test "refuses a name this call already used" do
    created = admit(candidate("ward stamp"), candidate("Ward Stamp"))

    assert_equal [ "ward stamp" ], created.map(&:name)
  end

  # The classifier resolves a take or a drop by name, so two things in one
  # world answering to one name is an ordering accident the player cannot see.
  test "refuses a name something in this story already has, wherever it is" do
    elsewhere = create(:location, story: @story, name: "The Supply Closet")
    create(:item, :lying, location: elsewhere, name: "ward stamp")
    holder = create(:character, story: @story, fullname: "Perrin Vaile")
    create(:item, character: holder, name: "brass key")

    assert_empty admit(candidate("Ward Stamp"), candidate("brass key"))
  end

  # An item and a person, or an item and an exit, answering to one word makes
  # two of the classifier's closed sets collide.
  test "refuses a name a person in this story is called" do
    create(:character, story: @story, fullname: "Perrin Vaile", nickname: "the clerk")

    assert_empty admit(candidate("Perrin Vaile"), candidate("the clerk"))
  end

  test "refuses a name a place in this story is called" do
    create(:location, :stub, story: @story, name: "The Supply Closet")

    assert_empty admit(candidate("the supply closet"))
  end

  # Another story's names are somebody else's problem: the closed sets are all
  # scoped to one world.
  test "a name used in another story is not a collision" do
    other = create(:story)
    create(:character, story: other, fullname: "Perrin Vaile")
    elsewhere = create(:location, :stub, story: other, name: "The Supply Closet")
    create(:item, :lying, location: elsewhere, name: "ward stamp")

    assert_equal 3, admit(candidate("Perrin Vaile"), candidate("The Supply Closet"), candidate("ward stamp")).size
  end

  # A refusal costs the room its furniture and nothing else -- the caller has
  # already paid for and saved the description this rode in on.
  test "a refused name does not take the ones beside it down with it" do
    create(:character, story: @story, fullname: "Perrin Vaile")

    created = admit(candidate("Perrin Vaile"), candidate("ward stamp"))

    assert_equal [ "ward stamp" ], created.map(&:name)
  end

  test "reports how much room is left, from the records" do
    registry = Item::Registry.new(@room)
    assert_equal Item::Registry::MAX_PER_ROOM, registry.room_for_items

    create(:item, :lying, location: @room, name: "seeded ledger")

    assert_equal Item::Registry::MAX_PER_ROOM - 1, registry.room_for_items
  end

  # Held items are not lying anywhere, so they do not count against the room --
  # the room's cap is a cap on the floor, which is the set `take` reads.
  test "something somebody is holding here does not fill the room up" do
    holder = create(:character, story: @story)
    Item::Registry::MAX_PER_ROOM.times { |n| create(:item, character: holder, name: "held #{n}") }

    assert_equal Item::Registry::MAX_PER_ROOM, Item::Registry.new(@room).room_for_items
  end
end
