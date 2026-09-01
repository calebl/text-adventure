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

  # The dimming rule is `.log:not(.streaming) > .turn:last-of-type`, so the
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
  # was a reload. The player is still standing where they were; they get the
  # reason and the input back.
  test "a failed turn returns the input along with the reason" do
    playthrough = create(:playthrough, :started)

    # Nothing queued, so classification raises.
    streams = play(playthrough, "open the ledger")
    replace = streams.last

    assert_equal "replace", replace["action"]
    assert_match "alert", replace.to_html
    assert_match "what do you do?", replace.to_html
    assert_nil playthrough.reload.current_scene
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

  test "a turn for a playthrough that is gone is dropped rather than raised" do
    assert_nothing_raised { NarrationJob.perform_now(0, "open the ledger") }
  end
end
