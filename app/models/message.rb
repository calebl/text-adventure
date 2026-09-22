# One message in one conversation with a model: the prompt that was sent or the
# answer that came back, with what it cost and which model wrote it.
#
# `scene` is WHICH TURN it was exchanged on, and it is here rather than on
# `Chat` because a durable conversation (see Chat::CHARACTER) spans many turns.
# It is what makes `Playthrough::Debug` able to say what one turn cost.
class Message < ApplicationRecord
  acts_as_message

  # RubyLLM 2 no longer declares this association on messages, but the app's
  # debug and cost views still read the persisted registry row.
  belongs_to :model, class_name: "RubyLLM::ActiveRecord::Model", foreign_key: :model_id, optional: true
  belongs_to :scene, optional: true
  has_one :usage_receipt, -> { where(operation: "chat", status: "succeeded").order(id: :desc) },
          as: :message, class_name: "RubyLLM::ActiveRecord::Usage"

  # MessageMethods#model returns only the model id in RubyLLM 2; callers here
  # need the registry record for existing debug and accounting views.
  def model
    receipt = usage_receipt
    return association(:model).reader unless receipt

    RubyLLM::ActiveRecord::Model.find_by(provider: receipt.provider, model_id: receipt.model)
  end

  def input_tokens = ruby_llm_usages.any? ? tokens.input : self[:input_tokens]
  def output_tokens = ruby_llm_usages.any? ? tokens.output : self[:output_tokens]
  def cache_read_tokens = ruby_llm_usages.any? ? tokens.cache_read : nil
  def cache_write_tokens = ruby_llm_usages.any? ? tokens.cache_write : nil

  def structured_content
    value = content_raw.presence || content
    value = JSON.parse(value) if value.is_a?(String)
    value if value.is_a?(Hash) || value.is_a?(Array)
  rescue JSON::ParserError
    nil
  end

  # A schema'd answer may be legacy `content_raw` or JSON in `content`.
  # Two columns, one question, so read display text through here.
  def text
    return content if content.present?
    return nil if content_raw.blank?

    content_raw.is_a?(String) ? content_raw : JSON.pretty_generate(content_raw)
  end

  # Which model wrote this. Only ever set on an assistant message -- a prompt is
  # not written by a model -- and it is the honest answer to "which model
  # actually answered", because `BaseAgent` rotates mid-conversation.
  def answering_model_id = usage_receipt&.model || model&.model_id || model_id_string

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
