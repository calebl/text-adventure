# STANDS IN FOR THE NETWORK AT THE `Chat#ask` SEAM.
#
# `FakeAgent` stands in one level higher, at `BaseAgent.new`, which is right for
# a test about what a generator does with an answer -- but it means no `Chat`
# row is ever written, so it cannot test the persistence itself. This replaces
# only the part that would reach a model: the prompt is persisted the way
# RubyLLM persists it, an assistant message is written with token counts and a
# model, and the caller gets a `RubyLLM::Message` back.
#
# So a test using this exercises the real `BaseAgent`, the real `Chat`, real
# rows and real replay -- everything except the HTTP call.
module OfflineExchange
  # What one stubbed call answers with. `content` may be a String (prose, which
  # is streamed to the block a word at a time the way RubyLLM does) or a Hash (a
  # schema'd answer, which RubyLLM stores in `content_raw` and never streams).
  Reply = Struct.new(:content, :input_tokens, :output_tokens, keyword_init: true)

  def self.reply(content, input: 120, output: 40)
    Reply.new(content: content, input_tokens: input, output_tokens: output)
  end

  # Queues `replies` -- Reply objects or bare contents -- and answers each
  # `Chat#ask` with the next one. Raises rather than answering when the queue
  # runs dry, because a test that made an unplanned model call should say so.
  def self.with(*replies)
    queue = replies.map { |reply| reply.is_a?(Reply) ? reply : reply(reply) }
    original = Chat.instance_method(:ask)

    Chat.define_method(:ask) do |message = nil, **_options, &block|
      raise "OfflineExchange ran out of queued replies (asked: #{message.to_s[0, 60].inspect})" if queue.empty?

      answer = queue.shift
      add_message(role: :user, content: message)
      OfflineExchange.persist_answer(self, answer, &block)
    end

    yield
  ensure
    Chat.define_method(:ask, original)
  end

  # Writes the assistant message the way `RubyLLM::ActiveRecord::ChatMethods`
  # does -- prose in `content`, a structured answer in `content_raw`, tokens and
  # the answering model on the row -- and returns what `Chat#ask` returns.
  def self.persist_answer(chat, answer)
    content = answer.content
    structured = content.is_a?(Hash) || content.is_a?(Array)

    chat.messages.create!(
      role: "assistant",
      content: structured ? nil : content,
      content_raw: structured ? content : nil,
      input_tokens: answer.input_tokens,
      output_tokens: answer.output_tokens,
      model: chat.model
    )

    content.to_s.scan(/\S+\s*/) { |part| yield Chunk.new(part) } if block_given? && !structured

    Answer.new(content)
  end

  Chunk = Struct.new(:content)
  Answer = Struct.new(:content)
end
