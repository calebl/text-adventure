# WHAT ONE RELAYED CALL WAS ALLOWED TO COST, AND WHAT IT DID COST.
#
# A receipt is opened INSIDE `Player::Allowance#admit!`, before the request
# goes, holding the call's worst case (`Relay::Request#reservation`) in
# `reserved_usd`. While it is `open`, that reservation counts against the
# player's headroom as `Player::Allowance#reserved`; a second call accepted in
# the same instant sees the first one's hold. When the call ends -- answered,
# refused upstream, cut off, or failed on the network -- `#settle!` closes it
# with `cost_usd`, which `Player::Allowance#spent` then counts instead.
#
# WHAT IT COSTS, by what is known when it ends (`cost_source` says which):
#
#   usage        the provider's usage came back: the dearer of the cost it
#                reports and its tokens priced from the registry (a decision:
#                of the reported cost and `SystemOneReceipt::COST_PER_REQUEST_USD`,
#                as the hosted engine charges one)
#   declined     the provider answered an error and reported no usage: a
#                request it refused is not one it bills
#   reservation  anything else -- a stream cut off before its final chunk, a
#                body with no usage, a network failure after sending. The call
#                may have been billed and nothing says for how much, so it
#                costs its whole worst case
#
# A receipt that is never settled (the process died mid-call) stays open and
# keeps holding its reservation for the month it was opened in -- a call that
# may have been billed is never free.
#
# The receipt holds numbers only: no prompt, no answer, no header, no key.
class RelayReceipt < ApplicationRecord
  STATUSES = %w[open closed].freeze
  COST_SOURCES = %w[usage declined reservation].freeze

  belongs_to :player

  validates :route, inclusion: { in: Relay::Request::ROUTES.keys.map(&:to_s) }
  validates :model, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :reserved_usd, numericality: { greater_than_or_equal_to: 0 }
  validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cost_source, inclusion: { in: COST_SOURCES }, allow_nil: true

  scope :unsettled, -> { where(status: "open") }
  scope :settled, -> { where(status: "closed") }

  def self.open!(player, request)
    create!(player: player, route: request.route.to_s, model: request.model, stream: request.stream?,
            status: "open", reserved_usd: request.reservation)
  end

  def open? = status == "open"

  # Closes the receipt once. `usage` is the provider's usage object as it came
  # back (or nil); `upstream_status` its HTTP status (or nil if none arrived).
  def settle!(upstream_status:, usage:)
    return self unless open?

    usage = nil unless usage.is_a?(Hash)
    input = token_count(usage, "prompt_tokens")
    output = token_count(usage, "completion_tokens")
    cost, source = charge(upstream_status, usage, input, output)
    update!(status: "closed", cost_usd: cost, cost_source: source, input_tokens: input, output_tokens: output,
            upstream_status: upstream_status, finished_at: Time.current)
    self
  end

  private

  def charge(upstream_status, usage, input, output)
    reported = usage && usage["cost"].is_a?(Numeric) ? usage["cost"].to_d : nil
    priced = usage && priced(input, output)
    return [ [ reported, priced ].compact.max, "usage" ] if reported || priced
    return [ BigDecimal("0"), "declined" ] if upstream_status && !(200..299).cover?(upstream_status)

    [ reserved_usd, "reservation" ]
  end

  def priced(input, output)
    return SystemOneReceipt::COST_PER_REQUEST_USD if route == "decisions"
    return nil if input.nil? && output.nil?

    price = Player::Allowance.price(model)
    (input.to_i * price[:input] + output.to_i * price[:output]) / 1_000_000
  end

  def token_count(usage, field)
    count = usage&.dig(field)
    count if count.is_a?(Integer) && count >= 0
  end
end
