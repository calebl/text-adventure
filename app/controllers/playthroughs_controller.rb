class PlaythroughsController < ApplicationController
  def index
    @stories = Story.includes(:universe, :locations, :characters, :protagonist).order(:created_at)
    @playthrough = current_playthrough
  end

  def create
    story = Story.find(params[:story_id])
    location = opening_location(story)

    if location.nil?
      redirect_to root_path, alert: no_opening_location_message(story)
      return
    end

    # AND A STORY WITH NO PLAYER CHARACTER IS NOT PLAYABLE EITHER, which is the
    # fix of 2026-09-05. A story whose cast nobody has marked `is_protagonist`
    # answers nil to `#protagonist` (`Story::Doctor`'s `:no_protagonist` has been
    # reporting it all along), and this line used to hand that nil straight to
    # `Playthrough.create!`, which accepts it, because `Playthrough#character` is
    # optional.
    #
    # The game that came out could be walked around and talked in and could not
    # PICK ANYTHING UP: the captain's playthrough 24 took a signet ring and a
    # key, read a perfect paragraph about pocketing both, and left them lying on
    # the floor. The engine refuses those lines now
    # (`Playthrough::Refusal`'s `:unplayable`), and this refuses the game.
    #
    # NO CHARACTER IS CREATED HERE, deliberately. `Story#create_character` is a
    # model call -- it invents a person, a name and a body -- and quietly
    # spending tokens inside a Play button is not a thing a button should do.
    # Where a story GETS its player character is a separate question and a
    # separate change; this only refuses to start a game without one, and says
    # the doctor's remedy for the worlds that already exist.
    if story.protagonist.nil?
      redirect_to root_path, alert: no_protagonist_message(story)
      return
    end

    playthrough = Playthrough.create!(
      story: story,
      character: story.protagonist,
      current_location: location,
      current_scene: opening_scene(story, location)
    )

    # THE PROTAGONIST ARRIVES NOW, and this is the only place that can say so.
    #
    # A world's opening arrival is written at world-building time and loaded out
    # of a seed file, so `Scene`'s after_create deliberately does not stamp the
    # visit for it -- stamping then would date the protagonist's presence to
    # whenever the file was seeded, and the first walk back into the opening room
    # would be narrated as a return after however long that was. Nobody was in
    # the room until this request.
    #
    # #73 dropped this call because the scene it created here stamped the visit
    # at exactly this moment, which made the two equivalent. That equivalence
    # does not survive the scene moving into the world, so the explicit stamp
    # comes back. It is also harmless on the fallback path below, where the
    # after_create has already written the same value.
    #
    # Stamped with the STORY's clock rather than with `Time.current`: the
    # protagonist arrives at the moment the story opens, which is the opening
    # arrival's own `story_timestamp`. Reaching for the wall clock here is the
    # defect `Location#time_since_last_visit` used to have, one layer up.
    location.mark_protagonist_visit!(story.clock)

    # Deliberately starting a playthrough takes the session over; merely
    # looking at one (below) does not.
    session[:playthrough_token] = playthrough.token
    redirect_to playthrough
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

  # The first entry in the turn log, and the reason a playthrough does not start
  # with an empty one.
  #
  # A world carries its own opening arrival: `rake game:new` narrates it once
  # with `Scene::Generator.opening`, the exporter writes it into the seed file
  # where it is hand-authored, and the loader loads it. So the normal answer
  # here is to hand the playthrough that Scene -- no model call on the one
  # screen a new player sees first, and real narrated prose rather than a room
  # description standing in for an arrival nobody wrote.
  #
  # Every playthrough of a story starts on the SAME opening Scene, which is what
  # makes it world rather than progress. The turn log walks backwards from
  # `current_scene`, so two playthroughs branching off one opening still each
  # read their own turns; `Scene#next_scenes` is plural for the forward
  # direction that stopped being single-valued.
  #
  # The fallback covers a story built before opening arrivals existed, and the
  # in-memory stories tests build: the room's own description, as #73 wrote it.
  # That scene is per-playthrough progress, so it is NOT marked `is_opening`.
  def opening_scene(story, location)
    story.opening_scene || Scene.create!(
      story: story,
      location: location,
      description: location.description,
      summary: "The story opens in #{location.name}.",
      story_timestamp: story.start_time
    )
  end

  def no_opening_location_message(story)
    "#{story.title} has no realized opening location -- either it predates " \
      "`rake game:new` generating them, or its opening room is still a stub. " \
      "Generate a new story to play."
  end

  # THE DOCTOR'S REMEDY, IN THE OPERATOR'S OWN TERMINAL. It is the same advice
  # `Story::Doctor`'s `:no_protagonist` finding gives and it is split the same
  # way, because telling somebody to mark a character that does not exist is
  # worse than useless: a `rake game:new` world has no characters at all and
  # needs one made first, while a world that has people needs one of them
  # promoted.
  def no_protagonist_message(story)
    remedy =
      if story.characters.none?
        "It has no characters at all -- make one with " \
          "`rails runner \"Story.find(#{story.id}).create_character\"`, then mark them the player with " \
          "`rails runner \"Story.find(#{story.id}).characters.first.update!(is_protagonist: true)\"`."
      else
        "Mark one of its characters the player with " \
          "`rails runner \"Story.find(#{story.id}).characters.first.update!(is_protagonist: true)\"`."
      end

    "#{story.title} has no player character yet, so there would be nobody to play: " \
      "nothing could be picked up or carried in it. #{remedy}"
  end
end
