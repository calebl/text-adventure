require "test_helper"

class Relay::StreamUsageTest < ActiveSupport::TestCase
  test "the usage is read off the final event wherever the chunks break" do
    stream = "data: {\"choices\":[{\"delta\":{\"content\":\"hé\"}}]}\n\n" \
             ": keep-alive\n\ndata: {\"choices\":[],\"usage\":{\"prompt_tokens\":12,\"cost\":0.5}}\r\n\r\ndata: [DONE]\n\n"
    [ 1, 3, 7, stream.bytesize ].each do |size|
      reader = Relay::StreamUsage.new
      stream.b.chars.each_slice(size) { |slice| reader << slice.join }
      assert_equal({ "prompt_tokens" => 12, "cost" => 0.5 }, reader.finish, "chunks of #{size}")
    end
  end

  test "a last event with no newline after it still counts, and a stream without usage has none" do
    reader = Relay::StreamUsage.new
    reader << "data: {\"usage\":{\"cost\":1}}"
    assert_equal({ "cost" => 1 }, reader.finish)

    assert_nil (Relay::StreamUsage.new << "data: {\"choices\":[]}\n\ndata: [DONE]\n\n").finish
  end

  test "a line past the ceiling is dropped rather than held" do
    reader = Relay::StreamUsage.new
    reader << ("x" * (Relay::StreamUsage::MAX_LINE_BYTES + 1))
    reader << "\ndata: {\"usage\":{\"cost\":2}}\n"
    assert_equal({ "cost" => 2 }, reader.finish)
  end
end
