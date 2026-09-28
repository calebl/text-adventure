# A ROOM ONE GAME HAS STOOD IN, and the record `Story::Doctor` asks when it
# judges whether a game can have met somebody.
#
# WHY IT EXISTS. The scene chain was the only record of where a game had been,
# and a move with no model writes no `Scene`: `Playthrough::Mechanics#stand_in`
# stands the party in the room, snapshots it and writes nothing prose-shaped
# (the Rust engine's offline turn does the same). So `rake game:mechanics
# NO_MODEL=1` and every offline walk stood in rooms nothing recorded, and the
# doctor read each condition row written at first contact there as a row for
# a stranger -- a `safe` finding, so a repair run afterwards deleted it.
#
# TAKEN WHERE A STAND IS TAKEN. `Playthrough::Snapshot#of_the_room!` is the one
# seam every Ruby path stands a party in a room through, so the visit is
# written there beside the room's things and people. The Rust engine takes its
# own snapshot and knows nothing of this table, so `Playthrough::RustEngine`
# takes the visit after every line it hands the engine, from the room the
# engine left the party in.
#
# IDEMPOTENT BY THE UNIQUE INDEX, as `Playthrough::Vitals.instantiate!` is: a
# room is stood in by one game once, however often it is walked back into.
#
# NO MODEL, NO NETWORK. Nothing a model reads is built from it.
class Playthrough::Visit < ApplicationRecord
  self.table_name = "playthrough_visits"

  belongs_to :playthrough
  belongs_to :location

  validates :location_id, uniqueness: { scope: :playthrough_id }
  validate :location_belongs_to_the_story

  # THIS GAME HAS STOOD IN THIS ROOM. Nil is a no-op: a playthrough standing
  # nowhere has stood nowhere.
  def self.record!(playthrough, location)
    return nil if playthrough.nil? || location.nil?

    find_or_create_by!(playthrough: playthrough, location: location)
  end

  private

  def location_belongs_to_the_story
    return if playthrough.nil? || location.nil? || location.story_id == playthrough.story_id

    errors.add(:location, "must belong to the playthrough's story")
  end
end
