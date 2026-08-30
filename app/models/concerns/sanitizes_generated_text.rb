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

  def sanitize_string(string)
    string.to_s.gsub(EMOJI, "").strip
  end
end
