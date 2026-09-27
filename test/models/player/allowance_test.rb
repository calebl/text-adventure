require "test_helper"

# THE SPEND GATE. Nothing here calls a model: spend is written as the receipts
# a call would have left, and the gate is asked about them.
class Player::AllowanceTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 9, 15, 12)

  setup do
    @player = create(:player, monthly_limit_usd: BigDecimal("0.10"))
    @game = create(:playthrough, :started, player: @player)
  end

  def allowance = Player::Allowance.new(@player, now: NOW)

  def spend_on_chat(input:, output:, at: NOW, model: create(:model))
    chat = create(:chat, player: @player, model: model)
    create(:message, :assistant, chat: chat, model: model, input_tokens: input, output_tokens: output, created_at: at)
  end

  test "chat spend is priced from the registry" do
    spend_on_chat(input: 1_000_000, output: 100_000) # 0.30 + 0.12 per the factory's price
    assert_in_delta 0.42, allowance.spent.to_f, 1e-9
  end

  test "a model the registry cannot price is charged dear, never free" do
    unpriced = create(:model, model_id: "somebody/unlisted", pricing: {})
    spend_on_chat(input: 1_000, output: 1_000, model: unpriced)
    assert_in_delta (15 + 75) / 1000.0, allowance.spent.to_f, 1e-9
  end

  test "System One receipts count, and so does a call filed under no playthrough" do
    create(:system_one_receipt, player: @player, created_at: NOW)
    create(:system_one_receipt, player: @player, cost_usd: 0.01, created_at: NOW)
    assert_in_delta 0.012, allowance.spent.to_f, 1e-9
  end

  test "last month's spend and other players' spend do not count" do
    create(:system_one_receipt, player: @player, cost_usd: 5, created_at: NOW - 1.month)
    create(:system_one_receipt, cost_usd: 5, created_at: NOW)
    spend_on_chat(input: 1_000_000, output: 0, at: NOW.beginning_of_month - 1.second)
    assert_equal 0, allowance.spent
  end

  test "every unfinished turn holds a reservation" do
    create(:playthrough_command, playthrough: @game, status: "pending")
    create(:playthrough_command, playthrough: @game, status: "running")
    create(:playthrough_command, playthrough: @game, status: "completed")
    assert_equal Player::Allowance::TURN_RESERVATION_USD * 2, allowance.reserved
  end

  test "a turn is admitted only while spend, holds and its own reservation fit" do
    create(:system_one_receipt, player: @player, cost_usd: 0.04, created_at: NOW)
    assert allowance.admits_turn?, "0.04 + 0.03 <= 0.10"

    create(:playthrough_command, playthrough: @game, status: "pending")
    assert allowance.admits_turn?, "0.04 + 0.03 + 0.03 = 0.10 is within the limit"

    create(:playthrough_command, playthrough: @game, status: "pending")
    assert_not allowance.admits_turn?, "a third reservation would pass the limit"
  end

  test "a revoked player is admitted nothing" do
    @player.revoke!
    assert_not allowance.admits_turn?
  end

  test "the refusal is the engine's own sentence and admit! runs nothing" do
    @player.update!(monthly_limit_usd: 0)
    ran = false
    error = assert_raises(Player::Allowance::LimitReached) { allowance.admit! { ran = true } }
    assert_not ran
    assert_includes error.message, "allowance is used up"
    assert_includes error.message, "2026-10-01"
  end
end
