require "test_helper"

class Eval::Prompt::BranchesBenchTest < ActiveSupport::TestCase
  test "one narrator call per case plus a receipted warmup and matching rendered identities" do
    registry = create(:model, model_id: "fake/model", name: "fake", provider: "openrouter")
    agents = []
    stub = lambda do |instructions, **options|
      Recorded.new(instructions, options.fetch(:playthrough), registry).tap { |agent| agents << agent }
    end
    corpus = Eval::Prompt.corpus("branches")
    result = BaseAgent.stub(:new, stub) do
      Eval::Prompt::Branches::Bench.new(corpus: corpus, arms: [ "fake/model" ], reps: 2, io: nil).run
    end
    assert_equal corpus.size * 2 + 1, agents.size
    assert_equal corpus.size * 2, result.rows.size
    assert_equal [ "narration" ], result.rows.pluck("pass").uniq
    assert_equal [ 1 ], result.rows.pluck("calls").uniq
    assert_equal [ nil ], result.rows.pluck("error").uniq
    assert_equal [ nil ], result.rows.map { |row| row.dig("human", "truthfulness") }.uniq
    assert_equal %w[next_beat_fit quality truthfulness], result.rows.first["human"].keys.sort
    assert_equal 100, result.warmups.sole["input_tokens"]
    assert result.prompt_stable
    assert_equal Eval::Prompt::Branches.identity, result.request_identity
    captured = Eval::Prompt::Branches.capture
    result.rows.each do |row|
      assert_equal captured.fetch(row["shape"]).fetch("request")[:user], row["prompt"]
      assert_equal captured.fetch(row["shape"]).fetch("facts"), row["facts"].slice(*captured.fetch(row["shape"]).fetch("facts").keys)
    end
    assert_includes Eval::Prompt::Board.new([ [ "fake", result ] ]).lines.join("\n"), "unlabelled (human-only)"
    result.passes.first.rows.first.fetch("human")["truthfulness"] = false
    assert_includes Eval::Prompt::Board.new([ [ "fake", result ] ]).lines.join("\n"), "1/18 labelled; 1 contradicted"
  end

  class Recorded < FakeAgent
    def initialize(instructions, game, registry)
      super()
      @chat = Chat.create!(purpose: "narration", playthrough: game, model: registry)
      @chat.messages.create!(role: "system", content: instructions, model: registry)
      @registry = registry
    end

    def ask(prompt, **)
      @chat.messages.create!(role: "user", content: prompt, model: @registry)
      @chat.messages.create!(role: "assistant", content: "You look around.", model: @registry,
                             input_tokens: 100, output_tokens: 20)
      Response.new("You look around.")
    end

    def attribute_to!(scene) = @chat.messages.where.not(role: "system").update_all(scene_id: scene.id)
  end
end
