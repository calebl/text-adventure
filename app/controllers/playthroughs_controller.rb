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
      current_location: location,
      current_scene: opening_scene(location)
    )

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

  # The first entry in the turn log, and the reason a playthrough no longer
  # starts with an empty one.
  #
  # Every other room the player walks into is narrated by `Scene::Generator`.
  # The opening room is the one arrival that never happens -- the player is
  # simply standing in it -- so nothing had ever written its text down, and the
  # play page read the location's own description out above the log instead.
  # That stand-in was conditional on the log being empty, so the first turn
  # made the opening text disappear from under the player.
  #
  # Writing it as a `Scene` is the cheap half of the answer: no model call on
  # the one screen a new player sees first, and the log now begins where the
  # story begins. It is a room description rather than a narrated arrival, and
  # that is the honest limit of it -- a world that carries its own opening
  # arrival would replace the text here and nothing else.
  #
  # Two things fall out of it, both of them corrections:
  #
  #   * `Scene`'s after_create stamps `last_protagonist_visit`, so the explicit
  #     `mark_protagonist_visit!` this method replaced is no longer needed. The
  #     protagonist is standing here, and now a record says so.
  #   * the first move gets a real `previous_scene`. `Scene::Generator#lead_in`
  #     used to be told "Nothing. This is where the story opens", which was
  #     false by then -- the story opened one room back.
  def opening_scene(location)
    Scene.create!(
      story: location.story,
      location: location,
      description: location.description,
      summary: "The story opens in #{location.name}.",
      story_timestamp: Time.current
    )
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
