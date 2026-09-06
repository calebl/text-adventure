require "test_helper"

class LocationTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @location = build(:location, :rivendell, story: @story)
  end

  test "should be valid with valid attributes" do
    assert @location.valid?
  end

  test "should require name" do
    @location.name = nil
    assert_not @location.valid?
    assert_includes @location.errors[:name], "can't be blank"
  end

  test "should require description" do
    @location.description = nil
    assert_not @location.valid?
    assert_includes @location.errors[:description], "can't be blank"
  end

  test "should require lore" do
    @location.lore = nil
    assert_not @location.valid?
    assert_includes @location.errors[:lore], "can't be blank"
  end

  test "should belong to story" do
    assert_equal @story, @location.story
  end

  test "should have many scenes" do
    @location.save!
    scene = create(:scene, :rivendell_arrival, story: @story, location: @location)
    assert_includes @location.scenes, scene
  end

  test "should have and belong to many connected locations" do
    @location.save!
    other_location = create(:location, :shire, story: @story)
    connection = create(:location_connection,
      location: @location,
      connected_location: other_location
    )

    @location.reload
    assert_includes @location.connected_locations, other_location
  end

  test "should track time since last visit" do
    @location.save!

    # No visit yet
    assert_nil @location.time_since_last_visit

    @location.update!(last_protagonist_visit: @story.start_time)

    assert_equal 90.minutes, @location.time_since_last_visit(@story.start_time + 90.minutes)
  end

  # THE WALL-CLOCK DEFECT, and the assertion that closes it. This used to be
  # `Time.current - last_protagonist_visit`, so a player who shut the tab for a
  # week and came back was told in fiction that they had been gone a week.
  test "time since last visit is measured in story time, not against the wall clock" do
    @location.save!
    @location.update!(last_protagonist_visit: @story.start_time)
    # Somewhere else, so the visit stamp this scene writes is not on @location.
    create(:scene, story: @story, location: create(:location, story: @story),
                   story_timestamp: @story.start_time + 20.minutes)

    travel 3.weeks do
      assert_equal 20.minutes, @location.time_since_last_visit,
                   "three weeks of somebody's life is not twenty minutes of the story"
    end
  end

  test "time since last visit defaults to the story's own clock" do
    @location.save!
    @location.update!(last_protagonist_visit: @story.start_time)
    create(:scene, story: @story, location: create(:location, story: @story),
                   story_timestamp: @story.start_time + 4.hours)

    assert_equal 4.hours, @location.time_since_last_visit
  end

  test "should mark protagonist visit at a story moment" do
    @location.save!
    at = @story.start_time + 3.hours

    @location.mark_protagonist_visit!(at)

    assert_equal at, @location.last_protagonist_visit
  end

  test "mobile and anchored scope the places that move" do
    @location.save!
    mover = create(:location, story: @story, name: "The Travelling Stair", mobile: true)

    assert_includes Location.mobile, mover
    assert_not_includes Location.mobile, @location
    assert_includes Location.anchored, @location
    assert_not_includes Location.anchored, mover
  end

  test "a location does not move by default" do
    assert_not Location.new.mobile?
  end

  test "defaults to a stub" do
    assert Location.new.stub?
  end

  test "a stub saves without a description or lore" do
    stub = build(:location, :stub, story: @story, name: "The Long Stair")

    assert stub.valid?
    assert stub.save
    assert stub.stub?
  end

  test "a realized location still requires a description and lore" do
    realized = build(:location, :stub, story: @story, detail_level: "realized")

    assert_not realized.valid?
    assert_includes realized.errors[:description], "can't be blank"
    assert_includes realized.errors[:lore], "can't be blank"
  end

  test "a stub still requires a name" do
    stub = build(:location, :stub, story: @story, name: nil)

    assert_not stub.valid?
    assert_includes stub.errors[:name], "can't be blank"
  end

  test "rejects a detail level it does not know" do
    location = build(:location, story: @story)
    location.detail_level = "half"

    assert_not location.valid?
    assert_includes location.errors[:detail_level], "is not included in the list"
  end

  test "scopes locations by detail level" do
    stub = create(:location, :stub, story: @story)
    realized = create(:location, story: @story)

    assert_includes Location.stubs, stub
    assert_not_includes Location.stubs, realized
    assert_includes Location.realized, realized
    assert_not_includes Location.realized, stub
  end

  test "exits are the locations connected out of here" do
    @location.save!
    neighbour = create(:location, :stub, story: @story)
    create(:location_connection, location: @location, connected_location: neighbour)

    assert_includes @location.reload.exits, neighbour
  end

  # ------------------------------------------------------------------------
  # DANGER: HOW LIKELY THIS PLACE IS TO BE BORN WITH THE WORLD'S MONSTERS IN IT.
  # A closed-set key into `Location::DANGERS`, the shape
  # `LocationConnection::DISTANCES` has -- the labels are what an author reads,
  # the numbers are what the engine rolls.

  test "a room is safe unless a world says otherwise" do
    assert_equal Location::SAFE, build(:location).danger
    assert_not_predicate build(:location), :dangerous?
    assert_equal 0, build(:location).danger_share
  end

  test "should refuse a danger the engine has no table for" do
    @location.danger = "a bit worrying"

    assert_not @location.valid?
    assert_includes @location.errors[:danger], "is not included in the list"
  end

  test "should refuse a blank danger" do
    @location.danger = nil

    assert_not @location.valid?
  end

  test "the share is faces of the danger die, and safe throws none" do
    assert_equal 0, Location::DANGERS.fetch(Location::SAFE)
    assert_equal Location::DANGER_DIE, Location::DANGERS.fetch("deadly")
    Location::DANGERS.each_value { |share| assert_includes 0..Location::DANGER_DIE, share }
  end

  test "an unknown danger reads as no share at all rather than raising" do
    room = build(:location)
    room.danger = "unheard-of"

    assert_equal 0, room.danger_share
    assert_not_predicate room, :dangerous?
  end

  test "the dangerous scope is every room that is not safe" do
    @location.save!
    dangerous = create(:location, :dangerous, story: @story, name: "The Bell Chamber")
    create(:location, :deadly, story: @story, name: "The Sump")

    assert_equal 2, @story.locations.dangerous.count
    assert_includes @story.locations.dangerous, dangerous
    assert_not_includes @story.locations.dangerous, @location
  end

  test "should have parent location relationship" do
    @location.save!
    child_location = create(:location,
      story: @story,
      name: "Elrond's Library",
      parent_location: @location
    )

    assert_equal @location, child_location.parent_location
  end

  # ------------------------------------------------------------------------
  # WHAT A PLACE DOES TO SOMEBODY STANDING IN IT. `Location::HAZARDS` is the
  # closed catalogue and the two columns are the world's -- written by a seed
  # file and by no model and no typed line. The readers are what
  # `Playthrough::Hazards` branches on, so each of them is asserted here rather
  # than through the engine.

  test "a room has no hazard by default and almost no room has one" do
    room = create(:location)

    assert_nil room.hazard
    assert_not room.hazardous?
    assert_nil room.hazard_entry
    assert_not room.hazard_at?(:on_arrival)
    assert_not room.hazard_at?(:every_turn)
  end

  test "a hazard has to be one of the catalogue's keys" do
    room = build(:location, hazard: "haunted", hazard_die: 4)

    assert_not room.valid?
    assert_includes room.errors[:hazard].join, "is not included"
  end

  test "a hazard die has to be one the engine throws" do
    assert_not build(:location, hazard: "flooded", hazard_die: 7).valid?
  end

  # HALF A HAZARD IS A COLUMN THAT LOOKS AS THOUGH IT SAID SOMETHING AND DID
  # NOT: the key says what happens and the die says how much.
  test "half a hazard is refused, either half" do
    assert_not build(:location, hazard: "flooded").valid?
    assert_not build(:location, hazard_die: 4).valid?
  end

  # THE TWO `when:` VALUES ARE TWO BRANCHES, and a room answers for exactly one.
  test "hazard_at? answers only for the moment the catalogue names" do
    room = create(:location, :flooded)

    assert room.hazard_at?(:on_arrival)
    assert_not room.hazard_at?(:every_turn)
  end

  test "an every_turn room answers the other one" do
    room = create(:location, :airless)

    assert room.hazard_at?(:every_turn)
    assert_not room.hazard_at?(:on_arrival)
  end

  # A KEY THE TABLE DOES NOT HAVE reads as no hazard at all, so nothing rolls
  # off it and `rake game:doctor` reports the row
  # (`location_with_an_unknown_hazard`) rather than anything guessing.
  test "a key the catalogue does not have is not a hazard" do
    room = create(:location)
    room.update_columns(hazard: "haunted", hazard_die: 4)

    assert_nil room.reload.hazard_entry
    assert_not room.hazardous?
  end

  test "the hazardous scope is the rooms that do something" do
    hazardous = create(:location, :flooded)
    create(:location)

    assert_equal [ hazardous ], Location.hazardous.to_a
  end

  # EVERY ENTRY IS WELL FORMED, which is what lets `Playthrough::Hazards` fetch
  # `:when` without a default and `Playthrough::Moment` fetch `:words`.
  test "every catalogue entry names a moment, a save and its words" do
    Location::HAZARDS.each do |key, entry|
      assert_includes Location::HAZARD_MOMENTS, entry[:when], "#{key} has an unroutable `when:`"
      assert entry.key?(:save), "#{key} has no `save:` -- nil is a value and an omission is not"
      assert entry[:save].nil? || Character::ABILITIES.include?(entry[:save]),
             "#{key} saves on something that is not one of Character::ABILITIES"
      assert entry[:words].present?, "#{key} has nothing to tell the prose"
    end
  end
  # --- the shape of a place, since the rulings of 2026-09-06 -----------------

  # NULL ON ALL FIVE IS THE ORDINARY STATE and must stay it: it is every row in
  # every database and all three checked-in worlds, which the captain's fourth
  # ruling leaves flat on purpose.
  test "a place has no inside by default, and that is not a defect" do
    room = create(:location)

    assert_nil room.box
    assert_not room.interior?
    assert_not room.placed?
    assert_predicate room, :valid?
  end

  test "an extent with no position is a footprint, and it is what an outermost place carries" do
    place = create(:location, :with_a_footprint)

    assert_predicate place, :interior?
    assert_not place.placed?
    assert_nil place.box
  end

  test "all five columns is a placed room, and the box reads them back" do
    room = create(:location, :placed)

    assert_predicate room, :interior?
    assert_predicate room, :placed?
    assert_equal Location::Box.new(x: 0, y: 0, z: 0, width: 7, depth: 8), room.box
  end

  # HALF A LAYOUT IS REFUSED AS ONE THING, for the reason half a hazard is:
  # a row carrying part of an answer looks as though it said something and did
  # not. `rake game:doctor` reports one a database already carries.
  test "a place carrying part of a box is refused" do
    room = build(:location, x: 1, y: 2)

    assert_not room.valid?
    assert_match(/neither a footprint/, room.errors.full_messages.join)
  end

  test "a position with no extent is refused too" do
    assert_not build(:location, x: 1, y: 2, z: 0).valid?
  end

  # A ROOM NOTHING CAN STAND IN. Zero paces across is not a small room.
  test "a room has to be at least one pace across" do
    assert_not build(:location, :with_a_footprint, width: 0).valid?
    assert_not build(:location, :with_a_footprint, depth: -1).valid?
  end

  # SIGNED ON PURPOSE: a room west of its parent's origin, or a basement below
  # it, are both ordinary.
  test "a position may be negative" do
    place = create(:location, :with_a_footprint)
    room = build(:location, story: place.story, parent_location: place,
                            x: -4, y: -2, z: -1, width: 3, depth: 3)

    assert_predicate room, :valid?
  end

  test "two sibling rooms in the same place at once overlap" do
    place = create(:location, :with_a_footprint)
    one = create(:location, story: place.story, parent_location: place, x: 0, y: 0, z: 0, width: 5, depth: 5)
    other = create(:location, story: place.story, parent_location: place, x: 4, y: 4, z: 0, width: 5, depth: 5)

    assert one.overlaps?(other)
    assert other.overlaps?(one)
  end

  test "two sibling rooms sharing a wall do not overlap" do
    place = create(:location, :with_a_footprint)
    one = create(:location, story: place.story, parent_location: place, x: 0, y: 0, z: 0, width: 7, depth: 8)
    other = create(:location, story: place.story, parent_location: place, x: 7, y: 0, z: 0, width: 5, depth: 8)

    assert_not one.overlaps?(other)
  end

  # COORDINATES ARE LOCAL TO A PARENT AND THERE IS NO GLOBAL SPACE, so the same
  # five numbers under two different parents are read in two different planes
  # and the comparison is meaningless. False rather than raised -- see
  # `Location#overlaps?`.
  test "the same box under two different parents does not overlap" do
    story = create(:story)
    here = create(:location, :with_a_footprint, story: story)
    there = create(:location, :with_a_footprint, story: story)
    one = create(:location, story: story, parent_location: here, x: 0, y: 0, z: 0, width: 5, depth: 5)
    other = create(:location, story: story, parent_location: there, x: 0, y: 0, z: 0, width: 5, depth: 5)

    assert_not one.overlaps?(other)
  end

  test "two rooms with no parent at all do not overlap" do
    story = create(:story)
    one = create(:location, story: story, width: 5, depth: 5)
    other = create(:location, story: story, width: 5, depth: 5)

    assert_not one.overlaps?(other)
  end

  # 2.5D, THE CAPTAIN'S THIRD RULING: each floor is its own plane.
  test "the same rectangle on two storeys of one place does not overlap" do
    place = create(:location, :with_a_footprint)
    ground = create(:location, story: place.story, parent_location: place, x: 0, y: 0, z: 0, width: 5, depth: 5)
    above = create(:location, story: place.story, parent_location: place, x: 0, y: 0, z: 1, width: 5, depth: 5)

    assert_not ground.overlaps?(above)
  end

  test "a room does not overlap itself" do
    room = create(:location, :placed)

    assert_not room.overlaps?(room)
  end

  # TWO ROOMS THAT HAVE NOT BEEN SAVED ARE STILL TWO ROOMS, which is the shape a
  # layout generator holds while it is deciding where to put things: it asks
  # whether a candidate box lands on one it has already chosen, and neither has
  # an id yet.
  test "two unsaved rooms on the same rectangle of one parent overlap" do
    place = create(:location, :with_a_footprint)
    one = build(:location, story: place.story, parent_location: place, x: 0, y: 0, z: 0, width: 5, depth: 5)
    other = build(:location, story: place.story, parent_location: place, x: 0, y: 0, z: 0, width: 5, depth: 5)

    assert one.overlaps?(other)
    assert other.overlaps?(one)
    assert_not one.overlaps?(one)
  end

  test "an unplaced room overlaps nothing, including a placed sibling" do
    place = create(:location, :with_a_footprint)
    placed = create(:location, story: place.story, parent_location: place, x: 0, y: 0, z: 0, width: 5, depth: 5)
    unplaced = create(:location, story: place.story, parent_location: place)

    assert_not unplaced.overlaps?(placed)
    assert_not placed.overlaps?(unplaced)
  end

  test "the scopes are places with an inside and rooms that have been placed" do
    story = create(:story)
    create(:location, story: story)
    footprint = create(:location, :with_a_footprint, story: story)
    placed = create(:location, :placed, story: story)

    assert_equal [ footprint, placed.parent_location, placed ].map(&:id).sort,
                 story.locations.with_a_footprint.pluck(:id).sort
    assert_equal [ placed ], story.locations.with_a_box.to_a
  end

  # HALF A LAYOUT IS IN NEITHER SCOPE. `#a_box_is_whole` refuses to save a row
  # like this, so it is written past the validation the way a database older
  # than the validation already carries one -- and that is exactly the row a
  # scope must not count as laid out, because `Story::Doctor` reads `#box` off
  # everything the scope hands it and a partial row has none.
  # A RING IS THE ONE QUESTION THAT CAN LOOP THE READER ASKING IT, so the walk
  # carries what it has seen. Written straight to the column because nothing in
  # the app will save a place inside itself.
  test "an ordinary chain of parents is in no ring" do
    place = create(:location, :with_a_footprint)
    room = create(:location, story: place.story, parent_location: place)

    assert_nil room.containment_ring
    assert_nil place.containment_ring
  end

  test "a place that is its own parent is a ring of one" do
    place = create(:location)
    place.update_column(:parent_location_id, place.id)

    assert_equal [ place ], place.reload.containment_ring
  end

  test "two places inside each other are one ring, answered the same way from either" do
    one = create(:location, name: "The Rusted Anchor")
    other = create(:location, story: one.story, name: "The Taproom", parent_location: one)
    one.update_column(:parent_location_id, other.id)

    assert_equal [ one, other ].map(&:id).sort, one.reload.containment_ring.map(&:id).sort
    assert_equal one.reload.containment_ring.map(&:id).sort,
                 other.reload.containment_ring.map(&:id).sort
  end

  # THE TAIL IS NOT THE RING. A room hanging off a ring is not itself inside
  # itself, and reporting it as part of one would send a reader to the wrong row.
  test "a room hanging off a ring answers with the ring alone" do
    one = create(:location, name: "The Rusted Anchor")
    other = create(:location, story: one.story, name: "The Taproom", parent_location: one)
    one.update_column(:parent_location_id, other.id)
    hanger = create(:location, story: one.story, name: "The Back Room", parent_location: other)

    assert_equal [ one, other ].map(&:id).sort, hanger.containment_ring.map(&:id).sort
  end

  test "a row carrying part of a box is in neither scope" do
    story = create(:story)
    create(:location, story: story).update_columns(width: 6, x: 1)
    create(:location, story: story).update_columns(x: 0, y: 0, z: 0)
    create(:location, story: story).update_columns(width: 6)

    assert_empty story.locations.with_a_footprint
    assert_empty story.locations.with_a_box
  end
end
