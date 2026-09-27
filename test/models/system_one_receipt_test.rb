require "test_helper"

class SystemOneReceiptTest < ActiveSupport::TestCase
  test "a receipt is filed under whoever the current turn belongs to, at the stated price" do
    player = create(:player)
    game = create(:playthrough, player: player)
    receipt = Current.set(player: player, playthrough: game) { SystemOneReceipt.record!(purpose: "classifier", transport: :typesafe_direct) }

    assert_equal player, receipt.player
    assert_equal game, receipt.playthrough
    assert_equal "typesafe_direct", receipt.transport
    assert_equal SystemOneReceipt::COST_PER_REQUEST_USD, receipt.cost_usd
  end

  test "a reported cost can raise the receipt and never lower it" do
    receipt = create(:system_one_receipt)
    receipt.reported!({ "cost" => 0.0001 })
    assert_equal SystemOneReceipt::COST_PER_REQUEST_USD, receipt.reload.cost_usd

    receipt.reported!({ "cost" => 0.01 })
    assert_equal BigDecimal("0.01"), receipt.reload.cost_usd

    receipt.reported!(nil)
    assert_equal BigDecimal("0.01"), receipt.reload.cost_usd
  end
end
