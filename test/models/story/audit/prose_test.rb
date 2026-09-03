require "test_helper"

# THE THREE PROSE PREDICATES, ONE AT A TIME, WITH THEIR NEGATIVE CASES.
#
# Every "must not flag" case in this file is a real sentence -- from the
# captain's own playthroughs or from `narration_corpus.json` -- and each one is
# the sentence that actually broke an earlier version of the rule it sits
# under. A check with no negative case is unmeasured; these are the measurements
# written down as tests so widening a pattern fails the build.
#
# The corpus-wide false-positive rate is measured elsewhere and on real prose:
# `Story::Scoreboard::CorpusTest` over 92 passages, and
# `Story::AuditPrecisionTest` over the 24 lab narrations.
class Story::Audit::ProseTest < ActiveSupport::TestCase
  Prose = Story::Audit::Prose

  # --- the passage stops mid-sentence ---------------------------------------

  test "prose that ends on a full stop is finished" do
    assert_not Prose.truncated?("The lamp gutters and goes out.")
  end

  test "prose that ends mid-word is truncated" do
    assert Prose.truncated?("his mouth set in the careful, unsmudg")
  end

  test "prose that ends mid-clause is truncated" do
    assert Prose.truncated?("his pen uncapped and laid across the page as though he is")
  end

  test "a closing quote, bracket or emphasis after the full stop is still finished" do
    [ %(He shrugs. "Suit yourself."), "You wait (and wait).", "You wait *and wait.*",
      "It is over…", "Is it?", "Get out!" ].each do |text|
      assert_not Prose.truncated?(text), text
    end
  end

  # A DASH IS UNDECIDED ON PURPOSE. Nothing in the 92 measured passages ends on
  # one, so there is no evidence to judge it with and the check says nothing
  # rather than guessing. See `Prose.truncated?`.
  test "a passage ending on a dash is not judged either way" do
    assert_not Prose.truncated?(%("But I never—"))
    assert_not Prose.truncated?("You reach for the handle and—")
  end

  test "nothing at all is not truncation" do
    assert_not Prose.truncated?("")
    assert_not Prose.truncated?(nil)
    assert_not Prose.truncated?("   \n ")
  end

  # --- the protagonist written as somebody else -----------------------------

  NAMES = [ "Isbet Marrow", "Isbet", "Marrow" ].freeze

  test "the protagonist's name in the possessive is a third-person reference" do
    found = Prose.third_person_references("Isbet's lips thin into something that is not quite a smile.", NAMES)

    assert_equal 1, found.size
    assert_equal :possessive, found.first.kind
    assert_equal "Isbet", found.first.name
  end

  test "a sentence that opens on the protagonist's name is a third-person reference" do
    found = Prose.third_person_references("Isbet Marrow does not wave back.", NAMES)

    assert_equal %i[sentence_subject], found.map(&:kind)
  end

  test "the protagonist's name followed by a third-person pronoun is a third-person reference" do
    text = "The air greets you first, and then the sight of Isbet Marrow exactly where you left her."
    found = Prose.third_person_references(text, NAMES)

    assert_equal %i[coreference], found.map(&:kind)
  end

  # THE CRUCIAL NEGATIVE, and a real narration: the name is on the strap of a
  # satchel and the passage is entirely in the second person. A vocabulary scan
  # flags it; this must not.
  test "the protagonist's name written on an object is not a third-person reference" do
    text = "The name is stitched into the strap in small, careful letters—*Isbet Marrow*—and " \
           "stitched again into the leather flap of the field notes tucked inside, in your own handwriting. " \
           "But it is yours. You are certain of that much."

    assert_empty Prose.third_person_references(text, NAMES)
  end

  # THE OTHER CRUCIAL NEGATIVE, also real: somebody addressing the player by
  # name, with their own pronoun after the closing quote. This is correct prose
  # and was the only false positive the three grammars produced on 92 passages.
  test "somebody addressing the player by name inside quotation marks is not a violation" do
    text = %(He reaches past you and sets a folded paper on the table, on top of your map. ) +
           %("That's the reminder. Two weeks overdue. Settle it by the new moon or settle it ) +
           %(out the door — your choice, Miss Marrow." He turns and thumps back down the stairs ) +
           %(without waiting for an answer.)

    assert_empty Prose.third_person_references(text, NAMES)
  end

  test "a curly-quoted address is guarded too" do
    assert_empty Prose.third_person_references("“Well then, Isbet. She will be waiting.”", NAMES)
  end

  test "one reference per grammar per sentence, however many times the name appears" do
    text = "Isbet's mouth tightens, and she doesn't look at you."
    found = Prose.third_person_references(text, NAMES)

    assert_equal 1, found.map(&:sentence).uniq.size
    assert_equal found.size, found.map(&:kind).uniq.size
  end

  test "no protagonist names means nothing to look for" do
    assert_empty Prose.third_person_references("Isbet Marrow does not wave back.", [])
  end

  # --- the names the records give a character -------------------------------

  test "a character's names are the full name, the nickname and each part" do
    character = build(:character, fullname: "Odile Vance", nickname: "Vance")

    assert_equal [ "Odile Vance", "Vance", "Odile" ], Prose.protagonist_names(character)
  end

  test "a name shorter than the floor is not scanned for" do
    character = build(:character, fullname: "Isbet Marrow", nickname: "Iz")

    assert_not_includes Prose.protagonist_names(character), "Iz"
  end

  test "nobody has no names" do
    assert_empty Prose.protagonist_names(nil)
  end

  # --- a door closing at the player's back ----------------------------------

  test "a door closing behind the player is a departure claim" do
    text = "The door clicks shut behind you, and somewhere on the other side of it, he waits."

    assert_equal 1, Prose.departure_claims(text).size
  end

  test "several phrasings of the same claim are all read" do
    [ "The door draws closed behind you on its own weight.",
      "The gate swings shut behind you.",
      "The hatch seals behind you with a soft thud." ].each do |text|
      assert_equal 1, Prose.departure_claims(text).size, text
    end
  end

  # THE ORDER IS THE RULE. This is the seeded world's own opening narration: it
  # contains a threshold, the word "close" and "behind you", and asserts
  # nothing. Requiring threshold-then-verb-then-"behind you" drops it.
  test "a door merely standing behind the player is not a departure claim" do
    text = "The mantle hisses over the two of you, and behind you, close enough to touch, the narrow " \
           "door of the supply closet stands exactly as unlocked as it has stood for eleven years."

    assert_empty Prose.departure_claims(text)
  end

  test "behind your brow is not behind you" do
    [ "You press your fingertips to your temples, willing the fog behind your brow to thin.",
      "A dull pressure blooms behind your eyes, the familiar warning of too much exposure." ].each do |text|
      assert_empty Prose.departure_claims(text), text
    end
  end

  test "a door closing behind somebody else is not a claim about the player" do
    text = "He slips out into the hallway, pulling the door softly shut behind him."

    assert_empty Prose.departure_claims(text)
  end

  test "a thing that is not a threshold closing behind the player is not a departure" do
    text = "The Registrar's stamp sits on the desk behind you, rocking once on its pad and going still."

    assert_empty Prose.departure_claims(text)
  end
end
