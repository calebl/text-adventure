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

  # --- a response the game will not keep ------------------------------------

  # A REFUSAL IS NOT A SCENE. The `ensure` in `#narrate` persists whatever
  # arrived, which is right for a call that died mid-sentence and wrong here: a
  # world that keeps what it generates would keep "I'm not going to narrate
  # that" as the turn the player reads, forever.
  test "saves nothing when the model refused and the rotation ran out" do
    playthrough = create(:playthrough, :started)
    refusal = "I'm not going to narrate that."
    agent = DoomedAgent.new(BaseAgent::RefusalError, refusal)

    chunks = []
    assert_no_difference -> { Scene.count } do
      assert_raises(BaseAgent::RefusalError) do
        BaseAgent.stub(:new, agent) do
          Scene::Narrator.new(playthrough).narrate("do it") { |chunk| chunks << chunk }
        end
      end
    end

    assert_equal refusal, chunks.join, "the player did watch it arrive"
    assert_nil playthrough.reload.current_scene, "and the game kept none of it"
  end

  # The same suppression for a different reason: a crisis response is not the
  # model failing, and it is still the one text that must never become a Scene.
  # `NarrationJob` is what puts something in its place.
  test "saves nothing when a crisis response was suppressed" do
    playthrough = create(:playthrough, :started)
    agent = DoomedAgent.new(BaseAgent::CrisisResponseError, %("Call 988," he says.))

    assert_no_difference -> { Scene.count } do
      assert_raises(BaseAgent::CrisisResponseError) do
        BaseAgent.stub(:new, agent) { Scene::Narrator.new(playthrough).narrate("goad him") }
      end
    end

    assert_nil playthrough.reload.current_scene
  end

  # `BaseAgent#ask` restarts the stream when it rotates, so one call hands the
  # block the chunks of BOTH attempts. Persisting the accumulated buffer would
  # file the refusal and its replacement as a single scene, which is why what is
  # kept is the last attempt's content and not the stream.
  test "keeps only what the model that actually answered wrote" do
    playthrough = create(:playthrough, :started)
    agent = RotatingAgent.new("I won't write that.", "The door gives under your shoulder.")

    chunks = []
    scene = BaseAgent.stub(:new, agent) do
      Scene::Narrator.new(playthrough).narrate("shove it") { |chunk| chunks << chunk }
    end

    assert_match "I won't write that.", chunks.join, "the block saw both attempts"
    assert_equal "The door gives under your shoulder.", scene.description
    assert_equal "The door gives under your shoulder.", playthrough.reload.current_scene.description
  end

  # Streams prose the way `BaseAgent#ask` does and then fails the call, which is
  # what an exhausted rotation looks like from out here: the player watched it
  # arrive, and it must not be kept.
  class DoomedAgent
    def initialize(error, text)
      @error = error
      @text = text
    end

    def ask(_prompt)
      @text.scan(/\S+\s*/) { |part| yield FakeAgent::Chunk.new(part) } if block_given?
      raise @error, "every model refused"
    end
  end

  # A rotation that recovered. One `ask`, two attempts streamed into the same
  # block, and `content` is what the second one wrote.
  class RotatingAgent
    def initialize(*texts) = @texts = texts

    def ask(_prompt)
      @texts.each { |text| text.scan(/\S+\s*/) { |part| yield FakeAgent::Chunk.new(part) } } if block_given?
      FakeAgent::Response.new(@texts.last)
    end

    # This one gets far enough to be stamped with the scene it paid for.
    def attribute_to!(_scene) = nil
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
  # --- the closed sets, in the prompt --------------------------------------

  # The instructions always said not to invent an exit the player had not been
  # told about. Nothing told the narrator which exits those were; the classifier
  # computed them every turn and threw them away.
  test "the prompt lists the ways out, who else is here and what the player carries" do
    playthrough = create(:playthrough, :started)
    story = playthrough.story
    here = playthrough.current_location
    stair = create(:location, story: story, name: "The Sunken Stair")
    create(:location_connection, location: here, connected_location: stair, distance: "adjacent", travel_method: "walking")
    maren = create(:character, story: story, fullname: "Maren Vosk", nickname: "Maren", location: here)
    playthrough.update!(current_scene: create(:scene, story: story, location: here, characters: [ maren ]))
    create(:item, character: playthrough.character, name: "Brass Key")

    agent = FakeAgent.new("You look around.")
    BaseAgent.stub(:new, agent) { Scene::Narrator.new(playthrough).narrate("look around") }
    prompt = agent.prompts.first

    assert_match(/Ways out of here: The Sunken Stair\./, prompt)
    assert_match(/Also here: Maren Vosk \(Maren\)\./, prompt)
    assert_match(/The player is carrying: Brass Key\./, prompt)
  end

  test "the instructions point the narrator at those lists" do
    assert_match(/do not add a\s+way out, a person or a possession that is not on those lists/, Scene::Narrator::INSTRUCTIONS)
  end

  # --- what kind of turn this is -------------------------------------------

  # `examine` reached the narrator indistinguishable from `other`, so a look at
  # the fireplace was as free to move the story on as anything else.
  test "an examine is narrated as a look, with nothing moving" do
    playthrough = create(:playthrough, :started)
    agent = FakeAgent.new("The ledger is bound in cracked leather.")

    BaseAgent.stub(:new, agent) { Scene::Narrator.new(playthrough).narrate("look at the ledger", intent: :examine) }

    assert_match(/looking more closely at something that is here/, agent.prompts.first)
    assert_match(/nobody arrives and nobody leaves/, agent.prompts.first)
  end

  test "an intent with no line of its own adds nothing to the prompt" do
    playthrough = create(:playthrough, :started)
    agent = FakeAgent.new("You wait.")

    BaseAgent.stub(:new, agent) { Scene::Narrator.new(playthrough).narrate("wait", intent: :other) }

    assert_no_match(/looking more closely/, agent.prompts.first)
    assert_no_match(/ALREADY happened/, agent.prompts.first)
  end
end
