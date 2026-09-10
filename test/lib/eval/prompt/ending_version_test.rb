require "test_helper"

class Eval::Prompt::EndingVersionTest < ActiveSupport::TestCase
  def setup
    story = create(:story)
    room = create(:location, :realized, story: story)
    character = create(:character, :protagonist, story: story)
    @prelude = create(:scene, story: story, location: room, description: "You set down the ring.", summary: "The ring falls.")
    @scene = create(:scene, story: story, location: room, previous_scene: @prelude)
    @game = create(:playthrough, story: story, character: character, current_location: room, current_scene: @scene)
    quest = create(:quest, story: story)
    @outcome = create(:quest_outcome, :default, quest: quest)
    @conclusion = Struct.new(:scene, :outcome).new(@scene, @outcome)
  end

  test "prelude description and summary vary without changing the scaffold or outgoing request" do
    before = capture
    @prelude.update!(description: "A different paragraph. " * 100, summary: "Another generated summary. " * 100)
    @scene.reload
    @game.reload
    after = capture

    refute_equal before[:prompt], after[:prompt]
    refute_equal before[:prelude], after[:prelude]
    assert_equal before[:scaffold], after[:scaffold]
    assert_equal @prelude.description, after.dig(:prelude, :description)
    assert_equal @prelude.summary, after.dig(:prelude, :summary)
    assert_not after[:prelude_stable]
    assert_nil Thread.current[Eval::Prompt::EndingVersion::KEY]
    assert_nil Thread.current[Eval::Prompt::EndingVersion::FIELDS_KEY]
  end

  test "record context and production framing remain in the scaffold" do
    before = capture
    @outcome.summary = "The recorded outcome has changed."
    after = capture
    refute_equal before[:scaffold], after[:scaffold]
    assert_includes after.dig(:scaffold, :user), @outcome.summary
    assert_includes after.dig(:scaffold, :user), "Write the ending."
    assert_equal Scene::Ending::INSTRUCTIONS, after.dig(:scaffold, :system)
  end

  test "the scaffold reads the actual agent system and schema" do
    renderer = Scene::Ending.new(@game)
    before = capture(renderer)
    renderer.send(:agent).with_instructions("Changed system instructions.").with_schema(Scene::Schema)
    after = capture(renderer)
    refute_equal before[:scaffold], after[:scaffold]
    assert_equal "Changed system instructions.", after.dig(:scaffold, :system)
    assert_equal Scene::Schema.new.to_json_schema, after.dig(:scaffold, :schema)
  end

  test "capture unwinds when request assembly exits early" do
    assert_raises(RuntimeError) { Eval::Prompt::EndingVersion.capture { raise "stop" } }
    assert_nil Thread.current[Eval::Prompt::EndingVersion::KEY]
    assert_nil Thread.current[Eval::Prompt::EndingVersion::FIELDS_KEY]
  end

  test "every live ending branch matches offline scaffold identity with varying prelude prose" do
    corpus = Eval::Prompt.corpus("ending")
    offline = Eval::Prompt::RequestVersion.offline(corpus)
    sequence = 0
    factory = lambda do |instructions = nil, **options|
      sequence += 1
      prose = "You hear the gate settle for the #{sequence}th time."
      answer = options[:purpose] == "arrival" ? { "description" => prose, "summary" => prose } : prose
      PreludeAgent.new(answer).with_instructions(instructions)
    end
    result = Eval::Prompt::RequestVersion.stub(:offline, offline) do
      BaseAgent.stub(:new, factory) do
        Eval::Prompt::Bench.new(corpus: corpus, arms: [ "fake/model" ], reps: 2, io: nil).run
      end
    end
    assert_equal offline[:request_identity], result.request_identity
    evidence = result.ending_requests
    assert evidence.fetch("scaffold_stable")
    assert evidence.fetch("complete")
    assert_equal corpus.size * result.reps, evidence.fetch("readings").size
    evidence.fetch("readings").group_by { |row| row.fetch("id") }.each_value do |rows|
      assert_equal result.reps, rows.map { |row| row.fetch("prompt") }.uniq.size
    end
  end

  class PreludeAgent < FakeAgent
    def schema = schemas.last
  end

  private

  def capture(renderer = Scene::Ending.new(@game))
    normal = renderer.send(:prompt_for, @conclusion)
    sent, recorded = Eval::Prompt::EndingVersion.capture { renderer.send(:prompt_for, @conclusion) }
    assert_equal normal, sent
    assert_equal sent, recorded[:prompt]
    recorded
  end
end
