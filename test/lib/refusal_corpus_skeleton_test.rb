require "test_helper"

# THE REDUCTION'S PROPERTIES, one at a time.
#
# `BaseAgent::RefusalPrecisionTest` is what says the reduced corpus measures the
# same thing the raw one did -- 207 records, 0 mismatches, run once against both
# and recorded in PR #88. That run cannot live in this repository, because
# reproducing it needs the prose the reduction exists to keep out.
#
# So what is pinned here is everything that comparison RELIED ON, stated as
# properties that hold for any text at all. If the reduction is ever changed,
# these are what say it is still the same function: offsets preserved, word
# boundaries preserved, the detector's own alphabet preserved, and nothing else
# surviving.
class RefusalCorpusSkeletonTest < ActiveSupport::TestCase
  S = RefusalCorpusSkeleton
  R = BaseAgent::Refusal

  # --- what the detector reads, and so what has to survive -------------------

  # The reason the reduction is character-for-character rather than
  # word-for-word: `flags` strips quoted dialogue FIRST, which shortens the
  # text, and then reads the first 300 characters of what is left. A reduction
  # that changed any length would move the window.
  test "every offset is preserved" do
    text = %(You cross the room. "I won't stop," she says. Nine hundred and eighty-eight.)

    assert_equal text.length, S.of(text).length
  end

  test "quotation marks, newlines, bullets, digits and punctuation are kept" do
    assert_equal %("xx," xx—xxx 3. x\n- x), S.of(%("me," he—and 3. x\n- q))
  end

  test "a capital I survives and every other letter does not" do
    assert_equal "I xx'x xxxxx xxxx.", S.of("I am't going home.")
    assert_equal "xx x xxxx", S.of("in a hole"), "a lowercase i is not the pronoun"
  end

  # `\b` is what `FIRST_PERSON` turns on, so a letter must be replaced by
  # something the boundary rules treat identically. Ruby's `\w` is ASCII-only
  # but its `\b` is Unicode-aware, so this is the check that matters, and it is
  # the one that makes the corpus's accented and CJK characters safe.
  test "a filler letter sits on a word boundary exactly where the letter did" do
    %w[a Z é 沥 座 位].each do |letter|
      assert_equal "qxq".match?(/\bq\b/), "q#{letter}q".match?(/\bq\b/), letter
      assert_equal "Ix".match?(R::FIRST_PERSON), "I#{letter}".match?(R::FIRST_PERSON), letter
    end
  end

  # --- the three rules, end to end -------------------------------------------

  test "a refusal is still a refusal after reduction" do
    text = "I'm not going to narrate that. Threatening to harm a child isn't something I'll roleplay."

    assert R.refused?(S.of(text))
    assert_equal R.flags(text), R.flags(S.of(text))
  end

  test "a character speaking in dialogue is still not a refusal after reduction" do
    text = %("I won't stop until you tell me to," she says, and means it.)

    assert_not R.refused?(S.of(text))
    assert_equal R.flags(text), R.flags(S.of(text))
  end

  test "a menu is still a menu after reduction" do
    text = "The narrator declines. Instead:\n\n- the alley\n- the ledger"

    assert R.refused?(S.of(text))
    assert_equal [ :list ], R.flags(S.of(text))
  end

  # The watchlist is the one predicate that reads words rather than shape, so
  # its words are the one thing kept verbatim -- inside quoted dialogue, which
  # is exactly where it arrived.
  test "a crisis line survives verbatim, inside the dialogue that carried it" do
    text = %("You're going to call 988," he says, "or text HOME to 741741.")

    assert R.crisis_response?(S.of(text))
    assert_equal R.flags(text), R.flags(S.of(text))
    assert_includes S.of(text), "988"
    assert_includes S.of(text), "741741"
  end

  test "every string on the watchlist survives" do
    [ "988", "741741", "Crisis Text Line", "Suicide & Crisis",
      "Suicide and Crisis", "findahelpline", "hotline", "Lifeline" ].each do |fragment|
      assert_includes S.of("She says: #{fragment}."), fragment
    end
  end

  # --- and what does not survive ---------------------------------------------

  test "the words are gone" do
    reduced = S.of("Vess leans across the bar, unhurried, and names her price.")

    assert_equal "xxxx xxxxx xxxxxx xxx xxx, xxxxxxxxx, xxx xxxxx xxx xxxxx.", reduced
  end

  # A reduction that could be undone would be encryption with extra steps. This
  # is the property that says it cannot: two different responses of the same
  # shape reduce to the same skeleton, so there is nothing to invert.
  test "the mapping is many to one, so there is no way back" do
    assert_equal S.of("the door gives"), S.of("her hand opens")
  end

  # Applying it twice changes nothing, which is what says the checked-in file
  # really is output of this function and not prose that resembles it.
  test "reducing a skeleton returns the same skeleton" do
    text = %(Berrin says "call 988 now" and steps back.\n\n- one\n- two)

    assert_equal S.of(text), S.of(S.of(text))
  end

  test "blank and nil reduce to nothing" do
    assert_equal "", S.of("")
    assert_equal "", S.of(nil)
  end
end
