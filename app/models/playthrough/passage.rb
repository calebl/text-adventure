# A doorway opened in one game. The connection keeps the world's initial
# barrier; an absent passage row means that barrier is still in place here.
# Opening does not edit geography or another game's door. Both directed rows
# for the same doorway are opened together, so walking back cannot relock it.
class Playthrough::Passage < ApplicationRecord
  self.table_name = "playthrough_passages"

  MEANS = %w[key lockpick lever force].freeze

  belongs_to :playthrough
  belongs_to :location_connection
  belongs_to :opened_by_item, class_name: "Item", optional: true

  validates :means, inclusion: { in: MEANS }
  validates :opened_at, presence: true
  validates :location_connection_id, uniqueness: { scope: :playthrough_id }
  validate :belongs_to_this_game

  def self.open!(playthrough, connection, means:, item: nil)
    transaction do
      reverse = LocationConnection.find_by(location: connection.connected_location, connected_location: connection.location)
      [ connection, reverse ].compact.map do |edge|
        find_or_create_by!(playthrough: playthrough, location_connection: edge) do |row|
          row.opened_at = playthrough.story_now
          row.means = means
          row.opened_by_item = item
        end
      end
    end
  end

  private

  def belongs_to_this_game
    return unless playthrough && location_connection

    unless location_connection.location.story_id == playthrough.story_id &&
           location_connection.connected_location.story_id == playthrough.story_id
      errors.add(:location_connection, "must belong to this game's world")
    end
    if opened_by_item && opened_by_item.playthrough_id != playthrough_id
      errors.add(:opened_by_item, "must belong to this game")
    end
  end
end
