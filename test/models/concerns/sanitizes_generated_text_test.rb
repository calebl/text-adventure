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

  # The real sample: a summary that came back at exactly its 200-character
  # max_length, with the JSON envelope's closing quote and brace inside it.
  test "strips a trailing JSON envelope fragment" do
    assert_equal "The tide has taken the lower ledger",
                 sanitize_string("The tide has taken the lower ledger\u{201D}}")
  end

  test "strips a straight-quoted envelope fragment" do
    assert_equal "a door", sanitize_string(%(a door"}))
  end

  test "strips a nested envelope fragment" do
    assert_equal "a door", sanitize_string(%(a door"}]}))
  end

  # Dialogue and quoted prose legitimately end on a closing quote. Only a brace
  # or bracket marks the run as structure rather than content.
  test "leaves a closing quote that is not envelope debris alone" do
    assert_equal %("Get out," she said."), sanitize_string(%("Get out," she said."))
    assert_equal "the ledger\u{201D}", sanitize_string("the ledger\u{201D}")
  end

  test "handles nil" do
    assert_equal "", sanitize_string(nil)
  end

  # --- the truncation guard -------------------------------------------------

  # No cap passed, no check: the callers that have never seen anything worse
  # than envelope debris keep behaving exactly as they did.
  test "without a cap, a long string is left alone" do
    long = "a" * 500

    assert_equal long, sanitize_string(long)
  end

  # THE REAL SAMPLE. A `pre_feeling` came back at exactly its 60-character cap
  # ending "hopeful for a (v" -- a phrase cut mid-word, which the narrator pass
  # then wrote fluent prose over, so the player could not tell.
  test "rejects a field that arrived at exactly its cap" do
    fragment = "wary, guarded, unwilling to hope, hopeful for a (v".ljust(60, "e")

    assert_equal 60, fragment.length
    error = assert_raises(SanitizesGeneratedText::TruncatedTextError) do
      sanitize_string(fragment, max_length: 60)
    end
    assert_match(/60-character cap/, error.message)
  end

  # Mid-word is not what identifies it, and it must not be: "so as not to r"
  # happens to end mid-word, "hopeful for a (v" happens to end mid-token, and a
  # cut could just as easily land on a space. Arriving AT the cap is the signal.
  test "rejects a field cut on a word boundary too" do
    assert_raises(SanitizesGeneratedText::TruncatedTextError) do
      sanitize_string("she would say nothing at all about the ".ljust(60, "x"), max_length: 60)
    end
  end

  test "rejects a field that came back past its cap" do
    assert_raises(SanitizesGeneratedText::TruncatedTextError) do
      sanitize_string("a" * 61, max_length: 60)
    end
  end

  # One character of headroom is all it takes to be a finished answer rather
  # than a cut one. With the caps sized as `Interaction::Schema` sizes them, a
  # real answer is nowhere near this line.
  test "accepts a field that stopped short of its cap" do
    assert_equal "surprised, wary", sanitize_string("surprised, wary", max_length: 60)
    assert_equal "a" * 59, sanitize_string("a" * 59, max_length: 60)
  end

  # The emoji strip and the envelope strip both shorten the text, and the
  # provider counted the characters it sent, not the ones we keep. Checking the
  # stripped length would let a cut answer through whenever the model had put an
  # emoji in it.
  test "measures the raw text, not what is left after stripping" do
    assert_raises(SanitizesGeneratedText::TruncatedTextError) do
      sanitize_string("#{"a" * 58}🌊", max_length: 59)
    end
  end

  test "a blank field is not a truncated one" do
    assert_equal "", sanitize_string(nil, max_length: 60)
    assert_equal "", sanitize_string("", max_length: 60)
  end
end
