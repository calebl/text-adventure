# WHAT ONE SYSTEM ONE REQUEST COST, because nothing else says.
#
# A chat leaves token receipts on `messages`, priced from the model registry.
# A System One request is not a chat (`SystemOneAgent`'s header): it has no
# message row and no token counts, and it cannot be switched off for one player
# -- a credential in the environment is the whole switch. Without a row of its
# own it would be spend no allowance could see, so every request writes one
# BEFORE it is sent, priced at `COST_PER_REQUEST_USD`, a stated constant. A
# request that fails after sending may still have been billed, so the row is
# never removed. When the provider reports a numeric `usage.cost` higher than
# the constant, the row is raised to it; it is never lowered.
class SystemOneReceipt < ApplicationRecord
  # Stated, not measured: a round figure above what a classifier or volition
  # request has been seen to report, so an allowance errs towards refusing.
  COST_PER_REQUEST_USD = BigDecimal("0.002")

  belongs_to :player, optional: true
  belongs_to :playthrough, optional: true

  validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }

  def self.record!(purpose:, transport:)
    create!(player: Current.player, playthrough: Current.playthrough, purpose: purpose,
            transport: transport&.to_s, cost_usd: COST_PER_REQUEST_USD)
  end

  def reported!(usage)
    cost = usage.is_a?(Hash) ? usage["cost"] : nil
    update!(cost_usd: cost) if cost.is_a?(Numeric) && cost > cost_usd
  end
end
