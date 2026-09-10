require "test_helper"

class Playthrough::MomentExperienceTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @room = create(:location, story: @story)
    @elsewhere = create(:location, story: @story)
    @player = create(:character, :protagonist, story: @story, fullname: "Cal", nickname: "Cal", level: 10)
    @npc = create(:character, story: @story, location: @room, fullname: "Maren", nickname: "Maren", level: 10)
    @scene = create(:scene, story: @story, location: @room, characters: [ @player, @npc ])
    @game = create(:playthrough, story: @story, character: @player, current_location: @room, current_scene: @scene)
  end

  test "a blow with no scene reaches the injured character with the current fighting state" do
    Playthrough::Turn.new(@game).strike!(@player, @npc, damage: @npc.max_hp - 1, round: 1)
    assert_equal @scene.id, @game.reload.current_scene_id

    prompt = InteractionAgent.new(@npc, playthrough: @game).character_prompt("What happened to you?")

    assert_includes prompt, "Your own condition: badly hurt (1 of #{@npc.max_hp})."
    assert_includes prompt, "You are currently fighting Cal."
    assert_includes prompt, "Cal struck Maren for #{@npc.max_hp - 1} hit points"
  end

  test "a ceasefire changes current conflict without erasing the injury or its cause" do
    Playthrough::Turn.new(@game).strike!(@player, @npc, damage: 2, round: 1)
    state = @game.npc_states.create!(character: @npc, location: @room)
    state.make_peace!

    prompt = InteractionAgent.new(@npc, playthrough: @game).character_prompt("Are we at peace?")

    assert_includes prompt, "You have a ceasefire with Cal; it still holds."
    assert_includes prompt, "Cal struck Maren for 2 hit points"
    assert_not_includes prompt, "You are currently fighting"
  end

  test "a remote attack is not an unwounded bystander's experience" do
    victim = create(:character, story: @story, location: @elsewhere, fullname: "Orren", level: 10)
    turn = Playthrough::Turn.new(@game)
    turn.stand_in!(@elsewhere)
    turn.strike!(@player, victim, damage: 2, round: 1)
    turn.stand_in!(@room)

    prompt = InteractionAgent.new(@npc, playthrough: @game).character_prompt("What happened while I was away?")

    assert_includes prompt, "Your own condition: unhurt."
    assert_not_includes prompt, "Orren"
    assert_not_includes prompt, "recorded blow"
    assert_not_includes prompt, "currently fighting"
  end

  test "a previous scene's command and inscription are not disclosed to an absent character" do
    note = create(:item, :readable, location: @elsewhere, character: nil)
    scene = create(:scene, story: @story, location: @elsewhere, characters: [ @player ],
                           typed: "read the hidden password", resolved_action: "examine", acted_on: note)
    @game.update!(current_scene: scene)

    prompt = InteractionAgent.new(@npc, playthrough: @game).character_prompt("Hello.")

    assert_not_includes prompt, "hidden password"
    assert_not_includes prompt, note.inscription
  end

  test "a game with no assigned player still builds the NPC context" do
    @game.update!(character: nil)
    @npc.update!(hostile: true)
    prompt = InteractionAgent.new(@npc, playthrough: @game).character_prompt("Hello.")

    assert_includes prompt, "Your own condition: unhurt."
    assert_not_includes prompt, "You are currently fighting"
  end

  test "another game neither inherits the wound nor recalls its blow" do
    Playthrough::Turn.new(@game).strike!(@player, @npc, damage: 2, round: 1)
    fresh = create(:playthrough, story: @story, character: @player, current_location: @room, current_scene: @scene)
    prompt = InteractionAgent.new(@npc, playthrough: fresh).character_prompt("Hello.")

    assert_includes prompt, "Your own condition: unhurt."
    assert_not_includes prompt, "recorded blow"
    assert_not_includes prompt, "currently fighting"
  end
end
