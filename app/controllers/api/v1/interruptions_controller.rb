# `POST /api/v1/games/:game_id/interruptions/:turn_id/acknowledge`: letting go
# of an old turn that cannot be resumed, which is
# `Playthrough::Session#acknowledge_interruption!` and nothing more.
class Api::V1::InterruptionsController < Api::V1::BaseController
  def acknowledge
    session = session_for(game)
    session.acknowledge_interruption!(params[:turn_id].to_s)
    render json: { standing: Protocol::V1.standing(session.standing) }
  end
end
