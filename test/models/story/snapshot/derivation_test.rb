require "test_helper"

# READING A GENERATION-TIME WORLD BACK OUT OF A PLAYED ONE, which is the half of
# this feature that can be WRONG -- the snapshot `rake game:new` takes cannot
# be, and every story in the captain's database predates it.
#
# So what is pinned here is the LINE and the RULES, one test each, on records
# stamped either side of it: the cutoff is the first play and not the first
# playthrough row; the opening room and arrival are generation whatever their
# timestamps say; a room play realized comes back as the stub it was; and the
# things that a backfill has re-dated are decided by their owner rather than by
# their own age.
class Story::Snapshot::DerivationTest < ActiveSupport::TestCase
  include ForkableWorld

  test "the line is the first play, and a deleted playthrough does not move it" do
    story = seeded_world
    playthrough = play!(story)

    assert_equal PLAY_STARTED_AT, Story::Snapshot::Derivation.new(story).cutoff

    # The scenes stay: a Scene belongs to its location, so deleting the
    # playthrough that made them leaves the record of somebody having played.
    playthrough.destroy!
    assert_equal PLAY_STARTED_AT, Story::Snapshot::Derivation.new(story.reload).cutoff
  end

  test "a world nobody has played derives as a plain export" do
    story = seeded_world
    derivation = Story::Snapshot::Derivation.new(story)

    assert derivation.unplayed?
    assert_equal WorldSeed::Exporter.new(story).document, derivation.document
    assert_includes derivation.notes.join(" "), "nothing has been played"
  end

  test "a room play realized comes back as the stub it was" do
    story = seeded_world
    play!(story)

    hallway = Story::Snapshot::Derivation.new(story).document["locations"].detect { |row| row["name"] == "The Hallway" }

    assert_equal "stub", hallway["detail_level"]
    assert_nil hallway["description"]
    assert_nil hallway["lore"]
    assert_equal "Doors closing, one after another.", hallway["teaser"]
  end

  # `Location::Generator#connect_exit!` connects an invented stub to the room
  # whose exits call invented it and to nothing else, so a neighbour younger
  # than the line dates the realization that made it. This is that rule.
  test "a room is kept realized when it invented no neighbour after the line" do
    story = seeded_world
    play!(story)

    document = Story::Snapshot::Derivation.new(story).document
    office = document["locations"].detect { |row| row["name"] == "The Office" }

    assert_equal "realized", office["detail_level"]
    assert_equal "An office.", office["description"]
  end

  test "rooms and people play created are left behind" do
    story = seeded_world
    play!(story)

    document = Story::Snapshot::Derivation.new(story).document

    assert_equal [ "The Office", "The Hallway" ], document["locations"].map { |row| row["name"] }
    assert_equal [ "Vesper Aal", "Corbel Ashe" ], document["characters"].map { |row| row["fullname"] }
    assert_equal 1, document["connections"].size
  end

  # `rake game:backfill_items` rewrote every item row when the world and
  # playthrough layers were split, so an item's own age is the backfill's. The
  # owner is the honest question, and this is the case that proves the age is
  # not being read: a template as young as the play that did NOT create it.
  test "a thing in a room kept realized survives being younger than the line" do
    story = seeded_world
    play!(story)
    story.opening_location.items.templates.update_all(created_at: PLAY_STARTED_AT + 1.hour)

    office = Story::Snapshot::Derivation.new(story).document["locations"].detect { |row| row["name"] == "The Office" }

    assert_equal [ "A Stamp" ], office["items"].map { |row| row["name"] }
  end

  test "a thing the demoted realization put in a room goes with it" do
    story = seeded_world
    play!(story)

    hallway = Story::Snapshot::Derivation.new(story).document["locations"].detect { |row| row["name"] == "The Hallway" }

    assert_nil hallway["items"]
  end

  # The opening arrival was written days late by `rake game:repair` for two of
  # the captain's stories, so it is generation by what it IS rather than by when
  # its row was written.
  test "the opening arrival is generation however late its row was written" do
    story = seeded_world
    play!(story)
    story.opening_scene.update_column(:created_at, PLAY_STARTED_AT + 2.days)

    document = Story::Snapshot::Derivation.new(story).document

    assert_equal "The Office", document.dig("opening_scene", "location")
    assert_equal [ "Vesper Aal" ], document.dig("opening_scene", "characters")
  end

  test "somebody play cast in the opening arrival comes out of its cast" do
    story = seeded_world
    play!(story)
    story.opening_scene.characters << story.characters.find_by(fullname: "Someone Play Made")

    document = Story::Snapshot::Derivation.new(story).document

    assert_equal [ "Vesper Aal" ], document.dig("opening_scene", "characters")
  end

  # `The Iron Gate Descends` is the story this is for: it was generated before
  # `Story::FirstScreen` made a protagonist, so its player row is a day younger
  # than its first playthrough and a world derived without it has nobody to
  # play it.
  test "the protagonist is kept however young their row is" do
    story = seeded_world
    play!(story)
    story.protagonist.update_column(:created_at, PLAY_STARTED_AT + 1.day)

    derivation = Story::Snapshot::Derivation.new(story)

    assert_includes derivation.document["characters"].map { |row| row["fullname"] }, "Vesper Aal"
    assert_includes derivation.notes.join(" "), "they are the player"
  end

  # A person left standing in a room this snapshot does not write is a
  # `character_in_a_stub` finding waiting to happen, so the placement goes and
  # the person stays.
  test "somebody standing in a room the snapshot does not write loses the placement" do
    story = seeded_world
    play!(story)
    story.characters.find_by(fullname: "Corbel Ashe").move_to!(story.locations.find_by(name: "The Hallway"))

    corbel = Story::Snapshot::Derivation.new(story).document["characters"].detect { |row| row["fullname"] == "Corbel Ashe" }

    assert_nil corbel["location"]
  end

  # A law the world did not have yet. `The Lunar Cartographer`'s nightly
  # rearrangement was added to its file after the world was seeded, and carrying
  # it into a fork of the graph as it stood makes a file the loader refuses.
  test "a mechanic younger than the line is left behind" do
    story = seeded_world
    play!(story)
    create(:world_mechanic, story: story, name: "The nightly rearrangement", created_at: PLAY_STARTED_AT + 1.hour)

    assert_nil Story::Snapshot::Derivation.new(story).document["mechanics"]
  end

  test "refuses a story with no opening arrival" do
    story = seeded_world
    play!(story)
    story.opening_scene.destroy!

    refusals = Story::Snapshot::Derivation.new(story.reload).refusals

    assert_equal 1, refusals.size
    assert_match "no opening arrival", refusals.first
  end

  test "refuses a story whose opening room is a stub" do
    story = seeded_world
    play!(story)
    story.opening_location.update_columns(detail_level: "stub")

    assert_match "is a stub", Story::Snapshot::Derivation.new(story.reload).refusals.join(" ")
  end

  test "refuses records that say play began before the story did" do
    story = seeded_world
    play!(story)
    story.update_column(:created_at, PLAY_STARTED_AT + 1.day)

    assert_match "is not after the story itself", Story::Snapshot::Derivation.new(story.reload).refusals.join(" ")
  end

  test "the manifest counts what was kept and what was left behind" do
    story = seeded_world
    play!(story)

    manifest = Story::Snapshot::Derivation.new(story).manifest

    assert_equal "2 kept, 1 left behind", manifest["locations"]
    assert_equal "2 kept, 1 left behind", manifest["characters"]
    assert_equal "1 kept, 1 left behind", manifest["connections (edges)"]
  end

  test "reading the derivation writes nothing" do
    story = seeded_world
    play!(story)

    assert_no_difference [ "Story.count", "Location.count", "Character.count", "Item.count", "Scene.count" ] do
      derivation = Story::Snapshot::Derivation.new(story)
      derivation.manifest
      derivation.notes
      derivation.document
    end
    assert_nil story.reload.generation_snapshot
  end
end
