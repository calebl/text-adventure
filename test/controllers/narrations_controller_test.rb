require "test_helper"

class NarrationsControllerTest < ActionDispatch::IntegrationTest
  # Never a live model: the fake stands in at the BaseAgent boundary, so these
  # pass with no API key and no ollama running.
  test "show streams the narration as server-sent events and persists the turn" do
    playthrough = create(:playthrough, :started)
    agent = FakeAgent.new("The ledger falls open.")

    BaseAgent.stub(:new, agent) do
      get playthrough_narration_path(playthrough, command: "open the ledger")
    end

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

  test "show reports a failed generation rather than hanging" do
    playthrough = create(:playthrough, :started)
    agent = FakeAgent.new # no queued responses: the next ask raises

    BaseAgent.stub(:new, agent) do
      get playthrough_narration_path(playthrough, command: "open the ledger")
    end

    assert_response :success
    assert_match "event: error", response.body
    assert_nil playthrough.reload.current_scene
  end
end
