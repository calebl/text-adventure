# WHERE A STAT BLOCK COMES FROM, and the only place in the app that decides one.
#
# THE CAPTAIN'S RULING, 2026-09-04: *"A model cannot set an NPC's numbers, the
# engine rolls them."* So there is no field for a stat on any schema, nothing in
# any prompt asks for one, and every number on `characters.level`,
# `characters.hit_die` and the three abilities that the app itself wrote came
# through here. The evening's ruling -- *"let's go with the 3 abilities"* --
# widened what a body is; it did not move who decides it.
#
# It is `Character::Registry`'s rule about race, age and sex taken one step
# further. Those are rolled by the engine and STATED in the realization prompt
# before the model answers, because *"asking for a value the prompt just
# supplied is a decision bought twice"*. A stat block is not even stated: the
# prose has no use for a hit die, and `Playthrough::Moment` tells the narrator
# how much is LEFT of the player rather than what they are made of.
#
# TWO ENTRY POINTS, and the difference between them is which roll this is.
# Every seed is plain arithmetic over integers (`Roll`, and read its header for
# why `String#hash` is not one of them), so the answer is the same in any
# process for ever -- which is what lets `rake game:backfill_stat_blocks`
# rehearse under `DRY_RUN=1` and then write exactly the numbers it printed.
#
#   `.for_existing`  a row that is already in the database, keyed on its own id.
#                    The backfill and `Story::Repair` both use it, so the number
#                    a dry run showed is the number the real run writes, and a
#                    repair re-run a week later re-derives the same body.
#   `.for_new`       somebody about to be created, keyed on where the story's
#                    clock stands and which of this call's slots they are. There
#                    is no id yet, and inventing a placeholder to key on would
#                    be pretending this roll is re-derivable when it is not: it
#                    happens once and the row keeps it.
#
# WHAT IT DOES *NOT* ROLL: the level. Every body starts at 1 because levels are
# stored and inert and nothing advances them (`Character#advance!`), so a rolled
# level would be a number with no rule behind it -- decoration, and decoration
# on a column the doctor reports about.
#
# THE ORDER OF THE DRAWS IS PART OF THE ANSWER, and this is the one thing in
# this file that must not be tidied. `Roll.generator` is handed around rather
# than kept precisely so that a caller throwing several dice for one decision
# throws them from ONE seed in ONE order (`Roll`'s header): the hit die first,
# then strength, then dexterity, then will, which is `Character::ABILITIES` in
# its stated order. Four draws in a fixed order are re-derivable for ever --
# which is what lets `DRY_RUN=1` print the numbers the real run writes and lets
# `rake game:sweep` assert a check outcome. Four draws in a set are not.
module Character::StatBlock
  # WHERE A BODY STARTS. One, and it is not a roll: see the header.
  STARTING_LEVEL = 1

  # 3d6 PER ABILITY, which is the roll an ability score has always been and the
  # roll `Character::ABILITY_RANGE` (3..18) is the bounds of.
  ABILITY_DICE = 3
  ABILITY_SIDES = 6

  # `{ level:, hit_die:, strength:, dexterity:, will: }`, ready to assign. A
  # Hash rather than a value object because every caller does exactly one thing
  # with it -- `assign_attributes` -- and the keys are the column names.
  def self.for_existing(character)
    roll(story: character.story_id, sequence: character.id)
  end

  def self.for_new(story, sequence: 0)
    roll(story: story.id, at: story.clock.to_i, sequence: sequence)
  end

  # ONE GENERATOR, AND THE DRAWS IN THE ORDER THE HEADER STATES. `Character::ABILITIES`
  # is iterated rather than the three columns being named again, so the list and
  # the roll cannot drift -- and because that list's order IS this roll's order.
  def self.roll(story:, at: 0, sequence: 0)
    rng = Roll.generator(story: story, at: at, sequence: sequence)

    { level: STARTING_LEVEL, hit_die: Roll.one_of(Character::HIT_DICE, rng: rng) }
      .merge(Character::ABILITIES.to_h { |ability| [ ability, Roll.pool(ABILITY_DICE, ABILITY_SIDES, rng: rng) ] })
  end
end
