require "test_helper"

# WHO DECIDES WHAT A ROOM OF A PLACE IS CALLED once a model has proposed
# something -- the engine, on every one of the grounds `Location::RoomName`
# refuses on, and never the model.
#
# THE SHAPE OF EVERY ASSERTION HERE IS THE SAME: a refusal answers NIL and the
# caller keeps the name the row already has. Nothing raises, because this runs
# between a paid-for answer arriving and the room being saved -- see the class
# header.
class Location::RoomNameTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, :stub, :placed, story: @story, name: "The Custom House room 1")
    @place = @room.parent_location
    @place.update!(name: "The Custom House")
  end

  def naming = Location::RoomName.for(@room)

  # --- the gate --------------------------------------------------------------
  #
  # A ROOM OF A LAID-OUT PLACE AND NOTHING ELSE. `Location#containing_place` is
  # the one reading of it, so a caller asks one question and has no gate of its
  # own.

  test "a room placed in a place is one this names" do
    assert_instance_of Location::RoomName, naming
    assert_equal @place, naming.place
  end

  test "a room inside nothing is not one this names" do
    assert_nil Location::RoomName.for(create(:location, :stub, story: @story))
  end

  # PLAIN CONTAINMENT IS NOT AN INTERIOR: a parent with no footprint is a
  # district a street sits in, and a street's name is its own
  # (`Location::Generator#interior_room?`).
  test "plain containment is not a place a room gets named inside" do
    district = create(:location, story: @story, name: "The Docks District")
    row = create(:location, :stub, story: @story, name: "Warehouse Row", parent_location: district)

    assert_nil Location::RoomName.for(row)
  end

  test "the place itself is never named by this" do
    assert_nil Location::RoomName.for(@place)
  end

  test "nil is not a room" do
    assert_nil Location::RoomName.for(nil)
  end

  # A HAND-AUTHORED NAME IS NOT PROPOSED AGAINST, which is what makes the class
  # header's claim about a seed file true: a world file may draw a whole
  # building by hand as stub rooms, and such a room's name is listed as an exit
  # and may already have been typed by the player before anybody walked in.
  #
  # IT IS THE GATE AND NOT A REFUSAL on purpose -- see `.for`. Nil means the
  # prompt never asks, so the row leaves both name checks' denominators instead
  # of reporting a refusal against a room that was never a candidate.
  test "a room of a place with a name of its own is not one this names" do
    @room.update!(name: "The Cellar Stair")

    assert_nil Location::RoomName.for(@room)
  end

  test "a room still called one of the place's own numbers is one this names" do
    @room.update!(name: "Custom House Room 1")

    assert_instance_of Location::RoomName, Location::RoomName.for(@room)
  end

  # --- what it takes ---------------------------------------------------------

  test "a short name that collides with nothing is taken as written" do
    assert_equal "the counting room", naming.accept("the counting room")
  end

  # The article is part of the name and is asked for, because the play page
  # prints the stored name as it stands -- see the class header and
  # `app/views/playthroughs/_turn_log.html.erb`.
  test "a leading article is kept, because the line that reads it adds none" do
    assert_equal "the harbourmaster's office", naming.accept("the harbourmaster's office")
  end

  test "surrounding whitespace and emoji are taken off rather than refused" do
    assert_equal "the cold store", naming.accept("  the cold store 🧊 ")
  end

  # --- what it refuses -------------------------------------------------------

  test "a blank proposal keeps the placeholder" do
    assert_nil naming.accept("")
    assert_nil naming.accept("   ")
    assert_nil naming.accept(nil)
  end

  # A field at its cap was cut off rather than finished
  # (`SanitizesGeneratedText::TruncatedTextError`), and half a name is not a
  # shorter name. It is REFUSED here and not raised: see the class header.
  test "a name that arrived at its cap is refused and does not raise" do
    assert_nil naming.accept("x" * Location::RoomName::LIMIT)
    assert_equal "x" * (Location::RoomName::LIMIT - 1), naming.accept("x" * (Location::RoomName::LIMIT - 1))
  end

  # `Playthrough::Grammar::JOINING_WORDS` reads a comma as *and*, so a room
  # named with one in it is a room a line cannot name --
  # `Location::Interior.placeholder_name` states the general rule.
  test "a comma is refused, because the grammar reads one as two acts" do
    assert_nil naming.accept("the long, low hall")
  end

  test "the name the room already has is refused" do
    assert_nil naming.accept("The Custom House room 1")
    assert_nil naming.accept("the custom house room 1")
  end

  # A NUMBER NO ROOM CARRIES IS STILL A PLACEHOLDER, and it is the one the
  # collision check below cannot see -- nothing answers to it.
  test "another of this place's placeholders is refused, invented number and all" do
    create(:location, :stub, story: @story, name: "The Custom House room 2",
                             parent_location: @place, x: 7, y: 0, z: 0, width: 5, depth: 8)

    assert_nil naming.accept("The Custom House room 2")
    assert_nil naming.accept("The Custom House room 12")
  end

  # THE PLACE'S OWN NAME INSIDE THE ROOM'S. The play page prints the two
  # together -- *"the <room> of <place>"*, the captain's ruling of 2026-09-06 --
  # so this is the doubling the class exists to remove, one notch quieter than a
  # placeholder: `The Custom House taproom` carries no ` room <n>` suffix, so
  # `Location::Interior.placeholder_name?` does not see it, and it collides with
  # nothing. The prompt tells the model to keep the place's name out; this is
  # the half that does not depend on it having listened.
  test "the place's own name inside the proposal is refused" do
    assert_nil naming.accept("The Custom House taproom")
    assert_nil naming.accept("the custom house cellar")
    # Containment and not equality, on `WorldSeed.natural_key`'s reading: the
    # place's name anywhere in the room's is the failure.
    assert_nil naming.accept("the back of the Custom House")
  end

  test "a room name that merely shares a word with the place is taken" do
    assert_equal "the custom counter", naming.accept("the custom counter")
  end

  test "a name another room of this place already answers to is refused" do
    create(:location, story: @story, name: "the counting room",
                      parent_location: @place, x: 7, y: 0, z: 0, width: 5, depth: 8)

    assert_nil naming.accept("the counting room")
    # And on `WorldSeed.natural_key`'s reading of one name, which is the reading
    # `Story::Doctor#duplicate_locations` reports a collision on.
    assert_nil naming.accept("Counting Room")
  end

  # WIDER THAN THIS PLACE ON PURPOSE. `Story::Doctor#duplicate_locations`
  # reports two locations of one story answering to one name as a defect a
  # person resolves by hand, and half the app looks a room up by name -- so
  # accepting one would be the engine writing the row the doctor exists to find.
  test "a name somewhere else in the story already has is refused" do
    create(:location, story: @story, name: "The Quay")

    assert_nil naming.accept("The Quay")
  end

  test "a name somebody in the story already has is refused" do
    create(:character, story: @story, fullname: "Neb Halloran", nickname: "Neb")

    assert_nil naming.accept("Neb Halloran")
    assert_nil naming.accept("Neb")
  end

  test "a name something in the story already has is refused" do
    create(:item, :lying, location: @room, name: "seal ledger")

    assert_nil naming.accept("seal ledger")
  end

  # ANOTHER STORY'S NAMES ARE NOT THIS STORY'S. The collision is per world, the
  # way every name check in the app is.
  test "a name another story uses is not a collision" do
    create(:location, story: create(:story), name: "the counting room")

    assert_equal "the counting room", naming.accept("the counting room")
  end

  # --- what the prompt is told ----------------------------------------------

  test "the rooms it names as taken are the siblings that have real names" do
    create(:location, story: @story, name: "the counting room",
                      parent_location: @place, x: 7, y: 0, z: 0, width: 5, depth: 8)
    create(:location, :stub, story: @story, name: "The Custom House room 3",
                             parent_location: @place, x: 0, y: 0, z: 1, width: 7, depth: 8)

    # The placeholders are left off: nothing was ever going to propose one, and
    # a fourteen-room building would spend fourteen lines saying so.
    assert_equal [ "the counting room" ], naming.named_siblings
  end

  test "it names no rooms as taken in a building nobody has written yet" do
    assert_equal [], naming.named_siblings
  end

  # --- the captain's ruling, executable --------------------------------------
  #
  # *The name the player reads must be the name the player can type back.* The
  # room is named by a model and resolved by `Playthrough::Grammar`, so the two
  # halves are asserted together here rather than trusted to agree.

  test "a name this accepts is one the player can type back and reach the room by" do
    hall = create(:location, :stub, :placed, story: @story, name: "The Custom House room 2")
    hall.update!(parent_location: @place, x: 7, y: 0, z: 0, width: 5, depth: 8)
    create(:location_connection, location: hall, connected_location: @room,
                                 distance: "adjacent", travel_method: "walking")
    create(:location_connection, location: @room, connected_location: hall,
                                 distance: "adjacent", travel_method: "walking")

    @room.update!(name: naming.accept("the counting room"))
    protagonist = create(:character, story: @story, is_protagonist: true)
    playthrough = create(:playthrough, story: @story, character: protagonist, current_location: hall)
    grammar = Playthrough::Grammar.new(playthrough)

    # The whole name, a fragment of it, and the fragment with the article the
    # player would probably type -- `Playthrough::Grammar::HOW_A_NAME_MATCHES`
    # and `LEADING_WORDS` between them. Slashed, because that is the only line
    # this grammar CLAIMS (`#claims?`, the captain's ruling of 2026-09-05); a
    # bare line goes to `Playthrough::Classifier`, whose closed set of exits is
    # built out of these same names.
    [ "/go the counting room", "/go counting room", "/go to the counting room" ].each do |line|
      reading = EngineSweep.without_a_model { grammar.reading_first(line) }

      assert_predicate reading, :resolved?, "#{line.inspect} did not resolve"
      assert_equal @room, reading.intent.subject, "#{line.inspect} resolved to the wrong room"
    end
  end
end
