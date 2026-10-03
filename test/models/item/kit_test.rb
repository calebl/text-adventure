require "test_helper"

# WHAT STANDS IN A ROOM AND WHAT LIES ABOUT IN IT, rolled from the engine's
# kit tables on the room's kind and density. What is pinned here is the roll's
# shape -- seeded on the name, one die per piece, no name twice, pieces first,
# nothing for a room with no word -- and the one writer that turns it into the
# world's own rows. The dice themselves are held to the Rust engine's by the
# `kits` vector portion (`lib/engine_vectors/kits.rb`).
class Item::KitTest < ActiveSupport::TestCase
  def roll(name = "The Reading Room", kind = "study", density = "lived-in")
    Item::Kit.roll(name: name, kind: kind, density: density)
  end

  test "every kind the game has is a kind the kits furnish" do
    assert_equal Location::Kind::KINDS.sort, Item::Kit::TABLES.fetch("kinds").keys.sort
  end

  test "a room with no kind, or one the tables lack, rolls nothing" do
    assert_empty roll("The Reading Room", nil)
    assert_empty roll("The Reading Room", "ballroom")
  end

  test "no density word means no small stuff, and the pieces are still the kind's" do
    things = roll("The Reading Room", "study", nil)

    assert things.any?
    assert things.none? { |thing| thing.kit_key.include?("/loose/") }
  end

  test "the same name rolls the same room, whatever article or spacing it is written with" do
    assert_equal roll("The Reading Room"), roll("reading   room")
    assert_not_equal roll("The Reading Room"), roll("The Map Room")
  end

  test "pieces come first, and a thing names a piece earlier in the list" do
    Item::Kit::TABLES.fetch("kinds").each_key do |kind|
      30.times do |n|
        things = roll("room #{n}", kind, "cluttered")
        pieces = things.take_while { |thing| thing.kit_key.count("/") == 1 }

        assert_equal pieces.size, things.count { |thing| thing.kit_key.count("/") == 1 }, kind
        things.select(&:within).each { |thing| assert_operator thing.within, :<, pieces.size, kind }
      end
    end
  end

  test "no room shows more than the kit's share of the cap or a name twice" do
    Item::Kit::TABLES.fetch("kinds").each_key do |kind|
      30.times do |n|
        names = roll("room #{n}", kind, "cluttered").map(&:name)

        assert_operator names.size, :<=, Item::Kit::VISIBLE, kind
        assert_equal names.uniq, names, kind
      end
    end
    assert_equal Item::Kit::MAX_VISIBLE_PER_ROOM, Item::Kit::VISIBLE + Item::Registry::MAX_PER_ROOM
  end

  test "a fixed piece is an immovable fixture, and one that can be carried off is a portable thing of its bulk" do
    things = roll.index_by(&:name)

    assert_equal [ Item::FIXTURE, "closed", Item::IMMOVABLE ], things.fetch("desk").then { [ _1.tier, _1.holds, _1.bulk ] }
    assert_equal [ Item::PORTABLE, nil, "heavy" ], things.fetch("chair").then { [ _1.tier, _1.holds, _1.bulk ] }
    assert_equal [ "on", 0 ], things.fetch("ledger").then { [ _1.how, _1.within ] }
  end

  test "a thing in a hollow piece lies in it" do
    things = roll("Cinder Lane", "street", "lived-in")
    gutter = things.index { |thing| thing.name == "gutter" }

    assert things.select { |thing| thing.within == gutter }.all? { |thing| thing.how == "in" }
    assert things.any? { |thing| thing.within == gutter }
  end

  # ------------------------------------------------------------------------
  # THE WRITER.

  test "furnishing writes the kit as the world's own rows, once" do
    room = create(:location, :stub, name: "The Reading Room", kind: "study", density: "lived-in")
    written = Item::Kit.new(room).furnish!

    assert_equal roll.map(&:name), written.map(&:name)
    assert written.all?(&:template?)
    assert written.all? { |item| item.kit_key.present? }
    desk = written.find { |item| item.name == "desk" }
    assert_equal desk, written.find { |item| item.name == "ledger" }.within
    assert_equal "The ledger, on the desk.", written.find { |item| item.name == "ledger" }.description

    assert_empty Item::Kit.new(room.reload).furnish!
    assert_equal written.size, room.items.count
  end

  test "a room with no word, and a place, are never furnished" do
    assert_empty Item::Kit.new(create(:location, :stub, kind: nil)).furnish!
    place = create(:location, :stub, kind: "study", density: "lived-in", width: 10, depth: 10)
    assert_predicate place, :place?
    assert_empty Location::Generator.new(place).furnish!
  end

  test "things on a piece carry no position, and what stands on the floor of a room with a box is placed" do
    room = create(:location, :stub, :placed, name: "The Reading Room", kind: "study", density: "lived-in")
    written = Item::Kit.new(room).furnish!

    assert written.select(&:within).none?(&:positioned?)
    assert written.reject(&:within).all?(&:positioned?)
  end
end
