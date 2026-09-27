# THE ENGINE API, VERSION 1 -- what every endpoint under /api/v1 shares.
#
# docs/protocol/v1.md is the contract. This API is one more thin front end on
# the driver, like the browser: each action is one call into
# `Playthrough::Session` or `Playthrough::Glance`, rendered by `Protocol::V1`,
# and none of them decides anything about the game.
#
# WHO IS ASKING. Every request carries `Authorization: Bearer <token>`, and the
# token is exchanged for a `Player` by digest (`Player.authenticate`, constant
# time). The token itself is never logged, echoed, or put in an error; a wrong
# or revoked one gets the same 401 as a missing one. A player reaches only
# their own games: `#game` looks a game up WITHIN the player's playthroughs, so
# another player's game id answers 404 exactly as a made-up one does, and the
# response cannot tell anyone which ids exist.
#
# NOTHING IS MASS-ASSIGNED. Each action reads the one or two parameters it
# names, as strings, and hands them to the driver; no parameter hash reaches a
# model.
class Api::V1::BaseController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate_player!

  rescue_from ActiveRecord::RecordNotFound do
    render json: Protocol::V1.error("not_found", "There is nothing here by that id."), status: :not_found
  end

  private

  attr_reader :current_player

  def authenticate_player!
    @current_player = authenticate_with_http_token { |token, _options| Player.authenticate(token) }
    return if @current_player

    headers["WWW-Authenticate"] = %(Bearer realm="text-adventure")
    render json: Protocol::V1.error("unauthorized", "A valid player token is required."), status: :unauthorized
  end

  def game = @game ||= current_player.playthroughs.find_by!(token: params[:game_id].to_s)

  def session_for(playthrough) = Playthrough::Session.new(playthrough)
end
