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
# "stop being afraid" names nothing anybody can walk toward. Every field here
# has to name something to move TOWARD, and the instructions say so twice.
module Character::Desires
  CONSCIOUS =
    "The future, standing, relationship, legacy, place or way of life they knowingly " \
    "organize their choices around and would name if asked what they want from their life. " \
    "Make it specific to this person and world. Do not substitute the clue, deadline, " \
    "delivery, payment or room they are dealing with today. One sentence, third person, " \
    "by name.".freeze

  UNCONSCIOUS =
    "The deeper reward their choices have pursued for years and they would deny: the " \
    "recognition, absolution, dependence, belonging, power or intimacy beneath the " \
    "conscious account. It explains a repeated pattern in the backstory and pulls at an " \
    "angle to the conscious desire, not merely today's hidden motive. One sentence, third " \
    "person, by name.".freeze

  RECOGNIZED =
    "The duty, oath, debt, craft, family burden or bodily discipline they believe they " \
    "must keep over years whether they want to or not. It predates today's assignment, " \
    "survives it, and can repeatedly obstruct the conscious desire. One sentence, third " \
    "person, by name.".freeze

  UNRECOGNIZED =
    "The enduring change, truth or relationship their life requires and their repeated " \
    "pattern prevents them from seeing. A reader can infer it from the backstory. It " \
    "cannot be completed by one confession, realization or errand: it demands a new way " \
    "of choosing across the story. If they never move toward it, pursuit of the conscious " \
    "desire ruins them. It must not be the conscious desire said twice. One sentence, " \
    "third person, by name.".freeze

  DESIRE_PURSUIT =
    "Which listed ENGINE ACT could repeatedly advance or protect the CONSCIOUS DESIRE in " \
    "ordinary rooms. The label is the next-step expression of the larger desire, not its " \
    "timescale.".freeze

  NEED_PURSUIT =
    "Which listed ENGINE ACT could repeatedly move them toward the UNRECOGNIZED NEED in " \
    "ordinary rooms. It may match desire_pursuit, but a different label should reflect a " \
    "real conflict rather than manufactured variety.".freeze

  # WHO IS WRITING, and the one copy of it. `Character::Generator` has a system
  # prompt of its own about writing a whole person; this is the sentence for a
  # call whose whole subject is what somebody is after
  # (`Character::DesireWriter`).
  #
  # THE HALF-GOAL RULE IS IN IT because it is the failure this prompt has to
  # avoid rather than a preference: "stop being afraid" names nothing beyond the
  # fear, so the field is dead the moment it is written.
  SYSTEM_PROMPT = <<~SYSTEM.freeze
    You write the story-scale forces that organize a person's life. You work from the
    four objects of desire: the future they knowingly build toward, the deeper reward
    they repeatedly pursue without admitting it, the obligation they knowingly carry,
    and the change or relationship they need but cannot yet see.

    Each object was already shaping choices before the opening scene and can keep
    creating pressure after today's errand succeeds or fails. A deadline, clue, delivery,
    inspection or escape may be today's tactic; it is not the whole object of desire.

    Write each object as something to move TOWARD. "Stop being afraid" is a half-goal;
    "build a life in which she can trust another keeper with the bell" names the state
    beyond the fear.

    Do not resolve anybody. Name the enduring pressure that can drive choices across the
    story.

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

      Write four STORY-SCALE things this person is after, then pick two TURN-SCALE labels.
      Work from everything above -- especially the years in their backstory, their repeated
      choices, what they fear losing, the future they imagine, and where today's situation
      presses on that life.

      An object of desire must satisfy both tests:
      1. It was shaping this person before the opening scene.
      2. Finishing today's errand would not finish it; it can drive choices across the
         whole story.

      The two labels are picked from this list and nothing else:

      #{pursuit_list}

      conscious_desire
        The future, standing, relationship, legacy, place or way of life they knowingly
        organize their choices around and would name if asked what they want from their
        life. Make it specific to this person and world. Do not substitute the clue,
        deadline, delivery, payment or room they are dealing with today. One sentence.

      unconscious_desire
        The deeper reward their choices have pursued for years and they would deny: the
        recognition, absolution, dependence, belonging, power or intimacy beneath the
        conscious account. It must explain a repeated pattern in the backstory and pull at
        an angle to the conscious desire, not merely restate today's hidden motive. One
        sentence.

      recognized_need
        The duty, oath, debt, craft, family burden or bodily discipline they believe they
        must keep over years whether they want to or not. It predates today's assignment,
        survives it, and can repeatedly obstruct the conscious desire. One sentence.

      unrecognized_need
        The enduring change, truth or relationship their life requires and their repeated
        pattern prevents them from seeing. A reader can infer it from the backstory. It
        cannot be completed by one confession, realization or errand: it demands a new way
        of choosing across the story. If they never move toward it, pursuit of the
        conscious desire ruins them. One sentence.

      desire_pursuit
        Pick the listed ENGINE ACT that could repeatedly advance or protect the conscious
        desire in ordinary rooms. The label is the next-step expression of the larger
        desire, not its timescale.

      need_pursuit
        Pick the listed ENGINE ACT that could repeatedly move them toward the unrecognized
        need in ordinary rooms. It may match desire_pursuit, but a different label should
        reflect a real conflict rather than manufactured variety.

      Rules:
      - Every field names something to move TOWARD. State what lies beyond a fear, refusal
        or escape.
      - The object is larger than any single room act. Picking something up, handing it
        over, walking, waiting or staying near somebody may advance, protect, rehearse or
        betray it; that act must not become the whole desire.
      - Use today's room as pressure or evidence, not as the horizon of the person's life.
      - Keep the four consistent with the backstory, fears and dislikes. A fear is often
        the shadow of an object, but is not the object itself.
      - The conscious desire and unrecognized need must not be the same thing said twice.
      - Write in the third person, by name.
      - Do not resolve any object or say how the story ends.
      - Respect the stated length of each field.
      #{several_people ? MORE_THAN_ONE : ""}
    DESIRES
  end

  # THE REALIZATION PATH'S TWO EXTRA LINES. A room is written in one answer, so
  # without the first of these the three people in it come out wanting the same
  # thing in the same words; without the second, nothing in the room presses on
  # the life-scale objects the common block asks for.
  MORE_THAN_ONE = <<~MORE.freeze
    - Each person in this room gets their own four. Two people in one room must not
      want the same thing in the same words.
    - At least one person's enduring object should be visibly pressed by something in
      this room or one step away. The nearby thing is today's tactic or test, not the
      whole object.
  MORE
end
