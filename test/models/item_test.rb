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

  # --- what is written on it ------------------------------------------------

  test "nothing has writing on it unless the world says so" do
    item = create(:item, character: @character)

    assert_not item.readable?
    assert_nil item.inscription
    assert_not item.inscribed?
  end

  test "a readable thing holds the words the engine owns" do
    item = create(:item, :readable, character: @character)

    assert item.readable?
    assert item.inscribed?
    assert_equal "Midnight. The Bell. They know about the maps.", item.inscription
  end

  # THE ONE SHAPE IT REFUSES: words on a thing nobody marked readable. `readable`
  # closes the set anything may ever write an inscription into.
  test "refuses an inscription on something that is not readable" do
    item = build(:item, character: @character, readable: false, inscription: "Midnight.")

    assert_not item.valid?
    assert_includes item.errors[:inscription], "cannot be written on something that is not readable"
  end

  # The other way round is legal and stays legal: a readable thing nobody has
  # read yet.
  test "a readable thing may have no words written down yet" do
    item = build(:item, :unwritten, character: @character)

    assert item.valid?
    assert item.readable?
    assert_not item.inscribed?
  end

  test "an inscription is bounded" do
    item = build(:item, :readable, character: @character,
                 inscription: "x" * (Item::INSCRIPTION_LIMIT + 1))

    assert_not item.valid?
    assert_includes item.errors[:inscription].first, "too long"
  end

  test "the readable and unwritten scopes answer the two questions an instrument asks" do
    plain = create(:item, character: @character)
    written = create(:item, :readable, character: @character)
    blank = create(:item, :readable, :unwritten, character: @character)

    assert_equal [ written, blank ].map(&:id).sort, Item.readable.pluck(:id).sort
    assert_equal [ blank.id ], Item.unwritten.pluck(:id)
    assert_not_includes Item.readable.pluck(:id), plain.id
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

  # THE WORLD'S OWN ROWS HAVE A PLACE OR THEY ARE NOTHING. Nobody is playing a
  # world, so there is no pair of hands for one of its rows to be in: a template
  # lies in a room or somebody holds it.
  test "one of the world's own rows in nobody's hands and nowhere at all is not a state the world has" do
    item = build(:item, character: nil, location: nil)

    assert_not_predicate item, :valid?
    assert_includes item.errors[:base],
                    "is a template in no place at all; the world's own rows lie in a location or " \
                    "are held by a character, and only one playthrough's own copy may be in the party's hands"
  end

  # AND ON A PLAYTHROUGH'S OWN COPY, NO PLACE IS A PLACE: the party's hands. It
  # is the most ordinary state an instance has, and it is the one thing that
  # separates the two layers' halves of `#in_exactly_one_place`.
  test "a playthrough's own copy in no room and nobody's hands is in the party's hands" do
    item = build(:item, character: nil, location: nil, playthrough: create(:playthrough, story: @story))

    assert_predicate item, :valid?
    assert_predicate item, :carried?
    assert_predicate item, :instance?
  end

  # Two at once would be an item that is takeable and already taken.
  test "an item cannot be held and lying somewhere at the same time" do
    room = create(:location, story: @story)
    item = build(:item, character: @character, location: room)

    assert_not_predicate item, :valid?
    assert_includes item.errors[:base], "is in 2 places at once (character_id, location_id); it may only be in one"
  end

  # ONE PLAYTHROUGH'S OWN COPY LYING IN A ROOM IS A REAL STATE and the ruling of
  # 2026-09-04 is what made it one: her copy of the stamp is on the closet floor
  # and the world's own stamp is still in the office.
  test "a playthrough's own copy can lie in a room, and that is one place and not two" do
    room = create(:location, story: @story)
    item = build(:item, playthrough: create(:playthrough, story: @story), location: room, character: nil)

    assert_predicate item, :valid?
    assert_predicate item, :lying?
    assert_not_predicate item, :carried?
  end

  # And so is one in an NPC's hands, in one game.
  test "a playthrough's own copy can be in one of the world's people's hands" do
    item = build(:item, playthrough: create(:playthrough, story: @story), character: @character, location: nil)

    assert_predicate item, :valid?
    assert_predicate item, :held?
    assert_not_predicate item, :carried?
  end

  # A COPY OF A COPY IS NOT A THING, and neither is one of the world's own rows
  # copying another. The link points one way, from the playthrough layer into
  # the world layer, exactly once.
  test "one of the world's own rows may not be a copy of anything" do
    room = create(:location, story: @story)
    template = create(:item, :lying, location: room)
    item = build(:item, :lying, location: room, template: template)

    assert_not_predicate item, :valid?
    assert_includes item.errors[:template], "is only for a playthrough's own copy; the world's own rows copy nothing"
  end

  test "a copy may not be a copy of another playthrough's copy" do
    room = create(:location, story: @story)
    other = create(:item, playthrough: create(:playthrough, story: @story), location: room, character: nil)
    item = build(:item, playthrough: create(:playthrough, story: @story), location: room, character: nil,
                        template: other)

    assert_not_predicate item, :valid?
    assert_includes item.errors[:template], "must be one of the world's own rows, not another playthrough's copy"
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
  test "in_story finds an item on all three legs, in both layers" do
    room = create(:location, story: @story)
    playthrough = create(:playthrough, story: @story)
    held = create(:item, character: @character, name: "Vilya")
    lying = create(:item, :lying, location: room, name: "Brass Key")
    carried = create(:item, :carried, playthrough: playthrough, name: "Iron Ledger")

    elsewhere = create(:story)
    create(:item, character: create(:character, story: elsewhere), name: "Narya")

    assert_equal [ held, lying, carried ].map(&:id).sort, Item.in_story(@story).pluck(:id).sort
  end

  # WHICH LAYER IS PART OF WHERE. "Lying in Ward Office 12" is two different
  # facts depending on whether it is the world's own row or one game's copy of
  # it, and a doctor finding that did not say which would send somebody looking
  # in the wrong place.
  test "whereabouts says where it is and whose it is in one sentence" do
    room = create(:location, story: @story, name: "Ward Office 12")
    playthrough = create(:playthrough, story: @story)

    assert_equal "held by #{@character.fullname} (the world's own)",
                 create(:item, character: @character).whereabouts
    assert_equal "lying in Ward Office 12 (the world's own)",
                 create(:item, :lying, location: room).whereabouts
    assert_equal "in the party's hands (playthrough ##{playthrough.id}'s)",
                 create(:item, :carried, playthrough: playthrough).whereabouts

    template = create(:item, :lying, location: room, name: "ward stamp")
    copy = create(:item, playthrough: playthrough, location: room, character: nil,
                         name: "ward stamp", template: template)
    assert_equal "lying in Ward Office 12 (playthrough ##{playthrough.id}'s copy of ##{template.id})",
                 copy.whereabouts
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

  # ------------------------------------------------------------------------
  # HOW HARD IT IS TO SHIFT, which is `bulk` -- a closed key whose value is the
  # penalty a thrower's strength pays, and a second table on the same key for
  # what a hit costs.

  test "every row is handy unless the world says otherwise" do
    assert_equal Item::HANDY, create(:item).bulk
    assert_equal 2, create(:item).bulk_penalty
    assert_predicate create(:item), :throwable?
  end

  test "a bulk outside the closed table is refused" do
    item = build(:item, bulk: "featherweight")

    assert_not_predicate item, :valid?
    assert_includes item.errors[:bulk], "is not included in the list"
  end

  test "a blank bulk is refused, because handy is a decision and nil is not" do
    assert_not_predicate build(:item, bulk: nil), :valid?
    assert_not_predicate build(:item, bulk: ""), :valid?
  end

  # NIL IS NOT A BIG NUMBER, IT IS THE ABSENCE OF A THROW. `Playthrough::Turn`
  # rolls nothing for one and `Playthrough::Refusal` says so.
  test "an immovable thing has no penalty, no die and cannot be thrown" do
    press = create(:item, :immovable)

    assert_nil press.bulk_penalty
    assert_nil press.thrown_die
    assert_not_predicate press, :throwable?
  end

  # THE SAME HONEST NOTHING `Location#danger_share` GIVES AN UNKNOWN DANGER: a
  # word that came from somewhere other than the engine reads as "does not
  # move", and `rake game:doctor` names the row.
  test "a bulk the engine has no table for reads as immovable" do
    item = create(:item)
    item.update_column(:bulk, "featherweight")

    assert_nil item.bulk_penalty
    assert_not_predicate item, :throwable?
  end

  test "the two tables are keyed the same way, and only immovable is missing a die" do
    assert_equal Item::BULK.keys, Item::THROWN_DAMAGE.keys + [ "immovable" ]
    assert_equal [ 4, 6, 8 ], Item::THROWN_DAMAGE.values_at("light", Item::HANDY, "heavy")
    assert_equal [ 0, 2, 5 ], Item::BULK.values_at("light", Item::HANDY, "heavy")
  end

  # A COPY OF A THING IS THAT THING, and `Item::NOT_COPIED` is an exception list
  # -- so the column came along without anybody naming it.
  test "bulk is not one of the columns a copy leaves behind" do
    assert_not_includes Item::NOT_COPIED, "bulk"
  end

  # --- where in the room it is lying, since slice 4 -------------------------

  test "a thing lying somewhere in a room reads its position back" do
    key = create(:item, :placed)

    assert_equal Location::Spot.new(x: 3, y: 4), key.position
    assert_predicate key, :positioned?
  end

  # WHAT EVERY ROW IN EVERY DATABASE IS, and the reason the columns are
  # nullable: unplaced is the honest state, not a defect.
  test "a thing with neither column is unplaced and perfectly valid" do
    key = create(:item, :lying)

    assert_nil key.position
    assert_not_predicate key, :positioned?
    assert_predicate key, :valid?
  end

  test "half a position is refused" do
    assert_not_predicate build(:item, :placed, y: nil), :valid?
    assert_not_predicate build(:item, :placed, x: nil), :valid?
  end

  test "a position is whole numbers" do
    assert_not_predicate build(:item, :placed, x: 2.5), :valid?
  end

  # ZERO IS A CELL. A validation that read `present?` on the integers would call
  # the near corner of a room "no position".
  test "a thing at the origin of its room is placed" do
    key = create(:item, :placed, x: 0, y: 0)

    assert_equal Location::Spot.new(x: 0, y: 0), key.reload.position
  end

  # A POSITION NEEDS A FLOOR, and these are the three places that are not one:
  # somebody's hands, the party's hands, and nowhere.
  test "a thing in a pair of hands cannot carry a position" do
    error = assert_raises(ActiveRecord::RecordInvalid) { create(:item, x: 1, y: 1) }

    assert_match(/pair of hands/, error.message)
  end

  test "a thing in the party's hands cannot carry a position" do
    assert_not_predicate build(:item, :carried, x: 1, y: 1), :valid?
  end

  # THE POSITION IS THE INITIAL SNAPSHOT, so it is deliberately NOT on the
  # exception list -- `Item::SnapshotTest` walks the copy itself.
  test "a position is not one of the columns a copy leaves behind" do
    assert_not_includes Item::NOT_COPIED, "x"
    assert_not_includes Item::NOT_COPIED, "y"
  end

  # BUT IT IS NOT PUSHED BACK DOWN BY A RE-SEED: where one player left a thing
  # is the player's business (`Item::TemplateRefresh`).
  test "a position is not one of the columns a re-seed refreshes onto a copy" do
    assert_not_includes Item::TemplateRefresh::FROM_THE_TEMPLATE, "x"
    assert_not_includes Item::TemplateRefresh::FROM_THE_TEMPLATE, "y"
  end

  # THE INSTRUMENTS' SCOPE, and it takes a row carrying EITHER column so that
  # half a position is a row `Story::Doctor` can see rather than one that reads
  # as unplaced.
  test "the positioned scope reaches both layers and a partial row" do
    placed = create(:item, :placed)
    partial = create(:item, :lying)
    partial.update_column(:x, 4)
    create(:item, :lying)

    assert_equal [ placed, partial ].map(&:id).sort, Item.positioned.pluck(:id).sort
  end
end
