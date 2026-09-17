require "test_helper"

class WorldSeedPhysicalParametersTest < ActiveSupport::TestCase
  def document
    YAML.safe_load_file(Rails.root.join("lib/engine_sweep/worlds/a-dose-beyond-two-doors.yml"))
  end

  test "a starting key can be resolved after its owner is loaded" do
    world = document
    key = world["locations"].first["items"].find { |row| row["name"] == "brass key" }
    world["locations"].first["items"].delete(key)
    world["characters"].first["items"] << key
    story = WorldSeed::Loader.new(world).load!
    edge = LocationConnection.where(location: story.locations, barrier: "keyed").first

    assert_equal "brass key", edge.key_template.name
    assert_equal story.protagonist, edge.key_template.character
  end

  test "export reload preserves physical profiles and barrier key bindings" do
    world = document
    world["locations"].first["items"].first["combustible"] = true
    story = WorldSeed::Loader.new(world).load!
    exported = WorldSeed::Exporter.new(story).document
    exported["story"]["title"] = "A Separate Physical World"
    copy = WorldSeed::Loader.new(exported).load!

    original_items = Item.templates.where(location: story.locations).order(:name).pluck(:name, :use_kind, :combustible)
    assert_equal original_items, Item.templates.where(location: copy.locations).order(:name).pluck(:name, :use_kind, :combustible)
    locks = LocationConnection.where(location: copy.locations, barrier: "keyed")
    assert_equal 2, locks.count
    assert_equal [ "brass key" ], locks.map { |edge| edge.key_template.name }.uniq
    assert_equal "key", locks.first.key_template.use_kind
    assert_not_equal story.id, locks.first.key_template.location.story_id
  end

  test "reseed refreshes profiles without restoring a consumed playthrough copy" do
    story = WorldSeed::Loader.new(document).load!
    game = Playthrough.create!(story: story, character: story.protagonist, current_location: story.opening_location, current_scene: story.scenes.first)
    potion = game.items.find_by!(name: "healing draught")
    potion.update!(location: nil, disposition: "consumed", **Location::Placement.unplaced)
    changed = document
    changed["locations"].first["items"].first["use_kind"] = "drink"
    WorldSeed::Loader.new(changed).load!
    Item::Snapshot.new(game).of_the_room!(story.opening_location)

    assert_equal "consumed", potion.reload.disposition
    assert_not_includes game.items_lying_in(story.opening_location), potion
    assert_not_includes game.carried, potion
    assert_equal 1, game.items.where(template: potion.template).count
    assert_equal "drink", potion.template.reload.use_kind
  end

  test "invalid physical parameters reject the entire world before creating rows" do
    [ ->(world) { world["connections"][1]["key_template"] = "missing key" },
      ->(world) { world["locations"][0]["items"][0]["use_kind"] = "infinite_health" },
      ->(world) { world["locations"][0]["items"][0]["combustible"] = "false" },
      ->(world) { world["locations"][0]["items"][0]["disposition"] = "consumed" } ].each do |change|
      world = document
      change.call(world)
      assert_no_difference [ "Story.count", "Item.count", "LocationConnection.count" ] do
        assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(world).load! }
      end
    end
  end
end
