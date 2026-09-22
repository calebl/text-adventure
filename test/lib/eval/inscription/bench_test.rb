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

  test "real writer makes one call and persists both layers through the public agent seam" do
    kase = Eval::Inscription.cases.first
    words = "The office will reopen at dawn."

    Eval::Inscription.stage(kase) do |inscriber|
      calls = 0
      ask = lambda do |_prompt, verify:, **|
        calls += 1
        verify.call("inscription" => words)
      end

      inscriber.agent.stub(:ask, ask) do
        assert_equal words, inscriber.inscribe!
        assert_equal words, inscriber.item.reload.inscription
        assert_equal words, inscriber.item.template.reload.inscription
        assert_equal words, inscriber.inscribe!
        assert_equal 1, calls
      end
    end
  end

  test "rejected writer answer is not persisted" do
    kase = Eval::Inscription.cases.first
    words = "x" * Item::INSCRIPTION_LIMIT

    Eval::Inscription.stage(kase) do |inscriber|
      calls = 0
      ask = lambda do |_prompt, verify:, **|
        calls += 1
        verify.call("inscription" => words)
      end

      inscriber.agent.stub(:ask, ask) do
        error = assert_raises(SanitizesGeneratedText::TruncatedTextError) { inscriber.inscribe! }
        assert_match(/#{Item::INSCRIPTION_LIMIT}-character cap/, error.message)
        assert_nil inscriber.item.reload.inscription
        assert_nil inscriber.item.template.reload.inscription
        assert_equal 1, calls
      end
    end
  end

  test "bench reads receipt accounting from persisted RubyLLM usage" do
    create(:model, model_id: MODEL, provider: "openrouter", name: MODEL)
    arm = Eval::Classifier::Arm.parse(MODEL)
    kase = Eval::Inscription.cases.first
    words = "The office will reopen at dawn."

    arm.pinned do
      Eval::Inscription.stage(kase) do |inscriber|
        inscriber.item.update!(inscription: words)
        inscriber.item.template.update!(inscription: words)
        chat = inscriber.agent.chat
        message = chat.messages.create!(role: "assistant", content: JSON.generate("inscription" => words))
        RubyLLM::ActiveRecord::Usage.create!(
          chat: chat, message: message, operation: "chat", provider: "openrouter", model: MODEL,
          status: "succeeded", input_tokens: 100, output_tokens: 20,
          cache_read_tokens: 7, cache_write_tokens: 3
        )

        row = Eval::Inscription::Bench.new(model: MODEL).read(inscriber, kase, 1)
        receipt = row.fetch("receipts").sole

        assert_equal MODEL, receipt.fetch("model")
        assert_equal 100, receipt.fetch("input_tokens")
        assert_equal 20, receipt.fetch("output_tokens")
        assert_equal 7, receipt.fetch("cached_tokens")
        assert_equal 3, receipt.fetch("cache_creation_tokens")
        assert_equal words, row.fetch("text")
        assert_equal words, row.fetch("template_text")
        assert_nil row["error"]
      end
    end
  end

  test "a malformed rejected response retains its usage receipt" do
    bench = Eval::Inscription::Bench.new(model: MODEL)
    row = { "receipts" => [] }
    message = RubyLLM::Message.new(role: :assistant, content: "not json", model: MODEL,
                                   input_tokens: 100, output_tokens: 20,
                                   cache_read_tokens: 7, cache_write_tokens: 3)

    bench.send(:capture_message, row, message)

    assert_equal "not json", row.fetch("raw")
    assert_equal 100, row.fetch("receipts").sole.fetch("input_tokens")
    assert_equal 20, row.fetch("receipts").sole.fetch("output_tokens")
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
