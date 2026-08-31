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
