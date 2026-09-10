require "test_helper"

class Story::PhysicalRepairTest < ActiveSupport::TestCase
  test "repairing a keyed one-way door preserves its key and each game's original opening" do
    story = create(:story)
    here = create(:location, story: story)
    there = create(:location, story: story)
    key = create(:item, character: nil, location: here, use_kind: "key")
    edge = create(:location_connection, location: here, connected_location: there,
                                        barrier: "keyed", key_template: key, hazard: "drop", hazard_die: 4)
    first = create(:playthrough, story: story, current_location: here)
    second = create(:playthrough, story: story, current_location: there)
    receipt = Playthrough::Passage.open!(first, edge, means: "key", item: first.items.find_by!(template: key)).sole

    result = Story::Repair.new(story).apply!.find { |row| row.code == :one_way_connection }

    assert result.repaired?, result.message
    back = LocationConnection.find_by!(location: there, connected_location: here)
    assert_equal "keyed", back.barrier
    assert_equal key, back.key_template
    assert_nil back.hazard
    assert back.open_for?(first)
    assert_not back.open_for?(second)
    assert_equal receipt.attributes.slice("playthrough_id", "means", "opened_at", "opened_by_item_id"),
                 back.passages.sole.attributes.slice("playthrough_id", "means", "opened_at", "opened_by_item_id")
  end

  test "contradictory barriers are manual even when their travel distance can be repaired" do
    story = create(:story)
    here = create(:location, story: story)
    there = create(:location, story: story)
    out = create(:location_connection, location: here, connected_location: there, barrier: "open")
    back = create(:location_connection, location: there, connected_location: here, barrier: "jammed", distance: "days away")
    repair = Story::Repair.new(story)

    assert_includes repair.manual.map(&:code), :connection_barriers_disagree
    assert_not_includes repair.plan.map(&:code), :connection_barriers_disagree
    repair.apply!

    assert_equal out.distance, back.reload.distance
    assert_equal "jammed", back.barrier
    assert_equal "open", out.reload.barrier
  end

  test "duplicate template repair keeps consumed identity across snapshot, backfill and reseed" do
    story, original, survivor, first, spent = duplicate_with_consumed_copy
    second = create(:playthrough, story: story, character: story.protagonist, current_location: story.opening_location)
    # This game has two independently snapshotted objects: the repair must not
    # discard either to resolve a duplicate on its behalf.
    assert_equal 2, second.items.where(template: [ original, survivor ]).count
    assert_includes Story::Repair.new(story).manual.map(&:code), :duplicate_items
    second.destroy!

    result = Story::Repair.new(story).apply!.find { |row| row.code == :duplicate_items }

    assert result.repaired?, result.message
    assert_equal survivor.id, spent.reload.template_id
    assert_equal "consumed", spent.disposition
    Item::Snapshot.new(first.reload).of_the_room!(story.opening_location)
    Item::LayerBackfill.new(story).run
    WorldSeed::Loader.new(WorldSeed.checked_in_document(story.title)).load!
    Item::TemplateRefresh.new(story.reload).refresh!
    Item::Snapshot.new(first.reload).of_the_room!(story.opening_location)

    assert_equal [ spent.id ], first.items.where(template: survivor).pluck(:id)
    assert_not first.items_lying_in(story.opening_location).exists?(template: survivor)
    assert_equal "consumed", spent.reload.disposition
    fresh = create(:playthrough, story: story, character: story.protagonist, current_location: story.opening_location)
    assert_equal "intact", fresh.items.find_by!(template: survivor).disposition
  end

  test "folding a duplicate key preserves the lock's reference without changing a game's item" do
    story, original, survivor, _game, spent = duplicate_with_consumed_copy
    original.update!(use_kind: "key")
    survivor.update!(use_kind: "key")
    edge = LocationConnection.find_by!(location: story.opening_location)
    edge.update!(barrier: "keyed", key_template: original)
    before = spent.attributes.except("template_id", "updated_at")

    result = Story::Repair.new(story).apply!.find { |row| row.code == :duplicate_items }

    assert result.repaired?, result.message
    assert_equal "keyed", edge.reload.barrier
    assert_equal survivor.id, edge.key_template_id
    assert_equal before, spent.reload.attributes.except("template_id", "updated_at")
  end

  test "a canonical non-key cannot replace the key named by a locked door" do
    story, original, _survivor, _game, _spent = duplicate_with_consumed_copy
    original.update!(use_kind: "key")
    edge = LocationConnection.find_by!(location: story.opening_location)
    edge.update!(barrier: "keyed", key_template: original)
    repair = Story::Repair.new(story)

    assert_includes repair.manual.map(&:code), :duplicate_items
    assert_not_includes repair.plan.map(&:code), :duplicate_items
    repair.apply!
    assert_equal original, edge.reload.key_template
  end

  private

  def duplicate_with_consumed_copy
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    original = Item.templates.lying_in(story.opening_location).first!
    name = original.name
    game = create(:playthrough, story: story, character: story.protagonist,
                               current_location: story.opening_location, current_scene: story.opening_scene)
    spent = game.items.find_by!(template: original)
    spent.update!(disposition: "consumed", location: nil, character: nil, x: nil, y: nil)
    scene = create(:scene, story: story, location: story.opening_location,
                           previous_scene: game.current_scene, acted_on: spent)
    game.update!(current_scene: scene)
    original.update!(name: name.swapcase)
    survivor = Item.create!(original.attributes.except("id", "created_at", "updated_at").merge("name" => name))
    [ story, original, survivor, game, spent ]
  end
end
