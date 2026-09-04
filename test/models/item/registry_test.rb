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

  # --- what is written on the ones that have writing on them ----------------

  test "a thing named readable with words on it is born with them" do
    item = admit(candidate("folded note").merge("readable" => true, "inscription" => "Midnight. The Bell.")).sole

    assert item.readable?
    assert_equal "Midnight. The Bell.", item.inscription
    assert item.inscribed?
  end

  # The ordinary answer, and the one most rooms give.
  test "a thing with nothing written on it carries no inscription" do
    item = admit(candidate("ward stamp").merge("readable" => false)).sole

    assert_not item.readable?
    assert_nil item.inscription
  end

  # A field that never arrived is not a thing with writing on it. `readable` is
  # read as a boolean and nothing else, so nothing acquires an inscription by a
  # field arriving in the wrong shape.
  test "readable is true and nothing else" do
    created = admit(
      candidate("first note").merge("inscription" => "Some words."),
      candidate("second note").merge("readable" => "true", "inscription" => "More words."),
      candidate("third note").merge("readable" => "yes")
    )

    assert_equal [ false, false, false ], created.map(&:readable)
    assert_equal [ nil, nil, nil ], created.map(&:inscription)
  end

  # THE THING IS KEPT AND THE WORDS ARE DROPPED. `readable` is the gate; a field
  # that disagrees with the gate is not evidence against it. Losing the room's
  # furniture over the contradiction would cost more than the contradiction.
  test "an inscription on a thing not marked readable is dropped and the thing is kept" do
    item = admit(candidate("ward stamp").merge("readable" => false, "inscription" => "Ward 12.")).sole

    assert_equal "ward stamp", item.name
    assert_nil item.inscription
    assert_not item.readable?
  end

  test "strips emoji out of an inscription too" do
    item = admit(candidate("folded note").merge("readable" => true, "inscription" => "Midnight. 🔔 The Bell.")).sole

    assert_equal "Midnight.  The Bell.".squeeze(" "), item.inscription.squeeze(" ")
  end

  # A field at its cap was cut off rather than finished, and this one is
  # persisted verbatim and quoted to the player forever afterwards -- so half of
  # it is not a shorter note, it is a note whose end is missing.
  #
  # IT IS DROPPED RATHER THAN RAISED, which is the opposite of every other
  # truncated field in the app, and the reason is where this runs: the room's
  # description is already saved and its exits are not written yet, so a raise
  # here leaves a realized room with no way out of it. The thing stays readable
  # and `Item::Inscriber` writes the words whole on the first read. Measured
  # live: a Sovereign's Circle handbill came back at exactly the cap.
  test "an inscription cut off at the cap is dropped and the thing stays readable" do
    cut = "x" * Item::INSCRIPTION_LIMIT

    item = admit(candidate("folded handbill").merge("readable" => true, "inscription" => cut)).sole

    assert_equal "folded handbill", item.name
    assert item.readable?
    assert_nil item.inscription
    assert_not item.inscribed?
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

  # BOTH CAPS BOUND THE WORLD AND NOT ANY GAME. A player's own copy of a thing
  # is not a second thing in the world -- since the captain's ruling of
  # 2026-09-04 a take moves that player's copy and the world's own row never
  # leaves the room -- so counting instances would spend a world's budget of
  # sixty on the same sixty things once per player.
  test "what a party is carrying costs the world cap nothing" do
    played = create(:playthrough, story: @story)
    create(:item, :carried, playthrough: played, name: "a thing in the player's hands")

    assert_equal Item::Registry::MAX_PER_STORY, Item::Registry.new(@room).world_for_items
  end

  # And the room's cap is the same statement one room down: three things may be
  # lying in it, however many parties have each taken their own copy of them.
  test "a party's own copy on the floor costs the room cap nothing" do
    played = create(:playthrough, story: @story)
    create(:item, :lying, location: @room, name: "the world's own oar")
    create(:item, playthrough: played, location: @room, character: nil, name: "a copy of the oar")

    assert_equal Item::Registry::MAX_PER_ROOM - 1, Item::Registry.new(@room).room_for_items
  end

  # THE CAP IS ON THE ONTOLOGY -- how many distinct things exist here -- and
  # every playthrough carries its own copy of the story's starting inventory, so
  # counting rows would spend the world's budget on one daybook once per player.
  test "the world cap counts names, so copies of the starting inventory cost one" do
    protagonist = create(:character, :protagonist, story: @story)
    create(:item, character: protagonist, name: "Ward Office 12 daybook")
    4.times { create(:playthrough, story: @story, character: protagonist) }

    assert_equal 5, Item.in_story(@story).where(name: "Ward Office 12 daybook").count
    assert_equal Item::Registry::MAX_PER_STORY - 1, Item::Registry.new(@room).world_for_items
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
