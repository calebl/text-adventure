# Strips emoji and surrounding whitespace from model output. Models reach for
# emoji in prose fields even when told not to, and they read badly in narration.
module SanitizesGeneratedText
  extend ActiveSupport::Concern

  # Raised when generated text arrives at or past the cap its schema asked it
  # to stay under -- which is to say, when the provider cut the answer off
  # rather than the model finishing it.
  #
  # A field at EXACTLY its `max_length` is truncation, not a coincidence: real
  # rows read "…hopeful for a (v" at exactly 60 characters and "…so as not to
  # r" at exactly 200. With caps sized to the content actually asked for (see
  # `Interaction::Schema`), a finished sentence lands nowhere near the ceiling,
  # so landing on it is a signal and not a near miss.
  #
  # It RAISES rather than trimming back to a word boundary, because a fragment
  # is not a shorter version of the answer -- it is an answer whose end is
  # missing, and the caller has no way to tell what was lost. Trimming it would
  # be the app depending on the model behaving; failing the call is the app
  # noticing that it did not.
  class TruncatedTextError < StandardError; end

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

  # `max_length` is the cap the schema asked the field to stay under. Passing
  # it turns on the truncation check -- see TruncatedTextError. It is optional
  # because most callers here read a field whose cap is loose enough that the
  # JSON-envelope strip below is the only truncation they have ever seen; a
  # caller that knows its cap should pass it.
  def sanitize_string(string, max_length: nil)
    text = string.to_s
    # On the RAW text, before the emoji strip: the provider counted these
    # characters, so this is the length that tells us whether it cut.
    reject_truncated_text!(text, max_length) if max_length

    strip_json_envelope_tail(text.gsub(EMOJI, "")).strip
  end

  private

  def reject_truncated_text!(text, max_length)
    return if text.length < max_length

    raise TruncatedTextError,
          "generated text arrived at its #{max_length}-character cap " \
          "(#{text.length} characters), so it was cut off rather than " \
          "finished: #{text.last(40).inspect}"
  end

  def strip_json_envelope_tail(string)
    return string unless string.match?(JSON_ENVELOPE_TAIL)

    Rails.logger.warn do
      "generated text ended in JSON envelope debris (truncated at a max_length " \
        "boundary?), stripping it: #{string.last(40).inspect}"
    end

    string.sub(JSON_ENVELOPE_TAIL, "")
  end
end
