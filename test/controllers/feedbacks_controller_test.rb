require "test_helper"

# Recording a verdict while playing. The two things that matter here are that it
# is ONE request per click and that it does not disturb the turn loop: the
# answer is a Turbo Stream replacing one footer, not a page, not a redirect.
class FeedbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @story = create(:story)
    @here = create(:location, story: @story)
    @first = create(:scene, story: @story, location: @here, description: "Stalls stand under wet canvas.")
    @turn = create(:scene, story: @story, location: @here, previous_scene: @first,
                           description: "Rain starts falling.", typed: "look up")
    @playthrough = create(:playthrough, story: @story, current_location: @here, current_scene: @turn)
  end

  test "one click records a verdict on a turn" do
    assert_difference -> { @playthrough.feedbacks.count }, 1 do
      post playthrough_feedbacks_path(@playthrough),
           params: { scene_id: @turn.id, verdict: "good" }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "good", @playthrough.feedbacks.sole.verdict
  end

  test "the note rides along with the verdict when there is one" do
    post playthrough_feedbacks_path(@playthrough),
         params: { scene_id: @turn.id, verdict: "weak", note: "the rain did nothing" },
         as: :turbo_stream

    assert_equal "the rain did nothing", @playthrough.feedbacks.sole.note
  end

  # AMENDABLE. He changes his mind about a turn once the next one lands, and the
  # same POST is what does it -- there is at most one verdict per turn, so there
  # is no id for the page to carry and no second endpoint.
  test "posting again amends the verdict rather than adding a second" do
    post playthrough_feedbacks_path(@playthrough),
         params: { scene_id: @turn.id, verdict: "good" }, as: :turbo_stream

    assert_no_difference -> { @playthrough.feedbacks.count } do
      post playthrough_feedbacks_path(@playthrough),
           params: { scene_id: @turn.id, verdict: "bad" }, as: :turbo_stream
    end

    assert_equal "bad", @playthrough.feedbacks.sole.verdict
  end

  test "clearing takes a mis-click back" do
    create(:playthrough_feedback, playthrough: @playthrough, scene: @turn)

    assert_difference -> { @playthrough.feedbacks.count }, -1 do
      delete playthrough_feedback_path(@playthrough, @turn), as: :turbo_stream
    end

    assert_response :success
  end

  # IT MUST NOT INTERRUPT PLAY. One element is replaced -- the verdict footer on
  # the turn that was judged -- so the prose does not reflow, a turn streaming
  # into `#stream` is untouched, and the next command is not blocked on this.
  test "the answer replaces one turn's footer and nothing else" do
    post playthrough_feedbacks_path(@playthrough),
         params: { scene_id: @turn.id, verdict: "good" }, as: :turbo_stream

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match 'action="replace"', response.body
    assert_match %(target="verdict_scene_#{@turn.id}"), response.body
    assert_no_match(/target="turn_log"/, response.body)
    assert_no_match(/id="stream"/, response.body)
  end

  test "the replaced footer comes back showing the verdict that was recorded" do
    post playthrough_feedbacks_path(@playthrough),
         params: { scene_id: @turn.id, verdict: "weak", note: "thin" }, as: :turbo_stream

    assert_match "mark weak chosen", response.body
    assert_match "thin", response.body
  end

  # THE CLOSED SET. A playthrough URL is the whole of a player's credentials and
  # two playthroughs of one story share an opening, so the turn is resolved
  # against `Playthrough#scene_chain` -- this playthrough's own turns -- rather
  # than by a bare `Scene.find` over every scene in the database.
  test "a scene that is not one of this playthrough's turns is not a turn to judge" do
    elsewhere = create(:scene, story: @story, location: @here, description: "Another player's turn.")

    assert_no_difference -> { Playthrough::Feedback.count } do
      post playthrough_feedbacks_path(@playthrough),
           params: { scene_id: elsewhere.id, verdict: "good" }, as: :turbo_stream
    end

    assert_response :not_found
  end

  # Scripts blocked, or the module still loading: the verdict is recorded either
  # way and the player lands back at the foot of the log.
  test "a verdict is still recorded without Turbo" do
    post playthrough_feedbacks_path(@playthrough), params: { scene_id: @turn.id, verdict: "good" }

    assert_redirected_to playthrough_path(@playthrough, anchor: "bottom")
    assert_equal "good", @playthrough.feedbacks.sole.verdict
  end

  # GATED LIKE THE DEBUG VIEW, on the same flag and for the same reason: there
  # is no auth in this app, so somebody handed a playthrough link to read a
  # story should be no more able to file evaluation data than to read the
  # prompts behind it.
  test "the instrument is absent when the debug view is" do
    with_env("TA_DEBUG_VIEW", "0") do
      assert_no_difference -> { Playthrough::Feedback.count } do
        post playthrough_feedbacks_path(@playthrough),
             params: { scene_id: @turn.id, verdict: "good" }, as: :turbo_stream
      end

      assert_response :not_found
    end
  end

  # --- what the play page shows ---------------------------------------------

  test "the play page carries a verdict footer for every turn in the log" do
    get playthrough_path(@playthrough)

    assert_select "footer.verdict", count: 2
    assert_select "#verdict_scene_#{@turn.id} input[type=submit][name=verdict]", count: 3
  end

  test "the play page shows the verdict already recorded on a turn" do
    create(:playthrough_feedback, :with_note, playthrough: @playthrough, scene: @turn, verdict: "bad")

    get playthrough_path(@playthrough)

    assert_select "#verdict_scene_#{@turn.id} .mark.bad.chosen"
    assert_select "#verdict_scene_#{@turn.id} input[name=note]"
  end

  # THE NOTE BOX FOLLOWS THE VERDICT, and the order is the point: a judgement
  # that has to be written out before it counts will not get recorded mid-play.
  test "an unjudged turn offers the buttons and not the note box" do
    get playthrough_path(@playthrough)

    assert_select "#verdict_scene_#{@turn.id} input[name=note]", count: 0
  end

  test "the play page carries no verdict footer when the instrument is off" do
    with_env("TA_DEBUG_VIEW", "0") do
      get playthrough_path(@playthrough)

      assert_select "footer.verdict", count: 0
    end
  end

  # THE DIMMING RULE. The stylesheet finds the newest turn with
  # `.log:not(.streaming) > .entry:last-of-type .turn` -- `.entry` being the
  # wrapper one turn's prose, verdict and machinery panel share (`turns/_turn`).
  # It used to hang off `.turn:last-of-type`, and `:last-of-type` counts elements
  # of the same tag among their siblings, so a `<div>` under a turn would quietly
  # become the last div in the log and the newest turn would stop reading at full
  # strength. The wrapper is what took that trap away; the footer stays a
  # `<footer>` because it reads as one.
  test "the footer does not take the newest turn's place in the log" do
    get playthrough_path(@playthrough)

    assert_select ".log:not(.streaming) > .entry .turn", count: 2
    assert_select ".log:not(.streaming) > .entry:last-of-type .turn", text: "Rain starts falling."
  end

  private

  def with_env(key, value)
    had = ENV.key?(key)
    previous = ENV[key]
    ENV[key] = value
    yield
  ensure
    had ? ENV[key] = previous : ENV.delete(key)
  end
end
