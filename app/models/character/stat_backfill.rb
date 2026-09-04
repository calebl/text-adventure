# A BODY FOR EVERYBODY WHO WAS WRITTEN BEFORE THERE WERE BODIES.
#
# `characters.level`, `characters.hit_die` and the three abilities are written
# from now on -- by a seed file, by `Character::Registry` and by
# `Character::Generator`. Every character in a database older than the columns
# has none of them, so `Character#max_hp` is nil for them,
# `Playthrough::Vitals` writes no row, `Character#check` answers nothing, and
# `rake game:doctor` reports every single person in the captain's database as
# `character_without_a_stat_block` and `character_without_abilities`.
# `rake game:backfill_stat_blocks` runs this, and it is one of `bin/update`'s
# steps.
#
# IT FILLS WHAT IS MISSING AND NOTHING ELSE, which matters now that a body is
# five columns rather than two. A row with a hand-authored `hit_die` and no
# abilities gets the three abilities and keeps its die: the roll is derived and
# the records win over a derivation, which is the rule everywhere in this app
# and the reason `EngineSweep::Invariants#stat_blocks_unmoved` can still read a
# seeded world's file back after `bin/update` has run over it.
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
# IDEMPOTENT: its candidates are the rows with any of the five columns empty, so
# a second run has nothing to do. It never re-rolls a column that already holds
# a number, for the same reason `Character::Registry` never moves somebody who
# is already somewhere.
#
# HALF A BLOCK IS A CANDIDATE TOO, on either side of the split.
# `Character#a_stat_block_is_whole` and `#abilities_are_whole` both refuse to
# save one, so such a row can only have arrived through raw SQL or a schema
# older than the validation -- and filling the empty columns is the only way to
# make it whole without inventing a partner for the half that is there.
#
# Offline, deterministic, free: no model call, no network, no key.
class Character::StatBackfill
  # ONE PERSON'S ANSWER. `rolled` is the whole five-column roll, so a dry run
  # can be compared against the real run's exactly; `filled` is the subset this
  # row was actually missing, which is what gets written and what gets printed.
  Answer = Data.define(:character, :rolled, :filled) do
    # THE VALUES THE ROW ENDS ON, which is what a report is about: the roll where
    # this run filled a column and the record where it left one alone.
    def value(column) = filled.fetch(column) { character[column] }

    def level = value(:level)
    def hit_die = value(:hit_die)

    def body? = filled.key?(:level) || filled.key?(:hit_die)
    def abilities? = Character::ABILITIES.any? { |ability| filled.key?(ability) }

    # What the body will be able to hold, which is the number a person reading
    # the report actually cares about. Nil for a row that had a body already and
    # only needed abilities -- there is nothing new to say about its ceiling.
    def max_hp
      return nil if level.nil? || hit_die.nil?

      hit_die + (level - 1) * (hit_die / 2 + 1)
    end

    def to_s = "#{character.fullname}: #{[ body_words, ability_words ].compact.join(", ")}"

    private

    def body_words = body? ? "level #{level}, d#{hit_die} (#{max_hp} hp)" : nil

    def ability_words
      return nil unless abilities?

      Character::ABILITIES.select { |ability| filled.key?(ability) }
                          .map { |ability| "#{ability} #{filled[ability]}" }.join(" ")
    end
  end

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # Returns the `Answer`s, in cast order, for the characters that were missing
  # any of the five columns when it started. Only the empty columns are written:
  # see the header.
  def run(dry_run: false)
    candidates.map do |character|
      rolled = Character::StatBlock.for_existing(character)
      filled = rolled.select { |column, _| character[column].nil? }
      character.update!(**filled) unless dry_run
      Answer.new(character: character, rolled: rolled, filled: filled)
    end
  end

  # Everybody missing any of the five columns -- no stat block, half a stat
  # block, no abilities, or a partial set of them. Ordered by id because that is
  # the order every report in this app prints a cast in, and because the roll is
  # keyed on the id, so the order is stable across runs too.
  #
  # `COLUMNS` is the two plus `Character::ABILITIES`, read off that list rather
  # than named again, so a fourth ability would arrive here by itself.
  COLUMNS = [ :level, :hit_die, *Character::ABILITIES ].freeze

  def candidates
    COLUMNS.map { |column| story.characters.where(column => nil) }
           .reduce { |scope, other| scope.or(other) }
           .order(:id).to_a
  end
end
