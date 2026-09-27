# `GET /api/v1/worlds`: the stories a game can be started in -- those with a
# realized opening room and a player character, which are the two things
# `Playthrough::Session.begin!` refuses without. Worlds are shared.
class Api::V1::WorldsController < Api::V1::BaseController
  def index
    stories = Story.includes(:protagonist).order(:created_at)
                   .where(id: Location.realized.select(:story_id)).select(&:protagonist)
    render json: { worlds: stories.map { |story| Protocol::V1.world(story) } }
  end
end
