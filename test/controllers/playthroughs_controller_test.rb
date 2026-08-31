require "test_helper"

class PlaythroughsControllerTest < ActionDispatch::IntegrationTest
  test "index lists the generated stories" do
    story = create(:story)

    get root_path

    assert_response :success
    assert_match story.title, response.body
  end

  test "index says how to generate a story when there are none" do
    get root_path

    assert_response :success
    assert_match "game:new", response.body
  end

  test "index offers to resume the playthrough bound to the session" do
    playthrough = create(:playthrough, :started)

    post playthroughs_path, params: { story_id: playthrough.story_id }
    get root_path

    assert_match "Resume", response.body
  end

  test "create starts a playthrough and binds it to the session" do
    story = create(:story)
    create(:location, story: story)

    assert_difference -> { story.playthroughs.count }, 1 do
      post playthroughs_path, params: { story_id: story.id }
    end

    playthrough = story.playthroughs.last
    assert_redirected_to playthrough
    assert_equal playthrough.token, session[:playthrough_token]
  end

  test "create makes the player the story's protagonist and starts them in the opening location" do
    story = create(:story)
    protagonist = create(:character, story: story, is_protagonist: true)
    opening = create(:location, story: story)
    create(:location, :stub, story: story)

    post playthroughs_path, params: { story_id: story.id }

    playthrough = story.playthroughs.last
    assert_equal protagonist, playthrough.character
    assert_equal opening, playthrough.current_location
  end

  # A stub is an exit nobody has walked into: a name and a teaser with nothing
  # to read. Starting there would drop the player into an unwritten room.
  test "create skips stub locations when choosing where to start" do
    story = create(:story)
    create(:location, :stub, story: story)
    opening = create(:location, story: story)

    post playthroughs_path, params: { story_id: story.id }

    assert_equal opening, story.playthroughs.last.current_location
  end

  test "create refuses a story that has no realized location to start in" do
    story = create(:story)
    create(:location, :stub, story: story)

    assert_no_difference -> { Playthrough.count } do
      post playthroughs_path, params: { story_id: story.id }
    end

    assert_redirected_to root_path
    assert_match story.title, flash[:alert]
  end

  test "index does not offer to play a story with no realized location" do
    playable = create(:story, title: "A Recent World")
    create(:location, story: playable)
    unplayable = create(:story, title: "An Older World")

    get root_path

    assert_match unplayable.title, response.body
    assert_match "No opening location", response.body
    assert_select "form input[type=submit]", count: 1
  end

  test "show renders the preface and the turn log oldest first" do
    playthrough = create(:playthrough, :in_scene)
    first = create(:scene, story: playthrough.story, location: playthrough.current_location,
                           description: "The door swings open.")
    second = create(:scene, story: playthrough.story, location: playthrough.current_location,
                            description: "Rain starts falling.", previous_scene: first)
    playthrough.update!(current_scene: second)

    get playthrough_path(playthrough)

    assert_response :success
    assert_match playthrough.story.preface, response.body
    assert_operator response.body.index("The door swings open."), :<,
                    response.body.index("Rain starts falling.")
  end

  test "create takes the session over from an earlier playthrough" do
    first = create(:playthrough, :started)
    story = create(:story)
    create(:location, story: story)

    post playthroughs_path, params: { story_id: first.story_id }
    post playthroughs_path, params: { story_id: story.id }

    assert_equal story.playthroughs.last.token, session[:playthrough_token]
  end

  test "show binds an unbound session and leaves a bound one alone" do
    first = create(:playthrough)
    second = create(:playthrough)

    get playthrough_path(first)
    assert_equal first.token, session[:playthrough_token]

    get playthrough_path(second)
    assert_equal first.token, session[:playthrough_token]
  end

  # The exits are the only move targets Playthrough::Classifier will accept, so
  # a player who cannot read them is guessing at the one command that matters.
  test "show names the room the player is in and the ways out of it" do
    playthrough = create(:playthrough, :started)
    create(:location_connection, location: playthrough.current_location,
                                 connected_location: create(:location, story: playthrough.story, name: "The Sunken Stair"))

    get playthrough_path(playthrough)

    assert_match "You are in", response.body
    assert_match playthrough.current_location.name, response.body
    assert_match "The Sunken Stair", response.body
  end

  # The opening room is the first thing the player reads, and it used to be
  # rendered above the log only while the log was empty. The first turn is the
  # first thing to put a Scene in that log, so it made the text the player had
  # just been reading vanish. The opening is a Scene of its own now, so it
  # stays where it was written and the log starts where the story starts.
  test "show keeps the opening text in the log once the first turn lands" do
    story = create(:story)
    create(:character, story: story, is_protagonist: true)
    create(:location, story: story, description: "Stalls stand under wet canvas.")

    post playthroughs_path, params: { story_id: story.id }
    playthrough = story.playthroughs.last

    get playthrough_path(playthrough)
    assert_match "Stalls stand under wet canvas.", response.body

    playthrough.update!(current_scene: create(:scene, story: story,
                                                      location: playthrough.current_location,
                                                      description: "Rain starts falling.",
                                                      previous_scene: playthrough.current_scene))

    get playthrough_path(playthrough)
    assert_match "Stalls stand under wet canvas.", response.body
    assert_match "Rain starts falling.", response.body
    assert_operator response.body.index("Stalls stand under wet canvas."), :<,
                    response.body.index("Rain starts falling.")
  end

  # The opening room is where the player is standing, so it has to read as a
  # return -- not a discovery -- when they walk back into it later.
  # `Location#last_protagonist_visit` is the whole of that mechanism, and it is
  # what `Scene::Generator` reads to choose between the two.
  #
  # `create` used to stamp it with an explicit `mark_protagonist_visit!`
  # because a playthrough started with no scene. It starts with one now, and
  # `Scene`'s after_create stamps the visit itself -- at the same moment and
  # with the same value, which is what makes dropping the explicit call safe
  # rather than merely tidy. This test is what says so.
  test "create marks the opening location as visited when the opening scene is written" do
    story = create(:story)
    opening = create(:location, story: story, last_protagonist_visit: nil)

    freeze_time do
      post playthroughs_path, params: { story_id: story.id }

      assert_equal Time.current, opening.reload.last_protagonist_visit
    end

    # The stamp came from the opening Scene, not from a second write: it is the
    # scene the playthrough now starts on.
    playthrough = story.playthroughs.last
    assert_equal opening, playthrough.current_scene.location
    assert opening.last_protagonist_visit.present?
  end

  # The log begins where the story begins. This is the cheap half of the
  # answer -- a room description standing in for an arrival nobody narrates --
  # and a world that carries its own opening arrival replaces the text and
  # nothing else.
  test "create opens the turn log with the room the player starts in" do
    story = create(:story)
    opening = create(:location, story: story, description: "Ash drifts past the shutters.")

    assert_difference -> { story.scenes.count }, 1 do
      post playthroughs_path, params: { story_id: story.id }
    end

    scene = story.playthroughs.last.current_scene
    assert_equal opening, scene.location
    assert_equal "Ash drifts past the shutters.", scene.description
    assert_nil scene.previous_scene
  end

  # `Scene::Generator#lead_in` reads the previous scene's summary, and the
  # first move now has one. It used to be told "this is where the story opens",
  # which was false by then -- the story opened one room back.
  test "the opening scene carries a summary for the first move to read" do
    story = create(:story)
    create(:location, story: story, name: "The Salt Chapel")

    post playthroughs_path, params: { story_id: story.id }

    assert_equal "The story opens in The Salt Chapel.",
                 story.playthroughs.last.current_scene.summary
  end

  # A talk turn keeps an Interaction alongside the Scene, and the log says who
  # the player was speaking to. Nothing else in the log has one.
  test "show names who the player was talking to on a talk turn" do
    playthrough = create(:playthrough, :in_scene)
    maren = create(:character, story: playthrough.story, fullname: "Maren Vosk")
    create(:interaction, character: maren, scene: playthrough.current_scene,
                         location: playthrough.current_location)

    get playthrough_path(playthrough)

    assert_match "talking to Maren Vosk", response.body
  end

  test "show says nothing about talking on a turn that was not one" do
    playthrough = create(:playthrough, :in_scene)

    get playthrough_path(playthrough)

    assert_no_match(/talking to/, response.body)
  end

  # Once the log is long enough to scroll, every turn in the same colour runs
  # into the one before it and the player cannot find where their turn's answer
  # starts. Past turns drop to the preface's colour; the newest keeps full
  # body colour. The stylesheet does that off `.log > .turn:last-of-type`, so
  # these assert that exact selector rather than a class of their own.
  test "show marks the newest turn in the log and not the ones before it" do
    playthrough = create(:playthrough, :in_scene)
    first = create(:scene, story: playthrough.story, location: playthrough.current_location,
                           description: "The door swings open.")
    playthrough.update!(current_scene: create(:scene, story: playthrough.story,
                                                      location: playthrough.current_location,
                                                      description: "Rain starts falling.",
                                                      previous_scene: first))

    get playthrough_path(playthrough)

    assert_select ".log:not(.streaming) > .turn", count: 2
    assert_select ".log:not(.streaming) > .turn:last-of-type", text: "Rain starts falling."
    assert_select ".log:not(.streaming) > .turn:last-of-type", text: "The door swings open.", count: 0
  end

  # A brand new playthrough has exactly one entry -- the opening room -- and it
  # is both the first and the newest, so it must read at full strength rather
  # than as an already-past turn.
  test "show marks the opening scene as the newest turn on a fresh playthrough" do
    story = create(:story)
    create(:location, story: story, description: "Stalls stand under wet canvas.")

    post playthroughs_path, params: { story_id: story.id }
    get playthrough_path(story.playthroughs.last)

    assert_select ".log:not(.streaming) > .turn:last-of-type",
                  text: "Stalls stand under wet canvas."
  end

  # While a turn is streaming, the #stream div is what the player is reading,
  # so the last persisted scene has become a *previous* turn. It sits outside
  # the log's wrapper and the wrapper says so, which is what keeps the three
  # states -- streaming, the redirect after it, and a plain load -- consistent.
  test "show hands the newest turn to the stream while a command is pending" do
    playthrough = create(:playthrough, :in_scene)

    get playthrough_path(playthrough, command: "open the ledger")

    assert_select ".log.streaming"
    assert_select ".log:not(.streaming) > .turn:last-of-type", count: 0
    assert_select "#stream.turn"
  end

  test "show streams when a command is pending and otherwise offers the input" do
    playthrough = create(:playthrough)

    get playthrough_path(playthrough)
    assert_match "what do you do?", response.body
    assert_no_match(/EventSource/, response.body)

    get playthrough_path(playthrough, command: "open the ledger")
    assert_match "EventSource", response.body
    assert_match "open the ledger", response.body
  end
end
