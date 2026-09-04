# A BODY FOR EVERYBODY WHO WAS WRITTEN BEFORE THERE WERE BODIES.
#
# `characters.level` and `characters.hit_die` are written from now on -- by a
# seed file, by `Character::Registry` and by `Character::Generator`. Every
# character in a database older than the columns has neither, so
# `Character#max_hp` is nil for them, `Playthrough::Vitals` writes no row, and
# `rake game:doctor` reports every single person in the captain's database as
# `character_without_a_stat_block`. `rake game:backfill_stat_blocks` runs this,
# and it is one of `bin/update`'s steps.
#
# IT IS THE ONE BACKFILL IN THIS APP THAT DOES NOT RECOVER AN ANSWER, AND THAT
# IS WORTH SAYING OUT LOUD. `Character::WhereaboutsBackfill` reads old arrival
# casts, `Scene::TransitionBackfill` reads stored classifier answers,
# `Item::LayerBackfill` reads turn logs -- each of them recovers a fact the
# records already held and REFUSES TO GUESS when they do not hold it. There is
# no such fact here: nothing anywhere on record implies how tough somebody's
# body is.
#
# So this is not a recovery, it is the ENGINE DECIDING, which is precisely what
# the captain ruled it must be: *"A model cannot set an NPC's numbers, the
# engine rolls them."* A hit die is not world lore that a wrong value would
# contradict -- it is a mechanical number whose only author is the engine -- so
# rolling one is the same act as rolling one for a person born five minutes ago
# in a room somebody just walked into, and the alternative is a doctor finding
# on every character in the database for ever with no honest way to clear it.
#
# DETERMINISTIC, AND THAT IS WHAT MAKES A DRY RUN WORTH ANYTHING.
# `Character::StatBlock.for_existing` seeds on `(story_id, character_id)`
# through `Roll` -- plain integer arithmetic, never `String#hash` -- so the
# numbers `DRY_RUN=1` printed are the numbers the real run writes, and running
# it again next year re-derives the same body.
#
# IDEMPOTENT: its candidates are the rows with NO stat block, so a second run
# has nothing to do. It never re-rolls somebody who has one, for the same reason
# `Character::Registry` never moves somebody who is already somewhere -- the
# records win over a derivation everywhere in this app.
#
# HALF A STAT BLOCK IS A CANDIDATE TOO. `Character#a_stat_block_is_whole`
# refuses to save one, so such a row can only have arrived through raw SQL or a
# schema older than the validation, and rolling both columns is the only way to
# make it whole without inventing a partner for the half that is there.
#
# Offline, deterministic, free: no model call, no network, no key.
class Character::StatBackfill
  # ONE PERSON'S ANSWER. `rolled` is the two numbers, so a dry run can print
  # exactly what a real run would write.
  Answer = Data.define(:character, :rolled) do
    def level = rolled[:level]
    def hit_die = rolled[:hit_die]

    # What the body will be able to hold, which is the number a person reading
    # the report actually cares about.
    def max_hp = hit_die + (level - 1) * (hit_die / 2 + 1)

    def to_s = "#{character.fullname}: level #{level}, d#{hit_die} (#{max_hp} hp)"
  end

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # Returns the `Answer`s, in cast order, for the characters that had no whole
  # stat block when it started.
  def run(dry_run: false)
    candidates.map do |character|
      rolled = Character::StatBlock.for_existing(character)
      character.update!(**rolled) unless dry_run
      Answer.new(character: character, rolled: rolled)
    end
  end

  # Everybody with no stat block, or with half of one. Ordered by id because
  # that is the order every report in this app prints a cast in -- and because
  # the roll is keyed on the id, so the order is stable across runs too.
  def candidates
    story.characters.where(level: nil).or(story.characters.where(hit_die: nil)).order(:id).to_a
  end
end
