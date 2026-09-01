# One message in one conversation with a model: the prompt that was sent or the
# answer that came back, with what it cost and which model wrote it.
#
# `scene` is WHICH TURN it was exchanged on, and it is here rather than on
# `Chat` because a durable conversation (see Chat::CHARACTER) spans many turns.
# It is what makes `Playthrough::Debug` able to say what one turn cost.
class Message < ApplicationRecord
  acts_as_message

  belongs_to :scene, optional: true

  # A schema'd answer is a Hash, and RubyLLM stores it in `content_raw` with
  # `content` left nil. Two columns, one question, so read it through here.
  def text
    return content if content.present?
    return nil if content_raw.blank?

    content_raw.is_a?(String) ? content_raw : JSON.pretty_generate(content_raw)
  end

  # Which model wrote this. Only ever set on an assistant message -- a prompt is
  # not written by a model -- and it is the honest answer to "which model
  # actually answered", because `BaseAgent` rotates mid-conversation.
  def answering_model_id = model&.model_id
end
