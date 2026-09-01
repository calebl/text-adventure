# One exchange with one character: what they thought and felt on either side of
# answering, what they did, and what they decided as a result.
#
# IT IS ALSO THE MEMORY OF A CONVERSATION. The verbatim exchange lives in a
# `Chat` and is trimmed to a couple of turns so replaying it cannot outgrow the
# context window (Chat#prune_history!); these rows are what is kept forever, one
# per exchange, in full. So a character's chat holds the recent words and their
# interactions hold everything that was ever decided.
class Interaction < ApplicationRecord
  belongs_to :character
  belongs_to :scene, optional: true
  belongs_to :location, optional: true

  validates :pre_thought, presence: true
  validates :pre_feeling, presence: true
  validates :action, presence: true
  validates :post_feeling, presence: true
  validates :post_thought, presence: true

  # DERIVED, not asked for. The exchange's one-line memory is already implied by
  # the fields that were paid for -- what was said to them, what they did about
  # it, what they decided -- so composing it costs nothing where a seventh schema
  # field or a second call would cost tokens on every line of dialogue. A caller
  # that supplies its own is left alone.
  before_validation :compose_summary, on: :create

  scope :chronological, -> { order(:created_at) }
  scope :for_character, ->(character) { where(character: character) }

  # An exchange is finished when the character has decided something about it.
  # `inner_resolution` is the sixth field of `Interaction::Schema`, written by
  # the same call that writes the other five.
  def completed?
    inner_resolution.present?
  end

  def character_name
    character.fullname
  end

  private

  def compose_summary
    return if summary.present?

    said = user_input.presence && %(the player said "#{user_input.to_s.truncate(80)}")
    self.summary = [ said, action.presence, inner_resolution.presence ].compact.join(" -- ").presence
  end
end
