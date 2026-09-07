# WHERE A GENERATED STORY IS GOING, ASKED ONCE, AT WORLD CREATION.
#
# THE ONE THING TO UNDERSTAND ABOUT THIS SCHEMA: **it names things and creates
# nothing.** Every field below is text or a pick from a closed list, and not one
# of them is a row -- there is no place here, no person, no thing, no id and no
# coordinate. `Quest::Generator` writes `quests`, `quest_steps` and
# `quest_outcomes` out of the answer and touches no other table. That is what
# lets an arc be written at `rake game:new`, when the world is one unrealized
# room and nobody at all, without the arc conjuring a world to fit it.
#
# WHY IT IS A SEPARATE CALL FROM `Story::Schema` and not six more fields on it
# -- the captain's Call 3 of 2026-09-06, *"a: yes, one separate call"*. One
# answer cannot be asked both to leave the ending open and to state it, and
# `Story::Generator`'s prompt ends *"Leave the ending open. You are starting a
# story, not outlining one."* That sentence is load-bearing (direction report
# §12) and this schema is the reason it does not have to move. A world is
# generated rarely and played many times, so a per-world round trip is the
# cheapest place in the app to spend one.
#
# WHAT IS CLOSED AND WHAT IS FREE, because the standing rule is that a model
# picks from a set the app closed:
#
#   CLOSED   `trigger` is `Quest::TRIGGERS`, the fixed table of four -- every
#            one of them something `Playthrough::Turn` already does, so there is
#            no beat the loop cannot reach and nothing to forbid. The step count
#            is bounded by `min_items`/`max_items`.
#   FREE     the names and the sentences, and they have to be: a place nobody
#            has invented yet has no closed list to be picked from. What keeps
#            them honest is that a name is a NAME and nothing acts on it until
#            a registry writes a row with it (`Quest::Binder`).
#
# NO `minutes` FIELD, AND THAT IS WHY `time_passed` IS NOT OFFERED HERE. The
# captain's rule is flat -- *"the model never writes a free number, only picks
# from the list"* -- and a deadline in story minutes is a free number. A
# `time_passed` beat is a thing a seed file writes, where a person chose the
# number; when the engine wants to schedule one it will be a pick out of a table
# in code, which is `ta-quest-outcomes`' business.
#
# NO POSITION FIELD EITHER: the array's order is the order, exactly as
# `WorldSeed::Exporter` writes a quest's steps without numbering them. A number
# a model has to keep in step with a list is a number a model gets wrong.
class Quest::Schema < RubyLLM::Schema
  # HOW MANY BEATS AN ARC IS ALLOWED TO HAVE. Three to five, which is the
  # direction report's figure and is a shape rather than a measurement: fewer
  # than three is a fetch quest, more than five is an outline -- and an outline
  # is the thing `Story::Generator`'s closing sentence exists to prevent.
  #
  # IT IS ALSO A COST CEILING THE DEADLINE HAS TO LIVE WITH. Every unbound step
  # is something `Quest::Deadline` may eventually have to place, one per
  # realization, so an arc of twelve would be a world that grew twelve buildings
  # nobody asked for.
  STEPS = (3..5).freeze

  # AND HOW MANY ENDINGS. At least two, because the captain's note of 2026-09-06
  # is that *"multiple endings to a quest must be possible"* and a schema that
  # allowed one would make that a thing only a seed file could have. At most
  # four, for `STEPS`' reason: a fifth ending is a branch nothing in the engine
  # can yet choose between.
  OUTCOMES = (2..4).freeze

  # THE TRIGGERS A GENERATED ARC MAY USE -- the fixed table of four less
  # `time_passed`, which needs a number this schema will not ask for. See the
  # header.
  TRIGGERS = (Quest::TRIGGERS - [ "time_passed" ]).freeze

  string :title,
         description: "What this story's quest is called, as a chronicler would name it. 2 to 5 words, no subtitle.",
         max_length: 80
  string :premise,
         description: "What the quest is, in one sentence, written for the game engine rather than the player.",
         max_length: 400

  array :steps,
        description: "The beats of the quest, in the order they would most naturally happen. " \
                     "Each one names ONE thing the world must eventually contain. Do not describe how the " \
                     "player gets there and do not invent a route between them.",
        min_items: STEPS.first,
        max_items: STEPS.last do
    object do
      string :summary,
             description: "What this beat asks of the player, in one short line. This is the only sentence " \
                          "about the quest the narrator is ever shown, so write it as a thing to do rather " \
                          "than as a thing that happens.",
             max_length: 160
      string :trigger,
             description: "What kind of thing this beat needs. reach_location: the player has to stand " \
                          "somewhere. speak_to: the player has to talk to somebody. hold_item: the player has " \
                          "to be carrying something.",
             enum: TRIGGERS
      string :target,
             description: "The NAME of that place, person or thing, as a player would refer to it. It does " \
                          "not exist yet and you are not creating it -- you are saying what the world must " \
                          "come to contain. A place: 1 to 4 words, no article. A person: their full name. " \
                          "A thing: what somebody would call it picking it up.",
             max_length: 60
      string :teaser,
             description: "One sentence about that place, person or thing -- the glimpse a narrator gives " \
                          "before you walk in, or the one line somebody would say about a person. It is what " \
                          "the world is handed if it has to build the thing itself.",
             max_length: 160
    end
  end

  array :outcomes,
        description: "The ways this quest can end. Exactly one of them is the ending the world is built " \
                     "toward; the rest are other ways it could go.",
        min_items: OUTCOMES.first,
        max_items: OUTCOMES.last do
    object do
      string :name,
             description: "A short label for this ending, lower case, hyphens for spaces. 1 to 3 words.",
             max_length: 40
      string :summary,
             description: "The ending itself, in one sentence, in the past tense -- what the player reads " \
                          "when the story closes on it.",
             max_length: 300
      boolean :is_default,
              description: "True for the ONE ending this world is built toward. False for every other."
    end
  end
end
