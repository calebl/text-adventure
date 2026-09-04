# WHERE A STAT BLOCK COMES FROM, and the only place in the app that decides one.
#
# THE CAPTAIN'S RULING, 2026-09-04: *"A model cannot set an NPC's numbers, the
# engine rolls them."* So there is no field for a stat on any schema, nothing in
# any prompt asks for one, and every number on `characters.level` /
# `characters.hit_die` that the app itself wrote came through here.
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
# stored and inert in this PR and nothing advances them (`Character#advance!`),
# so a rolled level would be a number with no rule behind it -- decoration, and
# decoration on a column the doctor reports about.
module Character::StatBlock
  # WHERE A BODY STARTS. One, and it is not a roll: see the header.
  STARTING_LEVEL = 1

  # `{ level:, hit_die: }`, ready to assign. A Hash rather than a value object
  # because every caller does exactly one thing with it -- `assign_attributes`
  # -- and the two keys are the column names.
  def self.for_existing(character)
    roll(story: character.story_id, sequence: character.id)
  end

  def self.for_new(story, sequence: 0)
    roll(story: story.id, at: story.clock.to_i, sequence: sequence)
  end

  def self.roll(story:, at: 0, sequence: 0)
    rng = Roll.generator(story: story, at: at, sequence: sequence)

    { level: STARTING_LEVEL, hit_die: Roll.one_of(Character::HIT_DICE, rng: rng) }
  end
end
