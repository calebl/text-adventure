# `/api/v1/games`: the player's own games. Starting one is
# `Playthrough::Session.begin!`, filed under the player; reading one is the
# whole screen (`Protocol::V1.screen`), which is also how a client reconnects.
class Api::V1::GamesController < Api::V1::BaseController
  def index
    games = current_player.playthroughs.includes(:story).order(:created_at)
    render json: { games: games.map { |playthrough| Protocol::V1.game(playthrough) } }
  end

  def create
    start = Playthrough::Session.begin!(Story.find(params.require(:world).to_s), player: current_player)
    unless start.started?
      render json: Protocol::V1.error("unplayable", start.refusal), status: :unprocessable_content
      return
    end

    render json: Protocol::V1.screen(session_for(start.playthrough)), status: :created
  rescue ActionController::ParameterMissing
    render json: Protocol::V1.error("invalid", "Name a world to start a game in."), status: :unprocessable_content
  end

  def show
    @game = current_player.playthroughs.find_by!(token: params[:id].to_s)
    render json: Protocol::V1.screen(session_for(game))
  end
end
