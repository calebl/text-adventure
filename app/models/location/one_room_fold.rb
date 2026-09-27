# A PLACE THAT WAS SPLIT AROUND ONE ROOM, AND PUTTING IT BACK TOGETHER.
#
# THE SHAPE. Before `Location::Parameters::ONE_ROOM` meant "the named place is
# the room", an exits answer that picked `inside: one room` gave the stub a
# footprint. The first entry then laid it out as a building of exactly one room
# that filled the whole of it, provisionally named "<place> room 1", moved the
# doorway onto that room and stood the party there. `Location::RoomName` refused
# the model's name for the room -- correctly, because the one name it should
# have had is the place's -- so the placeholder stayed, and the player who chose
# "Core Access Chamber" is standing in "Core Access Chamber room 1". New worlds
# no longer grow the shape; this is for the rows already written.
#
# THE SURVIVOR IS THE PLACE ROW, chosen deliberately:
#
#   its NAME is the one the player typed and the exits answer wrote;
#   its ID is the one a quest step bound at birth (`Quest::Binder` runs in
#     `Location::Generator.create_stub!`), the one a command journal resolved
#     the move to, and -- being the older row -- the one `Story#opening_location`
#     would pick if it ever came first;
#
# and the room's CONTENT goes onto it, because the room is what was played: its
# description is the prose the player read, and its scenes, things, people and
# doorway are where the game happened. So every reference to the room is moved
# onto the place, the place takes the room's description, lore and conditions,
# the footprint and the room's box and positions are cleared -- a room with no
# extent has no plane for a position to be read in -- and the room row is
# removed with nothing left pointing at it.
#
# NOT `Story::Repair#fold_location_into`. That fold assumes the row it removes
# has no play history, so it moves no scenes, no playthrough's current location
# and no per-game NPC location. Here the removed row carries all of the history.
#
# ONLY THE EXACT SHAPE IS FOLDED, and the proof is narrow on purpose: a place
# with exactly one child; the child still carries this place's placeholder name;
# the child's box is the whole footprint at the origin; every doorway onto the
# pair lands on the child and none on the place; nobody has stood in, left
# anything in, or put anybody in the place itself; the room was realized; and no
# checked-in world file speaks for either name. Anything short of that is left
# alone and reported by `Story::Doctor` (`one_room_place_left_split`), because a
# guess here moves somebody's game onto the wrong row and cannot be taken back.
#
# NO MODEL CALL, and nothing is invented: every value written is already on one
# of the two rows.
class Location::OneRoomFold
  # EVERY ROW THAT CAN NAME A LOCATION, as [model, column]. Moved from the room
  # to the place in one pass. A column added to the schema that references a
  # location belongs here too; `Location::OneRoomFoldTest` walks the schema's
  # foreign keys and fails if one is missing.
  REFERENCES = [
    [ Scene, :location_id ],
    [ Item, :location_id ],
    [ Character, :location_id ],
    [ Interaction, :location_id ],
    [ Playthrough, :current_location_id ],
    [ Playthrough::NpcState, :location_id ],
    [ Playthrough::Blow, :location_id ],
    [ Playthrough::Drift, :location_id ],
    [ Playthrough::Overreach, :location_id ],
    [ Playthrough::Toll, :location_id ],
    [ Playthrough::Volition::Record, :location_id ],
    [ LocationConnection, :location_id ],
    [ LocationConnection, :connected_location_id ]
  ].freeze

  # What somebody may have put IN the place row itself. Any of it makes the
  # pair two rooms with two histories, which is not this shape.
  PLACE_HISTORY = [
    [ Scene, :location_id ],
    [ Item, :location_id ],
    [ Character, :location_id ],
    [ Playthrough, :current_location_id ],
    [ Playthrough::NpcState, :location_id ],
    [ Playthrough::Blow, :location_id ],
    [ Playthrough::Toll, :location_id ],
    [ Playthrough::Volition::Record, :location_id ]
  ].freeze

  # What the place takes from the room, because it is what the player read and
  # what the room's cast and hazards were rolled against.
  CONTENT = %i[description lore danger hazard hazard_die population last_protagonist_visit generation_checkpoint].freeze

  class NotProven < StandardError; end

  # Every place in the story with exactly one child carrying its placeholder
  # name -- the candidates, proven or not. A single child with a name of its own
  # is somebody's deliberate floor plan and is not a candidate at all.
  def self.candidates(story)
    single = story.locations.where.not(parent_location_id: nil)
                  .group(:parent_location_id).having("COUNT(*) = 1").pluck(:parent_location_id)
    story.locations.where(id: single).order(:id).filter_map do |place|
      room = place.child_locations.first
      new(place, room) if Location::Interior.placeholder_name?(place, room.name)
    end
  end

  attr_reader :place, :room

  def initialize(place, room)
    @place = place
    @room = room
  end

  def proven? = reasons.empty?

  # WHY THIS PAIR IS NOT THE EXACT SHAPE, one clause each; empty when it is.
  def reasons
    @reasons ||= [
      ("#{place.name} carries no footprint of its own" unless place.place?),
      ("#{room.name} does not fill the whole of #{place.name}" unless fills_the_place?),
      ("#{room.name} has rooms inside it" if room.child_locations.exists?),
      ("#{room.name} was never written out" unless room.realized?),
      ("a doorway lands on #{place.name} itself" if doorway_on_the_place?),
      ("#{place.name} has play history of its own" if place_has_history?),
      ("a checked-in world file names #{place.name} or #{room.name}" if seeded?)
    ].compact
  end

  # Folds the room into the place, in one transaction. Re-proves the shape on
  # fresh rows first, so two runs racing, or a row that changed since the
  # candidate was read, fold nothing rather than something wrong.
  def fold!
    Location.transaction do
      @place = Location.lock.find(place.id)
      @room = Location.lock.find(room.id)
      @reasons = nil
      raise NotProven, "#{place.name}: #{reasons.join("; ")}" unless proven?

      move_references!
      clear_positions!
      move_world_events!
      Quest::Step.where(target_type: "Location", target_id: room.id).update_all(target_id: place.id)

      content = CONTENT.index_with { |column| room[column] }
      room.reload.destroy!
      place.update!(**content, width: nil, depth: nil)
    end
    place
  end

  private

  def fills_the_place?
    [ room.x, room.y, room.z, room.width, room.depth ] == [ 0, 0, 0, place.width, place.depth ]
  end

  def doorway_on_the_place?
    LocationConnection.where(location_id: place.id).or(LocationConnection.where(connected_location_id: place.id)).exists?
  end

  def place_has_history?
    PLACE_HISTORY.any? { |model, column| model.where(column => place.id).exists? }
  end

  def seeded?
    document = WorldSeed.checked_in_document(place.story.title)
    return false unless document

    keys = Array(document["locations"]).map { |row| WorldSeed.natural_key(row["name"]) }
    keys.include?(WorldSeed.natural_key(place.name)) || keys.include?(WorldSeed.natural_key(room.name))
  end

  def move_references!
    REFERENCES.each { |model, column| model.where(column => room.id).update_all(column => place.id) }
  end

  # A POSITION IS READ IN THE ROOM'S BOX (`Location::Spot`), and the place that
  # survives has none, so a thing or a person carried over keeps its room and
  # loses its corner -- unplaced, which is the ordinary state of every row in a
  # room with no box.
  def clear_positions!
    [ Item, Character ].each { |model| model.where(location_id: place.id).update_all(x: nil, y: nil) }
  end

  # The join table has no model, and a (world event, location) pair is unique,
  # so a link the place already has is dropped rather than duplicated.
  def move_world_events!
    connection = Location.connection
    connection.execute(Location.sanitize_sql_array([ <<~SQL.squish, room.id, place.id ]))
      DELETE FROM locations_world_events
      WHERE location_id = ?
        AND world_event_id IN (SELECT world_event_id FROM locations_world_events WHERE location_id = ?)
    SQL
    connection.execute(Location.sanitize_sql_array([ "UPDATE locations_world_events SET location_id = ? WHERE location_id = ?",
                                                     place.id, room.id ]))
  end
end
