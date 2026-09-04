require "test_helper"

# The loop. What matters here is not the prose -- it is where the player ends
# up, what got generated on the way, and what did NOT get generated on the way
# back, which is the whole claim the project makes.
#
# One FakeAgent stands in for every BaseAgent the turn builds, so the queued
# responses are the turn's model calls in order:
#
#   classify -> [realize detail, realize exits] -> arrival     (a move)
#   classify -> character reaction -> narration                (a talk)
#   classify -> narration                                      (anything else)
#
# Running out of queued responses raises, which is how a test that expected a
# call the loop did not make fails loudly instead of passing quietly.
class Playthrough::TurnTest < ActiveSupport::TestCase
  CLASSIFY = ->(intent, target) { { "intent" => intent, "target" => target } }

  DETAIL = {
    "description" => "Water stands ankle deep across the flagstones.",
    "lore" => "The vestibule drowned the winter the river took the lower town."
  }.freeze

  ARRIVAL = {
    "description" => "You come down into the cold and the water takes your boots.",
    "summary" => "The protagonist arrives in the Drowned Vestibule."
  }.freeze

  REACTION = {
    "pre_thought" => "Is that person talking to me?",
    "pre_feeling" => "surprised, wary",
    "action" => "She sets down the crate.",
    "post_feeling" => "steadier",
    "post_thought" => "Say something before this gets strange."
  }.freeze

  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ashgate Market")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
  end

  def play(command, *responses)
    agent = FakeAgent.new(*responses)
    chunks = []

    scene = BaseAgent.stub(:new, agent) do
      Playthrough::Turn.new(@playthrough).play(command) { |chunk| chunks << chunk }
    end

    [ scene, chunks, agent ]
  end

  # A neighbour plus the connection rows in both directions, which is what
  # Location::Generator writes when it realizes a room.
  def connect(name, **attributes)
    neighbour = create(:location, story: @story, name: name, **attributes)
    create(:location_connection, location: @here, connected_location: neighbour,
                                 distance: "adjacent", travel_method: "walking")
    create(:location_connection, location: neighbour, connected_location: @here,
                                 distance: "adjacent", travel_method: "walking")
    neighbour
  end

  # Somebody the game knows is standing here: the records place them in this
  # room, which is how `Character.present_in` -- and so Scene::Generator --
  # answers the question. The scene doubles as the one the player is currently
  # in; its cast is a snapshot and no longer what keeps anybody in the room.
  def stands_here(fullname, **attributes)
    character = create(:character, story: @story, fullname: fullname, location: @here, **attributes)
    scene = create(:scene, story: @story, location: @here, characters: [ character ])
    @playthrough.update!(current_scene: scene)
    character
  end

  # --- moving into somewhere new -------------------------------------------

  test "walking into a stub realizes it and narrates arriving" do
    vestibule = connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    scene, chunks, = play("go down to the vestibule",
                          CLASSIFY.call("move", "Drowned Vestibule"),
                          DETAIL, { "exits" => [] }, ARRIVAL)

    assert_predicate vestibule.reload, :realized?
    assert_equal DETAIL["description"], vestibule.description
    assert_equal ARRIVAL["description"], scene.description
    assert_equal vestibule, scene.location
    assert_equal [ ARRIVAL["description"] ], chunks
  end

  test "a move points the playthrough at the new location and the new scene" do
    vestibule = connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    scene, = play("go down", CLASSIFY.call("move", "Drowned Vestibule"),
                  DETAIL, { "exits" => [] }, ARRIVAL)

    @playthrough.reload
    assert_equal vestibule, @playthrough.current_location
    assert_equal scene, @playthrough.current_scene
  end

  test "the arrival scene links back to the scene the player left" do
    left_behind = create(:scene, story: @story, location: @here, description: "You turn from the stalls.")
    @playthrough.update!(current_scene: left_behind)
    connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    scene, = play("go down", CLASSIFY.call("move", "Drowned Vestibule"),
                  DETAIL, { "exits" => [] }, ARRIVAL)

    assert_equal left_behind, scene.previous_scene
  end

  # --- moving back into somewhere already written --------------------------

  # THE POINT OF THE WHOLE THING. A realized location is not regenerated, so
  # walking back costs one arrival call instead of three, and the room the
  # player reads is the room they left.
  test "walking back into a realized location generates nothing but the arrival" do
    market = create(:location, story: @story, name: "Ashgate Market",
                               description: "Stalls under wet canvas.", lore: "It was a fish market once.")
    vestibule = create(:location, story: @story, name: "Drowned Vestibule")
    create(:location_connection, location: vestibule, connected_location: market,
                                 distance: "adjacent", travel_method: "walking")
    @playthrough.update!(current_location: vestibule)

    _scene, _chunks, agent = play("back up to the market",
                                  CLASSIFY.call("move", "Ashgate Market"), ARRIVAL)

    # Two prompts: the classification and the arrival. No detail, no exits.
    assert_equal 2, agent.prompts.count
    assert_equal "Stalls under wet canvas.", market.reload.description
  end

  test "a return visit is narrated as coming back rather than as discovery" do
    market = create(:location, story: @story, name: "Riverside", last_protagonist_visit: 2.hours.ago,
                               description: "Stalls under wet canvas.", lore: "A fish market once.")
    create(:location_connection, location: @here, connected_location: market,
                                 distance: "adjacent", travel_method: "walking")

    _scene, _chunks, agent = play("go to the riverside",
                                  CLASSIFY.call("move", "Riverside"), ARRIVAL)

    arrival_prompt = agent.prompts.last
    assert_match(/has stood here before/, arrival_prompt)
    assert_match(/about 2 hours ago/, arrival_prompt)
  end

  # `Scene`'s after_create stamps the visit, so this is what makes the next
  # walk back read as a return.
  test "arriving stamps the location as visited" do
    vestibule = connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    play("go down", CLASSIFY.call("move", "Drowned Vestibule"),
         DETAIL, { "exits" => [] }, ARRIVAL)

    assert_not_nil vestibule.reload.last_protagonist_visit
  end

  # --- story time -----------------------------------------------------------

  test "an arrival costs the story the length of the walk" do
    connect("Drowned Vestibule")
    here_scene = create(:scene, story: @story, location: @here,
                                story_timestamp: @story.start_time + 1.hour)
    @playthrough.update!(current_scene: here_scene)

    scene, = play("go down", CLASSIFY.call("move", "Drowned Vestibule"), ARRIVAL)

    assert_equal here_scene.story_timestamp + 1.minute, scene.story_timestamp
  end

  test "a conversation costs the story ten minutes" do
    stands_here("Rell Vance")
    before = @playthrough.reload.story_now

    scene, = play("ask about the crate", CLASSIFY.call("talk", "Rell Vance"),
                  REACTION, "She looks up from the crate.")

    assert_equal before + Scene::TURN_MINUTES.fetch("conversation").minutes, scene.story_timestamp
  end

  test "any other turn costs the story one beat in the room" do
    before = @playthrough.reload.story_now

    scene, = play("look at the awnings", CLASSIFY.call("examine", "awnings"),
                  "Canvas, patched and repatched.")

    assert_equal before + Scene::TURN_MINUTES.fetch("action").minutes, scene.story_timestamp
  end

  test "no turn stamps a scene with the wall clock" do
    travel 3.weeks do
      scene, = play("look at the awnings", CLASSIFY.call("examine", "awnings"), "Canvas.")

      assert_operator scene.story_timestamp, :<, Time.current - 2.weeks
    end
  end

  # --- the world moving on its own ------------------------------------------

  # THE WORLD MOVES FIRST, and it does not need anybody to be watching. Nothing
  # is scheduled and nothing is in memory: the nights are simply owed, and the
  # next turn pays them.
  test "a turn catches the world up on every night the story has passed" do
    mechanic = create(:world_mechanic, story: @story, name: "The nightly rearrangement")
    @playthrough.update!(current_scene: create(:scene, story: @story, location: @here,
                                                       story_timestamp: @story.start_time + 2.days))

    play("look at the awnings", CLASSIFY.call("examine", "awnings"), "Canvas.")

    assert_not_nil mechanic.reload.last_run_at
    assert_operator mechanic.last_run_at, :>, @story.start_time
  end

  test "the world catching up costs no model call of its own" do
    create(:world_mechanic, story: @story, name: "The nightly rearrangement")
    @playthrough.update!(current_scene: create(:scene, story: @story, location: @here,
                                                       story_timestamp: @story.start_time + 2.days))

    # FakeAgent raises when a call it has no queued answer for arrives, so a turn
    # that made an extra one would fail here rather than pass quietly.
    _scene, _chunks, agent = play("look at the awnings", CLASSIFY.call("examine", "awnings"), "Canvas.")

    assert_equal 2, agent.prompts.size
  end

  # --- moving when the move cannot be made ---------------------------------

  test "a move nobody can make is narrated instead, and the player stays put" do
    connect("Drowned Vestibule")

    scene, chunks, = play("go north", CLASSIFY.call("move", "nothing"),
                          "There is nothing north of here but the river wall.")

    assert_equal @here, @playthrough.reload.current_location
    assert_equal "There is nothing north of here but the river wall.", scene.description
    assert_equal @here, scene.location
    assert_equal "There is nothing north of here but the river wall.", chunks.join
  end

  # --- talking -------------------------------------------------------------

  test "talking to someone here keeps the moment and what the character felt" do
    maren = stands_here("Maren Vosk")

    scene, chunks, = play("ask Maren about the ledger",
                          CLASSIFY.call("talk", "Maren Vosk"),
                          REACTION, "Maren sets down the crate and squares her shoulders.")

    assert_equal "Maren sets down the crate and squares her shoulders.", scene.description
    assert_equal @here, scene.location
    assert_equal scene, @playthrough.reload.current_scene
    assert_equal "Maren sets down the crate and squares her shoulders.", chunks.join

    interaction = scene.interactions.sole
    assert_equal maren, interaction.character
    assert_equal "ask Maren about the ledger", interaction.user_input
    assert_equal @here, interaction.location
    REACTION.each { |field, value| assert_equal value, interaction.public_send(field) }
  end

  # THE CAST IS A SNAPSHOT OF THE RECORDS, on every branch, written once in
  # `#play` rather than by the branches that happen to have a cast in hand.
  # This branch used to write the protagonist and the person spoken to and
  # nothing else, because that cast was the only thing keeping them in the
  # room; `Character.present_in` keeps them now, so the snapshot is the whole
  # room and a bystander is on it.
  test "a talk scene snapshots everybody the records put in the room" do
    maren = stands_here("Maren Vosk")
    bystander = create(:character, story: @story, fullname: "Tobin Ashe", location: @here)

    scene, = play("hello", CLASSIFY.call("talk", "Maren Vosk"), REACTION, "She looks up.")

    assert_equal [ @protagonist, maren, bystander ].sort_by(&:id), scene.characters.sort_by(&:id)
  end

  # And every other branch gets one too -- 184 of the 480 baseline turns of
  # 2026-09-03 had no record of who was in the room at all, because only an
  # arrival and a talk ever wrote one.
  test "a narrated turn snapshots the room's cast too" do
    maren = stands_here("Maren Vosk")

    scene, = play("look at the awning", CLASSIFY.call("examine", "nothing"),
                  "Rain has pooled in the canvas.")

    assert_equal [ @protagonist, maren ].sort_by(&:id), scene.characters.sort_by(&:id)
  end

  test "a talk scene links back to the scene the player was in" do
    stands_here("Maren Vosk")
    left_behind = @playthrough.current_scene

    scene, = play("hello", CLASSIFY.call("talk", "Maren Vosk"), REACTION, "She looks up.")

    assert_equal left_behind, scene.previous_scene
  end

  test "a talk summary names who was spoken to without a second model call" do
    stands_here("Maren Vosk")

    scene, _chunks, agent = play("hello", CLASSIFY.call("talk", "Maren Vosk"),
                                 REACTION, "She looks up.")

    assert_match(/spoke with Maren Vosk/, scene.summary)
    assert_equal 3, agent.prompts.count # classify, character, narrator
  end

  test "talking to nobody is narrated instead" do
    scene, = play("talk to the ghost", CLASSIFY.call("talk", "nothing"),
                  "Nobody answers. The stalls are empty.")

    assert_equal "Nobody answers. The stalls are empty.", scene.description
    assert_empty scene.interactions
  end

  # Blank prose is not a turn -- Scene validates a description, and a record
  # written from nothing is a turn the player cannot read.
  test "a talk that narrated nothing keeps no records" do
    stands_here("Maren Vosk")

    assert_no_difference [ -> { Scene.count }, -> { Interaction.count } ] do
      scene, = play("hello", CLASSIFY.call("talk", "Maren Vosk"), REACTION, "")

      assert_nil scene
    end
  end

  # THE TALK PATH IS WHERE THIS ACTUALLY HAPPENED, and it is the branch with the
  # most to suppress: `#talk_to` writes a `Scene` the player reads AND an
  # `Interaction` the character felt. A crisis response fails the narrator pass
  # before either exists, so neither is written and the exception reaches
  # `NarrationJob`, which shows the app's own message instead. See
  # `Playthrough::SafetyNotice`.
  test "a crisis response on the talk path keeps neither record" do
    stands_here("Maren Vosk")
    standing_in = @playthrough.current_scene

    assert_no_difference [ -> { Scene.count }, -> { Interaction.count } ] do
      assert_raises(BaseAgent::CrisisResponseError) do
        play("tell her nobody would miss her", CLASSIFY.call("talk", "Maren Vosk"),
             REACTION, BaseAgent::CrisisResponseError)
      end
    end

    assert_equal standing_in, @playthrough.reload.current_scene,
                 "the player is still standing exactly where they were"
  end

  # An exhausted refusal on the same path, for the same reason and by the same
  # route -- but it only gets here after `BaseAgent#ask` has tried every model,
  # which is the difference the two error classes carry.
  test "an exhausted refusal on the talk path keeps neither record" do
    stands_here("Maren Vosk")

    assert_no_difference [ -> { Scene.count }, -> { Interaction.count } ] do
      assert_raises(BaseAgent::RefusalError) do
        play("hello", CLASSIFY.call("talk", "Maren Vosk"), REACTION, BaseAgent::RefusalError)
      end
    end
  end

  # --- the paths that fall through to the narrator -------------------------

  test "examine and other are answered by the narrator in place" do
    %w[examine other].each do |action|
      scene, chunks, = play("look at the ledger", CLASSIFY.call(action, "nothing"),
                            "The ledger is swollen with damp.")

      assert_equal "The ledger is swollen with damp.", scene.description
      assert_equal @here, scene.location
      assert_equal @here, @playthrough.reload.current_location
      # The narrator streams: one chunk per word, not one paragraph.
      assert_operator chunks.count, :>, 1
    end
  end

  # --- taking -------------------------------------------------------------

  # THE APP OWNS TAKING. Everything in this section is about one claim: what the
  # player is carrying is a row the app wrote out of a closed set, and no
  # sentence the narrator produces can add to it or take from it.

  test "taking an item that is lying here moves the row into the player's hands" do
    key = create(:item, :lying, location: @here, name: "Brass Key")

    play("pick up the brass key", CLASSIFY.call("take", "Brass Key"),
         "You lift the key and feel the cold of it.")

    key.reload

    # INTO THE PARTY'S HANDS, not the protagonist's. The protagonist is one row
    # per story, so writing it there gave every playthrough of a world one
    # shared inventory.
    assert_equal @playthrough, key.playthrough
    assert_nil key.character_id
    assert_nil key.location_id
    assert_predicate key, :carried?
    assert_not_predicate key, :held?
  end

  test "a take keeps the moment as a scene the player can read back" do
    create(:item, :lying, location: @here, name: "Brass Key")

    scene, chunks, = play("pick up the brass key", CLASSIFY.call("take", "Brass Key"),
                          "You lift the key and feel the cold of it.")

    assert_equal "You lift the key and feel the cold of it.", scene.description
    assert_equal @here, scene.location
    assert_equal @here, @playthrough.reload.current_location
    assert_operator chunks.count, :>, 1
  end

  test "a take costs the story one beat in the room" do
    create(:item, :lying, location: @here, name: "Brass Key")

    before = @playthrough.story_now
    scene, = play("pick up the brass key", CLASSIFY.call("take", "Brass Key"), "You lift the key.")

    assert_equal before + 5.minutes, scene.story_timestamp
  end

  # THE ROW IS WRITTEN BEFORE THE PROSE, so the narrator is told a fact rather
  # than asked for one. This is the generator/narrator split: the app owns what
  # is true, the narrator owns the sentence about it.
  test "the narrator is told what the app already did" do
    create(:item, :lying, location: @here, name: "Brass Key",
                          description: "Worn smooth, with a bell-shaped bow.")

    _scene, _chunks, agent = play("pick up the brass key", CLASSIFY.call("take", "Brass Key"),
                                  "You lift the key.")
    narration_prompt = agent.prompts.last

    assert_match(/ALREADY happened/, narration_prompt)
    assert_match(/has picked up the Brass Key/, narration_prompt)
    assert_match(/bell-shaped bow/, narration_prompt)
    assert_match(/Do not contradict it/, narration_prompt)
  end

  # THE TEST THIS WHOLE BRANCH EXISTS FOR. The narrator says the player pocketed
  # something; the app never resolved a take; nothing is granted. Prose is not a
  # state change and cannot become one.
  test "the narrator cannot grant an item the app did not resolve" do
    key = create(:item, :lying, location: @here, name: "Brass Key")

    assert_no_changes -> { [ key.reload.playthrough_id, key.reload.location_id ] } do
      # The classifier read a take and resolved NOTHING -- the player named
      # something that is not on the floor -- and the narrator then writes the
      # most confident possible sentence about taking it anyway.
      scene, = play("pocket the brass key", CLASSIFY.call("take", "nothing"),
                    "You pick up the brass key and slip it into your coat, and it is yours now.")

      assert_equal @here, scene.location
    end

    assert_equal 0, @playthrough.carried.count
  end

  test "a take of something nobody has ever seen grants nothing and narrates the attempt" do
    assert_no_difference "Item.count" do
      scene, = play("take the silver locket", CLASSIFY.call("take", "Silver Locket"),
                    "There is no locket here, and your hand closes on nothing.")

      assert_equal "There is no locket here, and your hand closes on nothing.", scene.description
    end

    assert_equal 0, @playthrough.carried.count
  end

  # An item somebody is holding is not on the floor, so the classifier never
  # offers it and the loop can never move it. Theft is a different act.
  test "an item in somebody else's hands cannot be taken" do
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    ledger = create(:item, character: landlord, name: "Iron Ledger")

    play("take the ledger", CLASSIFY.call("take", "Iron Ledger"),
         "Grenn's hand closes over the ledger before yours does.")

    assert_equal landlord, ledger.reload.character
  end

  test "a take by a playthrough with nobody to hold the item narrates instead" do
    nobody = create(:playthrough, story: @story, current_location: @here)
    key = create(:item, :lying, location: @here, name: "Brass Key")

    agent = FakeAgent.new(CLASSIFY.call("take", "Brass Key"), "Your hands are not there to take it.")
    BaseAgent.stub(:new, agent) do
      Playthrough::Turn.new(nobody).play("take the key")
    end

    assert_nil key.reload.playthrough_id
    assert_equal @here, key.location
  end

  # --- putting something down ---------------------------------------------

  # THE OTHER DIRECTION, and it is not symmetry for its own sake. An app that
  # owns picking up but leaves putting down to the narrator has records that go
  # stale the first time a player sets something on a table.

  test "dropping something moves the row out of the player's hands and into the room" do
    key = create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    play("put down the key", CLASSIFY.call("drop", "Brass Key"),
         "You set the key on the sill and it slides an inch.")

    key.reload

    assert_nil key.playthrough_id
    assert_equal @here, key.location
    assert_predicate key, :lying?
  end

  # It lands in the ROOM, not nowhere -- which is what makes an inventory a
  # record of the world rather than a note somebody kept.
  test "what the player drops is there to pick up again" do
    key = create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    play("put down the key", CLASSIFY.call("drop", "Brass Key"), "You set the key on the sill.")

    assert_equal [ key ], Playthrough::Classifier.new(@playthrough.reload).items_here
  end

  test "the narrator is told what the app already did when something is dropped" do
    create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    _scene, _chunks, agent = play("put down the key", CLASSIFY.call("drop", "Brass Key"),
                                  "You set the key on the sill.")
    narration_prompt = agent.prompts.last

    assert_match(/ALREADY happened/, narration_prompt)
    assert_match(/no longer carried/, narration_prompt)
    assert_match(/lying in Ashgate Market/, narration_prompt)
  end

  test "a drop costs the story one beat in the room" do
    create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    before = @playthrough.story_now
    scene, = play("put down the key", CLASSIFY.call("drop", "Brass Key"), "You set the key down.")

    assert_equal before + 5.minutes, scene.story_timestamp
  end

  # THE MIRROR OF THE TEST ABOVE, and between them they are the whole claim:
  # prose cannot move an item in EITHER direction.
  test "the narrator cannot put down an item the app did not resolve" do
    key = create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    assert_no_changes -> { [ key.reload.playthrough_id, key.reload.location_id ] } do
      play("leave the key on the sill", CLASSIFY.call("drop", "nothing"),
           "You set the brass key down on the sill and walk away from it for good.")
    end

    assert_equal [ key ], @playthrough.carried.to_a
  end

  test "the narrator cannot give away an item on somebody else's behalf" do
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    ledger = create(:item, character: landlord, name: "Iron Ledger")

    play("make Grenn put down the ledger", CLASSIFY.call("drop", "Iron Ledger"),
         "Grenn sets the ledger on the table and steps back from it.")

    assert_equal landlord, ledger.reload.character
    assert_nil ledger.location_id
  end

  # A playthrough standing nowhere has no room to put anything down in, so the
  # drop does not happen. The turn then fails on the same thing every branch
  # fails on from nowhere -- a `Scene` needs a location -- and the point of the
  # test is what it does NOT do to the item on the way there.
  test "a drop by a playthrough standing nowhere moves nothing" do
    adrift = create(:playthrough, story: @story, character: @protagonist)
    key = create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    agent = FakeAgent.new(CLASSIFY.call("drop", "Brass Key"), "There is no floor here to set it on.")
    assert_raises(ActiveRecord::RecordInvalid) do
      BaseAgent.stub(:new, agent) { Playthrough::Turn.new(adrift).play("put down the key") }
    end

    assert_equal @playthrough, key.reload.playthrough
    assert_nil key.location_id
  end

  # Take, then drop, then take again: the row ends up where the app last put it
  # and nowhere else, which is the only claim an inventory has to make.
  test "an item can be picked up, put down and picked up again" do
    key = create(:item, :lying, location: @here, name: "Brass Key")

    play("take the key", CLASSIFY.call("take", "Brass Key"), "You lift the key.")

    assert_equal @playthrough, key.reload.playthrough

    play("put down the key", CLASSIFY.call("drop", "Brass Key"), "You set the key down.")

    assert_equal @here, key.reload.location
    assert_nil key.playthrough_id

    play("take the key", CLASSIFY.call("take", "Brass Key"), "You lift it again.")

    assert_equal @playthrough, key.reload.playthrough
  end

  # --- what the player typed ----------------------------------------------

  # `Scene#typed` is written by `play` rather than by each branch, so a branch
  # added later cannot forget it. One test per branch, because that is the
  # claim: all four of them, not the one that was easiest to wire.
  test "an arriving turn records what the player typed" do
    connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    scene, = play("go down", CLASSIFY.call("move", "Drowned Vestibule"), DETAIL, { "exits" => [] }, ARRIVAL)

    assert_equal "go down", scene.typed
  end

  test "a talking turn records what the player typed" do
    stands_here("Maren Vosk")

    scene, = play("ask Maren about the flood", CLASSIFY.call("talk", "Maren Vosk"), REACTION,
                  "She looks at the water and says nothing for a while.")

    assert_equal "ask Maren about the flood", scene.typed
  end

  test "a taking turn records what the player typed" do
    create(:item, :lying, location: @here, name: "Brass Key")

    scene, = play("pick up the brass key", CLASSIFY.call("take", "Brass Key"), "You lift the key.")

    assert_equal "pick up the brass key", scene.typed
  end

  test "a dropping turn records what the player typed" do
    create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    scene, = play("put down the brass key", CLASSIFY.call("drop", "Brass Key"), "You set the key down.")

    assert_equal "put down the brass key", scene.typed
  end

  test "a narrated turn records what the player typed" do
    scene, = play("look at the water", CLASSIFY.call("examine", "nothing"), "The water is still.")

    assert_equal "look at the water", scene.typed
  end

  # The opening arrival is world data written before anybody plays, so nobody
  # typed anything to cause it.
  test "an opening arrival has nothing typed" do
    opening = create(:scene, story: @story, location: @here, is_opening: true)

    assert_nil opening.typed
  end

  # --- what the turn did ----------------------------------------------------

  # `Scene#resolved_action` and `Scene#acted_on` are written beside `typed` and
  # for the same reason: this is the one place with the command AND the scene
  # on every branch. One test per branch, again, because that is the claim.
  #
  # WHY IT IS A COLUMN AT ALL: the records carried what the world IS after a
  # turn and never what the turn DID, so a check reading a narration against the
  # state before it had nothing to read. See `Story::Audit#check_take`.
  test "an arriving turn records the move and the room it moved to" do
    there = connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    scene, = play("go down", CLASSIFY.call("move", "Drowned Vestibule"), DETAIL, { "exits" => [] }, ARRIVAL)

    assert_equal "move", scene.resolved_action
    assert_equal there, scene.acted_on
    assert_predicate scene, :moved_to?
  end

  test "a talking turn records the talk and who was spoken to" do
    maren = stands_here("Maren Vosk")

    scene, = play("ask Maren about the flood", CLASSIFY.call("talk", "Maren Vosk"), REACTION,
                  "She looks at the water and says nothing for a while.")

    assert_equal "talk", scene.resolved_action
    assert_equal maren, scene.acted_on
  end

  test "a taking turn records the take and the item it moved" do
    key = create(:item, :lying, location: @here, name: "Brass Key")

    scene, = play("pick up the brass key", CLASSIFY.call("take", "Brass Key"), "You lift the key.")

    assert_equal "take", scene.resolved_action
    assert_equal key, scene.acted_on
    assert_predicate scene, :took?
    assert_not_predicate scene, :dropped?
  end

  test "a dropping turn records the drop and the item it moved" do
    key = create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    scene, = play("put down the brass key", CLASSIFY.call("drop", "Brass Key"), "You set the key down.")

    assert_equal "drop", scene.resolved_action
    assert_equal key, scene.acted_on
    assert_predicate scene, :dropped?
  end

  test "a narrated turn records the action it was read as and no record" do
    scene, = play("look at the water", CLASSIFY.call("examine", "nothing"), "The water is still.")

    assert_equal "examine", scene.resolved_action
    assert_nil scene.acted_on
    assert_equal "examine -> nothing", scene.resolution
  end

  # A REACH THAT FOUND NOTHING IS AN ACTION WITH NO RECORD, which is what that
  # turn really was -- and the same fact `Playthrough::Drift` counts. It must
  # not read as a resolved move.
  test "a move nobody can make records the move and no room" do
    scene, = play("go through the cellar door", CLASSIFY.call("move", "nothing"), "There is no cellar door.")

    assert_equal "move", scene.resolved_action
    assert_nil scene.acted_on
    assert_not_predicate scene, :moved_to?
    assert_equal "move -> nothing", scene.resolution
  end

  # THE ONE PLACE THE RECORD IS NOT THE CLASSIFIER'S ANSWER. A playthrough with
  # no protagonist resolves the item and then cannot carry it, so the branch
  # narrates instead and nothing moved. Writing the item down there would say a
  # row moved that did not, and `Scene#took?` is a seam a check trusts outright.
  test "a take nobody could make records the take and no item" do
    @playthrough.update!(character: nil)
    create(:item, :lying, location: @here, name: "Brass Key")

    scene, = play("pick up the brass key", CLASSIFY.call("take", "Brass Key"), "Nothing here is yours to lift.")

    assert_equal "take", scene.resolved_action
    assert_nil scene.acted_on
    assert_not_predicate scene, :took?
  end

  test "an opening arrival did nothing, and says so" do
    opening = create(:scene, story: @story, location: @here, is_opening: true)

    assert_nil opening.resolved_action
    assert_nil opening.resolution
  end

  test "a turn that produced no scene records nothing rather than raising" do
    stands_here("Maren Vosk")

    assert_nothing_raised do
      scene, = play("say hello", CLASSIFY.call("talk", "Maren Vosk"), REACTION, "")

      assert_nil scene
    end
  end

  # --- failure ------------------------------------------------------------

  # A generator that raises is the documented contract. The loop must not
  # swallow it into a half-move: the player has to still be where they were.
  test "a failed arrival leaves the player where they were" do
    connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    assert_raises(RuntimeError) do
      # Classification succeeds, realization succeeds, the arrival call has
      # nothing queued.
      play("go down", CLASSIFY.call("move", "Drowned Vestibule"), DETAIL, { "exits" => [] })
    end

    @playthrough.reload
    assert_equal @here, @playthrough.current_location
    assert_nil @playthrough.current_scene
  end

  test "moving into a stub that realization left unrealized raises rather than narrating an empty room" do
    connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    assert_raises(ActiveRecord::RecordInvalid) do
      # A detail answer with no description cannot be saved as realized.
      play("go down", CLASSIFY.call("move", "Drowned Vestibule"),
           { "description" => "", "lore" => "" })
    end
  end
  # --- a reach that found nothing is stated, not left to the prose -----------

  # THE NARRATOR USED TO BE TOLD NOTHING about a move that resolved to no exit,
  # so it walked the player through the door anyway and the next arrival
  # contradicted it. The classifier's finding is a fact about the world and it
  # goes through the same `fact:` seam `take` and `drop` use.
  test "a move to nowhere tells the narrator the player has not moved" do
    connect("The Sunken Stair")

    _scene, _chunks, agent = play("go north", CLASSIFY.call("move", "nothing"),
                                  "There is no way north. The wall is solid.")
    prompt = agent.prompts.last

    assert_match(/ALREADY happened/, prompt)
    assert_match(/reached for a way out that does not exist here/, prompt)
    assert_match(/still in Ashgate Market/, prompt)
    assert_match(/Ways out of here: The Sunken Stair\./, prompt)
    assert_equal @here, @playthrough.reload.current_location
  end

  test "a talk to nobody tells the narrator nobody else is here to answer" do
    _scene, _chunks, agent = play("talk to the ghost", CLASSIFY.call("talk", "nothing"),
                                  "Nobody answers.")

    assert_match(/tried to speak to somebody who is not here/, agent.prompts.last)
  end

  test "a take of nothing tells the narrator nothing was picked up" do
    _scene, _chunks, agent = play("pocket the brass key", CLASSIFY.call("take", "nothing"),
                                  "Your hand closes on nothing.")

    assert_match(/reached for something that is not lying here/, agent.prompts.last)
    assert_match(/Nothing was picked up/, agent.prompts.last)
  end

  test "a drop of nothing tells the narrator nothing changed hands" do
    _scene, _chunks, agent = play("drop the crown", CLASSIFY.call("drop", "nothing"),
                                  "You are not carrying any crown.")

    assert_match(/tried to put down something they are not carrying/, agent.prompts.last)
  end

  test "an examine is passed to the narrator as a look" do
    _scene, _chunks, agent = play("look at the stalls", CLASSIFY.call("examine", "nothing"),
                                  "Wet canvas, and under it the smell of fish.")

    assert_match(/looking more closely at something that is here/, agent.prompts.last)
    assert_no_match(/ALREADY happened/, agent.prompts.last)
  end

  # --- reading what is written on something ---------------------------------

  # THE WORDS COME OUT OF THE RECORDS AND GO INTO THE PROMPT VERBATIM. This is
  # the fact `Item#inscription` exists to make possible: the narrator is told
  # what the note says rather than asked what it might say, so two readings of
  # one note agree.
  test "a read hands the narrator the recorded words, quoted" do
    note = create(:item, :lying, :readable, location: @here, name: "folded note")

    scene, _chunks, agent = play("read the note", CLASSIFY.call("examine", "folded note"),
                                 "You unfold it. The ink is smudged but the words are plain.")
    prompt = agent.prompts.last

    assert_includes prompt, %(word for word: "#{note.inscription}")
    assert_includes prompt, "they do not change between readings"
    assert_equal "examine", scene.reload.resolved_action
    assert_equal note, scene.acted_on
  end

  # A SECOND READING IS A DATABASE READ. Two queued responses and no third: if
  # anything asked a model for the words again, the fake would run out and this
  # would fail loudly.
  test "reading the same thing twice quotes the same words and asks nothing again" do
    note = create(:item, :lying, :readable, location: @here, name: "folded note")

    _scene, _chunks, first = play("read the note", CLASSIFY.call("examine", "folded note"), "Once.")
    _scene, _chunks, again = play("read the note again", CLASSIFY.call("examine", "folded note"), "Twice.")

    assert_includes first.prompts.last, note.inscription
    assert_includes again.prompts.last, note.inscription
    assert_equal note.inscription, note.reload.inscription
  end

  # A readable thing nobody has read yet: ONE structured call writes the words
  # as a record, before any prose exists, and never again.
  test "the first read of a readable thing with no words writes them once" do
    note = create(:item, :lying, :unwritten, location: @here, name: "folded note")

    _scene, _chunks, agent = play("read the note", CLASSIFY.call("examine", "folded note"),
                                  { "inscription" => "Come to the west stair. Burn this." },
                                  "You unfold it and read.")

    assert_equal "Come to the west stair. Burn this.", note.reload.inscription
    assert_includes agent.prompts.last, %(word for word: "Come to the west stair. Burn this.")
  end

  # THE GATE. An examine that resolved to a thing with no writing on it narrates
  # exactly as it always did, and nothing generates text for it -- one queued
  # response and no more.
  test "looking at a thing with no writing on it generates nothing and narrates" do
    stamp = create(:item, :lying, location: @here, name: "ward stamp")

    scene, _chunks, agent = play("look at the stamp", CLASSIFY.call("examine", "ward stamp"),
                                 "Brass, worn smooth at the grip.")

    assert_nil stamp.reload.inscription
    assert_not_includes agent.prompts.last, "word for word"
    assert_equal "examine", scene.reload.resolved_action
    assert_equal stamp, scene.acted_on
  end

  # The turn that produced the complaint was a `take`. The words the records
  # already hold go over with the pickup; nothing is generated on this branch.
  test "taking a thing whose words are on record hands them over too" do
    note = create(:item, :lying, :readable, location: @here, name: "folded note")

    _scene, _chunks, agent = play("pickup the note. what does it say?",
                                  CLASSIFY.call("take", "folded note"),
                                  "You unfold it as you lift it.")

    assert_includes agent.prompts.last, "has picked up the folded note"
    assert_includes agent.prompts.last, %(word for word: "#{note.inscription}")
  end

  # AND A TAKE NEVER BECOMES A MODEL CALL. Picking a thing up is not reading it,
  # so a readable thing with no words yet is simply not quoted -- one queued
  # narration, and the fake would raise if anything asked for an inscription.
  test "taking a readable thing with no words on record writes none" do
    note = create(:item, :lying, :unwritten, location: @here, name: "folded note")

    _scene, _chunks, agent = play("take the note", CLASSIFY.call("take", "folded note"),
                                  "You put it in your pocket.")

    assert_nil note.reload.inscription
    assert_not_includes agent.prompts.last, "word for word"
  end

  test "an unclassifiable turn is narrated with no fact and no label" do
    _scene, _chunks, agent = play("hum a tune", CLASSIFY.call("other", "nothing"),
                                  "You hum, and the canvas hums back.")

    assert_no_match(/ALREADY happened/, agent.prompts.last)
    assert_no_match(/looking more closely/, agent.prompts.last)
  end
end
