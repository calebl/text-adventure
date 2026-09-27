require "test_helper"

# THE ONE WAY OUT. `Net::HTTP.start` is stubbed: what the relay would put on
# the wire is inspected, and nothing reaches it.
class Relay::UpstreamTest < ActiveSupport::TestCase
  KEY = "sk-or-v1-owners-key-never-to-be-seen".freeze

  FakeHttp = Struct.new(:sent, :answer) do
    def request(request)
      sent << request
      yield answer
    end
  end

  setup do
    @previous_key = ENV[Relay::KEY_VARIABLE]
    ENV[Relay::KEY_VARIABLE] = KEY
  end

  teardown { ENV[Relay::KEY_VARIABLE] = @previous_key }

  test "a call goes to OpenRouter's own path with the owner's key and the checked body, and nothing else" do
    sent = []
    answer = Net::HTTPOK.new("1.1", "200", "OK")
    answer["content-type"] = "application/json"
    opened = nil
    start = lambda do |host, port, **options, &block|
      opened = [ host, port, options[:use_ssl] ]
      block.call(FakeHttp.new(sent, answer))
    end

    status = nil
    Net::HTTP.stub(:start, start) do
      Relay::Upstream.new.post("/api/v1/chat/completions", "{\"model\":\"m\"}") { |response| status = response.status }
    end

    request = sent.sole
    assert_equal [ "openrouter.ai", 443, true ], opened
    assert_equal "/api/v1/chat/completions", request.path
    assert_equal "Bearer #{KEY}", request["Authorization"]
    assert_equal "{\"model\":\"m\"}", request.body
    assert_equal %w[accept accept-encoding authorization content-type host user-agent].sort, request.to_hash.keys.sort
    assert_equal 200, status
  end

  test "a network failure is Unavailable, and its message never carries what the error said" do
    [ SocketError.new("getaddrinfo: #{KEY}"), Net::ReadTimeout.new(KEY), OpenSSL::SSL::SSLError.new(KEY) ].each do |error|
      raised = Net::HTTP.stub(:start, ->(*, **) { raise error }) do
        assert_raises(Relay::Upstream::Unavailable) { Relay::Upstream.new.post("/api/v1/chat/completions", "{}") { nil } }
      end
      assert_not_includes raised.message, KEY
      assert_includes raised.message, error.class.name
    end
  end

  test "the client going away mid-stream is not renamed as the upstream's failure" do
    gone = ActionController::Live::ClientDisconnected.new("client disconnected")
    Net::HTTP.stub(:start, ->(*, **) { raise gone }) do
      assert_raises(ActionController::Live::ClientDisconnected) { Relay::Upstream.new.post("/x", "{}") { nil } }
    end
  end

  test "redaction strikes the key out of anything on its way out" do
    assert_equal "a [REDACTED] b", Relay.redact("a #{KEY} b")
    ENV.delete(Relay::KEY_VARIABLE)
    assert_equal "a b", Relay.redact("a b")
  end
end
