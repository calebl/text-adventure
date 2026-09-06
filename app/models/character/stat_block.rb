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

  # WHERE THE PLAYER'S BODY STARTS, and it is the one place a body is not
  # `STARTING_LEVEL`. The captain's call C1 -- level 3 on a d8, 18 hit points --
  # written out of the three checked-in seed files and into the engine so a
  # GENERATED protagonist gets it too. See `.for_a_protagonist`.
  PROTAGONIST_LEVEL = 3
  PROTAGONIST_HIT_DIE = 8

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

  # THE PLAYER'S OWN BODY, AND IT IS NOT THE BODY OF EVERYBODY ELSE. The
  # captain's call C1: *the player is level 3 with a d8*, which is 18 hit
  # points -- the figure every one of the three checked-in worlds writes into
  # its protagonist's `characters[].stats` by hand, and the figure
  # `Item::THROWN_DAMAGE`'s note is measured against ("it is survivable because
  # the seeded protagonists are level 3 on a d8").
  #
  # A GENERATED WORLD DID NOT GET IT, and that is the whole reason this method
  # exists. `rake game:new` builds the protagonist through
  # `Character::Generator`, which rolls `.for_new` like anybody else, so a
  # generated player opened the game as a level-1 body -- and one thrown heavy
  # thing kills one of those 37.3% of the time. A house rule that holds for a
  # world somebody authored and not for a world the task generated is a house
  # rule with a hole in it.
  #
  # THE DRAWS ARE STILL THE DRAWS. The two house numbers are merged OVER a
  # `.for_new` roll rather than replacing it, so the hit die is still drawn in
  # its stated place and the three abilities that follow it are the three
  # abilities this story at this moment would have given anybody -- which is
  # what keeps `Character::ABILITIES`' order load-bearing and the whole block
  # re-derivable. Only `level` and `hit_die` are the house's, and they are not
  # rolled at all: a house rule is a decision, not a die.
  def self.for_a_protagonist(story, sequence: 0)
    for_new(story, sequence: sequence)
      .merge(level: PROTAGONIST_LEVEL, hit_die: PROTAGONIST_HIT_DIE)
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
