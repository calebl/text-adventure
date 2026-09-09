# What one NPC has agreed to do in one game. The world keeps the character's
# original location and hostility; this row overrides them only for its own
# playthrough. An absent row means the world's initial state, so no backfill is
# needed when an existing game gains this capability.
#
# A ceasefire covers the blows already exchanged, never a future attack. The
# highest player blow ID is its boundary: hitting the character again breaks
# the agreement even if the old provoked_at stamp has not changed.
class Playthrough::NpcState < ApplicationRecord
  self.table_name = "playthrough_npc_states"

  belongs_to :playthrough
  belongs_to :character
  belongs_to :location, optional: true

  validates :character_id, uniqueness: { scope: :playthrough_id }
  validates :peace_after_blow_id, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :same_story

  def ceasefire_holds?
    ceasefire? && !playthrough.blows.where(attacker: playthrough.character, target: character)
                             .where("id > ?", peace_after_blow_id).exists?
  end

  def make_peace!
    update!(ceasefire: true,
            peace_after_blow_id: playthrough.blows.where(attacker: playthrough.character, target: character).maximum(:id).to_i)
  end

  private

  def same_story
    return unless playthrough

    errors.add(:character, "must belong to this story") if character && character.story_id != playthrough.story_id
    errors.add(:location, "must belong to this story") if location && location.story_id != playthrough.story_id
    errors.add(:character, "must be an NPC") if character && (character == playthrough.character || character.is_protagonist?)
  end
end
