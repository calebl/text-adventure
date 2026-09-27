# THE USAGE OF A STREAMED CHAT, read off the stream as it passes through.
#
# OpenRouter streams server-sent events: `data: {json}` lines, keep-alive
# comments, and `data: [DONE]`. With `stream_options.include_usage` (which
# `Relay::Request#forwarded_body` always sets on a stream) the last data event
# before `[DONE]` carries a `usage` object with the call's tokens and cost.
# This reads every data line for one and keeps the last it sees; it never
# changes a byte of what is passed on, and it keeps no line once it is read.
#
# A chunk boundary can fall anywhere, so an unfinished line is carried to the
# next chunk -- up to `MAX_LINE_BYTES`, past which the line is dropped rather
# than held. A usage event is small; a line that long is not one.
class Relay::StreamUsage
  MAX_LINE_BYTES = 1_048_576

  attr_reader :usage

  def initialize
    @pending = "".b
    @usage = nil
  end

  def <<(chunk)
    @pending << chunk.to_s.b
    lines = @pending.split("\n", -1)
    @pending = lines.pop || "".b
    lines.each { |line| read_line(line) }
    @pending = "".b if @pending.bytesize > MAX_LINE_BYTES
    self
  end

  # The end of the stream: a last line with no newline after it still counts.
  def finish
    read_line(@pending)
    @pending = "".b
    usage
  end

  private

  def read_line(line)
    data = line.delete_suffix("\r").delete_prefix("data:").strip
    return unless line.start_with?("data:") && data.start_with?("{")

    event = JSON.parse(data.force_encoding(Encoding::UTF_8))
    @usage = event["usage"] if event.is_a?(Hash) && event["usage"].is_a?(Hash)
  rescue JSON::ParserError, EncodingError
    nil
  end
end
