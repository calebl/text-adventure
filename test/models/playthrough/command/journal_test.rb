require "test_helper"

class Playthrough::Command::JournalTest < ActiveSupport::TestCase
  test "the factory builds a journal with no fabricated checkpoint" do
    assert_not build(:playthrough_command_journal).saved?("take")
  end

  test "a throw keeps its original die and applied blow through JSON and a new instance" do
    game = create(:playthrough, :started)
    coin = lying_here(game, game.current_location, name: "red coin")
    target = create(:character, story: game.story, location: game.current_location)
    check = Character::Check.new(ability: :strength, score: 15, penalty: 0, die: 3)
    blow = Playthrough::Turn.new(game).strike!(game.character, target, round: 1, damage: 1)
    result = Playthrough::Turn::Throw.struck(coin, target, check, blow: blow)
    submission = create(:playthrough_command, playthrough: game, journal: { "version" => 1 })
    Playthrough::Command::Journal.with(submission) do
      Playthrough::Command::Journal.commit("throw") { result }
    end
    restored = Playthrough::Command::Journal.new(submission.reload).read("throw")
    assert_equal result, restored
    assert_equal 3, restored.check.die
    assert_equal blow, restored.blow
  end

  test "a failed atomic receipt cannot leave its effect committed" do
    game = create(:playthrough, :started)
    coin = lying_here(game, game.current_location, name: "red coin")
    submission = create(:playthrough_command, playthrough: game)
    Playthrough::Command::Journal.with(submission) do
      assert_raises(ArgumentError) do
        Playthrough::Command::Journal.commit("bad") do
          coin.update!(location: nil)
          Object.new # An unsupported receipt must fail the whole transaction.
        end
      end
      assert_not Playthrough::Command::Journal.saved?("bad")
    end
    assert_equal game.current_location, coin.reload.location
  end
end
