# `POST /api/v1/games/:game_id/turns`: a typed line, accepted and handed to
# `NarrationJob` exactly as the browser's is, with the event adapter.
#
# THE ORDER IS THE GUARANTEE. The rate limit answers first; then
# `Playthrough::Session#accept!`, which is where the spend gate is -- a line
# that would take the player past this month's limit is refused there with
# the engine's own words and a 402, and nothing is written, enqueued or
# called. Only an accepted line reaches the job, so no model call can happen
# for a turn the allowance did not admit. Reads (every GET) are not gated:
# a player at the limit can still look at their games.
class Api::V1::TurnsController < Api::V1::BaseController
  TURNS_PER_MINUTE = 10

  # One store for the process, rather than `Rails.cache`: the limit must hold
  # in every environment, including the test one whose cache stores nothing.
  RATE_STORE = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: TURNS_PER_MINUTE, within: 1.minute, only: :create, store: RATE_STORE,
             by: -> { current_player.id },
             with: -> { render json: Protocol::V1.error("rate_limited", rate_limited_message), status: :too_many_requests }

  def create
    command = session_for(game).accept!(params[:line].to_s, params[:request_token].to_s)
    if command.nil?
      render json: Protocol::V1.error("blank_line", "Nothing was typed, so there is no turn."), status: :unprocessable_content
      return
    end

    NarrationJob.perform_later(game.id, command.command, command.request_token, "events")
    render json: { turn: Protocol::V1.turn(command) }, status: :accepted
  rescue Player::Allowance::LimitReached => e
    render json: Protocol::V1.error("limit_reached", e.message), status: :payment_required
  rescue ActiveRecord::RecordInvalid
    render json: Protocol::V1.error("conflict", "That turn could not be accepted as sent."), status: :conflict
  end

  private

  def rate_limited_message
    "That is more than #{TURNS_PER_MINUTE} turns in a minute. Wait a moment and send it again."
  end
end
