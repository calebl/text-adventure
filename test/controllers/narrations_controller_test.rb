require "test_helper"

class NarrationsControllerTest < ActionDispatch::IntegrationTest
  # Never a live model: the fake stands in at the BaseAgent boundary, so these
  # pass with no API key and no ollama running. The queued responses are the
  # turn's model calls in order -- classification first, then whatever the
  # classification led to.
  NOT_A_MOVE = { "intent" => "other", "target" => "nothing" }.freeze

  def get_narration(playthrough, command, *responses)
    agent = FakeAgent.new(*responses)

    BaseAgent.stub(:new, agent) do
      get playthrough_narration_path(playthrough, command: command)
    end

    agent
  end

  test "show streams a narrated turn as server-sent events and persists it" do
    playthrough = create(:playthrough, :started)

    get_narration(playthrough, "open the ledger", NOT_A_MOVE, "The ledger falls open.")

    assert_response :success
    assert_equal "text/event-stream", response.media_type
    assert_match "event: open", response.body
    assert_match "event: token", response.body
    assert_match "event: done", response.body

    streamed = response.body.scan(/^data: (\{"t":.*\})$/).flatten
                       .map { |json| JSON.parse(json)["t"] }.join
    assert_equal "The ledger falls open.", streamed

    scene = playthrough.reload.current_scene
    assert_equal "The ledger falls open.", scene.description
    assert_equal playthrough.current_location, scene.location
  end

  # The stream is the same three events whichever branch the turn took, which
  # is the point of putting the loop behind Playthrough::Turn: the browser does
  # not know or care whether the player moved.
  test "show streams a move, and the player ends up somewhere else" do
    playthrough = create(:playthrough, :started)
    here = playthrough.current_location
    there = create(:location, story: playthrough.story, name: "The Sunken Stair")
    create(:location_connection, location: here, connected_location: there,
                                 distance: "adjacent", travel_method: "taking stairs")

    get_narration(playthrough, "take the stairs down",
                  { "intent" => "move", "target" => "The Sunken Stair" },
                  { "description" => "The stair gives under you.", "summary" => "They go down." })

    assert_response :success
    assert_match "event: done", response.body
    assert_match "The stair gives under you.", response.body

    playthrough.reload
    assert_equal there, playthrough.current_location
    assert_equal "The stair gives under you.", playthrough.current_scene.description
  end

  test "show reports a failed generation rather than hanging" do
    playthrough = create(:playthrough, :started)

    get_narration(playthrough, "open the ledger") # nothing queued: classification raises

    assert_response :success
    assert_match "event: error", response.body
    assert_nil playthrough.reload.current_scene
  end
end
