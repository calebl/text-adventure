require "test_helper"

# The destructive one, so this counts every table before and after rather than
# trusting the `dependent:` options -- some of them are `nullify`, one of them
# is `restrict_with_error`, and the join rows for an edge are cleared by two
# separate HABTM declarations. What is asserted here is that a deleted story
# leaves nothing behind AND takes nothing that was not its.
class Story::DeletionTest < ActiveSupport::TestCase
  # Everything a story can own, all at once.
  def full_story(universe: nil)
    story = create(:story, universe: universe || create(:universe))
    opening = create(:location, story: story, name: "Your Office")
    street = create(:location, :stub, story: story, name: "The Street")
    [ [ opening, street ], [ street, opening ] ].each do |from, to|
      create(:location_connection, location: from, connected_location: to, distance: "adjacent", travel_method: "walking")
    end

    protagonist = create(:character, :protagonist, story: story)
    other = create(:character, story: story)
    create(:item, character: other)

    scene = create(:scene, :opening, story: story, location: opening, story_timestamp: story.start_time)
    scene.characters = [ protagonist, other ]
    later = create(:scene, story: story, location: opening, previous_scene: scene, story_timestamp: story.start_time + 5.minutes)
    create(:interaction, character: other, scene: later, location: opening)

    create(:playthrough, story: story, character: protagonist, current_location: opening, current_scene: later)

    mechanic = create(:world_mechanic, story: story)
    event = create(:world_event, story: story, world_mechanic: mechanic)
    event.locations = [ opening ]

    story
  end

  def row_counts
    {
      stories: Story.count, universes: Universe.count, races: Race.count,
      characters: Character.count, items: Item.count, interactions: Interaction.count,
      locations: Location.count, connections: LocationConnection.count,
      scenes: Scene.count, playthroughs: Playthrough.count,
      mechanics: WorldMechanic.count, events: WorldEvent.count,
      character_scenes: ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM characters_scenes"),
      event_locations: ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM locations_world_events")
    }
  end

  test "the manifest counts what will go and names the story" do
    story = full_story
    deletion = Story::Deletion.new(story)

    assert_equal story.title, deletion.confirmation
    assert_equal 2, deletion.manifest.fetch("characters")
    assert_equal 1, deletion.manifest.fetch("items")
    assert_equal 1, deletion.manifest.fetch("interactions")
    assert_equal 2, deletion.manifest.fetch("locations")
    assert_equal 2, deletion.manifest.fetch("connection rows")
    assert_equal 2, deletion.manifest.fetch("scenes")
    assert_equal 1, deletion.manifest.fetch("playthroughs")
    assert_equal 1, deletion.manifest.fetch("world mechanics")
    assert_equal 1, deletion.manifest.fetch("world events")
  end

  # A TYPO IN A STORY ID MUST NOT DESTROY A WORLD. The confirmation is the
  # title, because an id is exactly the thing that gets mistyped.
  test "refuses to delete without the story's own title" do
    story = full_story
    before = row_counts

    assert_raises(Story::Deletion::NotConfirmed) { Story::Deletion.new(story).destroy!(confirm: "yes") }
    assert_raises(Story::Deletion::NotConfirmed) { Story::Deletion.new(story).destroy!(confirm: story.id.to_s) }
    assert_raises(Story::Deletion::NotConfirmed) { Story::Deletion.new(story).destroy!(confirm: "") }
    assert_equal before, row_counts
  end

  test "accepts the title with stray whitespace or a different case" do
    story = full_story
    deletion = Story::Deletion.new(story)

    assert deletion.confirmed?("  #{story.title.upcase}\n")
  end

  test "deleting a story removes everything that belonged to it and nothing else" do
    full_story
    doomed = full_story
    doomed_races = Race.where(universe_id: doomed.universe_id).count
    before = row_counts

    removed = Story::Deletion.new(doomed).destroy!(confirm: doomed.title)
    after = row_counts

    assert_equal before[:stories] - 1, after[:stories]
    assert_equal before[:universes] - 1, after[:universes], "the universe was this story's alone"
    assert_equal before[:races] - doomed_races, after[:races]
    assert_equal before[:characters] - 2, after[:characters]
    assert_equal before[:items] - 1, after[:items]
    assert_equal before[:interactions] - 1, after[:interactions]
    assert_equal before[:locations] - 2, after[:locations]
    assert_equal before[:connections] - 2, after[:connections]
    assert_equal before[:scenes] - 2, after[:scenes]
    assert_equal before[:playthroughs] - 1, after[:playthroughs]
    assert_equal before[:mechanics] - 1, after[:mechanics]
    assert_equal before[:events] - 1, after[:events]
    # The join rows for the cast and for what the world touched, which no
    # `dependent:` option covers -- both HABTM declarations do.
    assert_equal before[:character_scenes] - 2, after[:character_scenes]
    assert_equal before[:event_locations] - 1, after[:event_locations]

    assert_equal deletion_manifest_total(removed), removed.values.sum
  end

  test "the other story sharing a universe survives, and so does the universe" do
    universe = create(:universe)
    kept = full_story(universe: universe)
    doomed = full_story(universe: universe)
    races = Race.where(universe: universe).count
    deletion = Story::Deletion.new(doomed)

    assert deletion.universe_shared?
    assert_equal [ kept.title ], deletion.universe_stories.pluck(:title)
    assert_match(/KEPT/, deletion.universe_disposition)

    deletion.destroy!(confirm: doomed.title)

    assert Story.exists?(kept.id)
    assert Universe.exists?(universe.id)
    assert_equal races, Race.where(universe: universe).count
    assert_equal 2, Character.where(story: kept).count
    assert_equal 2, Location.where(story: kept).count
  end

  test "a universe nothing else uses goes with the story" do
    story = full_story
    deletion = Story::Deletion.new(story)

    assert_not deletion.universe_shared?
    assert_match(/destroyed, nothing else uses them/, deletion.universe_disposition)

    universe_id = story.universe_id
    deletion.destroy!(confirm: story.title)

    assert_not Universe.exists?(universe_id)
    assert_empty Race.where(universe_id: universe_id)
  end

  # Every foreign key in the schema is enforced, so a wrong destruction order
  # raises rather than orphaning. Deleting the last story in the database has to
  # leave the story tables completely empty.
  test "deleting the only story leaves no orphans at all" do
    story = full_story
    Story::Deletion.new(story).destroy!(confirm: story.title)

    counts = row_counts
    counts.each do |table, count|
      assert_equal 0, count, "#{table} still holds #{count} row(s) after the only story was deleted"
    end
  end

  # A story that cannot be played is still a story: the tool has to remove the
  # broken ones, which is most of what it will be pointed at.
  test "deletes a story that has nothing in it" do
    story = create(:story)

    assert_equal 0, Story::Deletion.new(story).destroy!(confirm: story.title).values.sum
    assert_not Story.exists?(story.id)
  end

  private

  def deletion_manifest_total(removed)
    removed.values.sum
  end
end
