require "test_helper"

class MachineryControllerTest < ActionDispatch::IntegrationTest
  # BOTH HALVES OF THE PANEL, out of records, for one turn. The captain's ask of
  # 2026-09-05: the state the turn was played in and the exact prompt the
  # narrator was given, beside the prose rather than a page away.
  test "show renders the state half and the prompt half for one turn" do
    playthrough, scene = played_turn
    lying_here(playthrough, scene.location, name: "A cracked lantern")
    create(:item, :carried, playthrough: playthrough, name: "A brass ledger")
    create(:item, playthrough: playthrough,
                  character: scene.characters.find { |who| who != playthrough.character },
                  name: "A tide slate")
    exchange_on(scene, purpose: "narration", instructions: "You are the narrator.")
    exchange_on(scene, purpose: "classifier", instructions: "Classify the line.")

    get playthrough_machinery_path(playthrough, scene)

    assert_response :success

    # The five rows of the state half, and nothing else in it.
    assert_select ".sheet-line .who", text: "story time"
    assert_select ".sheet-line .who", text: "in the room"
    assert_select ".sheet-line .who", text: "on the floor"
    assert_select ".sheet-line .who", text: "you carry"
    assert_select ".sheet-line .who", text: "they carry"
    assert_select ".sheet-line", count: 5, message: "five short rows, whatever the cast is"
    assert_match "Grenn Ollivar: A tide slate", response.body
    assert_match "A cracked lantern", response.body
    assert_match "A brass ledger", response.body
    assert_match "A tide slate", response.body

    # And the prompt half, with the classifier under its own heading.
    assert_select "h2", text: "what the narrator was given"
    assert_select "h2", text: "what the classifier was given"
    assert_match "You are the narrator.", response.body
    assert_match "Classify the line.", response.body
    assert_select ".tag.purpose", text: "narration"
    assert_select ".tag.purpose", text: "classifier"
  end

  # WHICH VERSION OF THE INSTRUCTIONS WROTE IT -- the same digest
  # `Playthrough::Feedback` freezes and `rake eval:prompt` records, so two turns
  # on the page can be compared honestly rather than by eye over two prompts.
  test "show names the prompt version and the model that answered" do
    playthrough, scene = played_turn
    exchange_on(scene, purpose: "narration", instructions: "You are the narrator.")

    get playthrough_machinery_path(playthrough, scene)

    assert_response :success
    assert_select ".tag.version", text: "prompt #{Playthrough::PromptVersion.of("You are the narrator.")}"
    assert_match Model.last.model_id, response.body
  end

  # THE PANEL SAYS WHICH OF ITS ROWS IS HISTORICAL. Two of the five are columns
  # written when the turn was played; the other three are `Item` rows, which say
  # where a thing is now. A panel implying a snapshot the records cannot give
  # would be worse than one that gave less.
  test "show marks the rows it can only answer as they stand now" do
    playthrough, scene = played_turn

    get playthrough_machinery_path(playthrough, scene)

    assert_response :success
    assert_select ".sheet-line .mark", text: "this turn", minimum: 2
    assert_select ".sheet-line .mark", text: "now", minimum: 3
    assert_match "nothing records what was lying in #{scene.location.name}", response.body
  end

  # An absence is stated with its reason rather than rendered as whitespace --
  # `DebugHelper`'s one idea, and it holds here too.
  test "show says an empty floor, empty hands and a missing call rather than showing blanks" do
    playthrough, scene = played_turn

    get playthrough_machinery_path(playthrough, scene)

    assert_response :success
    assert_select ".absent", text: /nothing to pick up/
    assert_select ".absent", text: /carrying nothing/
    assert_select ".absent", text: /no classifier call on this turn/
  end

  # An opening arrival was generated when the world was built, not on a turn
  # anybody played, so it has no receipts and that is a different statement from
  # a turn whose receipts were pruned.
  test "show says an opening arrival was paid for at world-build time" do
    playthrough = create(:playthrough, :started)
    opening = create(:scene, :opening, story: playthrough.story,
                                       location: playthrough.current_location,
                                       story_timestamp: playthrough.story.start_time)
    playthrough.update!(current_scene: opening)

    get playthrough_machinery_path(playthrough, opening)

    assert_response :success
    assert_select ".absent", text: /generated when the world was built/
  end

  # --- what it will not answer ----------------------------------------------

  # THE GATE IS THE CONTROLLER'S, not the control's. This app has no auth: a
  # playthrough URL is the whole of a player's credentials, so an endpoint
  # standing behind a hidden control is an endpoint anybody with the link can
  # read -- and what this one answers with is the prompt text.
  test "show is not there at all when the debug view is off" do
    playthrough, scene = played_turn

    Playthrough::Debug.stub(:enabled?, false) do
      get playthrough_machinery_path(playthrough, scene)
    end

    assert_response :not_found
  end

  # THE TURN IS RESOLVED AGAINST THIS PLAYTHROUGH'S OWN CHAIN. Two playthroughs
  # of one story share its opening arrival and nothing else, and every
  # playthrough URL in the app is handed out -- so a scene id from the other game
  # must not answer with the prompts behind it.
  test "show refuses a turn from another playthrough of the same story" do
    playthrough, = played_turn
    other, elsewhere = played_turn(story: playthrough.story)

    get playthrough_machinery_path(playthrough, elsewhere)

    assert_response :not_found
    assert_not_equal playthrough.id, other.id
  end

  test "show refuses a scene that does not exist" do
    playthrough, = played_turn

    get playthrough_machinery_path(playthrough, 0)

    assert_response :not_found
  end

  # THE HARD RULE at the request level: opening an inspector costs a read.
  # `Playthrough::MachineryTest` asserts it against every table; this asserts it
  # through the controller, where a `before_action` or a stray snapshot would be
  # the way it got broken.
  test "show writes nothing and asks no model" do
    playthrough, scene = played_turn
    counts = table_counts

    BaseAgent.stub(:new, -> { flunk "the inspector asked a model something" }) do
      get playthrough_machinery_path(playthrough, scene)
    end

    assert_response :success
    assert_equal counts, table_counts
  end

  # Looking at a turn is not playing it. `PlaythroughsController#show` binds an
  # unbound session to the playthrough it renders; this must not, because it is a
  # window rather than a way in -- the same rule `DebugController` is under.
  test "show does not bind the session to the playthrough" do
    playthrough, scene = played_turn

    get playthrough_machinery_path(playthrough, scene)

    assert_nil session[:playthrough_token]
  end

  # --- the control on the play page -----------------------------------------

  # LAZY, ONE TURN AT A TIME: the log is the entire playthrough and `#turn_log`
  # is replaced at the end of every turn, so the panel is a frame that fetches
  # when it is opened rather than content rendered forty times per typed line.
  test "the play page draws a lazy frame per turn and no panel content" do
    playthrough, scene = played_turn

    get playthrough_path(playthrough)

    assert_response :success
    assert_select "details.machinery summary", text: "machinery"
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(scene, :machinery)}[loading=?]", "lazy"
    assert_select "turbo-frame[src=?]", playthrough_machinery_path(playthrough, scene)
    # The panel itself is NOT on the page: nothing precomputes it.
    assert_select ".machinery-panel", count: 0
    assert_no_match(/what the narrator was given/, response.body)
  end

  # The control is gated exactly as the verdict buttons and the debug link are,
  # and on the same flag -- so a player handed a link to read a story is never
  # shown the way into the prompts.
  test "the play page draws no control at all when the debug view is off" do
    playthrough, = played_turn

    Playthrough::Debug.stub(:enabled?, false) do
      get playthrough_path(playthrough)
    end

    assert_response :success
    assert_select "details.machinery", count: 0
    assert_select "turbo-frame", count: 0
  end

  # WITH NO JAVASCRIPT the frame never fetches, so what is inside it is an
  # ordinary link to the same action -- which renders the panel under the game's
  # own layout rather than as unstyled markup.
  test "the frame falls back to a plain link and the action renders a whole page" do
    playthrough, scene = played_turn

    get playthrough_path(playthrough)
    assert_select "turbo-frame a[href=?]", playthrough_machinery_path(playthrough, scene)

    get playthrough_machinery_path(playthrough, scene)
    assert_match "<!DOCTYPE html>", response.body
    assert_match "max-width: 44rem", response.body
  end

  # A Turbo Frame request wants the frame and nothing else. A layout on that
  # response is bytes Turbo throws away on every open.
  test "a frame request answers with the frame and no layout" do
    playthrough, scene = played_turn

    get playthrough_machinery_path(playthrough, scene), headers: { "Turbo-Frame" => "anything" }

    assert_response :success
    assert_no_match(/<!DOCTYPE html>/, response.body)
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(scene, :machinery)}"
  end

  # The debug page is untouched by any of this: it has its own layout by design,
  # and the two pages sharing a stylesheet is the thing that must not happen.
  test "the play page does not gain the debug page's stylesheet" do
    playthrough, scene = played_turn

    get playthrough_machinery_path(playthrough, scene)

    assert_no_match(/max-width: 76rem/, response.body)
  end

  private

  # A playthrough standing on a turn it played, with one of the world's people
  # in the room and recorded on the turn.
  # `story:` is a SECOND game of a world that already has one, which is what the
  # closed-set test needs: two playthroughs of one story share its protagonist
  # row (there is only ever one) and nothing else.
  def played_turn(story: nil)
    playthrough =
      if story
        create(:playthrough, story: story, character: story.characters.find_by(is_protagonist: true),
                             current_location: create(:location, story: story))
      else
        create(:playthrough, :started)
      end
    story = playthrough.story
    here = playthrough.current_location

    # A story has exactly one opening arrival and every playthrough of it starts
    # on that same one, so the second game reuses it rather than writing a second.
    opening = Scene.find_by(story: story, is_opening: true) ||
              create(:scene, :opening, story: story, location: here, story_timestamp: story.start_time)
    grenn = story.characters.find_by(fullname: "Grenn Ollivar") ||
            create(:character, story: story, fullname: "Grenn Ollivar", location: here)
    scene = create(:scene, story: story, location: here, previous_scene: opening,
                           story_timestamp: story.start_time + 10.minutes,
                           typed: "ask Grenn about the charts")
    scene.characters = [ playthrough.character, grenn ]
    playthrough.update!(current_scene: scene)

    [ playthrough, scene ]
  end

  def exchange_on(scene, purpose:, instructions: "You are the narrator.")
    chat = create(:chat, purpose: purpose)
    create(:message, :system, chat: chat, content: instructions) if instructions
    create(:message, chat: chat, scene: scene, content: "what do you do?")
    create(:message, :assistant, chat: chat, scene: scene)
    chat
  end

  def table_counts
    ActiveRecord::Base.connection.tables.sort.to_h do |table|
      [ table, ActiveRecord::Base.connection.select_all("SELECT COUNT(*) AS c FROM #{table}").first["c"] ]
    end
  end
end
