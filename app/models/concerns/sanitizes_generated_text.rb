# Strips emoji and surrounding whitespace from model output. Models reach for
# emoji in prose fields even when told not to, and they read badly in narration.
module SanitizesGeneratedText
  extend ActiveSupport::Concern

  def sanitize_string(string)
    string.to_s.gsub(/\p{Emoji_Presentation}|\p{Emoji}️?/, "").strip
  end
end
