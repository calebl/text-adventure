class PlaythroughsController < ApplicationController
  def index
    @stories = Story.includes(:universe, :locations, :characters, :protagonist).order(:created_at)
    @playthrough = current_playthrough
  end

  # Starting a game is `Playthrough::Session.begin!`; this binds the cookie to
  # it, or sends the player back with the sentence that says why not.
  def create
    start = Playthrough::Session.begin!(Story.find(params[:story_id]))
    unless start.started?
      redirect_to root_path, alert: start.refusal
      return
    end

    # Deliberately starting a playthrough takes the session over; merely
    # looking at one (below) does not.
    session[:playthrough_token] = start.playthrough.token
    redirect_to start.playthrough
  end

  # The log, the location line and the input, all rendered by the same partial
  # `NarrationJob` broadcasts when a turn finishes -- so a plain load, a Resume
  # link and the end of a turn all produce the same page.
  def show
    @playthrough = Playthrough.find(params[:id])
    bind_session_to(@playthrough)
  end

  private

  # There is no login and no user model: a single unguessable token in the
  # cookie is the whole of the binding, and it is what "Resume" on the index
  # follows. `||=` so that opening someone else's playthrough URL does not
  # throw away the one this session is actually playing.
  def bind_session_to(playthrough)
    session[:playthrough_token] ||= playthrough.token
  end

  def current_playthrough
    token = session[:playthrough_token]
    Playthrough.find_by(token: token) if token.present?
  end
end
