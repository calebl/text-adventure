# Strips emoji and surrounding whitespace from model output. Models reach for
# emoji in prose fields even when told not to, and they read badly in narration.
module SanitizesGeneratedText
  extend ActiveSupport::Concern

  # Deliberately NOT \p{Emoji}: that property matches the ASCII digits, `#` and
  # `*`, because those are the bases of the keycap emoji. Using it turned
  # "80 meters" into " meters" and quietly deleted every number a model wrote.
  # Extended_Pictographic is the pictographic set alone, which is what "emoji"
  # means here; the trailing variation selector and any zero-width joiner go
  # with it so multi-part emoji do not leave debris behind.
  EMOJI = /[\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}\u{1F1E6}-\u{1F1FF}][️‍]*/

  # A response cut at a `max_length` boundary leaves the JSON envelope inside
  # the value: a `Scene#summary` came back at exactly its 200-character cap
  # ending `…”}`, so a closing brace and a smart quote were persisted as
  # narrative content. It is the same class of failure `LocationConnection`'s
  # class comment records for a mid-word truncation, one step worse because the
  # debris is punctuation from the structure rather than half a word, and it
  # can reach any `max_length` field in any schema in the app -- which is why
  # the guard lives here, at the one seam every generated string passes
  # through, rather than beside the field it was first seen on.
  #
  # A run of quote / brace / bracket / comma / whitespace at the very end,
  # required to contain at least one brace or bracket. That requirement is what
  # keeps legitimate prose safe: dialogue routinely ends on a closing quote,
  # and no prose field here ends on `}` or `]`.
  JSON_ENVELOPE_TAIL = /[\s,"'“”‘’]*[}\]][\s,"'“”‘’}\]]*\z/

  def sanitize_string(string)
    strip_json_envelope_tail(string.to_s.gsub(EMOJI, "")).strip
  end

  private

  def strip_json_envelope_tail(string)
    return string unless string.match?(JSON_ENVELOPE_TAIL)

    Rails.logger.warn do
      "generated text ended in JSON envelope debris (truncated at a max_length " \
        "boundary?), stripping it: #{string.last(40).inspect}"
    end

    string.sub(JSON_ENVELOPE_TAIL, "")
  end
end
