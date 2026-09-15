require "test_helper"
require_relative "support"

class PhysicalConfirmationPayloadTest < ActiveSupport::TestCase
  Agent = Data.define(:purpose)

  setup do
    @rows = JSON.parse(PhysicalConfirmation::ROOT.join("requests.json").read).fetch("samples")
    @guard = PhysicalConfirmation::Gate.new(@rows)
    @guard.start!(@rows.first.fetch("case"))
    @guard.instance_variable_set(:@fixture, { game: Object.new })
    @request = @rows.first.fetch("calls").first
    @agent = Agent.new("classifier")
  end

  test "inspected request passes and records one attempt" do
    PhysicalConfirmation.stub(:request, @request) { @guard.before!(@agent, @request.fetch("prompt")) }
    assert_equal 1, @guard.sent.length
  end

  test "changed system user schema history and purpose fail before an attempt" do
    %w[prompt instructions schema history purpose].each do |key|
      changed = @request.merge(key => "uninspected text")
      PhysicalConfirmation.stub(:request, changed) do
        assert_raises(PhysicalConfirmation::Halt, key) { @guard.before!(@agent, changed["prompt"]) }
      end
      assert_empty @guard.sent
    end
  end

  test "unbound fixture and exhausted call count cannot send" do
    @guard.instance_variable_set(:@fixture, nil)
    assert_raises(PhysicalConfirmation::Halt) { @guard.before!(@agent, "anything") }
    @guard.instance_variable_set(:@fixture, { synthetic: true })
    @guard.instance_variable_set(:@sent, Array.new(60))
    assert_raises(PhysicalConfirmation::Halt) { @guard.before!(@agent, "anything") }
  end

  test "narration must match the registered actual builder" do
    @guard.instance_variable_set(:@call_index, 1)
    narrator = Agent.new("narration")
    request = @rows.first.fetch("calls")[1].merge("prompt" => "Fresh engine receipt in the fixture prompt")
    PhysicalConfirmation.stub(:request, request) do
      assert_raises(PhysicalConfirmation::Halt) { @guard.before!(narrator, request.fetch("prompt")) }
      @guard.built!(narrator, request.fetch("prompt"))
      @guard.before!(narrator, request.fetch("prompt"))
    end
    assert_equal 1, @guard.sent.length
  end

  test "extra repetition and unrelated game builder fail" do
    assert_raises(PhysicalConfirmation::Halt) { PhysicalConfirmation::Gate.new(@rows + @rows.first(7)) }
    assert_raises(PhysicalConfirmation::Halt) { @guard.game!(Object.new, @rows.first.fetch("line")) }
  end
end
