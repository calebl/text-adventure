require "test_helper"

class Playthrough::DebugTest < ActiveSupport::TestCase
  # THE HARD RULE. This is an observer: it must not generate, mutate a record,
  # or advance a playthrough. Anything else it does is a matter of taste; this
  # is not.
  #
  # Asserted against every table rather than against the ones it happens to
  # read, and against `maximum(:updated_at)` as well as counts, because an
  # update in place moves neither a count nor a max id. The read is deliberately
  # exhaustive -- every public method -- so a future addition that writes is
  # caught by the test that already exists.
  test "reading everything writes nothing" do
    playthrough = rich_playthrough
    before = database_snapshot

    BaseAgent.stub(:new, -> { flunk "the debug view asked a model something" }) do
      read_everything(Playthrough::Debug.new(playthrough))
    end

    assert_equal before, database_snapshot
  end

  # `Story#catch_up_world!` is the one write that would be easy to make by
  # accident: it is what `Playthrough::Turn#play` calls first, and it is the
  # thing that makes a stale mechanic fire. Looking at a world must not move it.
  test "a mechanic with nights owed is reported, not run" do
    playthrough = create(:playthrough, :in_scene)
    mechanic = create(:world_mechanic, story: playthrough.story, cadence: "nightly")
    create(:scene, story: playthrough.story, location: playthrough.current_location,
                   story_timestamp: playthrough.story.start_time + 3.days,
                   previous_scene: playthrough.current_scene).then do |scene|
      playthrough.update!(current_scene: scene)
    end

    debug = Playthrough::Debug.new(playthrough)
    entry = debug.mechanics.sole

    assert_operator entry.owed.size, :>=, 3, "three nights have passed unpaid"
    assert_nil mechanic.reload.last_run_at, "reading the world ran it"
    assert_equal 0, playthrough.story.world_events.count
  end

  # THE BRANCH IS DERIVED, because there is nothing stored to read it from.
  # Each of these is the record shape one branch of `Playthrough::Turn` leaves
  # behind.
  test "an opening arrival is reported as the world's own" do
    playthrough = create(:playthrough)
    opening = create(:location, story: playthrough.story)
    scene = create(:scene, :opening, story: playthrough.story, location: opening)
    playthrough.update!(current_location: opening, current_scene: scene)

    turn = Playthrough::Debug.new(playthrough).latest_turn

    assert_equal :opening, turn.branch
    assert_match(/is_opening/, turn.evidence.join(" "))
  end

  test "a turn that wrote an Interaction is reported as a conversation" do
    playthrough = create(:playthrough, :in_scene)
    scene = next_scene(playthrough, minutes: 10)
    character = create(:character, story: playthrough.story, fullname: "Maren Vosk")
    scene.characters = [ character ]
    create(:interaction, character: character, scene: scene,
                         location: playthrough.current_location, user_input: "ask about the ledger")

    turn = Playthrough::Debug.new(playthrough).latest_turn

    assert_equal :conversation, turn.branch
    assert_equal "ask about the ledger", turn.typed
    assert_match(/Interaction row/, turn.evidence.join(" "))
    assert_equal 'Scene::TURN_MINUTES["conversation"]', turn.cost_reading
  end

  test "a turn that changed location is reported as an arrival" do
    playthrough = create(:playthrough, :in_scene)
    destination = create(:location, story: playthrough.story, name: "Mournwell Lane")
    create(:location_connection, location: playthrough.current_location,
                                 connected_location: destination,
                                 distance: "a short walk", travel_method: "walking")
    scene = create(:scene, story: playthrough.story, location: destination,
                          previous_scene: playthrough.current_scene,
                          story_timestamp: playthrough.current_scene.story_timestamp + 5.minutes)
    playthrough.update!(current_location: destination, current_scene: scene)

    turn = Playthrough::Debug.new(playthrough).latest_turn

    assert_equal :arrival, turn.branch
    assert_match(/location changed/, turn.evidence.join(" "))
    assert_equal "the edge walked -- a short walk, walking", turn.cost_reading
  end

  test "a turn with no interaction, no cast and no move is reported as narration" do
    playthrough = create(:playthrough, :in_scene)
    next_scene(playthrough, minutes: 5)

    turn = Playthrough::Debug.new(playthrough).latest_turn

    assert_equal :narration, turn.branch
    assert_equal 'Scene::TURN_MINUTES["action"]', turn.cost_reading
  end

  # THE POINT OF SHOWING THE COST. Every turn is priced by a fixed table --
  # `Scene::TURN_MINUTES` or an edge's distance and method. A cost that matches
  # neither is how wall-clock time leaking back onto that path would look, and
  # it is the defect the whole story-time work exists to prevent.
  test "a turn priced by no fixed table says so" do
    playthrough = create(:playthrough, :in_scene)
    next_scene(playthrough, minutes: 47)

    assert_match(/matches no fixed table/, Playthrough::Debug.new(playthrough).latest_turn.cost_reading)
  end

  # EVERY BRANCH RECORDS A CAST NOW -- `Playthrough::Turn#play` snapshots
  # `Character.present_in` onto the turn beside `typed` -- so a narrated turn
  # with one is ordinary and the EMPTY one is what is worth saying. What the
  # view reports instead is a snapshot that no longer agrees with the records,
  # which is how somebody having moved since reads.
  test "a cast that no longer matches the room says who has moved since" do
    playthrough = create(:playthrough, :in_scene)
    scene = next_scene(playthrough, minutes: 5)
    grenn = create(:character, story: playthrough.story, fullname: "Grenn Ollivar")
    scene.characters = [ grenn ]

    evidence = Playthrough::Debug.new(playthrough).latest_turn.evidence.join(" ")

    assert_match(/cast recorded \(1\), snapshotted from Character.present_in/, evidence)
    assert_match(/Grenn Ollivar is no longer in this room/, evidence)
  end

  test "a turn with no cast at all says it was played before one was snapshotted" do
    playthrough = create(:playthrough, :in_scene)
    next_scene(playthrough, minutes: 5)

    assert_match(/no cast recorded/, Playthrough::Debug.new(playthrough).latest_turn.evidence.join(" "))
  end

  # THE CLOSED SET, asked of the classifier itself rather than worked out
  # again. If these two ever disagree the view is lying about what the game
  # will accept, which is worse than not showing it.
  test "the candidates are the classifier's own, and the enum is what the schema would offer" do
    playthrough = create(:playthrough, :started)
    playthrough.update!(current_scene: create(:scene, story: playthrough.story,
                                                      location: playthrough.current_location))
    exit_to = create(:location, story: playthrough.story, name: "The Sunken Stair")
    create(:location_connection, location: playthrough.current_location, connected_location: exit_to)
    create(:character, story: playthrough.story, fullname: "Grenn Ollivar", nickname: "Old Grenn",
                       location: playthrough.current_location)

    debug = Playthrough::Debug.new(playthrough)

    assert_equal [ "The Sunken Stair" ], debug.candidate_exits.map(&:name)
    assert_equal [ "Grenn Ollivar" ], debug.candidate_cast.map(&:fullname)
    assert_equal [ "The Sunken Stair", "Grenn Ollivar", "Old Grenn", "nothing" ], debug.candidate_enum
    assert_not_includes debug.candidate_cast, playthrough.character, "the player cannot talk to themselves"
  end

  # THE OTHER TWO CLOSED SETS. Asserted against the classifier's own methods,
  # so the day `take` stops resolving against the floor this fails rather than
  # quietly showing a set the model is not offered.
  test "the enum carries what is lying here and what is carried, as the classifier has them" do
    playthrough = create(:playthrough, :started)
    lantern = create(:item, :lying, location: playthrough.current_location, name: "A cracked lantern")
    ledger = create(:item, character: playthrough.character, name: "A brass ledger")

    debug = Playthrough::Debug.new(playthrough)
    classifier = Playthrough::Classifier.new(playthrough)

    assert_equal classifier.items_here, debug.candidate_items
    assert_equal classifier.items_carried, debug.candidate_carried
    assert_includes debug.candidate_enum, lantern.name
    assert_includes debug.candidate_enum, ledger.name
    assert_includes debug.candidate_enum, Playthrough::IntentSchema::NOTHING
  end

  test "the reconstructed prompt names the items on both sides of the seam" do
    playthrough = create(:playthrough, :started)
    create(:item, :lying, location: playthrough.current_location, name: "A cracked lantern")
    create(:item, character: playthrough.character, name: "A brass ledger")

    prompt = Playthrough::Debug.new(playthrough).classifier_prompt("take the lantern")

    assert_match "A cracked lantern", prompt
    assert_match "A brass ledger", prompt
    assert_match "## What Is Lying Here", prompt
    assert_match "## What The Player Is Carrying", prompt
  end

  test "the reconstructed classifier prompt carries the exits and the cast" do
    playthrough = create(:playthrough, :started)
    exit_to = create(:location, story: playthrough.story, name: "The Sunken Stair")
    create(:location_connection, location: playthrough.current_location, connected_location: exit_to,
                                 distance: "adjacent", travel_method: "climbing")

    prompt = Playthrough::Debug.new(playthrough).classifier_prompt("go down")

    assert_match "The Sunken Stair (adjacent, climbing)", prompt
    assert_match "go down", prompt
  end

  # Connections are written in both directions from one answer, so a missing
  # return edge is a defect and not a shape the world is allowed to have.
  test "a one-way exit is reported as one" do
    playthrough = create(:playthrough, :started)
    neighbour = create(:location, story: playthrough.story)
    create(:location_connection, location: playthrough.current_location, connected_location: neighbour)

    exit = Playthrough::Debug.new(playthrough).exits.sole

    assert exit.one_way?

    create(:location_connection, location: neighbour, connected_location: playthrough.current_location)
    assert_not Playthrough::Debug.new(playthrough).exits.sole.one_way?
  end

  # `Story::Doctor` reports `connection_directions_disagree` story-wide. This is
  # the same question asked of the room the player is standing in, and the two
  # must not disagree about the same rows.
  test "an edge whose two directions disagree is reported as disagreeing" do
    playthrough = create(:playthrough, :started)
    neighbour = create(:location, story: playthrough.story)
    create(:location_connection, location: playthrough.current_location, connected_location: neighbour,
                                 distance: "adjacent", travel_method: "walking")
    back = create(:location_connection, location: neighbour, connected_location: playthrough.current_location,
                                        distance: "adjacent", travel_method: "walking")

    assert_not Playthrough::Debug.new(playthrough).exits.sole.directions_disagree?

    back.update_columns(distance: "a long journey")
    exit = Playthrough::Debug.new(playthrough).exits.sole

    assert exit.directions_disagree?
    assert_not exit.one_way?
  end

  # Nil minutes on an edge that exists is not "no value" -- it is a value the
  # app cannot price, which is the doctor's `unknown_distance`. Reporting it as
  # absent would make the two pages say different things about one row.
  test "an edge priced by no fixed table is reported as unpriceable rather than blank" do
    playthrough = create(:playthrough, :started)
    neighbour = create(:location, story: playthrough.story)
    edge = create(:location_connection, location: playthrough.current_location,
                                        connected_location: neighbour,
                                        distance: "adjacent", travel_method: "walking")

    assert_equal 1.0, Playthrough::Debug.new(playthrough).exits.sole.minutes
    assert_not Playthrough::Debug.new(playthrough).exits.sole.unpriceable?

    edge.update_columns(distance: "a short walk down the flooded lanes")
    exit = Playthrough::Debug.new(playthrough).exits.sole

    assert exit.unpriceable?
    assert_nil exit.minutes
  end

  # `Story#clock` is the high-water mark across every playthrough, because the
  # world moves for everybody; a player's own next turn follows on from THEIR
  # last one. Two playthroughs of one world is where that stops being academic.
  test "the story's clock and this player's own moment are reported separately" do
    story = create(:story)
    location = create(:location, story: story)
    behind = create(:playthrough, story: story, current_location: location)
    behind.update!(current_scene: create(:scene, story: story, location: location,
                                                 story_timestamp: story.start_time + 1.hour))
    create(:scene, story: story, location: location, story_timestamp: story.start_time + 9.hours)

    debug = Playthrough::Debug.new(behind)

    assert_equal story.start_time + 9.hours, debug.story_clock
    assert_equal story.start_time + 1.hour, debug.story_now
  end

  test "the map counts stubs and realized places apart" do
    playthrough = create(:playthrough, :started)
    create(:location, :stub, story: playthrough.story)
    create(:location, :stub, story: playthrough.story)

    debug = Playthrough::Debug.new(playthrough)

    assert_equal 2, debug.stub_count
    assert_equal 1, debug.realized_count
  end

  # NOTHING RECORDS WHERE A CHARACTER STANDS, so "last seen" is the whole of
  # what the game knows -- and a character nobody has met is honestly nowhere
  # rather than somewhere the view invented for them.
  test "the cast says where each person was last recorded, and says when nobody knows" do
    playthrough = create(:playthrough, :in_scene)
    met = create(:character, story: playthrough.story, fullname: "Grenn Ollivar")
    unmet = create(:character, story: playthrough.story, fullname: "Isbet Marrow")
    playthrough.current_scene.characters = [ met ]

    people = Playthrough::Debug.new(playthrough).cast.index_by { |person| person.character.fullname }

    assert people["Grenn Ollivar"].seen?
    assert_equal playthrough.current_location, people["Grenn Ollivar"].last_scene.location
    assert_not people["Isbet Marrow"].seen?
    assert_equal 1, Playthrough::Debug.new(playthrough).unseen_count
  end

  test "the cast reports the latest scene a person was in, not the first" do
    playthrough = create(:playthrough, :in_scene)
    grenn = create(:character, story: playthrough.story)
    playthrough.current_scene.characters = [ grenn ]
    lane = create(:location, story: playthrough.story, name: "Mournwell Lane")
    later = create(:scene, story: playthrough.story, location: lane,
                           story_timestamp: playthrough.current_scene.story_timestamp + 1.hour)
    later.characters = [ grenn ]

    person = Playthrough::Debug.new(playthrough).cast.sole

    assert_equal lane, person.last_scene.location
  end

  # The map answers "who is here" with the HOLDOVER rule -- the same read
  # `Scene::Generator#holdovers` makes -- so the view and the game agree about
  # who the player will find. The protagonist and companions travel with the
  # player and would otherwise appear in every row, saying nothing.
  test "the map says who the game believes is standing in each place" do
    playthrough = create(:playthrough, :started)
    story = playthrough.story
    here = playthrough.current_location
    lane = create(:location, story: story, name: "Mournwell Lane")
    empty = create(:location, :stub, story: story, name: "The Celestial Spire")

    create(:character, story: story, fullname: "Grenn Ollivar", location: lane)
    playthrough.update!(current_scene: create(:scene, story: story, location: here,
                                                       story_timestamp: story.start_time + 5.minutes))

    places = Playthrough::Debug.new(playthrough).places.index_by { |place| place.location.name }

    assert_equal [ "Grenn Ollivar" ], places["Mournwell Lane"].cast.map(&:fullname)
    assert_empty places["The Celestial Spire"].cast
    assert places[here.name].here, "the place the player is standing in is marked"
    assert_not places["Mournwell Lane"].here
  end

  # The map reads `Character.present_in`, not a scene's cast, so no turn can
  # empty a room -- which is what a narrated turn used to do here, because the
  # view read back the last scene that had recorded anybody. A scene whose
  # snapshot is stale does not put anybody back either.
  test "no turn can empty a room the records have somebody in" do
    playthrough = create(:playthrough, :started)
    story = playthrough.story
    here = playthrough.current_location
    grenn = create(:character, story: story, fullname: "Grenn Ollivar", location: here)

    create(:scene, story: story, location: here, story_timestamp: story.start_time)
    create(:scene, story: story, location: here, story_timestamp: story.start_time + 5.minutes)

    place = Playthrough::Debug.new(playthrough).places.find { |candidate| candidate.location == here }

    assert_equal [ "Grenn Ollivar" ], place.cast.map(&:fullname)
  end

  # The chain is shared with the play page so the two cannot disagree about
  # which turns belong to this playthrough.
  test "the turn log is this playthrough's chain and nobody else's" do
    story = create(:story)
    location = create(:location, story: story)
    opening = create(:scene, :opening, story: story, location: location, description: "The story opens here.")
    mine = create(:playthrough, story: story, current_location: location)
    mine.update!(current_scene: create(:scene, story: story, location: location,
                                                description: "I turned left.", previous_scene: opening))
    create(:scene, story: story, location: location, description: "Somebody else turned right.",
                   previous_scene: opening)

    descriptions = Playthrough::Debug.new(mine).turns.map { |turn| turn.scene.description }

    assert_equal [ "The story opens here.", "I turned left." ], descriptions
  end

  test "enabled? is local by default and TA_DEBUG_VIEW overrides it either way" do
    assert Playthrough::Debug.enabled?, "the test environment is local"

    with_env("TA_DEBUG_VIEW", "0") { assert_not Playthrough::Debug.enabled? }
    with_env("TA_DEBUG_VIEW", "false") { assert_not Playthrough::Debug.enabled? }
    with_env("TA_DEBUG_VIEW", "1") { assert Playthrough::Debug.enabled? }
  end

  # --- what the records say about the prose --------------------------------

  # The sweep is the third clause of the standing constraint and the debug view
  # is where it becomes visible. It must stay read-only -- covered by the
  # exhaustive test at the top of this file -- and it must scope to this
  # playthrough's own turns rather than showing another player's.
  test "contradictions are reported for this playthrough's turns only" do
    playthrough = create(:playthrough, :in_scene)
    story = playthrough.story
    landlord = create(:character, story: story, fullname: "Grenn Ollivar")
    create(:item, character: landlord, name: "revolver", updated_at: 1.year.ago)
    playthrough.current_scene.update!(description: "You reach into your coat and draw your revolver.")

    elsewhere = create(:playthrough, story: story, current_location: playthrough.current_location)
    other_scene = create(:scene, story: story, location: playthrough.current_location,
                                 description: "You draw your revolver again, elsewhere.")
    elsewhere.update!(current_scene: other_scene)

    flags = Playthrough::Debug.new(playthrough).contradictions

    assert_equal 1, flags.size
    assert_equal :item_not_held, flags.first.code
    assert_equal playthrough.current_scene, flags.first.scene
  end

  test "drift is this playthrough's own, newest first" do
    playthrough = create(:playthrough, :in_scene)
    create(:playthrough_drift, playthrough: playthrough, action: "move",
                               command: "go through the cellar door", story_timestamp: 1.hour.from_now)
    create(:playthrough_drift, :talk, playthrough: playthrough, story_timestamp: 2.hours.from_now)
    create(:playthrough_drift, playthrough: create(:playthrough))

    debug = Playthrough::Debug.new(playthrough)

    assert_equal 2, debug.drifts.size
    assert_equal "talk", debug.drifts.first.action, "newest first"
    assert_equal({ "move" => 1, "talk" => 1 }, debug.drift_tally)
  end

  # BESIDE THE DRIFTS AND NEVER ADDED TO THEM: one is a reach that found
  # nothing, the other a reach that found more than a turn can answer.
  test "what a line named twice is this playthrough's own, newest first" do
    playthrough = create(:playthrough, :in_scene)
    create(:playthrough_overreach, playthrough: playthrough, story_timestamp: 1.hour.from_now)
    create(:playthrough_overreach, :talk, playthrough: playthrough, story_timestamp: 2.hours.from_now)
    create(:playthrough_overreach, playthrough: create(:playthrough))

    debug = Playthrough::Debug.new(playthrough)

    assert_equal 2, debug.overreaches.size
    assert_equal "talk", debug.overreaches.first.action, "newest first"
    assert_equal({ "take" => 1, "talk" => 1 }, debug.overreach_tally)
  end

  test "the two counters are read apart and never summed" do
    playthrough = create(:playthrough, :in_scene)
    create(:playthrough_drift, playthrough: playthrough)
    create(:playthrough_overreach, playthrough: playthrough)

    debug = Playthrough::Debug.new(playthrough)

    assert_equal 1, debug.drifts.size
    assert_equal 1, debug.overreaches.size
    assert_empty debug.drifts.map(&:class) & debug.overreaches.map(&:class)
  end

  test "a clean playthrough reports no contradictions and no drift" do
    debug = Playthrough::Debug.new(create(:playthrough, :in_scene))

    assert_empty debug.contradictions
    assert_empty debug.drifts
    assert_empty debug.drift_tally
    assert_empty debug.overreaches
    assert_empty debug.overreach_tally
  end

  # --- what the player thought -----------------------------------------------

  # The verdict is carried on the turn it judges, so the panel that reports the
  # branch and the models can report the judgement beside them.
  test "a turn carries the verdict recorded on it" do
    playthrough = create(:playthrough, :in_scene)
    create(:playthrough_feedback, :frozen, playthrough: playthrough,
                                           scene: playthrough.current_scene, verdict: "good")

    turn = Playthrough::Debug.new(playthrough).latest_turn

    assert_predicate turn, :judged?
    assert_equal "good", turn.feedback.verdict
    assert_equal "mistralai/mistral-medium-3.1", turn.feedback.prose_model
  end

  test "a turn nobody judged says so rather than carrying an empty verdict" do
    playthrough = create(:playthrough, :in_scene)

    assert_not_predicate Playthrough::Debug.new(playthrough).latest_turn, :judged?
  end

  # THE QUESTION THE INSTRUMENT EXISTS FOR: which model do the turns marked good
  # actually come from. Counted off the FROZEN provenance, never off `chats`, so
  # a turn whose conversations were pruned months ago still counts.
  test "verdicts are counted against the model that wrote the prose" do
    playthrough = create(:playthrough, :in_scene)
    mistral = "mistralai/mistral-medium-3.1"
    minimax = "minimax/minimax-m3"

    create(:playthrough_feedback, playthrough: playthrough, scene: playthrough.current_scene,
                                  verdict: "good", prose_model: mistral, answering_models: mistral)
    create(:playthrough_feedback, playthrough: playthrough, scene: next_scene(playthrough, minutes: 5),
                                  verdict: "good", prose_model: mistral, answering_models: mistral)
    create(:playthrough_feedback, playthrough: playthrough, scene: next_scene(playthrough, minutes: 5),
                                  verdict: "bad", prose_model: minimax, answering_models: minimax)

    debug = Playthrough::Debug.new(playthrough)

    assert_equal({ "good" => 2, "bad" => 1 }, debug.feedback_tally)
    assert_equal({ "good" => 2 }, debug.feedback_by_model.fetch(mistral))
    assert_equal({ "bad" => 1 }, debug.feedback_by_model.fetch(minimax))
    assert_equal 3, debug.feedback.size
    assert_equal "bad", debug.feedback.first.verdict, "newest first"
  end

  # A verdict recorded after its turn's receipts were pruned has no model on it,
  # and that row STAYS in the cross-tab under a nil key. Dropping it would
  # quietly shrink the denominator of every comparison read off this page.
  test "a verdict with no frozen model is counted as one, not dropped" do
    playthrough = create(:playthrough, :in_scene)
    create(:playthrough_feedback, playthrough: playthrough, scene: playthrough.current_scene,
                                  verdict: "weak")

    assert_equal({ "weak" => 1 }, Playthrough::Debug.new(playthrough).feedback_by_model.fetch(nil))
  end

  private

  # A playthrough with one of everything the view reads.
  def rich_playthrough
    playthrough = create(:playthrough, :started)
    story = playthrough.story
    here = playthrough.current_location

    neighbour = create(:location, :stub, story: story)
    create(:location_connection, location: here, connected_location: neighbour)
    create(:location_connection, location: neighbour, connected_location: here)

    opening = create(:scene, :opening, story: story, location: here, story_timestamp: story.start_time)
    talk = create(:scene, story: story, location: here, previous_scene: opening,
                          story_timestamp: story.start_time + 10.minutes)
    character = create(:character, story: story)
    talk.characters = [ character ]
    create(:interaction, character: character, scene: talk, location: here)
    playthrough.update!(current_scene: talk)

    mechanic = create(:world_mechanic, story: story)
    create(:world_event, :with_locations, world_mechanic: mechanic, story: story)

    # A verdict on the turn, so "reading everything writes nothing" covers the
    # feedback readers with rows to read rather than with an empty table.
    create(:playthrough_feedback, :frozen, :with_note, playthrough: playthrough, scene: talk)

    playthrough
  end

  def next_scene(playthrough, minutes:)
    scene = create(:scene, story: playthrough.story, location: playthrough.current_location,
                           previous_scene: playthrough.current_scene,
                           story_timestamp: playthrough.current_scene.story_timestamp + minutes.minutes)
    playthrough.update!(current_scene: scene)
    scene
  end

  # Every public method, so a future addition that writes is caught by the test
  # that is already here rather than by one somebody remembers to add.
  def read_everything(debug)
    (Playthrough::Debug.public_instance_methods(false) - [ :classifier_prompt ]).each do |name|
      debug.public_send(name)
    end
    debug.classifier_prompt
  end

  # Row counts and the newest `updated_at` per table: a count catches an insert
  # or a delete, the timestamp catches an update in place.
  def database_snapshot
    ActiveRecord::Base.connection.tables.sort.to_h do |table|
      rows = ActiveRecord::Base.connection.select_all("SELECT COUNT(*) AS c FROM #{table}").first["c"]
      updated =
        if ActiveRecord::Base.connection.column_exists?(table, :updated_at)
          ActiveRecord::Base.connection.select_all("SELECT MAX(updated_at) AS m FROM #{table}").first["m"]
        end

      [ table, [ rows, updated ] ]
    end
  end

  def with_env(key, value)
    had = ENV.key?(key)
    previous = ENV[key]
    ENV[key] = value
    yield
  ensure
    had ? ENV[key] = previous : ENV.delete(key)
  end
end
