require "test_helper"

class ItemDispositionTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @room = create(:location, story: @story)
    @player = create(:character, :protagonist, story: @story)
    @template = create(:item, character: nil, location: @room, use_kind: "healing", combustible: true)
    @game = create(:playthrough, story: @story, character: @player, current_location: @room)
    @copy = @game.items.find_by!(template: @template)
  end

  test "a spent copy is excluded from possession readers without deleting its identity" do
    @copy.update!(disposition: "consumed", location: nil, character: nil, x: nil, y: nil)

    assert_empty @game.carried
    assert_empty @game.items_lying_in(@room)
    assert_not @copy.carried?
    assert_not @copy.held?
    assert_not @copy.lying?
    assert_equal "intact", @template.reload.disposition
    assert_equal @template.id, @copy.template_id
  end

  test "revisiting does not recreate the consumed copy and another game still receives an intact one" do
    @copy.update!(disposition: "consumed", location: nil, character: nil, x: nil, y: nil)

    assert_no_difference "Item.count" do
      Item::Snapshot.new(@game.reload).of_the_room!(@room)
    end
    other = create(:playthrough, story: @story, character: @player, current_location: @room)

    assert_equal [ @copy.id ], @game.items.where(template: @template).pluck(:id)
    assert_equal "intact", other.items.find_by!(template: @template).disposition
  end

  test "world templates cannot be spent and a spent copy cannot remain in a hand or on a floor" do
    @template.disposition = "burned"
    assert_not @template.valid?
    @copy.disposition = "burned"
    assert_not @copy.valid?
    @copy.assign_attributes(location: nil, character: @player)
    assert_not @copy.valid?
  end

  test "the use profile is a closed world parameter and ordinary food does not heal wounds" do
    assert_equal Item::HEALING_POINTS, @copy.healing_points
    @copy.use_kind = "food"
    assert @copy.consumable?
    assert_equal 0, @copy.healing_points
    @copy.use_kind = "execute arbitrary properties"
    assert_not @copy.valid?
  end

  test "refreshing template metadata does not restore a spent copy" do
    @copy.update!(disposition: "consumed", location: nil, character: nil, x: nil, y: nil)
    @template.update!(description: "A clearer description of this draught.")
    Item::TemplateRefresh.new(@story).refresh!

    assert_equal "consumed", @copy.reload.disposition
    assert_not @copy.carried?
    assert_equal @template.description, @copy.description
  end
end
