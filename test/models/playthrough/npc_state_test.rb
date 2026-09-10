require "test_helper"

class Playthrough::NpcStateTest < ActiveSupport::TestCase
  setup do
    @game = create(:playthrough, :started)
    @person = create(:character, story: @game.story, location: @game.current_location, age: 32, sex: "female")
  end

  test "a character has one state per game and another game has its own state" do
    create(:playthrough_npc_state, playthrough: @game, character: @person)
    assert_not build(:playthrough_npc_state, playthrough: @game, character: @person).valid?

    second = create(:playthrough, story: @game.story)
    assert build(:playthrough_npc_state, playthrough: second, character: @person).valid?
  end

  test "state cannot place another story's character or cross its world boundary" do
    assert_not build(:playthrough_npc_state, playthrough: @game, character: create(:character)).valid?
    assert_not build(:playthrough_npc_state, playthrough: @game, character: @person, location: create(:location)).valid?
  end

  test "destroying a game deletes its states without moving the world character" do
    create(:playthrough_npc_state, playthrough: @game, character: @person)
    original = @person.location_id
    @game.destroy!

    assert_empty Playthrough::NpcState.where(character: @person)
    assert_equal original, @person.reload.location_id
  end

  test "deleting a room leaves its per-game residents nowhere" do
    room = create(:location, story: @game.story)
    state = create(:playthrough_npc_state, playthrough: @game, character: @person, location: room)
    room.destroy!

    assert_nil state.reload.location_id
    assert_not_includes @game.characters_located_in(@game.current_location), @person
  end
end
