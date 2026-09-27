# `GET /api/v1`: which protocol this is, what it can do, and what the player
# has spent. The one request a client makes before anything else.
class Api::V1::ServiceController < Api::V1::BaseController
  def show = render json: Protocol::V1.service(current_player)
end
