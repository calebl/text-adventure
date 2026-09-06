require "test_helper"
require "turbo/broadcastable/test_helper"

class NarrationJobTest < ActiveJob::TestCase
  include Turbo::Broadcastable::TestHelper

  # Never a live model: the fake stands in at the BaseAgent boundary, so these
  # pass with no API key and no ollama running. The queued responses are the
  # turn's model calls in order -- classification first, then whatever the
  # classification led to.
  NOT_A_MOVE = { "intent" => "other", "target" => "nothing" }.freeze

  # Long enough that batching has something to do: BATCH_SIZE is 20 characters,
  # and the fake streams a word at a time the way RubyLLM streams tokens.
  NARRATION = "The ledger falls open on a page of names, and every one of them " \
              "has been struck through twice.".freeze

  def play(playthrough, command, *responses)
    agent = FakeAgent.new(*responses)

    capture_turbo_stream_broadcasts(playthrough) do
      BaseAgent.stub(:new, agent) { NarrationJob.perform_now(playthrough.id, command) }
    end
  end

  def appends(streams)
    streams.select { |s| s["action"] == "append" }
  end

  test "narrates a turn, appends the prose, and persists it" do
    playthrough = create(:playthrough, :started)

    streams = play(playthrough, "open the ledger", NOT_A_MOVE, NARRATION)

    assert_equal NARRATION, appends(streams).map(&:text).join
    assert_equal [ "stream" ], appends(streams).map { |s| s["target"] }.uniq

    scene = playthrough.reload.current_scene
    assert_equal NARRATION, scene.description
    assert_equal playthrough.current_location, scene.location
  end

  # THE MEASUREMENT THAT SET BATCH_SIZE. One broadcast per token is ~75 bytes of
  # `<turbo-stream>` framing per token, and in production one row in
  # `solid_cable_messages` per token as well -- ~400 inserts for one narration
  # from a hosted model. So every batch but the last carries at least
  # BATCH_SIZE characters, and the remainder is flushed when the turn ends.
  test "batches the prose rather than broadcasting a token at a time" do
    playthrough = create(:playthrough, :started)

    batches = appends(play(playthrough, "open the ledger", NOT_A_MOVE, NARRATION)).map(&:text)

    assert_operator batches.count, :<, NARRATION.split.count,
                    "batching should broadcast fewer times than there are words"
    batches[0..-2].each do |batch|
      assert_operator batch.length, :>=, NarrationJob::BATCH_SIZE
    end
    assert_equal NARRATION, batches.join
  end

  # The end of the turn is a `replace` of the whole `#turn_log`, which is what
  # takes the place of the reload the SSE `done` handler used to do: the new turn
  # in the log, the location line, and the input, all in one element.
  test "finishes by replacing the turn log with the log, the place and the input" do
    playthrough = create(:playthrough, :started)

    streams = play(playthrough, "open the ledger", NOT_A_MOVE, NARRATION)
    replace = streams.last

    assert_equal "replace", replace["action"]
    assert_equal "turn_log", replace["target"]
    assert_match NARRATION, replace.to_html
    assert_match "You are in", replace.to_html
    assert_match "what do you do?", replace.to_html
  end

  # THE VERDICT IS AVAILABLE ON THE TURN THAT JUST LANDED, which is the whole
  # point of it being unobtrusive: judging a turn is a click on the paragraph he
  # has just finished reading, with no reload to wait for. The broadcast carries
  # the footers because it re-renders the log out of the records, which is also
  # why a verdict recorded a moment earlier survives the replacement.
  test "the finished log carries the verdict controls for the new turn" do
    playthrough = create(:playthrough, :started)

    replace = play(playthrough, "open the ledger", NOT_A_MOVE, NARRATION).last

    assert_match "footer class=\"verdict\"", replace.to_html
    assert_match %(id="verdict_scene_#{playthrough.reload.current_scene.id}"), replace.to_html
  end

  # The dimming rule is `.log:not(.streaming) > .entry:last-of-type .turn`, so the
  # finished log must not still claim to be streaming -- otherwise the turn the
  # player just took stays dim.
  test "the finished log is no longer marked as streaming" do
    playthrough = create(:playthrough, :started)

    replace = play(playthrough, "open the ledger", NOT_A_MOVE, NARRATION).last

    assert_match 'class="log"', replace.to_html
    assert_no_match(/cursor/, replace.to_html)
  end

  # THE ONE ATTRIBUTE THAT MUST NOT GO OVER THE CABLE.
  #
  # Turbo's stream renderer focuses the first `[autofocus]` element in a
  # broadcast with a plain `.focus()` -- no `preventScroll` -- so a broadcast
  # carrying it drags the viewport to the foot of the log at the end of every
  # turn, which is the scroll position this whole change exists to keep. Caught
  # in a browser, and this is what stops it coming back. `play.js` restores
  # focus itself, with `preventScroll`.
  test "the broadcast form does not carry autofocus" do
    playthrough = create(:playthrough, :started)

    replace = play(playthrough, "open the ledger", NOT_A_MOVE, NARRATION).last

    assert_match "what do you do?", replace.to_html
    assert_no_match(/autofocus/, replace.to_html)
  end

  # A move is the branch that cannot stream -- realizing a room is two schema'd
  # calls and the arrival is a third -- so it yields its finished paragraph in
  # one piece. The browser does not know or care which branch the turn took.
  test "streams a move, and the player ends up somewhere else" do
    playthrough = create(:playthrough, :started)
    here = playthrough.current_location
    there = create(:location, story: playthrough.story, name: "The Sunken Stair")
    create(:location_connection, location: here, connected_location: there,
                                 distance: "adjacent", travel_method: "taking stairs")

    streams = play(playthrough, "take the stairs down",
                   { "intent" => "move", "target" => "The Sunken Stair" },
                   { "description" => "The stair gives under you.", "summary" => "They go down." })

    assert_equal "The stair gives under you.", appends(streams).map(&:text).join

    playthrough.reload
    assert_equal there, playthrough.current_location
    assert_equal "The stair gives under you.", playthrough.current_scene.description
  end

  # NOBODY HAS TO BE WATCHING. This is the durability half: the job holds no
  # connection, so there is no client to disconnect and nothing to abort. The
  # turn is persisted whether or not a browser is subscribed, and the finished
  # `#turn_log` is broadcast to whoever reopens the page.
  test "a turn nobody is listening to still lands" do
    playthrough = create(:playthrough, :started)

    BaseAgent.stub(:new, FakeAgent.new(NOT_A_MOVE, NARRATION)) do
      NarrationJob.perform_now(playthrough.id, "open the ledger")
    end

    assert_equal NARRATION, playthrough.reload.current_scene.description
  end

  # A failed turn used to leave a dead cursor and no input, so the only way on
  # was a reload. The player is still standing where they were; they get a line
  # saying the turn did not finish, and the input back.
  test "a failed turn returns the input along with a line saying so" do
    playthrough = create(:playthrough, :started)

    # Nothing queued, so classification raises.
    streams = play(playthrough, "open the ledger")
    replace = streams.last

    assert_equal "replace", replace["action"]
    assert_match "alert", replace.to_html
    assert_match "what do you do?", replace.to_html
    assert_nil playthrough.reload.current_scene
  end

  # WHAT THE PLAYER READS IS THE APP'S, NOT THE EXCEPTION'S. `finish(error:
  # e.message)` put the raise's own text in the `.alert`, so a turn that lost a
  # character sheet to the truncation guard told the player about a
  # 320-character cap and quoted the fragment the app had just decided not to
  # keep. Every reason a turn fails is internal; none of them is a thing the
  # player did or can fix.
  test "a failed turn shows the app's own copy and never the exception's text" do
    playthrough = create(:playthrough, :started)
    raised = "generated text arrived at its 320-character cap (320 characters), so it " \
             'was cut off rather than finished: "...his own workspace,."'

    html = play(playthrough, "ask him about the ledger", NOT_A_MOVE,
                SanitizesGeneratedText::TruncatedTextError.new(raised)).last.to_html

    assert_match Playthrough::TurnFailureNotice::MESSAGE, html
    assert_no_match(/320-character cap/, html, "an internal cap is not the player's business")
    assert_no_match(/own workspace/, html, "and neither is a fragment of the suppressed answer")
  end

  # THE REASON IS NOT LOST, it moves. The log keeps the class and the message in
  # full, which is where somebody debugging a turn looks.
  test "the full error still reaches the log" do
    playthrough = create(:playthrough, :started)
    written = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(written)

    play(playthrough, "ask him about the ledger", NOT_A_MOVE,
         SanitizesGeneratedText::TruncatedTextError.new("cut off at its 320-character cap"))

    assert_match(/Narration failed/, written.string)
    assert_match(/TruncatedTextError/, written.string)
    assert_match(/cut off at its 320-character cap/, written.string)
  ensure
    Rails.logger = original
  end

  # The same copy whatever failed, so no branch can leak a message of its own.
  test "every failed turn reads the same, whichever call failed" do
    %w[classifier narrator].each do |failing|
      playthrough = create(:playthrough, :started)
      queued = failing == "classifier" ? [] : [ NOT_A_MOVE, RubyLLM::Error.new(nil, "502 Bad Gateway") ]

      html = play(playthrough, "open the ledger", *queued).last.to_html

      assert_match Playthrough::TurnFailureNotice::MESSAGE, html
      assert_no_match(/Bad Gateway/, html)
      assert_no_match(/FakeAgent/, html, "an internal message is not player-facing copy")
    end
  end

  # `html:` is inserted verbatim, so the narrator's own prose has to be escaped
  # on the way out -- a model that writes "a < b" would otherwise open a tag
  # inside the turn the player is reading.
  test "prose the model wrote is escaped rather than parsed as markup" do
    playthrough = create(:playthrough, :started)
    prose = "The sign reads <ALL DEBTS SETTLED> & nobody believes it, not once."

    streams = play(playthrough, "read the sign", NOT_A_MOVE, prose)

    assert_equal prose, appends(streams).map(&:text).join
    html = appends(streams).map(&:to_html).join
    assert_match "&lt;ALL ", html
    assert_match "SETTLED&gt;", html
    assert_match "&amp;", html
  end

  # --- the one failure the app answers itself --------------------------------

  # THE INTERCEPTION, END TO END. `BaseAgent` suppressed a response that
  # answered the turn with a real-world crisis line, so no scene was written and
  # the player gets something the app wrote instead: outside the fiction, in the
  # app's voice, and NOT styled as an error, because nothing went wrong.
  test "a suppressed crisis response leaves no scene and shows the app's own message" do
    playthrough = create(:playthrough, :started)

    streams = play(playthrough, "tell him nobody would miss him",
                   NOT_A_MOVE, BaseAgent::CrisisResponseError)
    replace = streams.last

    assert_equal "replace", replace["action"]
    assert_equal "turn_log", replace["target"]
    assert_match Playthrough::SafetyNotice::HEADING, replace.to_html
    assert_match "what do you do?", replace.to_html, "the player still gets the input back"
    assert_no_match(/class="alert"/, replace.to_html,
                    "nothing failed, so it must not read as an error")
    assert_nil playthrough.reload.current_scene, "and the model's version is not a scene"
  end

  # AT THE FOOT OF THE LOG, WHERE THE TURN WOULD HAVE BEEN, and not above it
  # with the error. The play page anchors at `#bottom`, so a message above a
  # long transcript is a message the player has to scroll up to find -- and this
  # is the one message in the app that must be where they are already looking.
  test "the safety message stands where the turn would have been" do
    playthrough = create(:playthrough, :started)

    html = play(playthrough, "tell him to do it", NOT_A_MOVE, BaseAgent::CrisisResponseError).last.to_html
    notice = html.index(Playthrough::SafetyNotice::HEADING)

    assert_operator notice, :>, html.index('class="log"'), "it belongs below the log, not above it"
    assert_operator notice, :<, html.index("what do you do?"), "and above the input the player types into"
  end

  # AN ORDINARY REFUSAL IS NOT THIS. It rotates inside `BaseAgent#ask`, and only
  # an exhausted rotation reaches here -- as a failed turn, with the reason,
  # like any other. The safety message belongs to one branch and stays there.
  test "an exhausted refusal is a failed turn and not a safety message" do
    playthrough = create(:playthrough, :started)

    replace = play(playthrough, "narrate it", NOT_A_MOVE, BaseAgent::RefusalError).last

    assert_match "alert", replace.to_html
    assert_no_match(/game speaking/, replace.to_html)
    assert_nil playthrough.reload.current_scene
  end

  test "a turn that lands normally says nothing out of band" do
    playthrough = create(:playthrough, :started)

    replace = play(playthrough, "open the ledger", NOT_A_MOVE, NARRATION).last

    assert_no_match(/game speaking/, replace.to_html)
    assert_no_match(/notice/, replace.to_html)
  end

  test "a turn for a playthrough that is gone is dropped rather than raised" do
    assert_nothing_raised { NarrationJob.perform_now(0, "open the ledger") }
  end

  # --- the line the engine will not play -------------------------------------

  # THE CAPTAIN'S RULING OF 2026-09-04, END TO END IN THE BROWSER. Two acts on
  # one line: nothing is written, no narrator is asked, and the player reads the
  # engine's own words and gets the input back so the next line can follow.
  #
  # `NOT_A_MOVE` and nothing else is queued -- the FakeAgent raises when it runs
  # out -- so a narrator call on this path would fail the test.
  test "two acts on one line arrive as a refusal with the input back" do
    playthrough = create(:playthrough, :started)
    here = playthrough.current_location
    index = create(:item, :lying, location: here, name: "Perrin's private index")
    apron = create(:item, :lying, location: here, name: "copy-room apron")

    streams = play(playthrough, "pick up the index and the apron",
                   { "intent" => "take", "target" => index.name, "also_named" => apron.name })
    replace = streams.last

    assert_empty appends(streams), "a refusal is the app's paragraph, not prose arriving"
    assert_equal "replace", replace["action"]
    assert_equal "turn_log", replace["target"]
    assert_match "two things at once", replace.to_html
    assert_match "One line is one act", replace.to_html
    assert_match "pick up the index and the apron", replace.to_html, "the line it refused is echoed"
    assert_match "what do you do?", replace.to_html, "and the next line can follow"
    assert_no_match(/class="alert"/, replace.to_html, "nothing failed, so it must not read as an error")

    assert_nil playthrough.reload.current_scene, "no turn was written"
    assert_nil index.reload.playthrough_id
    assert_nil apron.reload.playthrough_id
  end

  # THE OTHER SHAPE: a reach the records cannot answer. It names what IS here,
  # which `Playthrough::Mechanics` leaves to its read-out and the browser has to
  # say out loud.
  test "a reach that found nothing arrives as a refusal naming what is here" do
    playthrough = create(:playthrough, :started)
    create(:item, :lying, location: playthrough.current_location, name: "ward stamp")

    replace = play(playthrough, "pick up the cellar key",
                   { "intent" => "take", "target" => "nothing" }).last.to_html

    assert_match "did not resolve to anything lying here", replace
    assert_match "Lying here: ward stamp.", replace
    assert_match "what do you do?", replace
    assert_nil playthrough.reload.current_scene
    assert_equal 1, playthrough.drifts.count, "and the drift row is taken as it always was"
  end

  # WHERE IT STANDS is the safety notice's place, for the same reason: the page
  # anchors at `#bottom`, so a message above a long transcript is one the player
  # has to scroll up to find.
  test "a refusal stands below the log and above the input" do
    playthrough = create(:playthrough, :started)

    html = play(playthrough, "go down to the cellar",
                { "intent" => "move", "target" => "nothing" }).last.to_html
    refusal = html.index("Nothing has changed")

    assert_operator refusal, :>, html.index('class="log"')
    assert_operator refusal, :<, html.index("what do you do?")
  end

  # A ROUND OF A FIGHT, END TO END, THROUGH THE BROWSER'S OWN PATH AND FOR NO
  # MODEL CALL.
  #
  # `BaseAgent.new` is replaced by something that RAISES for the length of the
  # turn -- the guard `EngineSweep` uses -- so this is not "we did not notice a
  # call", it is "a call would have failed the test". The line the panel's
  # button posts is slashed, so `Playthrough::Grammar` reads it and the
  # classifier is never reached; `Playthrough::Turn#strike_at` writes a
  # `Playthrough::Blow` and calls no narrator; the riposte answers in the same
  # turn. NOTHING IS STREAMED -- there is no prose to stream -- and the panel
  # arrives on the ordinary end-of-turn `#turn_log` replace, which is the whole
  # of the Turbo story here.
  test "a button's line plays a whole round with no model call, and the panel comes back with it" do
    playthrough = fighting_playthrough
    opening = playthrough.current_scene
    exploded = ->(*) { raise "a round of a fight must make no model call" }

    streams = capture_turbo_stream_broadcasts(playthrough) do
      BaseAgent.stub(:new, exploded) do
        NarrationJob.perform_now(playthrough.id, "/attack Marek Sollen")
      end
    end

    assert_empty appends(streams), "an engine-only round streams no prose"

    replace = streams.last.to_html

    # THE PANEL COMES BACK AS A ROUND BOUNDARY: the round just fought, who
    # fought it, and the round the next line lands on. `/attack Marek Sollen`
    # IS round 1 -- the captain's ruling of 2026-09-05, *keep attack as a
    # blow* -- so this one turn produced both halves of the exchange and the
    # panel says so rather than appearing at `Round 2` unexplained.
    assert_match "A fight in The Bell of Saint Aravel.", replace
    assert_match "Round 1 is done: you struck Marek Sollen, and Marek Sollen answered. " \
                 "The fight is on because you struck.", replace
    assert_match "Round 2: what do you do?", replace
    assert_match(/Hero Protagonist hit Marek Sollen for \d+ \(round 1\)/, replace)
    assert_match(/Marek Sollen hit Hero Protagonist for \d+ \(round 1\)/, replace)
    assert_match "/attack Marek Sollen", replace, "and the button is back for the next round"
    # TWO BLOWS: the player's own and the one live foe's answer. A round is the
    # turn -- the captain's call C5.
    assert_equal 2, playthrough.blows.count
    assert_equal opening, playthrough.reload.current_scene,
                 "an attack writes no Scene of its own -- the blow rows are the record"
  end

  # AND THE PANEL GOES WHEN THE FIGHT DOES, on the same replace: the last foe
  # falls, `Playthrough::Fight#close!` writes the one Scene that says so, and
  # the ordinary log has it. The panel and the log agree because neither is
  # holding any state the other could contradict.
  test "the closing scene lands in the log and the panel is gone with it" do
    playthrough = fighting_playthrough
    monster = playthrough.story.characters.find_by(fullname: "Marek Sollen")
    # Down to one hit point, so the next blow of any die ends it whatever the
    # face -- `Roll`'s seed is built out of row ids and no fixture may depend on
    # one.
    Playthrough::Turn.new(playthrough).harm!(monster, monster.max_hp - 1)
    exploded = ->(*) { raise "closing a fight must make no model call" }

    streams = capture_turbo_stream_broadcasts(playthrough) do
      BaseAgent.stub(:new, exploded) do
        NarrationJob.perform_now(playthrough.id, "/attack Marek Sollen")
      end
    end

    replace = streams.last.to_html

    assert_no_match(/A fight\. The Bell of Saint Aravel/, replace)
    assert_match "The fight in The Bell of Saint Aravel is over", replace
    assert_match "Marek Sollen is dead.", replace
    assert_match "what do you do?", replace, "and the ordinary loop resumes"
    assert_predicate playthrough.reload.current_scene, :engine_authored?
  end

  private

  # A GAME STANDING IN FRONT OF A MONSTER. Level 3 with a d8 on both sides,
  # which is 18 hit points (the captain's call C1) and is fixed here for
  # `Playthrough::Fight`'s stated reason: a fixture must never depend on which
  # face came up.
  def fighting_playthrough
    story = create(:story)
    room = create(:location, story: story, name: "The Bell of Saint Aravel")
    hero = create(:character, :protagonist, story: story, level: 3, hit_die: 8)
    create(:character, :monster, story: story, location: room, fullname: "Marek Sollen",
                                 level: 3, hit_die: 8)
    create(:playthrough, story: story, character: hero, current_location: room,
                         current_scene: create(:scene, story: story, location: room))
  end
end
