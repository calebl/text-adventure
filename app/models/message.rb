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

  private

  # A STORED STRUCTURED ANSWER GOES BACK AS THE JSON STRING THE MODEL WROTE.
  #
  # RubyLLM hands `content_raw` back as a `RubyLLM::Content::Raw`, and what a
  # provider puts on the wire for one is up to the provider: OpenAI's formatter
  # JSON-encodes it, ollama's sends the Hash through untouched and ollama then
  # refuses the whole request --
  # `RubyLLM::BadRequestError: invalid message content type: map[string]interface {}`.
  #
  # That is not an edge case here. Replaying a schema'd answer is what EVERY
  # resumed conversation does: the second thing you say to a character, and the
  # second of `Location::Generator`'s two calls, both send the first answer back.
  # Encoding it ourselves is provider-neutral and is also what the conversation
  # actually was -- the model wrote JSON, so JSON is what it is reminded of.
  # `content_raw` stays the record; this is only what goes back out.
  #
  # MessageTest pins the ollama formatter behaviour that makes this necessary,
  # so if the gem starts encoding raw payloads this can go.
  def extract_content
    return super if content_raw.blank?

    content_raw.is_a?(String) ? content_raw : JSON.generate(content_raw)
  end
end
