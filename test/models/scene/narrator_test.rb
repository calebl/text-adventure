require "test_helper"

class Scene::NarratorTest < ActiveSupport::TestCase
  test "yields the narration in chunks and returns the persisted scene" do
    playthrough = create(:playthrough, :started)
    agent = FakeAgent.new("You step into the hall.")

    chunks = []
    scene = BaseAgent.stub(:new, agent) do
      Scene::Narrator.new(playthrough).narrate("go inside") { |chunk| chunks << chunk }
    end

    assert_operator chunks.length, :>, 1
    assert_equal "You step into the hall.", chunks.join
    assert_equal "You step into the hall.", scene.description
    assert_equal playthrough.current_location, scene.location
    assert_equal scene, playthrough.reload.current_scene
  end

  test "asks unschema'd -- streaming and structured output are incompatible" do
    playthrough = create(:playthrough, :started)
    agent = FakeAgent.new("You step into the hall.")

    BaseAgent.stub(:new, agent) { Scene::Narrator.new(playthrough).narrate("go inside") }

    assert_empty agent.schemas
  end

  test "prompts with the story, the location and what just happened" do
    playthrough = create(:playthrough, :in_scene)
    playthrough.current_scene.update!(description: "The door swings open.")
    agent = FakeAgent.new("Rain starts falling.")

    BaseAgent.stub(:new, agent) { Scene::Narrator.new(playthrough).narrate("look up") }

    prompt = agent.prompts.first
    assert_match playthrough.story.title, prompt
    assert_match playthrough.current_location.name, prompt
    assert_match "The door swings open.", prompt
    assert_match "look up", prompt
  end

  test "chains each turn onto the previous one" do
    playthrough = create(:playthrough, :started)

    first = BaseAgent.stub(:new, FakeAgent.new("One.")) do
      Scene::Narrator.new(playthrough).narrate("go inside")
    end
    second = BaseAgent.stub(:new, FakeAgent.new("Two.")) do
      Scene::Narrator.new(playthrough.reload).narrate("keep going")
    end

    assert_equal first, second.previous_scene
  end

  # The point of the ensure block: a browser that closes mid-stream kills the
  # generation, and the player should still get back whatever was written.
  test "keeps the partial narration when the consumer blows up mid-stream" do
    playthrough = create(:playthrough, :started)
    agent = FakeAgent.new("One two three four five")

    assert_raises(RuntimeError) do
      BaseAgent.stub(:new, agent) do
        Scene::Narrator.new(playthrough).narrate("go inside") do |chunk|
          raise "client vanished" if chunk.include?("three")
        end
      end
    end

    assert_equal "One two three", playthrough.reload.current_scene.description.strip
  end

  test "saves nothing when the model produced no text" do
    playthrough = create(:playthrough, :started)

    assert_no_difference -> { Scene.count } do
      BaseAgent.stub(:new, FakeAgent.new("")) do
        Scene::Narrator.new(playthrough).narrate("go inside")
      end
    end

    assert_nil playthrough.reload.current_scene
  end

  # --- what the narrator remembers ------------------------------------------

  # It used to see exactly one scene, so a playthrough had a memory one turn
  # deep and the only way to deepen it was to paste in more full descriptions --
  # which is what puts a long game outside the context window. The recap spends
  # `scenes.summary` instead, under a fixed budget: see Playthrough#recap.
  test "the prompt carries the turns before the last one, as summaries" do
    playthrough = create(:playthrough, :started)
    first = create(:scene, story: playthrough.story, location: playthrough.current_location,
                           summary: "You came in out of the rain.", description: "Long prose about the rain.")
    second = create(:scene, story: playthrough.story, location: playthrough.current_location,
                            previous_scene: first, summary: "You spoke to the clerk.",
                            description: "Long prose about the clerk.")
    playthrough.update!(current_scene: second)

    agent = FakeAgent.new("You look up.")
    BaseAgent.stub(:new, agent) { Scene::Narrator.new(playthrough).narrate("look up") }
    prompt = agent.prompts.first

    assert_includes prompt, "Long prose about the clerk.", "the turn just taken is still there in full"
    assert_includes prompt, "You came in out of the rain.", "and the one before it, as its summary"
    assert_not_includes prompt, "Long prose about the rain.", "not as its prose -- that is the whole trade"
  end

  test "a first turn has nothing to recap and says nothing about it" do
    playthrough = create(:playthrough, :started)
    agent = FakeAgent.new("You look up.")

    BaseAgent.stub(:new, agent) { Scene::Narrator.new(playthrough).narrate("look up") }

    assert_not_includes agent.prompts.first, "Earlier, in order:"
  end
end
