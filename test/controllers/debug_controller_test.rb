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

    # WHAT THE TURN DID, out of `scenes.resolved_action` and `scenes.acted_on`
    # rather than worked out again from the branch -- the one field on the page
    # that says what CHANGED.
    assert_select ".panel.now .k", text: "resolved to"
    assert_match "talk -&gt; Grenn Ollivar", response.body

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

    # And the honest gap, which is now honest about two fewer things. It no
    # longer names `ta-chat-persist` (the prompts, answers, token counts and
    # models it promised are kept), no longer claims a retention ceiling (there
    # is none unless `TA_CHAT_KEEP_TURNS` is set), and no longer names
    # `ta-api-iface` for a `scenes.typed` column that exists and is written on
    # every branch. A false bullet in this list is worse than a missing one.
    assert_select "h2", text: "what is not recorded"
    assert_no_match(/ta-chat-persist/, response.body)
    assert_no_match(/ta-api-iface/, response.body)
    assert_match "TA_CHAT_KEEP_TURNS", response.body
    assert_match "scenes.typed", response.body
    assert_match "ta-arrival-diff", response.body
  end

  # THE TWO COUNTERS RENDER SIDE BY SIDE AND ARE NEVER ONE NUMBER: a drift is a
  # reach that found nothing, an overreach a reach that found more than a turn
  # can answer. Both sections say so in words when they are empty, because a
  # blank table reads as a broken page rather than a clean playthrough.
  test "show reports what a line named twice beside the drift it is not" do
    playthrough = played_playthrough
    create(:playthrough_drift, playthrough: playthrough, command: "go through the cellar door")
    create(:playthrough_overreach, playthrough: playthrough,
                                   command: "pickup the index and the apron",
                                   acted: "Perrin's private index", unacted: "copy-room apron")

    get playthrough_debug_path(playthrough)

    assert_response :success
    assert_select "h3", text: /named two/
    # "resolved to" rather than "acted on": since the ruling of 2026-09-04 the
    # line is refused whole, so neither name was acted on. See
    # `Playthrough::Overreach`.
    assert_select "th", text: "also named"
    assert_select "th", text: "resolved to"
    assert_match "pickup the index and the apron", response.body
    assert_match "copy-room apron", response.body
    assert_match "the loop's limit, not a defect", response.body

    # And the drift section is still its own, with its own evidence column.
    assert_select "h3", text: /drift/
    assert_select "th", text: "was offered"
    assert_match "go through the cellar door", response.body
  end

  test "show says both counters are empty rather than rendering a blank table" do
    get playthrough_debug_path(played_playthrough)

    assert_response :success
    assert_match "every line this player typed named one thing", response.body
    assert_match "resolved to a record", response.body
  end

  # THE PANEL DESCRIBES THE RULE, so it has to render under both settings --
  # uncapped (above) and capped. The capped branch interpolates
  # `Chat::KEEP_TURNS` into the page; with the default nil that would render an
  # empty gap in a sentence, which is what `Chat.capped?` exists to prevent.
  test "show describes the retention cap when one is set" do
    playthrough = played_playthrough

    with_keep_turns(25) do
      get playthrough_debug_path(playthrough)
    end

    assert_response :success
    assert_match "older than 25 turns", response.body
    assert_select "h2", text: "what is not recorded"
  end

  # --- the evaluation instrument, read back ---------------------------------

  # REVIEWABLE TOGETHER: the turn, the player's own words, the prose, and the
  # provenance frozen when the verdict was recorded, in one table. Enough to
  # answer "which model do the turns I marked good actually come from" without a
  # console, which is the question the whole instrument exists for.
  test "show reviews every verdict beside the turn and the frozen provenance" do
    playthrough = played_playthrough
    turn = playthrough.current_scene
    turn.update!(typed: "ask Grenn about the charts")
    create(:playthrough_feedback, :frozen, :with_note, playthrough: playthrough, scene: turn,
                                                       verdict: "good")

    get playthrough_debug_path(playthrough)

    assert_response :success
    assert_select "h2", text: "what you thought of each turn"
    assert_select "a[href=?]", "#feedback"
    assert_select ".verdict.good", text: "good"

    # The four things a reader needs six weeks later.
    assert_match "ask Grenn about the charts", response.body
    assert_match "mistralai/mistral-medium-3.1", response.body
    assert_match "narration", response.body
    assert_match "the room read as somewhere", response.body

    # And the cross-tab the freezing is for.
    assert_select "h3", text: "verdict against the model that wrote the prose"
  end

  # A verdict recorded after its turn's conversations were pruned keeps the
  # verdict and not the receipts. That is a real state and the page says which
  # it is looking at rather than showing a blank.
  test "show says when a verdict outlived the receipts rather than showing nothing" do
    playthrough = played_playthrough
    create(:playthrough_feedback, playthrough: playthrough, scene: playthrough.current_scene,
                                  verdict: "weak")

    get playthrough_debug_path(playthrough)

    assert_select ".absent", text: /receipts/
  end

  test "show says nothing has been judged when nothing has" do
    playthrough = played_playthrough

    get playthrough_debug_path(playthrough)

    assert_select ".absent", text: /every turn on the play page carries three buttons/
    assert_select ".absent", text: /not judged/
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
  #
  # BOTH DIRECTIONS ARE WRITTEN DOWN HERE, and that is the point of the test
  # rather than tidiness: a disagreement is a relationship between two rows, so
  # a test that pins one row and lets a factory pick the other is asserting
  # against a value it does not know. This one used to, and failed once in 35
  # runs when the two happened to match -- see `test/factories/location_connections.rb`.
  # Each `.warn` is matched on its whole phrase, so a cell that renders the
  # wrong side of the edge fails here too.
  test "show flags a one-way edge, disagreeing directions and an unpriceable one" do
    playthrough = create(:playthrough, :started)
    one_way = create(:location, story: playthrough.story, name: "The Sunken Stair")
    out = create(:location_connection, location: playthrough.current_location, connected_location: one_way,
                                       distance: "adjacent", travel_method: "walking")

    get playthrough_debug_path(playthrough)
    assert_select ".warn", text: /MISSING — one-way/

    create(:location_connection, location: one_way, connected_location: playthrough.current_location,
                                 distance: "a long journey", travel_method: "riding")
    get playthrough_debug_path(playthrough)
    assert_select ".warn", text: /disagrees — a long journey, riding/

    out.update_columns(distance: "a short walk down the flooded lanes")
    get playthrough_debug_path(playthrough)
    assert_select ".warn", text: /not in DISTANCES \/ TRAVEL_METHODS/
  end

  # THE OTHER SIDE OF THAT BRANCH, asserted rather than assumed. An edge whose
  # two rows agree is the normal case and the view must say so plainly -- and
  # this is exactly the state the flake above rendered while a test was
  # expecting a warning, so it is worth a test of its own.
  test "show says an edge written in both directions is fine" do
    playthrough = create(:playthrough, :started)
    neighbour = create(:location, story: playthrough.story, name: "Mournwell Lane")
    [ [ playthrough.current_location, neighbour ], [ neighbour, playthrough.current_location ] ].each do |from, to|
      create(:location_connection, location: from, connected_location: to,
                                   distance: "adjacent", travel_method: "walking")
    end

    get playthrough_debug_path(playthrough)

    assert_select "td", text: "yes"
    assert_select ".warn", count: 0
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

  # WHAT HE IS CARRYING AND WHAT IS AT HIS FEET, on the room section, out of
  # `Item` -- the two closed sets `take` and `drop` resolve against, and the
  # halves of the game state the page used to leave out.
  test "the room section shows what is carried and what is lying here" do
    playthrough = played_playthrough
    create(:item, :carried, playthrough: playthrough, name: "A brass ledger")
    create(:item, :lying, location: playthrough.current_location, name: "A cracked lantern")

    get playthrough_debug_path(playthrough)

    assert_response :success
    assert_select ".k", text: "carrying"
    assert_select ".k", text: "lying here"
    assert_match "A brass ledger", response.body
    assert_match "A cracked lantern", response.body
  end

  # WHAT IS WRITTEN ON THE THINGS IN FRONT OF HIM, verbatim -- the same string
  # `Playthrough::Turn#read_fact` hands the narrator. Seeing the record beside
  # the prose the turn produced is how a misquote is caught by eye before
  # `inscription_misquoted` catches it by rule.
  test "the room section shows what is written on a readable thing" do
    playthrough = played_playthrough
    create(:item, :lying, :readable, location: playthrough.current_location, name: "A folded note")

    get playthrough_debug_path(playthrough)

    assert_response :success
    assert_select ".k", text: /\Areads/
    assert_match "Midnight. The Bell. They know about the maps.", response.body
  end

  test "a readable thing nobody has read yet says so on the page" do
    playthrough = played_playthrough
    create(:item, :lying, :readable, :unwritten, location: playthrough.current_location,
           name: "A folded note")

    get playthrough_debug_path(playthrough)

    assert_response :success
    assert_match "readable, nothing written down yet", response.body
  end

  test "a thing with no writing on it gets no line of its own" do
    playthrough = played_playthrough
    create(:item, :lying, location: playthrough.current_location, name: "A cracked lantern")

    get playthrough_debug_path(playthrough)

    assert_response :success
    assert_match "A cracked lantern", response.body
    assert_select ".k", text: /\Areads/, count: 0
  end

  test "an empty floor and empty hands are spelled out rather than left blank" do
    playthrough = played_playthrough

    get playthrough_debug_path(playthrough)

    assert_response :success
    assert_match "nothing to pick up", response.body
    assert_match "carrying nothing", response.body
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
    grenn = create(:character, story: story, fullname: "Grenn Ollivar", nickname: "Old Grenn")
    talk = create(:scene, story: story, location: here, previous_scene: opening,
                          story_timestamp: story.start_time + 10.minutes,
                          resolved_action: "talk", acted_on: grenn,
                          summary: "The player spoke with Grenn Ollivar.")
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

  def with_keep_turns(keep)
    original = Chat.const_get(:KEEP_TURNS)
    Chat.send(:remove_const, :KEEP_TURNS)
    Chat.const_set(:KEEP_TURNS, keep)
    yield
  ensure
    Chat.send(:remove_const, :KEEP_TURNS)
    Chat.const_set(:KEEP_TURNS, original)
  end
end
