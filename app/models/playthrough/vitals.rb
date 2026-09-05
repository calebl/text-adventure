# THE CONDITION OF ONE BODY IN ONE GAME, and the only table in the app that
# holds a number that can change during play.
#
# THE CAPTAIN'S RULING OF 2026-09-04 applied to people. `Item` split into two
# layers -- the world owns the template, the playthrough owns the instance --
# and a stat block falls on both sides of that line without a judgement call
# being needed:
#
#   WHO SOMEBODY IS       `characters.level` and `characters.hit_die`, the WORLD
#                         layer, exactly like `race`, `age` and `sex`. Two
#                         people playing one seeded world meet the same
#                         Sub-Inspector Rowe with the same numbers.
#   HOW MUCH IS LEFT OF   this table, one row per (playthrough, character).
#   THEM                  Playthrough A hurt Rowe; playthrough B did not, and B
#                         must not be able to tell.
#
# MAX HP IS DERIVED AND NEVER STORED (`Character#max_hp`): one number per body,
# not two that can disagree.
#
# AN ABSENT ROW MEANS UNHURT, and that is the honest default rather than a
# shortcut. Almost every person in a world is never touched, so writing a row at
# full health for each of them would be writing "nothing has happened" once per
# NPC per game. `Playthrough#vitals_for` reads the absence as full health, and
# the row is written when the party first stands in front of somebody
# (`Playthrough::Vitals::Snapshot`) or the first time a number changes.
#
# THE WRITERS ARE CLOSED, exactly as the inventory's are. `Playthrough#carried`
# is the one reader and `Playthrough::Turn#carry!` / `#put_down!` the only
# writers; here `Playthrough#vitals_for` is the one reader and
# `Playthrough::Turn#harm!` / `#mend!` the only writers. NO PROSE EVER TOUCHES
# A NUMBER -- there is no narrator tool for damage, and there is not going to be
# one (AGENTS.md -> *The standing constraint*).
#
# ZERO IS DEATH AND DEATH IS TERMINAL. The captain, 2026-09-04: *"zero hit
# points means death. Playthrough is over and you can't do anything else. You
# have to start a new playthrough."* So there is no `dead` column: `hp_current`
# is the whole state and `#dead?` reads it, because two columns that say one
# thing are two columns that can disagree. What death does to the GAME is
# `playthroughs.ended_at`, written in the same statement -- see
# `Playthrough::Turn#harm!`.
class Playthrough::Vitals < ApplicationRecord
  self.table_name = "playthrough_vitals"

  belongs_to :playthrough
  belongs_to :character

  validates :hp_current, presence: true,
                         numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :character_id, uniqueness: { scope: :playthrough_id }
  validate :hp_within_the_stat_block
  validate :character_belongs_to_the_story

  # THIS GAME'S ROW FOR THIS BODY, AT FULL HEALTH IF IT DID NOT EXIST. The one
  # creator of a row in this table, so `Playthrough::Vitals::Snapshot` (first
  # contact) and `Playthrough::Turn#harm!` (the first number that changed)
  # cannot come to disagree about what a fresh body starts on.
  #
  # Nil for somebody with no stat block: there is no maximum to start them at,
  # and inventing one is the thing `characters.level` is nullable to avoid. That
  # state is a `rake game:doctor` finding, not a row.
  def self.instantiate!(playthrough, character)
    return nil if playthrough.nil? || character.nil? || !character.stat_block?

    find_or_create_by!(playthrough: playthrough, character: character) do |row|
      row.hp_current = character.max_hp
    end
  end

  # WHAT A CONSUMER IS TOLD, AND IT EXISTS EVEN WHEN THE ROW DOES NOT.
  #
  # `Playthrough#vitals_for` answers with one of these whether or not anything
  # has happened to the body, which is what lets `Playthrough::Moment`, the
  # `rake game:mechanics` read-out and `EngineSweep::Expectation` all read one
  # shape and never write the "absent row means unhurt" rule out a second time.
  #
  # It is a value and not the record on purpose: the three consumers above only
  # ever READ, and handing them an ActiveRecord object is handing them `update!`.
  Condition = Data.define(:character, :hp, :max) do
    def self.for(character, row)
      new(character: character, hp: row&.hp_current || character.max_hp, max: character.max_hp)
    end

    def dead? = hp <= 0
    def unhurt? = hp >= max

    # HALF GONE OR WORSE. One threshold and not a table of them: the line exists
    # so the narrator can be told something a reader would notice, and a second
    # adjective would be a second thing to keep consistent with prose nobody
    # measures.
    def badly_hurt? = !dead? && hp * 2 <= max

    # For a prompt and for a read-out. The numbers are always printed when
    # anything is wrong, because "hurt" alone is a mood and "4 of 11" is a fact.
    def in_words
      return "dead" if dead?
      return "unhurt" if unhurt?

      "#{badly_hurt? ? "badly hurt" : "hurt"} (#{hp} of #{max})"
    end

    def to_s = "#{character.fullname} is #{in_words}."
  end

  def condition = Condition.for(character, self)

  # WHETHER THIS GAME HAS PICKED A FIGHT WITH THIS BODY. The captain's sixth
  # ruling of 2026-09-05: *"anyone can be attacked"*, and being attacked makes
  # somebody a foe FOR THIS PLAYTHROUGH ONLY -- so the mark is here, on the row
  # that is already this game's copy of a person, and not on
  # `characters.hostile`, which is the world's and which no typed line may write
  # (`EngineSweep::Invariants#hostility_unmoved`).
  #
  # A MOMENT AND NOT A BOOLEAN, for `playthroughs.ended_at`'s reason: when a
  # fight started is worth as much as that it did, and it is STORY time rather
  # than the wall clock (AGENTS.md -> *Story time*).
  def provoked? = provoked_at.present?

  # THE ONE WRITER OF THE MARK, and it is called from exactly one place --
  # `Playthrough::Turn#provoke!`, inside the transaction that writes the first
  # blow. Idempotent: the moment a fight started does not move because a second
  # blow landed, which is `Playthrough#end!`'s rule one table over.
  def provoke!(at)
    return self if provoked?

    update!(provoked_at: at)
    self
  end

  def max = character&.max_hp

  def dead? = hp_current.to_i <= 0

  private

  # A BODY CANNOT HOLD MORE THAN THE TEMPLATE SAYS IT CAN. Skipped when the
  # character has no stat block, because then there is no maximum to compare
  # against -- that row is `vitals_without_a_template` and the doctor reports it
  # rather than this refusing to save it.
  def hp_within_the_stat_block
    ceiling = max
    return if ceiling.nil? || hp_current.nil? || hp_current <= ceiling

    errors.add(:hp_current, "is #{hp_current}, past the #{ceiling} #{character.fullname} can hold")
  end

  # The same statement `Playthrough#character_belongs_to_story` makes: a row
  # pointing into another world would put somebody else's person in this game.
  def character_belongs_to_the_story
    return if character.nil? || playthrough.nil? || playthrough.story_id.nil?
    return if character.story_id == playthrough.story_id

    errors.add(:character, "must belong to the playthrough's story")
  end
end
