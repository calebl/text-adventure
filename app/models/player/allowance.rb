# WHAT A PLAYER MAY STILL SPEND THIS MONTH, and the one gate on spending it.
#
# THE RULE. Something that will spend -- a turn on the hosted engine, or one
# call through the model relay -- is accepted only if
#
#     spent this month + reserved + its own reservation <= monthly_limit_usd
#
# `spent` is metered from the receipts the calls themselves left: every
# assistant message in a chat filed under this player (`chats.player_id`,
# stamped by `BaseAgent` from `Current`), priced from the `ruby_llm_models`
# registry, plus every `SystemOneReceipt`, plus every settled `RelayReceipt`.
# So a player has one monthly cap whether they play on the hosted engine or
# through the relay from an engine of their own. `reserved` is what is accepted
# but not yet metered: one `TURN_RESERVATION_USD` for each of the player's
# turns that is pending or running (a `Playthrough::Command`), because its
# calls have not left receipts yet, plus the `reserved_usd` of each relay call
# still open. Holding those is what stops two acceptances in the same second
# from each seeing the same headroom: the second one counts the first.
#
# THE CHECK AND THE ACCEPTANCE ARE ONE STEP. `#admit!` holds a lock per player
# (`GameLock`, a file lock, so it holds across Puma threads and job processes
# alike) and a database transaction around reading the headroom and writing
# the row that holds the reservation, so no other acceptance for the same
# player can fall between them. There are two callers, and both run before any
# model call: `Playthrough::Session#accept!`, which writes the command row
# before the turn is enqueued, and `Relay::OpenrouterController`, which opens
# the call's `RelayReceipt` before the request is forwarded.
#
# WHAT A RESERVATION IS. For a hosted turn, `TURN_RESERVATION_USD`: a worst case
# for one turn, derived from the bench's per-turn token figures and the
# registry price of the front model, rounded up -- not measured per turn. A turn
# that realizes several rooms can cost more than its reservation, and that
# overrun is the one way metered spend can pass the limit; the next turn is
# then refused. For a relayed call the relay sees no turns, only calls, so the
# reservation is per call instead -- the call's own worst case, from its size
# and its output ceiling (`Relay::Request#reservation`) -- and it is held for
# exactly as long as the call is open. The instance's own OpenRouter keys, with
# credit limits set at the provider, are the backstop for any overrun.
#
# A MODEL THE REGISTRY CANNOT PRICE IS NOT FREE. It is charged at
# `UNPRICED_PER_MILLION`, deliberately dear, so a gap in the registry refuses
# turns early instead of letting them through uncounted.
class Player::Allowance
  TURN_RESERVATION_USD = BigDecimal("0.03")
  UNPRICED_PER_MILLION = { input: BigDecimal("15"), output: BigDecimal("75") }.freeze
  UNFINISHED = %w[pending running].freeze

  class LimitReached < StandardError
    attr_reader :allowance

    def initialize(allowance, reservation = TURN_RESERVATION_USD, held_for: "a turn")
      @allowance = allowance
      super(allowance.limit_reached_message(reservation, held_for: held_for))
    end
  end

  # A model's registry price per million tokens, or `UNPRICED_PER_MILLION` when
  # the registry cannot price it.
  def self.price(model_id)
    standard = Model.find_by(model_id: model_id)&.pricing&.dig("text_tokens", "standard")
    input = standard&.dig("input_per_million")
    output = standard&.dig("output_per_million")
    return UNPRICED_PER_MILLION if input.blank? || output.blank?

    { input: input.to_d, output: output.to_d }
  end

  attr_reader :player, :now

  def initialize(player, now: Time.current)
    @player = player
    @now = now
  end

  def period_start = now.utc.beginning_of_month
  def period_end = period_start.next_month
  def limit = player.monthly_limit_usd.to_d

  def spent = chat_spend + system_one_spend + relay_spend

  def reserved = unfinished_turns.count * TURN_RESERVATION_USD + open_relay_calls.sum(:reserved_usd).to_d

  def remaining = [ limit - spent - reserved, 0 ].max

  def admits?(reservation) = !player.revoked? && spent + reserved + reservation <= limit

  def admits_turn? = admits?(TURN_RESERVATION_USD)

  # Runs the block -- the write that holds `reservation`, a turn's command row
  # or a relay call's receipt -- only if it fits, and with every other
  # acceptance for this player shut out until it returns. Raises
  # `LimitReached` having written nothing.
  def admit!(reservation = TURN_RESERVATION_USD, held_for: "a turn")
    GameLock.synchronize("player", player.id) do
      ActiveRecord::Base.transaction do
        raise LimitReached.new(self, reservation, held_for: held_for) unless admits?(reservation)

        yield
      end
    end
  end

  # THE ENGINE'S OWN WORDS FOR A SPENT ALLOWANCE. Nothing in it is a model's.
  def limit_reached_message(reservation = TURN_RESERVATION_USD, held_for: "a turn")
    format("This month's play allowance is used up ($%.2f of $%.2f, with $%.2f held for %s). " \
           "Your games can still be read; new turns open again on %s.",
           spent + reserved, limit, reservation, held_for, period_end.to_date.iso8601)
  end

  private

  def unfinished_turns
    Playthrough::Command.joins(:playthrough).where(playthroughs: { player_id: player.id }, status: UNFINISHED)
  end

  def open_relay_calls = player.relay_receipts.unsettled.where(created_at: period_start...)

  def relay_spend
    player.relay_receipts.settled.where(created_at: period_start...).sum(:cost_usd).to_d
  end

  def system_one_spend
    player.system_one_receipts.where(created_at: period_start...).sum(:cost_usd).to_d
  end

  def chat_spend
    prices = {}
    messages.sum(BigDecimal("0")) do |message|
      usage = message.ruby_llm_usages.select { |row| row.operation == "chat" && row.status == "succeeded" }.max_by(&:id)
      model = usage&.model || message.model_id_string.presence || registry_id(message[:model_id]) ||
              message.chat.model_id_string.presence || registry_id(message.chat.ruby_llm_model_id)
      input = (usage ? usage.input_tokens : message[:input_tokens]).to_i
      output = (usage ? usage.output_tokens : message[:output_tokens]).to_i
      price = prices[model] ||= self.class.price(model)
      (input * price[:input] + output * price[:output]) / 1_000_000
    end
  end

  def messages
    Message.joins(:chat).where(chats: { player_id: player.id }, role: "assistant")
           .where(created_at: period_start...).includes(:ruby_llm_usages, :chat)
  end

  def registry_id(row_id) = (Model.where(id: row_id).pick(:model_id) if row_id)
end
