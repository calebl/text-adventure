require "test_helper"

# The rules, one at a time. `BaseAgent::RefusalPrecisionTest` is what says they
# work on real prose; this is what says each one does what its name claims, so a
# regression points at a rule rather than at a count.
class BaseAgent::RefusalTest < ActiveSupport::TestCase
  # --- what a refusal looks like --------------------------------------------

  test "an opening in the model's own voice is a refusal" do
    assert BaseAgent::Refusal.refused?("I'm not going to narrate that.")
    assert BaseAgent::Refusal.refused?("I can't write that scene.")
    assert BaseAgent::Refusal.refused?("I won't produce that content, even in fiction.")
  end

  # The refusal that decided the rule. No "I can't", no "I cannot", no "as an
  # AI" -- nothing a word list carries -- and it is the response a previous
  # report's 0/5 refusal rate turned on.
  test "a refusal with none of the usual phrases in it is still caught" do
    assert BaseAgent::Refusal.refused?(
      "I'm not going to narrate that. Threatening to harm a child isn't something " \
      "I'll roleplay, regardless of the setting or framing."
    )
  end

  # A model that declines by offering alternatives is refusing, and
  # `Scene::Narrator::INSTRUCTIONS` forbids the menu in as many words. The
  # corpus has one that opens "The narrator declines this particular scene" --
  # third person, no first person anywhere in it -- so the list is the only
  # thing that catches it.
  test "a menu is a refusal even with no first person in it" do
    assert BaseAgent::Refusal.refused?(<<~PROSE)
      The narrator declines this particular scene. Where the story could go instead:

      - the argument that starts in the doorway
      - the debt itself, and who else is on the page
    PROSE
    assert BaseAgent::Refusal.refused?("Some ways to go:\n\n1. the alley\n2. the ledger")
  end

  # --- what a refusal does not look like ------------------------------------

  # The false positive that killed the regex version, and it is a real sentence
  # from the corpus: Vess, mid-seduction. A pattern matching on words reads it
  # as a refusal because the words are the same words.
  test "a character saying I in dialogue is not a refusal" do
    assert_not BaseAgent::Refusal.refused?(
      %("I won't stop until you tell me to," she says, and means it.)
    )
    assert_not BaseAgent::Refusal.refused?(
      %(Kell shrugs. "If I let myself think about it too long, I won't be able to do the work.")
    )
  end

  test "second-person narration is not a refusal" do
    assert_not BaseAgent::Refusal.refused?(
      "You slide the seal-knife from your belt without ceremony, the little bronze " \
      "blade catching the gaslight as you cross the room."
    )
  end

  # A hyphen that opens a line of prose is not a bullet: the rule wants the
  # space after it, because that is what a list has and an em-dash break does
  # not.
  test "prose that begins a line with a dash is not a menu" do
    assert_not BaseAgent::Refusal.refused?("The door gives.\n-and then it does not.")
  end

  test "blank and nil are not refusals" do
    assert_not BaseAgent::Refusal.refused?("")
    assert_not BaseAgent::Refusal.refused?(nil)
  end

  # The opening is 300 characters after the dialogue comes out. A model that
  # refuses does it up front; an "I" deep in a long narration is somebody
  # speaking, and the quote-stripper does not catch every attribution.
  test "an I well past the opening is not read as the model talking" do
    prose = "You cross the room. " * 20

    assert_not BaseAgent::Refusal.refused?("#{prose}I is the last letter here.")
    assert BaseAgent::Refusal.refused?("I refuse. #{prose}")
  end

  # --- the watchlist, which is a different thing -----------------------------

  # Inside quoted dialogue on purpose: that is where it actually arrived, and it
  # is why the structural rule cannot see it -- the quote-stripper takes the
  # whole line out before the opening is read.
  test "a crisis line inside dialogue is a crisis response and not a refusal" do
    text = %("Here's what's going to happen," he says. "You're going to call or text ) +
           %(988 right now, or text HOME to 741741.")

    assert BaseAgent::Refusal.crisis_response?(text)
    assert_not BaseAgent::Refusal.refused?(text), "the structural rule cannot see this, which is the point"
  end

  test "every string on the watchlist is recognised" do
    [ "call 988 now", "text HOME to 741741", "the Crisis Text Line",
      "Suicide & Crisis Lifeline", "Suicide and Crisis Lifeline",
      "the 24-hour Lifeline", "a crisis hotline", "findahelpline.com" ].each do |fragment|
      assert BaseAgent::Refusal.crisis_response?("She says: #{fragment}."), fragment
    end
  end

  test "ordinary narration carries none of the watchlist" do
    assert_not BaseAgent::Refusal.crisis_response?(
      "The telegraph office is shut. Nine hundred and eighty-eight marks, the ledger says."
    )
    assert_not BaseAgent::Refusal.crisis_response?("You take the line down to the water.")
  end

  # --- the flags, which are what gets logged --------------------------------

  test "flags name every rule that fired" do
    assert_equal [], BaseAgent::Refusal.flags("You open the door.")
    assert_equal [ :unquoted_first_person ], BaseAgent::Refusal.flags("I won't write that.")
    assert_equal [ :list ], BaseAgent::Refusal.flags("Try instead:\n\n- the alley")
    assert_equal [ :crisis_resource ], BaseAgent::Refusal.flags(%("Call 988," she says.))
    assert_equal [ :unquoted_first_person, :list, :crisis_resource ],
                 BaseAgent::Refusal.flags("I'm concerned. Please reach out:\n\n* 988 (call or text)")
  end
end
