# THE ONE WAY A RELAYED CALL LEAVES THIS INSTANCE: a POST to OpenRouter with
# the owner's key, and nothing else of the player's request but its checked
# body.
#
# `#post` yields a `Response` as soon as the status line and headers are in,
# before the body is read, so a stream can be passed on chunk by chunk while
# OpenRouter is still writing it. The connection closes when the block returns.
#
# THE KEY is read from `Relay::KEY_VARIABLE` here, put in the one header that
# needs it, and never anywhere else. `Unavailable`'s message names the error's
# class only: a network error's message can carry a URL or a header value, and
# this one reaches a log line.
#
# Tests stand a fake in for this class (`Relay::Upstream.stub(:new, ...)`), the
# way `BaseAgent.new` is stubbed everywhere else, so no test reaches the
# network.
class Relay::Upstream
  OPEN_TIMEOUT = 10
  # A stream's gap between chunks, or a whole answer's wait: a narration of the
  # output ceiling is well inside it.
  READ_TIMEOUT = 120

  class Unavailable < StandardError; end

  # What the network can raise, and all of it is `Unavailable`. Anything else
  # -- the client going away while a stream is written to it, say -- is not the
  # upstream's failure and is not renamed as one.
  NETWORK_ERRORS = [ IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError,
                     Net::HTTPBadResponse, Net::ProtocolError, Zlib::Error ].freeze

  # What OpenRouter answered, readable once: either `#each_chunk` for a stream
  # or `#read` for a whole body.
  class Response
    def initialize(http_response)
      @http_response = http_response
    end

    def status = @http_response.code.to_i
    def content_type = @http_response["content-type"]
    def success? = (200..299).cover?(status)

    def each_chunk(&) = @http_response.read_body(&)

    def read = @http_response.read_body.to_s
  end

  def post(path, body)
    uri = URI.join(Relay::UPSTREAM, path)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{ENV.fetch(Relay::KEY_VARIABLE)}"
    request["Content-Type"] = "application/json"
    request.body = body

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(request) { |response| yield Response.new(response) }
    end
  rescue *NETWORK_ERRORS => e
    raise Unavailable, "the upstream request failed (#{e.class})"
  end
end
