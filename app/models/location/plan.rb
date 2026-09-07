# WHAT THE ENGINE KNOWS ABOUT THE SHAPE OF ONE ROOM, SAID IN SENTENCES.
#
# THE CAPTAIN'S FIRST RULING OF 2026-09-06 has two halves -- *the whole interior
# is laid out on first entry, and rooms are realized lazily*. `Location::Interior`
# is the first half. This is what the second half is handed: when somebody
# finally walks into one of those rooms and a model is asked to write it, the
# geometry is ALREADY DECIDED, and this is the file that reads it out.
#
#   This room is 6 by 4 paces -- about 9 by 6 metres.
#   It is on storey 0 of The Rusted Anchor, which is 12 by 8 paces across;
#   storey 0 is the ground floor.
#   Its ways out: a door in the north wall, to The Rusted Anchor room 2; a door
#   in the east wall, to The Rusted Anchor room 3; a stair down to The Rusted
#   Anchor room 7, on storey -1, in the south-west of this room.
#
# EVERY ONE OF THOSE IS A RECORD READ OUT. `Playthrough::Moment`'s doctrine
# applied to geometry, and it is the whole reason this class exists rather than
# a paragraph in a prompt: the dimensions are the room's own `Location::Box`,
# the wall a door is in is `Location::Box#wall_towards` on the two boxes a
# `LocationConnection` names, the storey is the box's `z`, and the place is the
# `parent_location`. NOTHING HERE IS ASKED OF A MODEL and nothing here is
# invented -- which is what makes a description that contradicts one of these
# sentences a defect an offline check can catch (`Story::Audit::Prose`'s
# geometry predicates, scored by `Eval::Realization::Scorer`).
#
# ONE BUILDER FOR THE ROOM WRITER AND THE NARRATOR, for `Playthrough::Moment`'s
# own reason: the prompt that WRITES a room and the prompt that narrates a turn
# in it must not come to describe the same walls two ways. `Location::Generator`
# states these facts before the room is written and `Playthrough::Moment` states
# them on every turn afterwards, out of this one file.
#
# AND TWO PROMPTS THAT COULD READ IT DO NOT, which is a decision in each case
# rather than an omission, and the reason is different for each. Named here
# because these four prompts are the whole set: the room writer
# (`Location::Generator`) and the narrator (`Scene::Narrator`, through
# `Playthrough::Moment#narration_context`) carry the plan; the ARRIVAL
# (`Scene::Generator`) and the TALK TURN (`InteractionAgent#narrator_prompt`,
# through `#narrator_moment_section`) do not.
#
#   * THE ARRIVAL builds its own context for the moment of walking in -- the
#     room's name, its description, its lore and its ways out -- and the
#     description it is handed was written against this plan a moment earlier,
#     so the geometry reaches that paragraph through the room rather than twice.
#     What `Playthrough::Moment` covers is every turn AFTER it, where the room's
#     description is one line among many and the player may have been standing
#     here for twenty turns.
#   * THE TALK TURN asks `Playthrough::Moment` for the same block with
#     `plan: false`. It shares a reader with the narrator and would otherwise
#     have gained these sentences by accident, and no prompt in `InteractionAgent`
#     has a stored baseline to judge the change against -- the captain's rule of
#     2026-09-06, and AGENTS.md names `Character#interaction_instructions` among
#     the prompts it binds. Geometry was never asked for in dialogue either.
#
# THE ROOM'S NAME IS THIS PLAN'S CUSTOMER AND NOT ITS OUTPUT. The worked example
# above still reads "The Rusted Anchor room 2" because a room is UNWRITTEN until
# somebody walks in, and a placeholder is what an unwritten room is called
# (`Location::Interior.placeholder_name`). What changed is what happens when
# somebody does: `Location::DetailSchema` now carries an optional `name`, the
# detail prompt asks for one against these very sentences
# (`Location::Generator#name_instruction`), and `Location::RoomName` decides
# whether to take it. So these facts are read out twice -- once to a model
# choosing what to call the room, and once on every turn afterwards to the
# narrator -- and a room named "the counting room" was named against the size,
# the storey and the doors below.
#
# WHERE THE STAIRS ARE IS THE ONE THING THAT NEEDED DERIVING, and it is derived
# from the records rather than invented for the sentence. There is no stairwell
# record (`Location::Box#shares_ground?`): a stair exists only between two rooms
# that stand over each other, so the stairwell can only be in the ground they
# share -- and `Location::Box#bearing_of` names which end of the room that is,
# or says nothing when the shared ground is not plainly in one end. The captain
# asked for *"a stair down in the south-west corner"*; this is the honest half
# of that, and a room whose records do not place the stairwell says only that
# there is one.
#
# A ROOM AND NOT A PLACE, on both halves, which is `Location::Generator#interior_room?`'s
# rule and its reason: a box with no parent is three numbers with nothing to
# measure them against (`Story::Doctor#boxes_with_no_parent`), and a parent with
# no box is plain containment -- a district a street is in -- which nobody laid
# out and whose ways out are still a model's to name. `.for` answers nil for
# everything else, so every caller asks one question and none of them has a nil
# check of its own.
#
# IT SAYS NOTHING ABOUT WHAT IS IN THE ROOM. Items and people are placed within
# a room by a later slice and are `Playthrough::Moment`'s and the registries' to
# state; this is walls, doors and floors, which is the part the engine owns
# outright.
class Location::Plan
  # HOW A WAY OUT IS DESCRIBED WHEN IT IS NOT A DOOR AND NOT A STAIR: an edge to
  # somewhere outside this building, or between two rooms the geometry says
  # share no wall. The second is a fault `Story::Doctor` reports
  # (`door_between_rooms_that_share_no_wall`) and this still has to describe it,
  # because a room's prompt is built from the records a database really carries
  # -- so it is named honestly as a way out with no wall rather than given one.
  WAY_OUT = "a way out".freeze

  # A ROOM, OR NIL. See the header for why both halves are required.
  def self.for(room)
    return nil if room.nil? || !room.placed? || room.parent_location_id.nil?

    new(room)
  end

  attr_reader :room

  def initialize(room)
    @room = room
  end

  def place = room.parent_location

  def box = room.box

  # THE FACTS, ONE PER SENTENCE, in the order a person reads a room: how big it
  # is, where in the building it stands, and what leads out of it. Plain
  # sentences and no headings, so a caller can put them in its own register --
  # `Location::Generator` under a heading of its own and `Playthrough::Moment`
  # beside the lines it already writes.
  def sentences
    [ size_sentence, storey_sentence, ways_out_sentence ].compact
  end

  def to_prompt = sentences.join(" ")

  # THE SAME FACTS AS RECORDS, for a checker rather than a prompt.
  # `Eval::Realization::Bench` stores this beside the answer, and
  # `Eval::Realization::Scorer` reads a description against it -- so the check
  # compares the prose with what the prompt was built from and never with a
  # second derivation of the geometry.
  #
  # THE PLACE'S FOOTPRINT IS HERE BECAUSE `#storey_sentence` STATES IT, and
  # every number that reaches a model has to reach the checker too. Prose that
  # says "fourteen by ten paces" of a room inside a fourteen-by-ten building is
  # repeating a fact it was handed, and a checker that only had the ROOM's box
  # would report that as a defect (`Eval::Realization::Scorer#judge_size_the_records_do_not_hold`).
  # Nil for a place with no extent, which is what `#footprint_clause` leaves
  # unsaid.
  def to_h
    { "room" => room.name, "place" => place.name, "storey" => box.z,
      "place_width" => place.width, "place_depth" => place.depth,
      "width" => box.width, "depth" => box.depth,
      "doors" => doors.map { |way| { "wall" => way.wall, "to" => way.to.name } },
      "stairs" => stairs.map { |way| { "to" => way.to.name, "up" => way.up?, "storey" => way.storey,
                                       "bearing" => way.bearing } },
      "other_ways_out" => others.map { |way| way.to.name } }
  end

  # ONE WAY OUT OF THIS ROOM, as the records have it: the room on the far side,
  # and whatever the two boxes say about where the way out stands. `wall` is nil
  # for anything that is not a door in a wall of this room, and `storey` is nil
  # for anything that does not change storey -- so which of the three kinds a
  # way out is, is a question about the records rather than a label somebody
  # attached.
  Way = Data.define(:to, :wall, :storey, :bearing, :from_storey) do
    def door? = !wall.nil?
    def stair? = !storey.nil?
    def up? = stair? && storey > from_storey
  end

  def doors = ways_out.select(&:door?)
  def stairs = ways_out.select(&:stair?)
  def others = ways_out.reject { |way| way.door? || way.stair? }

  # EVERY WAY OUT, IN ONE ORDER, and the order is the walls of a compass and
  # then the name -- so two readings of one room list its doors the same way,
  # whatever order the rows were written in. The stairs follow the doors and the
  # edges that are neither follow those, which is the order the sentence reads
  # in.
  def ways_out
    @ways_out ||= begin
      ways = LocationConnection.from_location(room).includes(:connected_location)
                               .map { |edge| way_for(edge.connected_location) }
      ways.sort_by { |way| [ Location::Box::WALLS.index(way.wall) || Location::Box::WALLS.size,
                             way.stair? ? 0 : 1, way.to.name.to_s ] }
    end
  end

  private

  def size_sentence
    wide, deep = box.metres

    "This room is #{box.width} by #{box.depth} paces -- about #{wide} by #{deep} metres."
  end

  # WHERE IN THE BUILDING IT STANDS, and the frame the number is read in said
  # out loud. A storey index is not a height (`Location::Box`) and it is read in
  # the PARENT's plane, so "storey 0 is the ground floor" is the sentence that
  # stops a reader taking `z` for a height in metres or for a floor of the
  # world.
  # AND THE PLACE'S FOOTPRINT ONLY WHERE THE RECORDS HOLD ONE.
  # `Story::Doctor#boxes_with_no_parent_footprint` exists because a stored
  # database can carry a placed room whose parent has no extent, and this class
  # describes the records a database really has rather than inventing around
  # them -- so the clause goes, the way `#stair_clause` drops the bearing when
  # the records do not place the stairwell. "which is by paces across" is not a
  # sentence to put in a live prompt.
  def storey_sentence
    "It is on storey #{box.z} of #{place.name}#{footprint_clause}; storey 0 is the ground floor."
  end

  def footprint_clause
    return "" unless place.interior?

    ", which is #{place.width} by #{place.depth} paces across"
  end

  # WHAT LEADS OUT, AND WHERE EACH ONE IS. The closing sentence is the closed
  # set stated as a fact, which is the cheap half of the standing constraint --
  # the same thing `Playthrough::Moment` does with "There are no others."
  #
  # A ROOM WITH NO WAY OUT SAYS SO. `Location::Interior` leaves the single room
  # of a one-room interior with none until slice 4 wires the way in, and a room
  # the prompt said nothing about is a room the prose is free to invent a door
  # for.
  def ways_out_sentence
    return "Nothing leads out of this room yet." if ways_out.empty?

    "Its ways out: #{ways_out.map { |way| clause_for(way) }.join("; ")}. " \
      "Those are every way out of this room#{closed_walls_clause}."
  end

  # THE CLOSED SET IS A RECORD; THE CLOSED WALLS ARE NOT ALWAYS ONE. Which rows
  # lead out of this room is exactly what `LocationConnection` holds, so the
  # first half of that sentence is always true. "No other wall of it holds a
  # door" is a second and stronger claim, and a room with a way out the records
  # give no wall to is precisely the room where it is FALSE: `WAY_OUT` is the
  # doorway INTO the building (`#clause_for`), which physically passes through a
  # wall -- the records simply do not say which, because the far side stands in
  # another plane (`#way_for`). The Custom House's entry room is the worked
  # example: its own outer wall carries the quay door, and claiming otherwise
  # would leave the model no truthful way to describe the way in.
  #
  # SO THE CLAIM IS MADE ONLY WHERE THE RECORDS CARRY IT -- a room whose every
  # way out is a door in a named wall or a stair.
  #
  # AND THIS SENTENCE IS WHY NOTHING CHECKS THE WALLS AFTERWARDS. Telling the
  # model no other wall holds a door invites prose that names the DOORLESS walls
  # beside the doors, and six measured grammars each read one of those as a door
  # claim of its own -- see `Story::Audit`'s header for the record and
  # `Eval::Realization::UNAVAILABLE_TO_A_REALIZATION` for the question, reported
  # unanswered. The sentence stays: it is a record, and informing the prose is
  # the half of the standing constraint that does not depend on being verifiable.
  def closed_walls_clause
    return "" if others.any?

    ", and no other wall of it holds a door"
  end

  def clause_for(way)
    return "a door in the #{way.wall} wall, to #{way.to.name}" if way.door?
    return stair_clause(way) if way.stair?

    "#{WAY_OUT} to #{way.to.name}#{", which is outside #{place.name}" unless way.to.parent_location_id == place.id}"
  end

  def stair_clause(way)
    "a stair #{way.up? ? "up" : "down"} to #{way.to.name}, on storey #{way.storey}" \
      "#{", in the #{way.bearing} of this room" if way.bearing}"
  end

  # ONE FAR END, READ AS GEOMETRY. Only a SIBLING is read that way -- a room in
  # this same place -- because coordinates are local to a parent
  # (`Location::Box`) and the box of a room in another building is measured in
  # another plane. Everything else is a way out with no wall, which is what the
  # way INTO a building is.
  #
  # THE STOREY DECIDES WHETHER IT IS A STAIR, AND NOT THE `travel_method`. The
  # label on an edge is direction-neutral and is written by whatever wrote the
  # row, while a stair is an edge between two PLANES (`Location::Box`'s ruling
  # 3) -- so the boxes are what say which this is, and a mislabelled row is
  # described by where it actually goes.
  def way_for(other)
    return Way.new(to: other, wall: nil, storey: nil, bearing: nil, from_storey: box.z) unless sibling?(other)

    far = other.box
    return Way.new(to: other, wall: box.wall_towards(far), storey: nil, bearing: nil,
                   from_storey: box.z) if far.z == box.z

    ground = box.shared_ground(far)
    Way.new(to: other, wall: nil, storey: far.z, bearing: ground && box.bearing_of(ground), from_storey: box.z)
  end

  def sibling?(other) = other.parent_location_id == room.parent_location_id && other.placed?
end
