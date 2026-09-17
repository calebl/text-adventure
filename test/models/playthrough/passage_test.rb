require "test_helper"

class Playthrough::PassageTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @here = create(:location, story: @story)
    @there = create(:location, story: @story)
    @door = create(:location_connection, location: @here, connected_location: @there, barrier: "jammed")
    @back = create(:location_connection, location: @there, connected_location: @here, barrier: "jammed")
    @game = create(:playthrough, story: @story, current_location: @here)
  end

  test "opening a door affects both directions in one game and preserves the world's barriers" do
    other = create(:playthrough, story: @story, current_location: @here)
    assert_not @door.open_for?(@game)

    assert_difference "Playthrough::Passage.count", 2 do
      Playthrough::Passage.open!(@game, @door, means: "force")
    end

    assert @door.open_for?(@game)
    assert @back.open_for?(@game)
    assert_not @door.open_for?(other)
    assert_equal "jammed", @door.reload.barrier
    assert_equal "jammed", @back.reload.barrier
  end

  test "reopening preserves its original receipt" do
    first = Playthrough::Passage.open!(@game, @door, means: "force")
    stamp = first.first.opened_at

    assert_no_difference "Playthrough::Passage.count" do
      Playthrough::Passage.open!(@game.reload, @door.reload, means: "lever")
    end

    assert_equal stamp, first.first.reload.opened_at
    assert_equal "force", first.first.means
  end

  test "a foreign door or item cannot be attributed to this game" do
    other = create(:playthrough)
    foreign_item = create(:item, playthrough: other, character: nil, location: nil)

    assert_no_difference "Playthrough::Passage.count" do
      assert_raises(ActiveRecord::RecordInvalid) do
        Playthrough::Passage.open!(@game, @door, means: "key", item: foreign_item)
      end
      assert_raises(ActiveRecord::RecordInvalid) do
        Playthrough::Passage.open!(other, @door, means: "force")
      end
    end
    assert_not @door.open_for?(other)
  end

  test "a keyed door accepts only a key template from its world" do
    key = create(:item, character: nil, location: @here, use_kind: "key")
    @door.update!(barrier: "keyed", key_template: key)
    copy = Item::Snapshot.new(@game).of_the_room!(@here).find { |item| item.template_id == key.id }

    @door.key_template = copy
    assert_not @door.valid?
    assert_includes @door.errors.attribute_names, :key_template
  end

  test "an open ordinary door needs no playthrough row" do
    @door.update!(barrier: "open")

    assert @door.open_for?(@game)
    assert_empty @game.passages
  end
end
