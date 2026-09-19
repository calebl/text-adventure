# WHAT A MODEL IS ASKED FOR WHEN IT WRITES WHAT SOMEBODY IS AFTER, AND THE ONE
# PLACE IT IS WRITTEN DOWN.
#
# THERE ARE TWO GENERATION BOUNDARIES AND THEY MUST NOT DISAGREE.
# `Character::Schema` writes one whole sheet on its own call; the `people`
# object of `Location::DetailSchema` writes up to a roomful riding on the
# room's own description. Both ask for the same six values, so both read their
# field descriptions and their instruction block out of this module -- the
# reason `Character::Registry::PERSON_LIMITS` is a table one file reads rather
# than a number two files each hold: two definitions of a conscious desire
# would make one world inconsistent with itself.
#
# NEITHER BOUNDARY ADDS A CALL. Six fields are appended to an answer the game
# was already paying for.
#
# WHAT THE LENGTHS ARE IS NOT HERE, and that is deliberate. The whole-sheet
# path is capped by `Character::DESIRE_LIMIT` and the realization path by
# `Character::Registry::PERSON_LIMITS`, because a cap is a fact about how much
# of an answer a caller can afford and the two callers can afford different
# amounts. What is here is what the four MEAN, which is the same either way.
#
# THE SOURCE. The four objects of desire are Story Grid's -- a conscious want,
# an unconscious want, a recognized need and an unrecognized need -- and the
# one rule below that is worth naming is *no half goals*: a desire phrased as
# "stop being afraid" names nothing anybody can walk toward, and there is no
# act in a room that satisfies it. Every field here has to name something to
# move TOWARD, and the instructions say so twice.
module Character::Desires
  CONSCIOUS =
    "What this person would say if somebody asked them what they want, today, in this story. " \
    "Specific, and reachable by somebody standing in a room in this world. Name something to " \
    "move TOWARD, never something to stop or escape. One sentence, third person, by name.".freeze

  UNCONSCIOUS =
    "What they are actually pursuing and would deny if you said it to them. It sits at an angle " \
    "to the conscious desire rather than agreeing with it: the conscious desire is the reason " \
    "they give themselves, and this is what keeps them going when that reason runs out. One " \
    "sentence, third person, by name.".freeze

  RECOGNIZED =
    "Something they know they must do whether they want to or not, and may resent. A real " \
    "obligation this world imposes on them -- their work, their family, their debt, their oath, " \
    "their body -- and one that can get in the way of the conscious desire. One sentence, third " \
    "person, by name.".freeze

  UNRECOGNIZED =
    "What they need and cannot see, not even unconsciously. A reader should be able to see it " \
    "from the backstory above while they cannot. If they never do it, pursuing the conscious " \
    "desire ruins them. It must not be the conscious desire said twice. One sentence, third " \
    "person, by name.".freeze

  DESIRE_PURSUIT =
    "Which listed shape the CONSCIOUS DESIRE has -- the one that fits the act they would take " \
    "tomorrow morning.".freeze

  NEED_PURSUIT =
    "Which listed shape the UNRECOGNIZED NEED has. It may be the same label as the one above; " \
    "the more interesting answer is usually a different one.".freeze

  # WHO IS WRITING, and the one copy of it. `Character::Generator` has a system
  # prompt of its own about writing a whole person; this is the sentence for a
  # call whose whole subject is what somebody is after
  # (`Character::DesireWriter`).
  #
  # THE HALF-GOAL RULE IS IN IT because it is the failure this prompt has to
  # avoid rather than a preference: "stop being afraid" names nothing a person
  # in a room can walk toward, so there is no act the engine could ever weight
  # toward it and the field is dead the moment it is written.
  SYSTEM_PROMPT = <<~SYSTEM.freeze
    You write what people in a story are after. You work from the four objects of
    desire: what a person knows they want, what they are actually pursuing without
    knowing it, what they know they must do whether they want to or not, and what
    they need and cannot see.

    You write each one as a thing to move TOWARD, never as a thing to move away
    from. "Stop being afraid" is not an object of desire; "get the ledger into a
    Registry that still has his file open" is.

    You do not resolve anybody. You say what they are reaching for on the day the
    story starts.

    DO NOT INCLUDE EMOJIS IN YOUR RESPONSE.
  SYSTEM

  def self.system_prompt = SYSTEM_PROMPT

  # THE SEVEN LABELS AND WHAT EACH ONE MEANS, AS PROMPT TEXT. Read off
  # `Character::PURSUITS` rather than written out again, so a label added to
  # that table reaches both prompts without anybody remembering to.
  def self.pursuit_list
    Character::PURSUITS.map { |label, meaning| "  #{label.ljust(9)}#{meaning}" }.join("\n")
  end

  # WHAT BOTH GENERATION PROMPTS APPEND, and the ONE copy of it.
  #
  # `several_people:` is the realization path's two extra lines and nothing
  # else. That call writes a roomful in one answer, so it needs telling that
  # the four belong to each person separately; the whole-sheet call writes one
  # person and would be paying for a sentence about a situation it is never in.
  def self.instructions(several_people: false)
    <<~DESIRES
      ## Their Four Objects of Desire

      Write four things this person is after and pick two labels for them. Work from
      everything above -- their backstory, what they like and dislike, what they are
      afraid of, how old they are, how strong their will is, and where they are
      standing.

      The two labels are picked from this list and nothing else:

      #{pursuit_list}

      Rules:
      - Every one of the four names something to move TOWARD. A field that only says
        what they want to stop or escape is not finished. Say what is on the other
        side of it.
      - Write them so an ordinary act in a room could serve one: picking something
        up, handing something over, walking out, staying put, standing near
        somebody. Do not write a desire nobody could act on in a room.
      - Keep them consistent with the fears and dislikes above. A fear is usually the
        shadow of one of these four and should read that way.
      - The conscious desire and the unrecognized need must not be the same thing
        said twice.
      - Write in the third person, by name.
      - Do not resolve any of them, and do not say how the story ends.
      - Respect the stated length of each field.
      #{several_people ? MORE_THAN_ONE : ""}
    DESIRES
  end

  # THE REALIZATION PATH'S TWO EXTRA LINES. A room is written in one answer, so
  # without the first of these the three people in it come out wanting the same
  # thing in the same words; without the second, a roomful of goals the player
  # cannot reach from where they are standing.
  MORE_THAN_ONE = <<~MORE.freeze
    - Each person in this room gets their own four. Two people in one room must not
      want the same thing in the same words.
    - At least one of them should want something that is in this room or one step
      out of it.
  MORE
end
