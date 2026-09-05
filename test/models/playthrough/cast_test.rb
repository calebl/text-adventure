require "test_helper"

# WHO THIS PARTY CAN SPEAK TO, TAKE A SWING AT, OR BE TOLD ABOUT, HERE, IN THIS
# GAME.
#
# `Playthrough#cast_in` is the exact counterpart of `#items_lying_in` one table
# over, and it is here for that method's reason: `Character.present_in` is the
# WORLD's answer, and since a playthrough can take somebody's last hit point the
# world's answer is no longer this game's. Before it, `talk to Rowe` on a corpse
# resolved, reached `InteractionAgent`, and the corpse answered.
#
# THE FOUR READERS EACH HAVE A TEST HERE, because a reader left on the world's
# answer is exactly the shape of the defect this closes.
class Playthrough::CastTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @room = create(:location, story: @story, name: "The Bell Chamber")
    @protagonist = create(:character, :protagonist, story: @story, level: 3, hit_die: 8)
    @rowe = create(:character, story: @story, location: @room, fullname: "Halkett Rowe")
    @game = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
  end

  def kill!(character) = Playthrough::Turn.new(@game).harm!(character, character.max_hp)

  test "the room's cast is the world's, plus the party" do
    assert_includes @game.cast_in(@room), @rowe
    assert_includes @game.cast_in(@room), @protagonist
  end

  test "nowhere has nobody in it" do
    assert_equal [], @game.cast_in(nil)
  end

  test "a body this game has killed is out of this game's cast" do
    kill!(@rowe)

    assert_not_includes @game.cast_in(@room), @rowe
    assert_includes Character.present_in(@room), @rowe, "the world still says he is standing there"
    assert_equal @room, @rowe.reload.location, "and nothing moved him"
  end

  test "another game of the same world still meets him alive" do
    other = create(:playthrough, story: @story, character: @protagonist, current_location: @room)
    kill!(@rowe)

    assert_not_includes @game.cast_in(@room), @rowe
    assert_includes other.cast_in(@room), @rowe
  end

  # READER ONE: the closed set the classifier offers a model, and the one the
  # fixed grammar matches a typed name against.
  test "the classifier stops offering a corpse to talk to" do
    classifier = Playthrough::Classifier.new(@game)
    assert_includes classifier.characters_here, @rowe

    kill!(@rowe)

    assert_not_includes classifier.characters_here, @rowe
    assert_not_includes classifier.offered_for(:talk), @rowe
    assert_not_includes classifier.offered_for(:attack), @rowe
  end

  # READER TWO: what the prose is told about the room.
  test "the narrator is not told about somebody the player can no longer speak to" do
    kill!(@rowe)

    assert_not_includes Playthrough::Moment.new(@game).others, @rowe
  end

  # READER THREE: the cast a turn snapshots onto its `Scene`.
  test "a turn records this game's cast and not the world's" do
    kill!(@rowe)
    scene = create(:scene, story: @story, location: @room)

    assert_not_includes Playthrough::Turn.new(@game).cast_of(scene), @rowe
  end

  # READER FOUR: the `rake game:mechanics` read-out, through the classifier --
  # which is what `rake game:sweep`'s `present:` asserts.
  test "the mechanics read-out drops him from present" do
    engine = Playthrough::Mechanics.new(@game, model: false)
    assert_includes engine.state.present, @rowe

    kill!(@rowe)

    assert_not_includes engine.state.present, @rowe
  end

  # AND `Character.present_in` STAYS THE WORLD'S ANSWER, because
  # `Character::Registry`, `EngineSweep::Invariants#cast_unmoved`,
  # `Playthrough::Vitals::Snapshot` and the doctor all legitimately want it.
  test "the world's own reader is untouched" do
    kill!(@rowe)

    assert_equal [ @rowe ], Character.present_in(@room).to_a
  end
end
