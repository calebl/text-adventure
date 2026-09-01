require "test_helper"

class DebugControllerTest < ActionDispatch::IntegrationTest
  # THE PAGE RENDERS FOR A REAL PLAYTHROUGH, which is most of what a view test
  # can honestly claim. Every section is asserted by something only that section
  # can produce, so a section that silently stops rendering fails here.
  test "show renders every section for a played-through world" do
    playthrough = played_playthrough

    get playthrough_debug_path(playthrough)

    assert_response :success

    # The turn he just took, and the branch derived from records rather than
    # read from a label that does not exist.
    assert_select "h2", text: "the turn you just took"
    assert_select ".panel.now .branch.conversation", text: "conversation"
    assert_match "ask Grenn about the charts", response.body

    # The five structured fields the player only ever reads as prose.
    assert_match "pre_thought", response.body
    assert_match "I wonder what this person wants", response.body

    # The place, stub-versus-realized, and the graph in both directions.
    assert_match playthrough.current_location.name, response.body
    assert_select "th", text: "return edge"

    # The closed set the classifier will accept next turn.
    assert_select "h2", text: "what the classifier will accept next turn"
    assert_match "The Sunken Stair", response.body
    assert_match "## Ways Out", response.body

    # The world's own clock and what it did to itself.
    assert_select "h2", text: "the world's clock"
    assert_match "The nightly rearrangement", response.body
    assert_match "Mournwell Lane now opens onto", response.body

    # The durable background: every character and every place this world has
    # generated, present and closed so it does not compete with the turn.
    assert_select "details#cast summary", text: /the cast/
    assert_select "details#map summary", text: /the map/
    assert_select "details summary", text: /the universe/
    assert_match "Grenn Ollivar", response.body
    assert_match "The Sunken Stair", response.body
    assert_select "a[href=?]", "#cast"
    assert_select "a[href=?]", "#map"

    # The conversations, which is the half of a turn the player never sees.
    assert_select "h2", text: "the conversations you are having"
    assert_select "a[href=?]", "#conversations"

    # And the honest gap -- which no longer names `ta-chat-persist`, because the
    # prompts, answers, token counts and models it promised are kept now. What
    # is left is the pruning ceiling and the missing `scenes` column.
    assert_select "h2", text: "what is not recorded"
    assert_no_match(/ta-chat-persist/, response.body)
    assert_match "ta-api-iface", response.body
    assert_match "ta-arrival-diff", response.body
  end

  # THE HARD RULE, at the request level: a GET of this page is an observer.
  # `Playthrough::DebugTest` asserts it against every table; this asserts it
  # through the controller, where a `before_action` or a stray `session` write
  # would be the way it got broken.
  test "show writes nothing and asks no model" do
    playthrough = played_playthrough
    counts = table_counts

    BaseAgent.stub(:new, -> { flunk "the debug view asked a model something" }) do
      get playthrough_debug_path(playthrough)
    end

    assert_response :success
    assert_equal counts, table_counts
  end

  # Looking at a playthrough is not playing it. `PlaythroughsController#show`
  # binds an unbound session to the playthrough it renders; this must not,
  # because it is a window rather than a way in.
  test "show does not bind the session to the playthrough" do
    playthrough = create(:playthrough, :in_scene)

    get playthrough_debug_path(playthrough)

    assert_nil session[:playthrough_token]
  end

  # A stub location has no description YET, and that is information rather
  # than an empty field. The view is required to say which.
  test "show says a stub is unwritten rather than blank" do
    playthrough = create(:playthrough, :in_scene)
    playthrough.current_location.update_columns(detail_level: "stub", description: nil, lore: nil)

    get playthrough_debug_path(playthrough)

    assert_response :success
    assert_select ".absent", text: /not written YET/
  end

  # A character the world generated but nobody has met is nowhere, and the view
  # says so rather than inventing a place for them.
  test "show lists a generated character nobody has met and says they are nowhere" do
    playthrough = create(:playthrough, :in_scene)
    create(:character, story: playthrough.story, fullname: "Isbet Marrow")

    get playthrough_debug_path(playthrough)

    assert_match "Isbet Marrow", response.body
    assert_select ".absent", text: /never in a scene/
  end

  # A stub nobody has walked into is still a real record with a name, and the
  # map lists it as one.
  test "show lists stub locations on the map with nobody in them" do
    playthrough = create(:playthrough, :in_scene)
    create(:location, :stub, story: playthrough.story, name: "The Celestial Spire")

    get playthrough_debug_path(playthrough)

    assert_match "The Celestial Spire", response.body
    assert_select ".absent", text: /nobody known here/
  end

  # The page must not be a quieter second opinion than `rake game:doctor` about
  # the same rows: a one-way edge, two directions that disagree, and a value
  # outside the fixed tables all have to read as problems here too.
  test "show flags a one-way edge, disagreeing directions and an unpriceable one" do
    playthrough = create(:playthrough, :started)
    one_way = create(:location, story: playthrough.story, name: "The Sunken Stair")
    create(:location_connection, location: playthrough.current_location, connected_location: one_way)

    get playthrough_debug_path(playthrough)
    assert_select ".warn", text: /MISSING/

    create(:location_connection, location: one_way, connected_location: playthrough.current_location,
                                 distance: "a long journey", travel_method: "riding")
    get playthrough_debug_path(playthrough)
    assert_select ".warn", text: /disagrees/

    LocationConnection.find_by(location: playthrough.current_location, connected_location: one_way)
                      .update_columns(distance: "a short walk down the flooded lanes")
    get playthrough_debug_path(playthrough)
    assert_select ".warn", text: /not in DISTANCES/
  end

  # And it names the deeper audit rather than standing in for it.
  test "show points at rake game:doctor for the whole story" do
    playthrough = create(:playthrough, :in_scene)

    get playthrough_debug_path(playthrough)

    assert_match "rake game:doctor", response.body
  end

  # A world with nothing in it must still render: this page is most useful when
  # something has gone wrong, which is exactly when records are missing.
  test "show renders a playthrough that has never been played" do
    playthrough = create(:playthrough)

    get playthrough_debug_path(playthrough)

    assert_response :success
    assert_select ".absent", text: /nothing has been played/
    assert_select ".absent", text: /current_location is nil/
  end

  # THE GATE IS THE CONTROLLER'S, not the link's. This app has no auth: a
  # playthrough URL is the whole of a player's credentials, so a debug page
  # standing behind a hidden link would be a debug page anybody with the link
  # can read.
  test "show is not there at all when the debug view is off" do
    playthrough = create(:playthrough, :in_scene)

    Playthrough::Debug.stub(:enabled?, false) do
      get playthrough_debug_path(playthrough)
    end

    assert_response :not_found
  end

  test "the play page offers the link only when the debug view is on" do
    playthrough = create(:playthrough, :in_scene)

    get playthrough_path(playthrough)
    assert_select "a[href=?]", playthrough_debug_path(playthrough)

    Playthrough::Debug.stub(:enabled?, false) do
      get playthrough_path(playthrough)
    end
    assert_select "a[href=?]", playthrough_debug_path(playthrough), count: 0
  end

  # The game's own layout is untouched: the debug page has its own, so it
  # cannot change how the story reads (`ta-api-iface` owns that, and has not
  # started).
  test "the debug page does not use the game's layout" do
    playthrough = create(:playthrough, :in_scene)

    get playthrough_debug_path(playthrough)
    assert_no_match(/what do you do\?/, response.body)
    assert_match "max-width: 76rem", response.body

    get playthrough_path(playthrough)
    assert_match "max-width: 44rem", response.body
    assert_no_match(/max-width: 76rem/, response.body)
  end

  private

  # A world that has been played: an opening, a conversation, a stub nobody has
  # walked into, a mechanic and the event it wrote.
  def played_playthrough
    playthrough = create(:playthrough, :started)
    story = playthrough.story
    here = playthrough.current_location

    stair = create(:location, :stub, story: story, name: "The Sunken Stair")
    create(:location_connection, location: here, connected_location: stair)
    create(:location_connection, location: stair, connected_location: here)

    opening = create(:scene, :opening, story: story, location: here, story_timestamp: story.start_time)
    talk = create(:scene, story: story, location: here, previous_scene: opening,
                          story_timestamp: story.start_time + 10.minutes,
                          summary: "The player spoke with Grenn Ollivar.")
    grenn = create(:character, story: story, fullname: "Grenn Ollivar", nickname: "Old Grenn")
    talk.characters = [ playthrough.character, grenn ]
    create(:interaction, character: grenn, scene: talk, location: here,
                         user_input: "ask Grenn about the charts")
    playthrough.update!(current_scene: talk)

    mechanic = create(:world_mechanic, story: story, name: "The nightly rearrangement")
    create(:world_event, world_mechanic: mechanic, story: story)

    playthrough
  end

  def table_counts
    ActiveRecord::Base.connection.tables.sort.to_h do |table|
      [ table, ActiveRecord::Base.connection.select_all("SELECT COUNT(*) AS c FROM #{table}").first["c"] ]
    end
  end
end
