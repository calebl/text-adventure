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

  # --- the prose against the floor plan --------------------------------------
  #
  # THE TWO GRAMMARS ARE SILENT ON EVERY PASSAGE IN THIS REPOSITORY -- 0
  # detections over all 367 real ones, which is measured and written down on the
  # methods themselves. A check that cannot fire looks exactly like a clean
  # result, so these fire them on written sentences of the shape a room handed a
  # plan invites, and pin the negatives that would make either one noisy.

  # EVERY SENTENCE FIVE ROUNDS OF REVIEW PRODUCED, positives and negatives, each
  # as its own case with the walls it must and must not yield. The list is long
  # on purpose: this check began as a threshold anywhere in the sentence and was
  # narrowed four times, and each narrowing closed one shape of one mistake
  # because the negatives on hand only covered the shapes the round before had
  # found. `Story::Audit::Prose`'s relation grammar is what replaced the
  # narrowing, and this list is what stops the next one being needed.
  #
  # A DOORLESS WALL MAY STAND ON EITHER SIDE OF A DOOR IN ONE SENTENCE, and
  # `Location::Plan#closed_walls_clause` is what invites a model to name it
  # there -- so both orders are pinned, and so is every connective between them.

  # --- PUT IN IT: a threshold bound to the wall by a preposition of place ----

  test "a door in a named wall is a claim about that wall" do
    claims = Prose.door_claims("A low door in the north wall stands open on the stair.")

    assert_equal [ "north" ], claims.map(&:wall)
    assert_equal "A low door in the north wall stands open on the stair.", claims.sole.sentence
  end

  test "a corner is a wall of its own, and the placement may be into or through" do
    assert_equal [ "south-west" ], Prose.door_claims("A door is set into the south-west wall.").map(&:wall)
    assert_equal [ "east" ], Prose.door_claims("A gate stands through the east wall.").map(&:wall)
  end

  test "a verb or particle may sit between the threshold and the preposition" do
    assert_equal [ "east" ], Prose.door_claims("The door out is in the east wall.").map(&:wall)
    assert_equal [ "east" ], Prose.door_claims("A door leads out through the east wall.").map(&:wall)
  end

  test "every wall the prose puts a door in is read, and each one once" do
    text = "A door in the north wall leads on, and a second door in the east wall stands ajar. " \
           "The north wall door is the one with the bar across it."

    assert_equal [ "north", "east" ], Prose.door_claims(text).map(&:wall)
  end

  # --- HELD BY IT: a wall that carries one ----------------------------------

  test "a wall that is broken by, holds or carries a threshold is a claim" do
    assert_equal [ "east" ],
                 Prose.door_claims("The east wall is broken by a hatch nobody has opened in years.").map(&:wall)
    assert_equal [ "north-east" ], Prose.door_claims("The North-East wall carries a shuttered gate.").map(&:wall)
    assert_equal [ "east" ], Prose.door_claims("The east wall holds a door in the corner.").map(&:wall)
    assert_equal [ "north" ], Prose.door_claims("The north wall has a door in it.").map(&:wall)
  end

  # --- WALL FIRST: the inversion of the first form ---------------------------

  test "the wall named first and the threshold after it is the same relation" do
    assert_equal [ "north" ], Prose.door_claims("In the north wall, a door.").map(&:wall)
  end

  # --- a second door named without the word ---------------------------------

  # THE SHAPE THE REPOSITORY'S OWN WORKED EXAMPLE USES
  # (`lib/engine_sweep/worlds/the-quay-house.yml`, The Custom House room 3): a
  # sentence names one door by the noun and the next by "one" or "another".
  test "another or one standing in for a door names the wall it is put in" do
    assert_equal [ "north", "west" ],
                 Prose.door_claims("A door in the north wall goes through to the counting room, and one " \
                                   "in the west wall stands half open on the dark.").map(&:wall)
    assert_equal [ "north", "east" ],
                 Prose.door_claims("A door in the north wall opens on the landing, and another in the " \
                                   "east wall leads on.").map(&:wall)
  end

  test "another closing the phrase names the wall that holds it" do
    assert_equal [ "south", "east" ],
                 Prose.door_claims("A door in the south wall opens on the dark, and the east wall has " \
                                   "another.").map(&:wall)
    assert_equal [ "north", "west" ],
                 Prose.door_claims("The door in the north wall is the one they use, and the west wall " \
                                   "has another.").map(&:wall)
  end

  # --- and everything that is NOT a claim -----------------------------------

  # A COMPASS WORD IS NOT A WALL, and a wall with nothing put in it or held by
  # it is not a door. Both are what keep this off ordinary description.
  test "a wall with no door in it, and a door with no wall, claim nothing" do
    [ "The north wall is bare plaster and the damp is coming through it.",
      "Two doors lead out of here, and neither of them is locked.",
      "The door on the north side of the yard is the one they use.",
      "Ledgers to the ceiling, and a smell of tar that never leaves the plaster." ].each do |text|
      assert_empty Prose.door_claims(text), text
    end
  end

  test "a wall the sentence denies a door to is not a claim" do
    assert_empty Prose.door_claims("There is no door in the north wall, whatever the plans say.")
  end

  # A DOOR MERELY NEAR A WALL IS NOT A DOOR IN IT, which is the whole of why the
  # grammar reads relations. Every one of these was a false positive of some
  # earlier version, and each names a doorless wall beside a real door.
  test "a door near a wall it is not in claims nothing about that wall" do
    { "Rain streaks the south wall beside the door." => [],
      "Ledgers line the south wall; the door out is in the east wall." => [ "east" ],
      "A cold hearth on the south wall, and a door leads out through the east wall." => [ "east" ],
      "The north wall carries the door, and the west wall carries the shelves." => [ "north" ],
      "The north wall has a door in it, and the east wall is bare." => [ "north" ] }.each do |text, walls|
      assert_equal walls, Prose.door_claims(text).map(&:wall), text
    end
  end

  # THE DOORLESS WALL AFTER THE DOORS, which is the order a description that
  # answers the plan's closing sentence tends to use.
  test "doorless walls named after the doors claim nothing" do
    { "A door in the north wall gives back onto the landing, and another in the east wall leads on; " \
      "the south wall is hung with tarred canvas and the west wall carries a run of pigeonholes." =>
        [ "north", "east" ],
      "A door in the north wall gives back onto the landing, and another in the east wall leads on; " \
      "the west wall is one long run of pigeonholes." => [ "north", "east" ],
      "A door in the north wall opens on the landing; the south wall is the one the damp has ruined." =>
        [ "north" ],
      "A door in the north wall leads on, and the one behind the desk is barred; the east wall is bare." =>
        [ "north" ] }.each do |text, walls|
      assert_equal walls, Prose.door_claims(text).map(&:wall), text
    end
  end

  # AND THE DOORLESS WALL BEFORE THEM, the order a bridge length could not
  # answer on its own.
  test "doorless walls named before the doors claim nothing" do
    { "Bare boards, a cold hearth on the south wall, and a door in the east wall." => [ "east" ],
      "The south wall is blank, and a door in the north wall gives back onto the landing." => [ "north" ],
      "The east wall is bare, and a door in the west wall opens on the stair." => [ "west" ],
      "The south wall is blank, and another in the east wall leads on past the door." =>
        [ "east" ] }.each do |text, walls|
      assert_equal walls, Prose.door_claims(text).map(&:wall), text
    end
  end

  # "one" IS A NUMERAL AND A PRONOUN FIRST. Held by a wall it has to close the
  # noun phrase; put in a wall the preposition disambiguates it.
  test "one used as a numeral or a pronoun claims no door" do
    { "A door in the north wall, and the south wall has one long shelf of ledgers." => [ "north" ],
      "A door in the north wall; the west wall carries one great map of the estuary." => [ "north" ],
      "The east wall is the only one still standing beside the door." => [],
      "A door in the west wall opens onto the quay, and one in the east goes further in." =>
        [ "west" ] }.each do |text, walls|
      assert_equal walls, Prose.door_claims(text).map(&:wall), text
    end
  end

  test "an anaphor with no threshold anywhere in the sentence claims nothing" do
    assert_empty Prose.door_claims("You are the only one here, and the north wall is damp to the touch.")
    assert_empty Prose.door_claims("One in the north wall would have helped, if anybody had cut one.")
  end

  # THE ONE PIECE OF PROSE IN THE REPOSITORY THIS GRAMMAR READS, verbatim from
  # `lib/engine_sweep/worlds/the-quay-house.yml`. Both walls are walls The
  # Custom House room 3's boxes really share, so the two detections it produces
  # are the measured figure on `Prose.door_claims` and must not move.
  test "the repository's own worked example reads as the two doors its boxes hold" do
    text = "The back office, 7 by 6 paces of bare boards on storey 0. A door in the north wall\n" \
           "goes through to the counting room, and one in the west wall stands half open on the\n" \
           "dark. Nothing else opens anywhere."

    assert_equal [ "north", "west" ], Prose.door_claims(text).map(&:wall)
  end

  test "a size stated as a pair of paces is read, in either phrasing" do
    assert_equal [ [ 4, 6 ] ], Prose.size_claims("The room is 6 by 4 paces of wet flagstone.").map(&:paces)
    assert_equal [ [ 4, 6 ] ], Prose.size_claims("It runs six paces by four, no more.").map(&:paces)
    assert_equal [ [ 4, 6 ] ], Prose.size_claims("Four paces by six paces, and every one of them cold.").map(&:paces)
  end

  # THE UNIT IS WHAT MAKES IT A MEASUREMENT OF THIS ROOM, and a single
  # measurement does not say which axis it measured.
  test "a pair with no paces in it, and a single measurement, claim nothing" do
    [ "The counter runs six by four and the till is at the end of it.",
      "The room is four paces wide.",
      "Six feet by four, and painted on the floor." ].each do |text|
      assert_empty Prose.size_claims(text), text
    end
  end

  test "a storey stated as the engine states it is read" do
    assert_equal [ 1 ], Prose.storey_claims("Everything on storey 1 smells of tar.").map(&:storey)
    assert_equal [ -1 ], Prose.storey_claims("The cellar is storey -1 and it is under water.").map(&:storey)
  end

  # FLOOR-NUMBERING IS A CONVENTION AND THE PROMPT NEVER USES IT, so a passage
  # that says it is a passage this cannot convict. Stated as a test because the
  # miss is deliberate.
  test "the second floor is not a storey claim" do
    assert_empty Prose.storey_claims("You come out on the second floor with the rain on the skylight.")
  end
end
