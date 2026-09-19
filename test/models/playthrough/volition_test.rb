require "test_helper"

# `Playthrough::NpcAction`'s tests one class over, and the same three questions:
# what is in the closed set, what happens when a token that was in it is no
# longer in it, and what the receipt says either way.
class Playthrough::VolitionTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Counting Room")
    @next_door = create(:location, story: @story, name: "The Stairwell")
    create(:location_connection, location: @room, connected_location: @next_door)
    create(:location_connection, location: @next_door, connected_location: @room)
    @player = create(:character, :protagonist, story: @story)
    @game = create(:playthrough, story: @story, character: @player, current_location: @room)
    @clerk = create(:character, :driven, story: @story, location: @room, fullname: "Odile Vance")
  end

  def volition(character = @clerk, location: @room)
    Playthrough::Volition.new(@game, character, location: location, round: 1)
  end

  # --- the closed set -------------------------------------------------------

  test "waiting is always offered" do
    assert_includes volition.choices.keys, Playthrough::Volition::WAIT
  end

  test "one move token per way out of the room they are standing in" do
    assert_includes volition.choices.keys, "move:#{@next_door.id}"
    assert_equal 1, volition.choices.keys.count { |token| token.start_with?("move:") }
  end

  test "one take token per thing lying in this game's copy of the room" do
    item = create(:item, character: nil, location: @room, playthrough: @game)

    assert_includes volition.choices.keys, "take:#{item.id}"
  end

  # THE ENGINE REFUSES THE PLAYER A THING THAT DOES NOT MOVE
  # (`Playthrough::Refusal`'s `:immovable`), so it must not hand one to
  # somebody else in the same room. One rule, both sides of the counter.
  test "a thing that does not move for anybody is not offered to anybody" do
    press = create(:item, character: nil, location: @room, playthrough: @game, bulk: "immovable")

    assert_not_includes volition.choices.keys, "take:#{press.id}"
  end

  test "the world's own template is not offered -- only this game's copy is" do
    template = create(:item, character: nil, location: @room, playthrough: nil)

    assert_not_includes volition.choices.keys, "take:#{template.id}"
  end

  test "a held thing is offered as a gift only while the player is standing here" do
    held = create(:item, character: @clerk, location: nil, playthrough: @game)

    assert_includes volition.choices.keys, "give:#{held.id}"

    @game.update!(current_location: @next_door)

    assert_not_includes volition.choices.keys, "give:#{held.id}"
  end

  test "attack and speak are not on the list, whoever is in the room" do
    foe = create(:character, :monster, story: @story, location: @room)
    tokens = volition(foe).choices.keys

    assert_empty tokens.grep(/attack|speak|ceasefire|accept/)
  end

  test "somebody who is not in the room is offered nothing but waiting" do
    elsewhere = create(:character, story: @story, location: @next_door)

    assert_equal [ Playthrough::Volition::WAIT ], volition(elsewhere).choices.keys
  end

  # --- applying -------------------------------------------------------------

  test "a walk writes this game's whereabouts and never the world's" do
    result = volition.apply!("move:#{@next_door.id}")

    assert_predicate result, :applied?
    assert_equal @next_door, @game.location_of(@clerk)
    assert_equal @room, @clerk.reload.location, "characters.location_id is the world layer"
  end

  test "a walk ends any travel agreement" do
    @game.npc_states.create!(character: @clerk, location: @room, following: true)
    volition.apply!("move:#{@next_door.id}")

    assert_not @game.npc_states.find_by(character: @clerk).following?
  end

  test "taking moves this game's copy into their hands" do
    item = create(:item, character: nil, location: @room, playthrough: @game)
    volition.apply!("take:#{item.id}")

    assert_equal @clerk, item.reload.character
    assert_nil item.location
  end

  test "giving puts it in the player's hands" do
    held = create(:item, character: @clerk, location: nil, playthrough: @game)
    volition.apply!("give:#{held.id}")

    assert_nil held.reload.character
    assert_nil held.location
    assert_includes @game.carried, held
  end

  test "waiting is a receipt that moved nothing" do
    result = volition.apply!(Playthrough::Volition::WAIT)

    assert_equal "none", result.status
    assert_equal "none", result.serves
    assert_equal 1, @game.volitions.count
  end

  # --- the set is rebuilt at apply time -------------------------------------

  test "a token that was offered and is no longer available is rejected and moves nothing" do
    item = create(:item, character: nil, location: @room, playthrough: @game)
    token = "take:#{item.id}"

    assert_includes volition.choices.keys, token

    item.update!(location: nil, character: @player)
    result = volition.apply!(token)

    assert_equal "rejected", result.status
    assert_equal @player, item.reload.character, "a rejected pick moves nothing"
  end

  # A STAGED FIXTURE ASSIGNS ITS OWN ROW IDS SO A MEASURED REQUEST IS
  # BYTE-IDENTICAL RUN TO RUN, and those ids are negative
  # (`Eval::Dialogue::Stage`). A token pattern that matched only digits built a
  # token out of one, offered it, accepted it back, and then matched no branch
  # -- applying an act with no sentence for it.
  test "a row with a negative id is named, offered and acted on like any other" do
    stairs = create(:location, story: @story, name: "The Back Stair", id: -910002)
    create(:location_connection, location: @room, connected_location: stairs)

    assert_includes volition.choices.keys, "move:-910002"

    result = volition.apply!("move:-910002")

    assert_predicate result, :applied?
    assert_equal stairs, @game.location_of(@clerk)
  end

  test "a token the set never held is rejected" do
    result = volition.apply!("attack:#{@player.id}")

    assert_equal "rejected", result.status
  end

  test "a rejected pick is still on the record, so the tally is honest" do
    volition.apply!("move:999999")

    assert_equal 1, @game.volitions.where(status: "rejected").count
  end

  # --- the receipt and the row ---------------------------------------------

  test "every outcome writes exactly one row, carrying the engine's own sentence" do
    volition.apply!("move:#{@next_door.id}")
    row = @game.volitions.sole

    assert_equal "applied", row.status
    assert_equal @room, row.location
    assert_includes row.fact, @clerk.fullname
    assert_includes row.fact, @next_door.name
  end

  test "the row refuses a character from another story" do
    other = create(:character, story: create(:story))
    row = Playthrough::Volition::Record.new(playthrough: @game, character: other, location: @room,
                                            chosen: "wait", status: "none", fact: "x", serves: "none", round: 1)

    assert_not row.valid?
    assert_includes row.errors[:character], "must belong to this story"
  end

  test "the row refuses the player" do
    row = Playthrough::Volition::Record.new(playthrough: @game, character: @player, location: @room,
                                            chosen: "wait", status: "none", fact: "x", serves: "none", round: 1)

    assert_not row.valid?
    assert_includes row.errors[:character], "must be an NPC"
  end

  # --- the room loop --------------------------------------------------------

  test "everybody in the room gets one turn, in id order, and the player gets none" do
    second = create(:character, :driven, story: @story, location: @room)
    Playthrough::Volition.run!(@game, location: @room, round: 1)

    assert_equal [ @clerk.id, second.id ].sort, @game.volitions.pluck(:character_id).sort
  end

  test "a foe does not also wander off -- the riposte acted for them" do
    create(:character, :monster, story: @story, location: @room)
    Playthrough::Volition.run!(@game, location: @room, round: 1)

    assert_equal [ @clerk.id ], @game.volitions.pluck(:character_id)
  end

  test "a game that is over writes nothing" do
    @game.update!(ended_at: Time.current)

    assert_empty Playthrough::Volition.run!(@game, location: @room, round: 1)
    assert_equal 0, @game.volitions.count
  end

  # --- determinism ----------------------------------------------------------

  # THE PROPERTY THAT LETS `rake game:sweep` ASSERT WHAT SOMEBODY DID: the
  # decision is a function of the records and this game's own seed, so
  # replaying the turn replays the decision. The records are put back between
  # the two, because a decision that MOVED somebody is a turn the second run
  # would not be starting from.
  test "the same turn of the same game decides the same way every time" do
    first = volition.decide!

    @game.volitions.delete_all
    @game.npc_states.delete_all
    @game.items.each { |item| item.update!(character: nil, location: @room) }

    assert_equal first.chosen, volition.decide!.chosen
  end

  # NO PURSUIT, NO BEHAVIOUR -- and it is a hard nothing rather than a small
  # chance of something, which is what lets this ship without a backfill:
  # every world nobody has opted in behaves exactly as it did yesterday.
  test "somebody the world has said nothing about does nothing at all" do
    quiet = create(:character, story: @story, location: @room)

    assert_nil volition(quiet).decide!
    assert_equal 0, @game.volitions.count
  end

  test "the room loop skips them too, and still gives a turn to everybody else" do
    create(:character, story: @story, location: @room)
    Playthrough::Volition.run!(@game, location: @room, round: 1)

    assert_equal [ @clerk.id ], @game.volitions.pluck(:character_id)
  end
end
