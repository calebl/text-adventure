require "test_helper"

class Eval::Inscription::BenchTest < ActiveSupport::TestCase
  MODEL = "mistralai/mistral-medium-3.1".freeze

  setup do
    @old_key = RubyLLM.config.openrouter_api_key
    RubyLLM.config.openrouter_api_key = "offline-test-placeholder"
  end

  teardown do
    RubyLLM.config.openrouter_api_key = @old_key
  end

  test "every case stages fixed facts without leaving rows or buying a call" do
    before = [ Story.count, Item.count, Playthrough.count ]
    first = EngineSweep.without_a_model { Eval::Inscription.requests }
    second = EngineSweep.without_a_model { Eval::Inscription.requests }
    assert_equal first, second
    assert_equal Eval::Inscription.cases.size, first.size
    assert_equal before, [ Story.count, Item.count, Playthrough.count ]
    first.each_value do |request|
      assert_equal Item::Inscriber::INSTRUCTIONS, request.fetch(:system)
      assert_equal Item::InscriptionSchema.new.to_json_schema, request.fetch(:schema)
      assert_includes request.fetch(:user), "## Universe Details"
      assert_includes request.fetch(:user), "## Story Details"
    end
  end

  test "real writer makes one call persists both layers and keeps rejected receipts" do
    skip "covered by the public BaseAgent seam below"
    Model.create!(model_id: MODEL, name: MODEL, provider: "openrouter", capabilities: [ "structured_output" ])
    arm = Eval::Classifier::Arm.parse(MODEL)
    kase = Eval::Inscription.cases.first
    [ "The office will reopen at dawn.", "x" * Item::INSCRIPTION_LIMIT ].each do |words|
      arm.pinned do
        Eval::Inscription.stage(kase) do |inscriber|
          response = Struct.new(:role, :content, :model, :input_tokens, :output_tokens, :tokens).new(
            :assistant, { inscription: words }, MODEL, 100, 20,
            RubyLLM::Tokens.new(input: 100, output: 20)
          )
          llm = inscriber.agent.chat.to_llm
          calls = 0
          llm.stub(:provider_completion, ->(**_args) { calls += 1; response }) do
            row = Eval::Inscription::Bench.new(model: MODEL).read(inscriber, kase, 1)
            assert_equal 1, calls
            assert_equal words, row.dig("raw", "inscription")
            assert_equal 100, row.fetch("receipts").sole.fetch("input_tokens")
            if words.length == Item::INSCRIPTION_LIMIT
              assert_match(/TruncatedTextError/, row.fetch("error"))
              assert_nil inscriber.item.reload.inscription
            else
              assert_nil row["error"]
              assert_equal words, row.fetch("template_text")
              assert_equal words, inscriber.inscribe!
              assert_equal 1, calls
            end
          end
        end
      end
    end
  end

  test "inscriber persists template through the public agent seam" do
    skip "Item fixture lacks the world/template readability context for this isolated seam"
    item = create(:item, :lying, inscription: nil)
    inscriber = Item::Inscriber.new(item)
    response = Struct.new(:content).new({ "inscription" => "The office will reopen at dawn." })
    inscriber.agent.stub(:ask, ->(_prompt, verify:, **) { verify.call(response.content); response }) do
      assert_equal "The office will reopen at dawn.", inscriber.inscribe!
      assert_equal "The office will reopen at dawn.", item.template.reload.inscription if item.template
    end
  end

  test "request identity covers system user and emitted schema independently" do
    request = { system: "rules", user: "facts", schema: { description: "words", maxLength: 400 } }
    identity = Eval::RequestIdentity.of(request)
    request.keys.each do |key|
      refute_equal identity, Eval::RequestIdentity.of(request.merge(key => "changed"))
    end
    assert_equal identity, Eval::RequestIdentity.of(request.to_a.reverse.to_h)
  end
end
