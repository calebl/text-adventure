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

  test "resume links to the foot of the log rather than the top of the page" do
    playthrough = create(:playthrough, :started)

    post playthroughs_path, params: { story_id: playthrough.story_id }
    resumed = playthrough.story.playthroughs.last
    get root_path

    assert_select "a[href=?]", playthrough_path(resumed, anchor: "bottom"), text: /Resume/
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

  # THE SLASH MENU IS RENDERED INTO THE FORM AND FETCHED FROM NOWHERE. The whole
  # point of `Playthrough::SlashMenu` is that the box needs no request and no
  # model: the closed sets arrive with the turn, and `#turn_log` is replaced at
  # the end of every turn, so they rebuild themselves.
  test "show renders this turn's closed sets into the play form" do
    playthrough = create(:playthrough, :started)
    story = playthrough.story
    here = playthrough.current_location
    create(:location_connection, location: here,
                                 connected_location: create(:location, story: story, name: "The Sunken Stair"))
    create(:character, story: story, fullname: "Halkett Rowe", location: here)
    create(:item, :lying, playthrough: playthrough, location: here, name: "ward stamp")
    create(:item, :carried, playthrough: playthrough, name: "brass compass")

    get playthrough_path(playthrough)

    assert_select "[data-controller=slash][data-slash-menu-value]" do |elements|
      menu = JSON.parse(elements.first["data-slash-menu-value"])

      assert_equal %w[go talk take drop read attack], menu["verbs"].map { |verb| verb["word"] }
      assert_equal [ "The Sunken Stair" ], menu["targets"]["go"]
      assert_equal [ "Halkett Rowe" ], menu["targets"]["talk"]
      assert_equal [ "ward stamp" ], menu["targets"]["take"]
      assert_equal [ "brass compass" ], menu["targets"]["drop"]
      assert_equal [ "ward stamp", "brass compass" ], menu["targets"]["read"]
      assert_equal [ "Halkett Rowe" ], menu["targets"]["attack"]
    end
  end

  # IT DEGRADES TO A PLAIN TEXT BOX. Everything the menu adds is data attributes
  # and one empty list; with no JavaScript the field is an ordinary input in an
  # ordinary form and every line the menu could have written can be typed.
  test "the play form is a plain text field with the menu empty and hidden" do
    playthrough = create(:playthrough, :started)

    get playthrough_path(playthrough)

    assert_select "form input[type=text][name=command][role=combobox][aria-expanded=false]"
    assert_select "ul.slash-menu[role=listbox][hidden]", ""
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
  #
  # The moment is STORY time: the story's own `start_time`, which is when the
  # opening arrival happens by definition. Never the wall clock.
  test "create marks the opening location as visited when the opening scene is written" do
    story = create(:story)
    opening = create(:location, story: story, last_protagonist_visit: nil)

    post playthroughs_path, params: { story_id: story.id }

    assert_equal story.start_time, opening.reload.last_protagonist_visit

    # The stamp came from the opening Scene, not from a second write: it is the
    # scene the playthrough now starts on.
    playthrough = story.playthroughs.last
    assert_equal opening, playthrough.current_scene.location
    assert_equal story.start_time, playthrough.current_scene.story_timestamp
  end

  # THE PAYOFF. A world carries its own opening arrival, so the first thing a new
  # player reads is real narrated prose and the request that starts a playthrough
  # makes no model call at all.
  test "create opens the turn log with the world's own opening arrival" do
    story = create(:story)
    opening = create(:location, story: story, description: "Ash drifts past the shutters.")
    arrival = create(:scene, :opening, story: story, location: opening,
                                       description: "You come up the last step and the shutters are already open.")

    assert_no_difference -> { story.scenes.count } do
      BaseAgent.stub(:new, -> { flunk "starting a playthrough asked a model something" }) do
        post playthroughs_path, params: { story_id: story.id }
      end
    end

    playthrough = story.playthroughs.last
    assert_equal arrival, playthrough.current_scene

    get playthrough_path(playthrough)
    assert_match "You come up the last step and the shutters are already open.", response.body
  end

  # Every playthrough of a story starts on the SAME opening scene -- that is what
  # makes it world rather than progress. The turn log walks backwards from
  # `current_scene`, so two playthroughs branching off one opening each read
  # their own turns and neither reads the other's.
  test "two playthroughs share one opening arrival and keep separate logs" do
    story = create(:story)
    opening = create(:location, story: story)
    arrival = create(:scene, :opening, story: story, location: opening, description: "The story opens here.")

    post playthroughs_path, params: { story_id: story.id }
    first = story.playthroughs.last
    first.update!(current_scene: create(:scene, story: story, location: opening,
                                                description: "The first player turns left.",
                                                previous_scene: arrival))

    post playthroughs_path, params: { story_id: story.id }
    second = story.playthroughs.last
    second.update!(current_scene: create(:scene, story: story, location: opening,
                                                 description: "The second player turns right.",
                                                 previous_scene: arrival))

    get playthrough_path(second)
    assert_match "The story opens here.", response.body
    assert_match "The second player turns right.", response.body
    assert_no_match(/The first player turns left\./, response.body)
  end

  # --- THE CAPTAIN'S REPORT, AS A REGRESSION TEST -----------------------------
  #
  # He started a new playthrough and the protagonist was already carrying things
  # from a previous one. The party's inventory was `items.character_id` pointing
  # at `story.protagonist` -- one Character row per story -- so every play of a
  # world shared one pair of hands and nothing on creation emptied them.
  #
  # THIS IS THE POSITION SHAPE, and PR 109's argument: two people playing one
  # seeded world stand in two rooms, and carry two different sets of things.

  test "a new playthrough does not open holding what an earlier one picked up" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    opening = create(:location, story: story)
    create(:scene, :opening, story: story, location: opening, story_timestamp: story.start_time)
    stamp = create(:item, :lying, location: opening, name: "ward stamp")

    post playthroughs_path, params: { story_id: story.id }
    first = story.playthroughs.last
    Playthrough::Turn.new(first).send(:carry!, stamp)
    assert_equal [ "ward stamp" ], first.carried.pluck(:name)

    post playthroughs_path, params: { story_id: story.id }
    second = story.playthroughs.last

    assert_not_equal first, second
    assert_empty second.carried, "a new game opened holding the last one's things"
    assert_equal first, stamp.reload.playthrough
    assert_nil protagonist.items.reload.first, "and nothing was left on the story's protagonist"
  end

  # WHAT A NEW GAME DOES START WITH is the story's own starting inventory -- the
  # seed file's `characters[].items` under the protagonist -- as its own copy,
  # because an `Item` is in exactly one place and a second player must not find
  # the daybook already in somebody else's hands.
  test "each new playthrough opens with its own copy of the story's starting inventory" do
    story = create(:story)
    protagonist = create(:character, :protagonist, story: story)
    opening = create(:location, story: story)
    create(:scene, :opening, story: story, location: opening, story_timestamp: story.start_time)
    daybook = create(:item, character: protagonist, name: "Ward Office 12 daybook")

    post playthroughs_path, params: { story_id: story.id }
    first = story.playthroughs.last
    post playthroughs_path, params: { story_id: story.id }
    second = story.playthroughs.last

    assert_equal [ daybook.name ], first.carried.pluck(:name)
    assert_equal [ daybook.name ], second.carried.pluck(:name)
    assert_not_equal first.carried.sole.id, second.carried.sole.id
    assert_equal protagonist, daybook.reload.character
  end

  # THE STORY-TIME HAZARD.
  #
  # An opening arrival is written when the WORLD is built and loaded out of a
  # seed file, so it deliberately does not stamp `last_protagonist_visit` --
  # stamping then would date the protagonist's presence to whenever the file was
  # seeded, and the first walk back into the opening room would be narrated as a
  # return after however long that was. Nobody is in the room until a playthrough
  # starts. #73 dropped the explicit stamp because the scene it created here did
  # the job at exactly this moment; that equivalence does not survive the scene
  # moving into the world, so the stamp is explicit again.
  #
  # The value is a moment on the STORY's clock, which is why three weeks of wall
  # clock between building the world and playing it changes nothing here.
  test "create stamps the visit when the player arrives, not when the world was built" do
    story = create(:story)
    opening = create(:location, story: story, last_protagonist_visit: nil)
    scene = create(:scene, :opening, story: story, location: opening, story_timestamp: story.start_time)

    assert_nil opening.reload.last_protagonist_visit, "building the world is not somebody standing in the room"

    travel 3.weeks do
      post playthroughs_path, params: { story_id: story.id }

      assert_equal scene.story_timestamp, opening.reload.last_protagonist_visit
      assert_not_equal Time.current.to_i, opening.last_protagonist_visit.to_i,
                       "three weeks on somebody's calendar is not three weeks of the story"
    end
  end

  # The fallback: a story built before opening arrivals existed. The log begins
  # where the story begins either way, with the room's own description standing
  # in for an arrival nobody narrated.
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

  # And it is per-playthrough progress, not world -- so it is not an opening.
  test "the fallback opening scene is not marked as the world's opening" do
    story = create(:story)
    create(:location, story: story)

    post playthroughs_path, params: { story_id: story.id }

    assert_not story.playthroughs.last.current_scene.is_opening?
    assert_nil story.reload.opening_scene
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

  # The play page is one state now: the log, where the player is, and the input.
  # There is no `?command=` variant of it any more -- a turn in flight is a Turbo
  # Stream replacing `#turn_log`, which TurnsControllerTest covers, and the
  # finished turn arrives the same way from NarrationJob.
  test "show offers the input and no longer streams from the page itself" do
    playthrough = create(:playthrough)

    get playthrough_path(playthrough)

    assert_match "what do you do?", response.body
    assert_no_match(/EventSource/, response.body)
  end

  # THE SUBSCRIPTION, and where it sits. Inside `#turn_log` it would be torn
  # down and rebuilt every time a turn finished, and the tail of the next turn
  # would be broadcast to a channel nobody was listening on.
  test "show subscribes to the playthrough's stream from outside the replaced region" do
    playthrough = create(:playthrough)

    get playthrough_path(playthrough)

    assert_select "turbo-cable-stream-source", count: 1
    assert_select "#turn_log turbo-cable-stream-source", count: 0
  end

  # ...but a real page load is a real page load, and there the attribute means
  # what it says: put the cursor in the box. NarrationJobTest asserts the other
  # half, which is that a broadcast must not carry it.
  test "show autofocuses the input, because a page load is what autofocus is for" do
    playthrough = create(:playthrough)

    get playthrough_path(playthrough)

    assert_select "#turn_log input[type=text][autofocus]"
  end

  # Where the page sits is not something the suite can see, so this pins the
  # markup the fix stands on instead of pretending to test a viewport: the
  # anchor a plain reload and the index's Resume link both aim at. Following the
  # narration down while it arrives is `app/javascript/play.js`, covered by the
  # browser walk in the PR.
  test "show ends with the anchor the log's foot is reached by" do
    playthrough = create(:playthrough)

    get playthrough_path(playthrough)

    assert_select "#bottom"
  end
  # --- a playthrough that is over -------------------------------------------
  #
  # The captain's ruling of 2026-09-04: at zero hit points the character is dead
  # and the playthrough is over. The input is not disabled and not left there to
  # be refused line after line -- it is gone, and what stands in its place says
  # why and offers the one thing that is left.

  test "a dead playthrough shows the death statement instead of the input" do
    playthrough = dead_playthrough

    get playthrough_path(playthrough)

    assert_response :success
    assert_select "input[name=command]", 0
    assert_select "div.notice", text: /#{Regexp.escape(Playthrough::DeathNotice::HEADING)}/
  end

  test "a dead playthrough offers the one way on: a new playthrough of the same world" do
    playthrough = dead_playthrough

    get playthrough_path(playthrough)

    assert_select "form[action=?]", playthroughs_path do
      assert_select "input[name=?][value=?]", "story_id", playthrough.story_id.to_s
    end
  end

  test "a playthrough that is still running keeps its input" do
    playthrough = dead_playthrough
    playthrough.update!(ended_at: nil)

    get playthrough_path(playthrough)

    assert_select "input[name=command]", 1
    assert_select "div.notice", 0
  end

  # THE BATTLE PANEL, AND IT IS DERIVED. The captain's call C9 of 2026-09-05 --
  # ***"go with buttons for now"*** -- shape (a) of the combat scout's §12: a
  # panel of records inside `#turn_log`, rendered when `Playthrough#foes_in`
  # answers with somebody and gone when it does not. There is no battle flag to
  # set and none to clear.
  test "a room with somebody hostile in it shows the battle panel" do
    playthrough = fighting_playthrough

    get playthrough_path(playthrough)

    assert_response :success
    assert_select "#turn_log div.sheet.battle" do
      # THE HEADING IS WHERE, THE LEAD IS WHAT JUST HAPPENED, AND THE ROUND SITS
      # OVER THE BUTTONS -- the captain's reading of 2026-09-05, that a panel
      # saying `Round 2` with nothing about round 1 reads as a mode that was
      # entered. All three are `Playthrough::Battle`'s own words, off the rows.
      assert_select "h2", text: "A fight in The Bell of Saint Aravel."
      assert_select "p.sheet-lead", text: "No blow has landed yet."
      assert_select "h3.sheet-prompt", text: "Round 1: what do you do?"
      # NUMBERS AND NOT BARS. The condition line is `18 of 18`, in the house
      # grey -- the reading experience is `ta-api-iface`'s stage.
      assert_select "p.sheet-line span.state", text: "18 of 18", count: 2
      assert_select "p.sheet-line span.mark", text: "hostile"
    end
  end

  # ONE UI. A button is `turns#create` with a fixed command string -- the same
  # route the text box posts to -- and the string is SLASHED, so
  # `Playthrough::Grammar` reads it and the classifier is never called. That is
  # the whole of "a round costs zero model calls".
  test "the panel's buttons post fixed commands to the same turn route" do
    playthrough = fighting_playthrough

    get playthrough_path(playthrough)

    assert_select "div.sheet-actions form[action=?]", playthrough_turns_path(playthrough) do
      assert_select "input[name=?][value=?]", "command", "/attack Marek Sollen"
      # THE LABEL SAYS IT IS A BLOW AND SAYS THE DIE, and the die is the party's
      # own `hit_die` -- already on the panel under every condition line.
      assert_select "input[type=submit][value=?]", "strike Marek Sollen (d8)"
    end
    # THE WAY OUT IS ALWAYS THERE -- the captain's call C1, a fight is always
    # escapable by leaving the room.
    assert_select "div.sheet-actions input[name=?][value=?]", "command", "/go The Stair"
  end

  # AND THE BOX IS STILL UNDER IT. The panel is a shortcut into the one loop and
  # not a mode: a player who would rather type `/attack Marek Sollen`, or say
  # something the buttons have no word for, still can.
  test "the free-text box stays under the panel" do
    playthrough = fighting_playthrough

    get playthrough_path(playthrough)

    assert_select "div.sheet.battle", 1
    assert_select "input[name=command][type=text]", 1
  end

  test "a room with nobody hostile in it shows no panel" do
    playthrough = fighting_playthrough
    playthrough.update!(current_location: playthrough.story.locations.find_by(name: "The Stair"))

    get playthrough_path(playthrough)

    assert_select "div.sheet.battle", 0
    assert_select "input[name=command][type=text]", 1
  end

  # THE LAST KILL TAKES THE PANEL AWAY and the ordinary loop resumes with
  # nothing to reconcile -- the fight wrote through the same records the prose
  # loop writes through, so there is no battle state to hand back.
  test "killing the last foe takes the panel away" do
    playthrough = fighting_playthrough
    monster = playthrough.story.characters.find_by(fullname: "Marek Sollen")
    Playthrough::Turn.new(playthrough).harm!(monster, 99)

    get playthrough_path(playthrough)

    assert_select "div.sheet.battle", 0
  end

  # A DEAD PLAYER IS NOT IN A FIGHT, whatever is standing over them: the death
  # notice has the screen and the input is gone, exactly as before this panel
  # existed.
  test "a dead playthrough shows the death notice and no panel" do
    playthrough = fighting_playthrough
    Playthrough::Turn.new(playthrough).harm!(playthrough.character, 99)

    get playthrough_path(playthrough)

    assert_select "div.sheet.battle", 0
    assert_select "input[name=command][type=text]", 0
    assert_select "div.notice", text: /#{Regexp.escape(Playthrough::DeathNotice::HEADING)}/
  end

  # THE LAST EXCHANGE, in the engine's own sentence about its own dice --
  # `Playthrough::Blow#to_s`, reused verbatim so the browser and
  # `rake game:mechanics` cannot describe one blow two ways.
  test "the panel prints the blows of the round just fought" do
    playthrough = fighting_playthrough
    monster = playthrough.story.characters.find_by(fullname: "Marek Sollen")
    Playthrough::Turn.new(playthrough).strike!(playthrough.character, monster, round: 1)

    get playthrough_path(playthrough)

    # ROUND 1 IS DONE AND ROUND 2 IS NEXT, and the panel says both: the boundary
    # is the whole of what the captain was missing when he took his first turn
    # of a fight and read `Round 2` off a panel he had never seen before.
    assert_select "div.sheet.battle p.sheet-lead",
                  text: /\ARound 1 is done: you struck Marek Sollen, .*The fight is on because you struck\.\z/
    assert_select "div.sheet.battle h3.sheet-prompt", text: "Round 2: what do you do?"
    assert_select "p.sheet-note", text: /Hero Protagonist hit Marek Sollen for \d+ \(round 1\)/
  end

  private

  # A game the player has died in, through the engine's own writer rather than
  # by setting the column: `Playthrough::Turn#harm!` is where the ending is
  # written, and a test that wrote `ended_at` by hand would not notice if it
  # stopped being.
  def dead_playthrough
    story = create(:story)
    room = create(:location, story: story)
    hero = create(:character, :protagonist, story: story, level: 1, hit_die: 6)
    playthrough = create(:playthrough, story: story, character: hero, current_location: room,
                                       current_scene: create(:scene, story: story, location: room))
    Playthrough::Turn.new(playthrough).harm!(hero, 99)
    playthrough
  end

  # A GAME STANDING IN FRONT OF SOMEBODY THE WORLD SAYS IS HOSTILE, which is the
  # whole of what puts the panel on the page -- there is no flag to set. Level 3
  # with a d8 on both sides, which is 18 hit points (the captain's call C1) and
  # is fixed here for `Playthrough::Fight`'s stated reason: `Roll`'s seed is
  # built out of row ids, so no fixture may depend on a face coming up.
  def fighting_playthrough
    story = create(:story)
    room = create(:location, story: story, name: "The Bell of Saint Aravel")
    stair = create(:location, story: story, name: "The Stair")
    create(:location_connection, location: room, connected_location: stair)
    create(:location_connection, location: stair, connected_location: room)
    hero = create(:character, :protagonist, story: story, level: 3, hit_die: 8)
    create(:character, :monster, story: story, location: room, fullname: "Marek Sollen",
                                 level: 3, hit_die: 8)
    create(:playthrough, story: story, character: hero, current_location: room,
                         current_scene: create(:scene, story: story, location: room))
  end
end
