require "test_helper"

# THE ONE AUTHOR OF WHAT THE ENGINE SAYS WHEN IT WILL NOT PLAY A LINE.
#
# It is a value object over an `Intent` and a closed set, so nothing here needs
# a playthrough, a model or a database row: the whole class is the captain's
# ruling of 2026-09-04 turned into three sentences. What it must never do is
# turn a played line into a refusal, or a refused one into silence -- which is
# why `.for` returning nil is asserted as carefully as the copy is.
class Playthrough::RefusalTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @here = create(:location, story: @story, name: "Ward Office 12")
    @there = create(:location, story: @story, name: "The Supply Closet")
    @rowe = create(:character, story: @story, fullname: "Halkett Rowe", nickname: "Rowe")
    @lasco = create(:character, story: @story, fullname: "Perrin Lasco")
    @index = create(:item, :lying, location: @here, name: "Perrin's private index")
    @apron = create(:item, :lying, location: @here, name: "copy-room apron")
    @press = create(:item, :lying, :immovable, location: @here, name: "filing press")
  end

  def intent(action, **resolved)
    Playthrough::Classifier::Intent.new(action: action, **resolved)
  end

  # --- what is refused and what is not ---------------------------------------

  test "a line the loop can play earns no refusal" do
    assert_nil Playthrough::Refusal.for(intent(:move, destination: @there), typed: "go to the closet")
    assert_nil Playthrough::Refusal.for(intent(:talk, speaker: @rowe), typed: "ask Rowe about the file")
    assert_nil Playthrough::Refusal.for(intent(:take, item: @index), typed: "take the index")
    assert_nil Playthrough::Refusal.for(intent(:drop, item: @index), typed: "drop the index")
  end

  # THE BOUNDARY OF "CANNOT DETERMINE", stated as a test because it is the half
  # of the ruling that is easiest to overshoot. A coherent non-mechanic line is
  # not undeterminable -- the classifier placed it, it reaches for no record,
  # and refusing it would refuse everything that is not move / talk / take /
  # drop.
  # --- a thing that does not move -------------------------------------------
  #
  # THE ONE SHAPE THAT IS A FACT ABOUT A RECORD rather than about the reading.
  # Both names resolved and one act was asked for, so it is neither drift nor
  # overreach; what refuses it is `Item::BULK`.
  test "a throw of something immovable is refused, and names the thing and its bulk" do
    refusal = Playthrough::Refusal.for(intent(:throw, item: @press, at: @rowe), typed: "throw the press at Rowe")

    assert_equal :immovable, refusal.kind
    assert_match(/filing press/, refusal.text)
    assert_match(/immovable/, refusal.text)
    assert_match(/no die was thrown/, refusal.text)
    assert_match(/Nothing has changed/, refusal.text)
  end

  test "a throw of something that does move earns no refusal at all" do
    handy = create(:item, name: "Ward Office 12 daybook", location: @here, character: nil)

    assert_nil Playthrough::Refusal.for(intent(:throw, item: handy, at: @rowe), typed: "throw the daybook at Rowe")
    assert_nil Playthrough::Refusal.for(intent(:throw, item: @index, at: @there), typed: "throw the index at the closet")
  end

  test "a coherent line that reaches for no record is not refused" do
    assert_nil Playthrough::Refusal.for(intent(:other), typed: "look at the sky")
    assert_nil Playthrough::Refusal.for(intent(:examine), typed: "wait")
  end

  # --- two acts on one line ---------------------------------------------------

  test "two things named on one line names both, in the verb they were named in" do
    refusal = Playthrough::Refusal.for(
      intent(:take, item: @index, also_named: @apron), typed: "pick up the index and the apron"
    )

    assert_equal :named_more_than_one, refusal.kind
    assert_equal "pick up the index and the apron", refusal.typed
    assert_match(/two things at once/, refusal.reason)
    assert_match(/take Perrin's private index/, refusal.reason)
    assert_match(/take copy-room apron/, refusal.reason)
    assert_match(/One line is one act/, refusal.reason)
    assert_match(/Nothing has changed/, refusal.reason)
  end

  test "each action phrases its own pair" do
    assert_match(/go to The Supply Closet, and go to Ward Office 12/,
                 refuse(intent(:move, destination: @there, also_named: @here)).reason)
    assert_match(/talk to Halkett Rowe, and talk to Perrin Lasco/,
                 refuse(intent(:talk, speaker: @rowe, also_named: @lasco)).reason)
    assert_match(/drop Perrin's private index, and drop copy-room apron/,
                 refuse(intent(:drop, item: @index, also_named: @apron)).reason)
    # A look resolves a record too since `ta-item-inscriptions`, so a pair of
    # them has to be sayable -- and it is said as `read`, the word a player types.
    assert_match(/read Perrin's private index, and read copy-room apron/,
                 refuse(intent(:examine, item: @index, also_named: @apron)).reason)
    # AND `attack` SINCE COMBAT SLICE 8. Two people hit on one line is two acts
    # like any other, and without a row in `ASKED` the pair would have come back
    # as two bare names with no verb in front of either.
    assert_match(/attack Halkett Rowe, and attack Perrin Lasco/,
                 refuse(intent(:attack, speaker: @rowe, also_named: @lasco)).reason)
  end

  # THE ASYMMETRY IS DELIBERATE AND IT IS THE WHOLE BOUNDARY: a look can name two
  # things and it cannot miss one. "look at the sky" resolves to nothing and
  # stays narrated; "read the note and the index" is two acts on one line.
  test "an examine can be refused for naming two and never for landing on nothing" do
    assert_nil Playthrough::Refusal.for(intent(:examine), typed: "look at the sky", offered: [ @index ])
    assert_equal :named_more_than_one,
                 refuse(intent(:examine, item: @index, also_named: @apron)).kind
    assert_not_includes Playthrough::Drift::ACTIONS, "examine"
    assert_includes Playthrough::Overreach::ACTIONS, "examine"
  end

  # A person is named by their fullname, which is the name a refusal should
  # offer back -- the same one the closed enum is built from.
  test "a person is named the way the records name them" do
    refusal = refuse(intent(:talk, speaker: @rowe, also_named: @lasco))

    assert_match "talk to Halkett Rowe", refusal.reason
    assert_no_match(/talk to Rowe/, refusal.reason, "the nickname is not the name to offer back")
  end

  test "it never names a list it was not given" do
    refusal = refuse(intent(:take, item: @index, also_named: @apron), offered: [ @index, @apron ])

    assert_nil refusal.offer, "the two names are already in the reason; the floor is not the point"
  end

  # --- a reach that resolved to nothing ---------------------------------------

  # THE SET WAS EMPTY, OR THE COMMAND DID NOT LAND IN IT, and they are different
  # facts. It used to be one sentence for both, so "pickup everything" in a room
  # with three things on the floor was refused with "Nothing of that name is
  # lying here" -- printed directly above a read-out listing all three.
  test "an empty set is refused by saying it is empty" do
    assert_match(/There is nothing lying here to pick up/, refuse(intent(:take)).reason)
    assert_match(/There is nobody here to talk to/, refuse(intent(:talk)).reason)
    assert_match(/There is no way out of here at all/, refuse(intent(:move)).reason)
    assert_match(/You are carrying nothing/, refuse(intent(:drop)).reason)
    assert_match(/There is nobody here to fight/, refuse(intent(:attack)).reason)
  end

  test "a set with something in it is refused by saying the command did not land on it" do
    refusal = refuse(intent(:take), offered: [ @index, @apron ])

    assert_equal :unresolved, refusal.kind
    assert_match(/did not resolve to anything lying here/, refusal.reason)
    assert_equal "Lying here: Perrin's private index, copy-room apron.", refusal.offer
  end

  test "each action offers its own closed set back" do
    assert_equal "The ways out are: The Supply Closet.", refuse(intent(:move), offered: [ @there ]).offer
    assert_equal "Here with you: Halkett Rowe.", refuse(intent(:talk), offered: [ @rowe ]).offer
    assert_equal "You are carrying: copy-room apron.", refuse(intent(:drop), offered: [ @apron ]).offer
    # THE SAME SENTENCE AS A `talk`'S, because it is the same list read back --
    # the captain's ruling of 2026-09-05, *"anyone can be attacked"*, and there
    # is no narrower one to offer.
    assert_equal "Here with you: Halkett Rowe.", refuse(intent(:attack), offered: [ @rowe ]).offer
  end

  # AN ATTACK THAT FOUND NOBODY IS A REACH THAT FOUND NOTHING, which is what
  # `Playthrough::Drift::ACTIONS` gaining the word means for what the player
  # reads -- and it gets its own sentence rather than the `talk` one, because
  # they typed a blow.
  test "an attack that landed on nobody is refused as a reach that found nothing" do
    refusal = refuse(intent(:attack), offered: [ @rowe, @lasco ])

    assert_equal :unresolved, refusal.kind
    assert_match(/did not resolve to anybody here to swing at/, refusal.reason)
    assert_equal "Here with you: Halkett Rowe, Perrin Lasco.", refusal.offer
    assert_includes Playthrough::Drift::ACTIONS, "attack"
  end

  # `EMPTY` has already said the set is empty; "Lying here: nothing" says it
  # twice and worse.
  test "an empty set is not offered back" do
    assert_nil refuse(intent(:take)).offer
    assert_equal refuse(intent(:take)).reason, refuse(intent(:take)).text,
                 "with nothing to offer the two readings are the same sentence"
  end

  # --- an answer the app cannot read ------------------------------------------

  test "an intent outside the table that named a record asks for it again plainly" do
    refusal = refuse(intent(:other, unknown_action: "steal"))

    assert_equal :unreadable, refusal.kind
    assert_match(/did not come back as anything the game knows how to do/, refusal.reason)
    assert_match(/go somewhere, talk to somebody, take something, or put something down/, refusal.reason)
    assert_nil refusal.offer
  end

  # --- the two consumers -----------------------------------------------------

  # `#reason` for the mode that prints the records under every refusal,
  # `#text` for the one that does not. Nothing else differs between them.
  test "text folds what is here into the middle, and reason leaves it out" do
    refusal = refuse(intent(:move), offered: [ @there ])

    assert_equal "That did not resolve to one of the ways out of here. " \
                 "The ways out are: The Supply Closet. Nothing has changed.", refusal.text
    assert_equal "That did not resolve to one of the ways out of here. Nothing has changed.", refusal.reason
    assert_equal refusal.text, refusal.to_s
  end

  test "a kind outside the three is not constructible" do
    error = assert_raises(ArgumentError) do
      Playthrough::Refusal.new(kind: :invented, typed: "x", fact: "y")
    end

    assert_match(/is not one of/, error.message)
  end

  # The four shapes are the whole of it, so a fifth added without a sentence
  # would be a refusal with nothing in it. `:dead` comes off the second entry
  # point rather than `.for`: it is a fact about the GAME and there is no
  # `Intent` behind it, which is exactly why it has a constructor of its own.
  test "every kind the class declares is one of the two entry points can produce" do
    produced = [
      refuse(intent(:take, item: @index, also_named: @apron)),
      refuse(intent(:take)),
      refuse(intent(:other, unknown_action: "steal")),
      refuse(intent(:throw, item: @press, at: @rowe)),
      Playthrough::Refusal.dead(typed: "look")
    ].map(&:kind)

    assert_equal Playthrough::Refusal::KINDS.sort, produced.sort
  end

  test "a dead refusal states the death, names the player and offers a new playthrough" do
    refusal = Playthrough::Refusal.dead(typed: "go north", character: @rowe)

    assert_equal :dead, refusal.kind
    assert_equal "go north", refusal.typed
    assert_match(/#{Regexp.escape(@rowe.fullname)} is dead/, refusal.text)
    assert_match(/new playthrough/, refusal.text)
  end

  # "Nothing has changed" is an invitation to try again, and there is nothing to
  # try: the game is over. Both readings drop it, and only for this shape.
  test "a dead refusal does not tell the player nothing has changed" do
    refusal = Playthrough::Refusal.dead(typed: "look")

    assert_not_includes refusal.text, Playthrough::Refusal::UNCHANGED
    assert_not_includes refusal.reason, Playthrough::Refusal::UNCHANGED
    assert refusal.game_over?
    assert_not refuse(intent(:take)).game_over?
  end

  test "a dead refusal with no protagonist addresses the player instead of naming one" do
    refusal = Playthrough::Refusal.dead(typed: "look")

    assert_match(/You are dead/, refusal.text)
  end

  private

  def refuse(built, typed: "something", offered: [])
    Playthrough::Refusal.for(built, typed: typed, offered: offered)
  end
end
