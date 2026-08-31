class PlaythroughsController < ApplicationController
  def index
    @stories = Story.includes(:universe, :locations).order(:created_at)
    @playthrough = current_playthrough
  end

  def create
    story = Story.find(params[:story_id])
    location = opening_location(story)

    if location.nil?
      redirect_to root_path, alert: unplayable_message(story)
      return
    end

    playthrough = Playthrough.create!(
      story: story,
      character: story.protagonist,
      current_location: location
    )

    # The protagonist is standing here from this moment, and nothing else says
    # so: `Scene`'s after_create stamps the visit, and a playthrough starts
    # with no scene. Without this the opening room is still unvisited when the
    # player walks back into it, so the first place they ever stood would be
    # narrated to them as a discovery.
    location.mark_protagonist_visit!

    # Deliberately starting a playthrough takes the session over; merely
    # looking at one (below) does not.
    session[:playthrough_token] = playthrough.token
    redirect_to playthrough
  end

  def show
    @playthrough = Playthrough.find(params[:id])
    bind_session_to(@playthrough)

    @scenes = scene_log(@playthrough)
    @exits = @playthrough.current_location&.exits&.order(:id) || Location.none
    @command = params[:command].presence
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

  # `game:new` generates the opening location and realizes it, so it is the
  # story's first realized location. Stubs are skipped: they are exits nobody
  # has walked into yet, with a name and a teaser but nothing to read.
  #
  # Returns nil for a story generated before opening locations existed. There
  # is nothing honest to start such a story at -- inventing a room would put
  # the player somewhere the story does not contain -- so `create` sends them
  # back with an explanation instead.
  def opening_location(story)
    story.locations.realized.order(:id).first
  end

  def unplayable_message(story)
    "#{story.title} has no realized opening location -- either it predates " \
      "`rake game:new` generating them, or its opening room is still a stub. " \
      "Generate a new story to play."
  end

  # The turn log, oldest first. Scenes are a `previous_scene` linked list, so
  # walking back from the playthrough's current scene gives this playthrough's
  # turns and not some other playthrough's.
  #
  # `interactions` is preloaded because the turn partial reads it on every
  # scene to name who the player was talking to, and all but the talk turns
  # have none.
  def scene_log(playthrough)
    scenes = []
    scene = playthrough.current_scene

    while scene
      scenes.unshift(scene)
      scene = scene.previous_scene
    end

    ActiveRecord::Associations::Preloader.new(
      records: scenes, associations: { interactions: :character }
    ).call

    scenes
  end
end
