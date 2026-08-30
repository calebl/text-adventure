require "test_helper"

class SanitizesGeneratedTextTest < ActiveSupport::TestCase
  include SanitizesGeneratedText

  test "strips emoji" do
    assert_equal "The Drowned Ledger", sanitize_string("The Drowned Ledger 🌊")
    assert_equal "waves", sanitize_string("🌊 waves 🌊")
  end

  test "strips emoji built from several code points" do
    assert_equal "a family", sanitize_string("a family 👨‍👩‍👧")
    assert_equal "a flag", sanitize_string("a flag 🏳️‍🌈")
  end

  # \p{Emoji} matches the ASCII digits, so the obvious regex here silently
  # deleted every number a model wrote -- "80 meters" came back as "meters".
  test "keeps digits, which the model uses for distances and times" do
    assert_equal "80 meters", sanitize_string("80 meters")
    assert_equal "3 days on foot", sanitize_string("3 days on foot 🥾")
  end

  test "keeps ordinary punctuation" do
    assert_equal "a door -- half open, hinges gone.", sanitize_string("a door -- half open, hinges gone.")
  end

  test "strips surrounding whitespace" do
    assert_equal "a door", sanitize_string("  a door\n")
  end

  test "handles nil" do
    assert_equal "", sanitize_string(nil)
  end
end
