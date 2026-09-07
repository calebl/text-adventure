# THE INSIDE OF A PLACE, LAID OUT IN ONE GO AND WITHOUT ASKING ANYBODY.
#
# THE CAPTAIN'S FIRST RULING OF 2026-09-06: *the whole interior is laid out on
# first entry, and rooms are realized lazily.* This file is the first half of
# that sentence. The geometry of every room and every door is decided in one
# call, from one seeded `Roll`, with NO MODEL INVOLVED AT ALL -- so connectivity
# is a guarantee rather than a hope. The second half is unchanged and is not
# here: a room is still a stub until somebody walks into it, and the prose is
# still written one room at a time, against the plan this file laid down
# (`Location::Plan`).
#
# WHY NO MODEL. The standing constraint -- *nothing may depend on the narrator
# obeying its prompt* -- reads on a floor plan more strongly than it reads
# anywhere else, because a map is not prose that can be a little wrong. A model
# asked for eight rooms and their doors gives back rooms in the same place at
# once, doors to rooms it did not write, and a top floor nothing reaches, and no
# amount of prompting makes any of those impossible. Integers and a spanning
# path make all three impossible. So the model is never asked, and what it IS
# told, when the room it is writing is one of these, is what the engine already
# decided -- `Location::Plan` reads this layout out to it.
#
# WHAT IT WRITES: child `Location` rows carrying a BOX, and `LocationConnection`
# rows in BOTH directions -- a door is two rows, the ruling of 2026-09-03. It
# writes NO name that means anything, NO description, NO lore, NO items and NO
# people. A room comes out of here exactly as a stub comes out of
# `Location::Generator#create_stub!`, because it comes out THROUGH it: one path
# a room is born by, one place its `danger` is rolled.
#
# --- the two guarantees, and how each one is bought ------------------------
#
# EVERY ROOM IS REACHABLE FROM THE ENTRY. Not asserted afterwards -- built. A
# storey is a GRID of rooms, and the doors of its backbone follow a SERPENTINE
# path through that grid: along one row, back along the next, and so on. A
# serpentine visits every cell of any grid and only ever steps between
# neighbours, so it is a spanning path that EXISTS for every grid this file can
# roll, rather than a search that can fail on one. Storeys are then bound
# together by stairs. `#close_connectivity!` re-reads the records afterwards and
# joins anything left stranded; on a layout this file built it finds nothing to
# do, and it is there because "connected" has to be a property of the ROWS at
# the end and not of an argument about the code.
#
# NO ROOM LEADS MORE WAYS OUT THAN `Location::ExitsSchema::MAX_EXITS`. That cap
# is a cap on the ROOM and not on one answer, and `EngineSweep::Invariants#exit_cap`
# fails a walk that breaks it, so a layout that ignored it would be a layout
# that fails the sweep. The budget is spent in a fixed order and never
# overdrawn: the backbone first (a serpentine gives a room two doors at most),
# then the stairs, then whatever extra doors are left over. THE ENTRY ROOM KEEPS
# ONE SLOT FREE, because the way IN to a place has to attach to a room one day
# and a room at its cap has nowhere to attach it -- that is slice 4's problem
# and this is what stops this file creating it.
#
# --- which storeys there are, and which way is down -------------------------
#
# AN INTERIOR MAY DESCEND. A place is laid out on storeys `-BASEMENTS` through
# `STOREYS - 1`, so a warren cut downward out of a tunnel and an inn with a
# cellar are both things the records can now SAY -- which they could not before,
# because this file numbered storeys upward from 0 and every deep floor came out
# ABOVE the way in. `Location::Plan` could already read a negative storey (its
# header's worked example is a stair down to storey -1) and `Story::Map` already
# draws its storeys highest first; what was missing was a layout that wrote one.
#
# THE ENTRY ROOM IS ON STOREY 0 WHATEVER ELSE THE PLACE HAS. The way in is the
# first room written and `.entry_room` reads it back as the lowest id, so the
# ground floor is built FIRST and the basements last -- `#storey_order` is where
# that is said and why. A cellar is somewhere you go DOWN to from the way in,
# which is the whole of what a cellar is.
#
# AND A STAIR JOINS TWO ADJACENT STOREYS IN BOTH DIRECTIONS ALREADY, because a
# door is two rows (the ruling of 2026-09-03) and a stair is a door: the row
# from the cellar to the hall and the row from the hall to the cellar are one
# edge said twice, and which of them is "down" is read off the two boxes rather
# than off a label (`Location::Plan#way_for`). So nothing here writes a
# direction and nothing downstream has to trust one.
#
# AND WHAT SUPPLIES THE COUNT IS A PICK. `Location::Parameters` is the closed
# vocabulary a model chooses a building out of -- how far up, how far down, how
# dangerous, which way that runs, and what standing in it does to you -- and this
# file is what CONSUMES it. The captain's Call 7 of 2026-09-06 and his Call 2 of
# 2026-09-07: the picks arrive on the detail call at first entry and are spent
# here, in the same transaction as the flip to `realized`, and not one of them
# gets a column. The ROWS are the record: how many storeys is the min and max `z`
# of the children, the gradient IS each room's own danger, and how warren-like it
# is is the door count.
#
# `parameters:` NIL AND `Location::Parameters.none` ARE DIFFERENT STATES AND MUST
# NOT BE COLLAPSED. Nil is a caller that ASKED NOBODY -- a seed file's building
# drawn by hand, a test, the engine's own fallback -- and every draw is the
# engine's exactly as it was before this slice, which is what keeps a world
# already exported re-derivable. A `Location::Parameters` is a caller that ASKED
# and got an answer, defaults included: the storeys come off the picks rather
# than off `STOREYS` and `BASEMENTS`, each room's danger is rolled from the
# building's own weighted list, and a hazardous building rolls its hazard per
# room. Re-deriving a nil-laid-out world under a parameters object would come out
# a different building.
#
# SO `BASEMENTS` STAYS ZERO-WEIGHTED, and that is not a leftover. It is what a
# place laid out by a caller with no picks gets, and every world in the
# repository was written by one.
#
# --- the shape of a storey --------------------------------------------------
#
# A GRID, AND NOT A BINARY SPACE PARTITION, which is the alternative that was
# rejected. A BSP is the better-known dungeon shape and gives prettier rooms,
# but a BSP leaf can touch six neighbours, so its spanning tree has to be
# searched for under a degree cap and the search can fail -- and the failure is
# a building whose top floor cannot be reached. A grid cell touches four
# neighbours at most and a serpentine through it always exists. The rooms are
# still not uniform: the column widths and row depths are rolled independently,
# so a storey is a grid of DIFFERENT rooms rather than a chessboard.
#
# THE ROOMS TILE THE FOOTPRINT EXACTLY. There are no corridors and no gaps, and
# that is a decision rather than an omission: a gap between two rooms is a
# region of the plane nothing owns, which every reader downstream would have to
# have an opinion about -- what is in it, whether you can stand in it, what
# happens when a description mentions it. Rooms that share walls have none of
# those questions, and a corridor is a room.
#
# --- what a world supplies and what this file supplies ----------------------
#
# `WorldMechanic`'s contract, applied to a floor plan: A WORLD SUPPLIES
# PARAMETERS, NEVER BEHAVIOUR. The parameter a world supplies is the FOOTPRINT
# -- how big this place is -- which a seed file may write today and whatever
# decides that a generated stub is a place will write tomorrow. Everything
# derived from it is the engine's and lives in the constants below: how many
# storeys, how many rooms fit on one, how small a room may be, how a door's
# distance follows from the geometry. A world that says "twelve by eight" is
# saying how big the inn is; it is not saying how the inn is divided up, because
# that is behaviour and behaviour is in Ruby where it can be read.
#
# A PLACE WITH NO FOOTPRINT GETS ONE ROLLED, from `FOOTPRINT_SIDES` -- and that
# is the policy for a caller that does not exist yet. It is for whatever decides
# that a GENERATED stub becomes a place: such a stub carries no extent at the
# moment that decision is made (`Location::Generator.create_stub!` writes none),
# so the branch has to be here before its caller is, or the decision would come
# down to whether somebody remembered a width.
#
# AND REFUSING IS THE POLICY FOR THE ONLY CALLER THERE IS TODAY, which is the
# other half and is stated here so the paragraph above is not read as describing
# what the app does. The one in-app path is `Location::Generator#lay_out_interior!`
# behind `Location#place?`, which is true only of a row that ALREADY carries a
# footprint -- so a stub without one is not laid out at all, and the roll is
# reached only by calling `.lay_out!` directly, which the tests do. That is
# deliberate: WHICH generated stubs become places is a scoping decision being
# settled separately, and this slice does not make it.
#
# THERE IS NO `interior:` KEY AND NO COLUMN FOR ONE. A world that wanted to say
# *sprawling* rather than *twelve by eight* would be naming a key into a table
# in this file -- `Location::DANGERS`' shape exactly -- and that is a column on
# `locations` plus a loader, an exporter and a validation for it. Nothing asks
# for it yet, and a parameter with no world to supply it is a column the doctor
# would have to report on. The footprint is the parameter until something needs
# more.
#
# --- the two travel-time rules ----------------------------------------------
#
# AN INTERIOR EDGE DERIVES ITS DISTANCE FROM THE GEOMETRY, and an EXTERIOR EDGE
# KEEPS ITS LABEL. Both halves matter and they are stated here together because
# they are one rule with two sides:
#
#   INSIDE, the rooms have boxes, so how far apart two of them are is arithmetic
#   (`Location::Box#paces_to`) and nothing should be picking a label for it.
#   `#distance_for` turns those paces into one of `LocationConnection::DISTANCES`'
#   own keys using that table's own minutes, so there is no second table of
#   numbers to keep in step with the first. At the sizes a building comes in
#   every door is the shortest of them, which is correct and is the point: the
#   arithmetic is what makes a cathedral-sized place not say the same thing as a
#   broom cupboard.
#
#   OUTSIDE, there is no geometry to derive anything from -- the captain's
#   *"connected locations don't necessarily have to be planar distances"*, and
#   two cities share no origin (`Location::Box`). So an exterior edge keeps the
#   label it has, whether a model picked it or a seed file wrote it, and NOTHING
#   in this file touches an existing `LocationConnection`.
#
# STAIRS ARE `travel_method: "taking stairs"`, which the table has carried since
# before any of this, and their distance is derived like a door's from the
# horizontal separation alone. A storey index is not a height (`Location::Box`),
# so there is no number of paces a floor is worth; what going up costs is the
# travel method's own multiplier, which is where the app already keeps it.
#
# --- determinism ------------------------------------------------------------
#
# ONE GENERATOR, KEYED ON THE STORY AND THE PLACE, AND THE DRAWS IN A FIXED
# ORDER -- `Character::StatBlock`'s rule, and the one thing here that must not be
# tidied. Every number is drawn from a `Roll.generator` seeded with plain
# integer arithmetic (`Roll`, and read its header for why `String#hash` is not
# one of them), so the same place lays out the same way in any process, after
# any restart, for ever: an offline sweep re-derives the walls a real run wrote
# and plays a building nobody kept (`lib/engine_sweep/scripts/a-building-with-two-floors.yml`).
# THERE IS NO REHEARSAL COMMAND for a layout, and the `DRY_RUN=1` that
# `Character::StatBlock` names is not one -- it belongs to `rake game:update`,
# and it prints what a step of `Update::REGISTRY` would write. Nothing here is
# an update step; whatever backfills the interiors of a world laid out before
# this file existed would be, and re-derivability is what it would rest on.
#
# KEYED ON THE PLACE'S ID AND NOT ON THE CLOCK, which is `Location::Danger.generator_for`'s
# choice and its reason: a place is laid out ONCE and its id is the durable
# thing about it, so a layout re-derived next week is the layout on the records.
# `playthrough: 0`, because an interior is WORLD data on exactly the terms a
# stat block is -- every game walks the same building.
#
# ITS OWN `Roll::INTERIOR` AXIS, because its identity is a location id and
# `Location::Danger` already keys a room's cast on one. See `Roll`'s header for
# why an axis rather than another band of `sequence`.
class Location::Interior
  # HOW SMALL A ROOM MAY BE, in paces on a side. Three: two rooms of two paces
  # meeting at a doorway is a corridor with a door in the middle of it, and a
  # place divided that finely is a place whose prose has nothing to say about
  # any one of its rooms. It is a floor on the DIVISION and not on the room -- a
  # place smaller than this across is laid out as a single room rather than
  # refused, because the footprint is the world's parameter and the world wins.
  MINIMUM_SIDE = 3

  # HOW MANY FLOORS A PLACE COMES IN AT AND ABOVE THE GROUND, and how many rooms
  # one floor is divided into. Both are the engine's and neither is a target:
  # the footprint decides what actually fits, and a place too small for the
  # bottom of the room range holds fewer.
  #
  # AT AND ABOVE, because `BASEMENTS` counts the other direction and the two are
  # added: a place is laid out on storeys `-BASEMENTS .. STOREYS - 1`.
  STOREYS = (1..3).freeze
  ROOMS_PER_STOREY = (2..6).freeze

  # HOW MANY STOREYS GO BELOW THE ENTRY, and it is `STOREYS`' counterpart in
  # every respect: the engine's, rolled from one seeded `Roll`, and a count of
  # planes rather than a height (`Location::Box`). A place laid out with two of
  # them has rooms on storeys -2 and -1 under the ground floor, and the stairs
  # that bind them are the stairs that bind any two adjacent storeys.
  #
  # WHY IT IS ZERO-WEIGHTED TODAY, which is the choice this file is making and
  # not an oversight. A GENERATED place gets no basement, so every world already
  # laid out lays out the same way after this change as before it -- the range
  # holds one value, `#basements` does not draw at all, and no draw after it
  # moves. What supplies a real count is the stage-one pick of `ta-interior-entry`
  # (the captain's Call 7 answer C1 of 2026-09-07: a model may pick "storeys
  # below" from a closed list), which is a slice of its own and is deliberately
  # not front-run here. What this slice buys is the other half of that pick: a
  # layout that has somewhere to WRITE the answer.
  #
  # SO THE ONE WAY TO GET A BASEMENT TODAY IS TO ASK FOR ONE -- `.lay_out!`'s
  # `below:`, which is how `lib/engine_sweep/worlds/the-quay-house.yml`'s bonded
  # cellar was written and is the "a world supplies parameters" channel until
  # the pick exists. A seed file's own channel is unchanged and needs nothing
  # new: `z` has always been a signed integer on `locations` and
  # `WorldSeed::Loader` has always accepted one, so a file may write `z: -1`
  # outright.
  BASEMENTS = (0..0).freeze

  # HOW BIG A PLACE NOBODY SIZED IS, on each side. A building rather than a
  # district: the range is bounded above so an interior stays a thing a player
  # walks through in a few moves, and bounded below by room enough for the top
  # of `ROOMS_PER_STOREY` to fit at `MINIMUM_SIDE`.
  FOOTPRINT_SIDES = (9..18).freeze

  # HOW MANY WAYS UP THERE ARE BETWEEN TWO FLOORS. At least one, or the floor
  # above is not part of the building.
  STAIRWELLS = (1..2).freeze

  # WHETHER A PAIR OF ROOMS THAT SHARE A WALL GET A DOOR BEYOND THE BACKBONE'S.
  # This many faces of `DOOR_DIE`, which is `Location::DANGERS`' shape and its
  # reason: the die and the share are the whole of the decision and both are
  # written down here. A building of nothing but the backbone is a corridor
  # folded up; every wall a door is a building with no rooms in it.
  DOOR_DIE = 6
  EXTRA_DOOR_SHARE = 2

  # HOW FAR A PERSON WALKS IN A MINUTE, IN PACES. It is the one number that
  # turns `Location::Box`'s paces into `LocationConnection::DISTANCES`' minutes,
  # and it is here rather than on either of them because it belongs to neither:
  # a box does not know how fast anybody walks and a distance label does not
  # know what a pace is.
  PACES_PER_MINUTE = 60

  # THE TWO WAYS YOU GET AROUND INSIDE A BUILDING, as keys into
  # `LocationConnection::TRAVEL_METHODS`. Named here so nothing in this file
  # writes a bare string a typo could make into a validation failure at the far
  # end of a layout.
  WALKING = "walking"
  STAIRS = "taking stairs"

  # THE WAY IN, and the reader `Story::Doctor` asks for it. The FIRST room
  # created, which is the start of storey 0's serpentine and therefore a corner
  # of the ground floor -- where a door onto a street is. Lowest id rather than
  # a column, because a place is laid out once and in one order, so the order
  # the rows were written in IS the answer and a column would be a second thing
  # that could disagree with it.
  def self.entry_room(place) = place.child_locations.order(:id).first

  # WHERE SOMEBODY ARRIVING AT THIS LOCATION ACTUALLY ENDS UP, and there is one
  # of these rather than an `if` at each caller because the captain's ruling of
  # 2026-09-06 -- *"the prince should be in a Room inside a Location, not in an
  # unrealized location"* -- is a rule about the PARTY and not about one branch.
  # `Playthrough::Turn#move_to` and `Playthrough::Mechanics#stand_in` are the two
  # writers of where a party stands, and two spellings of this would be two
  # answers to whether a player can stand in a container.
  #
  # ITSELF FOR EVERYTHING ELSE, which is every room in every flat world: a room,
  # a street, a district (plain containment -- a parent with no footprint, whose
  # children are ordinary places and not rooms of an inside), and a place NOBODY
  # HAS OPENED YET. That last one is not an oversight -- a stub place has no
  # rooms to arrive in, and arriving is exactly what lays them out
  # (`Location::Generator#lay_out_interior!`), so this is asked AFTER the
  # realization and not before it.
  def self.way_in(location) = (location.laid_out? && entry_room(location)) || location

  # THE ROOMS A WAY IN MAY LAND ON, IN THE ORDER IT MAY TAKE THEM: the entry
  # room, and then the rest of the GROUND FLOOR by the order they were written.
  #
  # THE ENTRY ROOM FIRST BECAUSE THE SLOT WAS KEPT FOR IT (see the header) --
  # every other room of storey 0 is at whatever cap the layout left it, so the
  # first way in is the only one guaranteed a home. The rest are offered because
  # a place can be named by more than one neighbour before anybody opens it, and
  # a second street door on a second ground-floor room is an ordinary building;
  # a second door into the cellar is not, which is why nothing below storey 0
  # and nothing above it is on this list.
  #
  # IT SAYS NOTHING ABOUT BUDGET. Whether a room may take one more way out is
  # `Location::ExitsSchema::MAX_EXITS` read off the records at the moment of
  # writing, which is `Location::Generator#open_the_way_in!`'s to ask -- this is
  # the order, not the permission.
  def self.doorstep(place)
    rooms = place.child_locations.order(:id).to_a
    entry = rooms.first

    [ entry, *rooms.select { |room| room != entry && room.z&.zero? } ].compact
  end

  # THE PLACEHOLDER A ROOM IS CALLED BEFORE ANYBODY WRITES IT, and it is a
  # method rather than an interpolation at the call site so there is ONE place
  # to ask what an unwritten room looks like.
  #
  # A STUB IS A NAME AND A TEASER TODAY, and it stays one here -- what changes is
  # who wrote them. A stub from `Location::Generator` is named by the model that
  # named the exit leading to it; a room in an interior has no exit leading to it
  # yet and nobody has said a word about it, so the engine names it after the
  # place it is in and numbers it. That is deliberately not evocative: it is
  # ordinal, obviously provisional, unique within the story, and stable, which
  # are the four things a placeholder has to be. The teaser carries what the
  # ENGINE knows and nothing it does not -- how big the room is and which floor
  # it is on -- so the call that eventually writes this room is handed facts
  # rather than an invented atmosphere it would have to stay consistent with.
  #
  # AND IT CARRIES NO COMMA, which looks like a typographic preference and is
  # not. `Playthrough::Grammar::JOINING_WORDS` reads a comma as *and*, so a line
  # naming a room with one in it would be refused as two acts in a line
  # (`Playthrough::Refusal`) -- a room the player could see and could not walk
  # into. The rule generalizes: a name the engine writes has to be a name the
  # grammar can be handed back.
  def self.placeholder_name(place, number) = "#{place.name} room #{number}"

  # AND WHETHER A NAME IS ONE OF THIS PLACE'S PLACEHOLDERS, asked of the SHAPE
  # `.placeholder_name` writes rather than of the rows -- which is the whole
  # reason it is worth having. A number no room of this building carries is
  # still a placeholder, and it is the one a collision check cannot see:
  # `Location::RoomName` refuses a model that proposes `The Custom House room
  # 12` for an eight-room building, because a room permanently called a
  # placeholder is worse than a room still called its own number. Nothing
  # afterwards could tell the two apart.
  #
  # IDENTITY IS `WorldSeed.natural_key`'s, for the reason `Location::RoomName`
  # gives at length: case, runs of whitespace and a leading article are not part
  # of a name in this repo, and this has to agree with the check that refuses on
  # them.
  def self.placeholder_name?(place, name)
    WorldSeed.natural_key(name).match?(/\A#{Regexp.escape(WorldSeed.natural_key(place.name))} room \d+\z/)
  end

  attr_reader :place, :story, :parameters

  # `below:` IS THE ONE PARAMETER A CALLER MAY OVERRULE, and it is here rather
  # than on the place for `BASEMENTS`' reason: nothing writes a count of
  # basements to a column yet, and a parameter with no world to supply it is a
  # column the doctor would have to report on. Nil means ROLL IT, which is what
  # every caller in the app passes by passing nothing.
  def self.lay_out!(place, below: nil, parameters: nil)
    new(place, below: below, parameters: parameters).lay_out!
  end

  def initialize(place, below: nil, parameters: nil)
    @place = place
    @story = place.story
    @below = validated_below(below)
    @parameters = parameters
  end

  # THE WHOLE INTERIOR, IN ONE TRANSACTION. A place half laid out is worse than
  # a place with no inside at all: it has rooms that lead nowhere and a floor
  # plan nothing can finish, and nothing downstream could tell it from a
  # deliberate one.
  #
  # LAID OUT ONCE, EVER, which is `Location::Generator#realize!`'s guarantee said
  # about geometry: a place that already has children is returned untouched, so
  # walking back into a building gives you the building you left. It is asked of
  # the RECORDS rather than of a flag, because the rooms are the answer.
  def lay_out!
    raise ArgumentError, "an interior is laid out inside a saved place" unless place.persisted?
    return place if place.child_locations.exists?

    Location.transaction do
      write_footprint!
      storeys = storey_plans.map { |boxes| create_rooms!(boxes) }

      storeys.each { |storey| open_backbone!(storey) }
      by_height(storeys).each_cons(2) { |below, above| raise_stairs!(below, above) }
      storeys.each { |storey| open_extra_doors!(storey) }
      close_connectivity!(storeys.flatten)
    end

    place
  end

  private

  # THE ONE GENERATOR THE WHOLE LAYOUT IS DRAWN FROM. See the header for why it
  # is keyed on the place's id, why the playthrough is zero and why the axis is
  # its own.
  def rng
    @rng ||= Roll.generator(story: story.id, sequence: place.id, kind: Roll::INTERIOR)
  end

  # THE PLANE THE ROOMS ARE READ IN. A place that carries a footprint keeps it
  # untouched -- that is the world's parameter and this file does not overrule
  # one -- and a place with none is given one. Drawn FIRST when it is drawn at
  # all, so the order of every draw after it is fixed.
  def write_footprint!
    return if place.interior?

    place.update!(width: Roll.one_of(FOOTPRINT_SIDES.to_a, rng: rng),
                  depth: Roll.one_of(FOOTPRINT_SIDES.to_a, rng: rng))
  end

  # EVERY STOREY'S BOXES, in serpentine order -- which is the order the rooms are
  # created in and therefore the order the backbone's doors are opened in.
  def storey_plans
    storey_order(storeys_above, basements).map { |z| storey_boxes(z) }
  end

  # HOW MANY STOREYS AT AND ABOVE THE GROUND: the pick, or a roll. `#basements`'
  # shape and its rule -- a caller that asked somebody gets the answer, a caller
  # that asked nobody gets the engine's own range.
  def storeys_above
    return parameters.above if parameters

    Roll.one_of(STOREYS.to_a, rng: rng)
  end

  # WHICH STOREYS THERE ARE, AND IN WHAT ORDER THEY ARE BUILT: the ground floor
  # first, then up, then down. The SET is `-below .. above - 1`; the ORDER is
  # this, and the order is load-bearing twice over.
  #
  # THE ENTRY ROOM IS THE FIRST ROOM WRITTEN, and `.entry_room` reads it back off
  # the records as the lowest id -- so the way in has to be a room of the GROUND
  # floor whatever else the place has, or a building with a cellar would have its
  # street door in the cellar. Storey 0 first is what makes that true by
  # construction rather than by a column. `#close_connectivity!` leans on the
  # same thing when it takes `rooms.first` as the entry.
  #
  # AND A PLACE WITH NO BASEMENTS DRAWS EXACTLY WHAT IT DREW BEFORE THIS FILE
  # COULD DESCEND. `(0...above)` is what this method used to be, and the
  # basements are appended rather than mixed in -- so every draw of every storey
  # of every world already laid out lands in the order it landed in then. See
  # `BASEMENTS` for the other half of that guarantee, which is that a generated
  # place has none.
  #
  # THE STAIRS ARE NOT BUILT IN THIS ORDER, because they are the one thing that
  # is a question about HEIGHT rather than about the order rooms were written in
  # -- `#by_height` is where that is said.
  def storey_order(above, below) = (0...above).to_a + (-below..-1).to_a

  # HOW MANY STOREYS GO BELOW: what the caller asked for, or a roll. See
  # `BASEMENTS` for why the roll is zero-weighted today.
  #
  # A RANGE OF ONE VALUE IS NOT DRAWN AT ALL, and that is a determinism rule
  # rather than a saving. `Roll.one_of` with one choice happens not to advance
  # the generator on the Ruby this repo runs, but "happens not to" is not
  # something a world's re-derivability may rest on: every draw after this one
  # would move if it ever started to. So the draw is skipped where there is
  # nothing to decide, and the whole of what widening `BASEMENTS` costs is
  # stated in one place -- it starts drawing, and the layouts move.
  def basements
    return @below unless @below.nil?
    return parameters.below if parameters
    return BASEMENTS.min if BASEMENTS.min == BASEMENTS.max

    Roll.one_of(BASEMENTS.to_a, rng: rng)
  end

  # THE STOREYS IN HEIGHT ORDER, LOWEST FIRST, which is the order STAIRS are
  # built in and the only place this file reads a storey as a height rather than
  # as an index. `#raise_stairs!` joins two ADJACENT storeys, and adjacency is a
  # fact about the numbers: with a cellar the pairs are (-1, 0) and (0, 1), and
  # taking the storeys in the order the ROOMS were written would have paired the
  # top floor with the cellar and left the cellar unreachable.
  #
  # IT IS THE IDENTITY FOR A PLACE WITH NO BASEMENTS, whose storeys were written
  # from the ground up already -- so nothing about an existing layout's stairs
  # moves. `#storey_order` carries the rest of that argument.
  def by_height(storeys) = storeys.sort_by { |storey| storey.first.z }

  # A COUNT OF BASEMENTS, OR NIL. Refused rather than coerced, for
  # `Location::Interior`'s own reason about half-written geometry: a caller that
  # passed a string or a negative would otherwise get a building whose storeys
  # nobody asked for, and no record afterwards would say why.
  def validated_below(below)
    return nil if below.nil?
    raise ArgumentError, "below is a whole number of storeys, got #{below.inspect}" unless below.is_a?(Integer)
    raise ArgumentError, "below is a count and not a storey index, got #{below}" if below.negative?

    below
  end

  # ONE FLOOR, DIVIDED. The grid is rolled first and the room sizes second, so a
  # storey is a grid of different-sized rooms rather than a chessboard.
  def storey_boxes(storey)
    columns = Roll.one_of(column_choices.to_a, rng: rng)
    rows = Roll.one_of(row_choices(columns).to_a, rng: rng)

    widths = share(place.width, columns)
    depths = share(place.depth, rows)
    lefts = offsets(widths)
    tops = offsets(depths)

    serpentine(columns, rows).map do |(column, row)|
      Location::Box.new(x: lefts[column], y: tops[row], z: storey,
                        width: widths[column], depth: depths[row])
    end
  end

  # HOW MANY COLUMNS A FLOOR MAY HAVE: what fits at `MINIMUM_SIDE`, capped by
  # the top of `ROOMS_PER_STOREY` so one axis cannot spend the whole allowance,
  # and never fewer than one -- a place narrower than a room is one room wide.
  def column_choices = 1..[ [ place.width / MINIMUM_SIDE, ROOMS_PER_STOREY.max ].min, 1 ].max

  # HOW MANY ROWS, GIVEN THE COLUMNS. The bounds are the room range divided by
  # what the columns already committed to, so the grid lands inside
  # `ROOMS_PER_STOREY` by construction rather than by a retry -- and the
  # footprint still wins, because a floor with no room for a second row gets one
  # row whatever the range says.
  def row_choices(columns)
    most = [ [ place.depth / MINIMUM_SIDE, ROOMS_PER_STOREY.max / columns ].min, 1 ].max
    fewest = [ [ (ROOMS_PER_STOREY.min + columns - 1) / columns, 1 ].max, most ].min

    fewest..most
  end

  # ONE AXIS OF THE FOOTPRINT CUT INTO `parts`, IN PACES, SUMMING TO EXACTLY THE
  # FOOTPRINT. Every part starts at the same floor and the paces left over are
  # dealt out ONE AT A TIME by roll -- which is why the rooms come out uneven,
  # and why the total cannot drift: nothing is divided and nothing is rounded.
  # The loop is bounded by the footprint, which is bounded by `FOOTPRINT_SIDES`
  # or by whatever a world file wrote, so it is a handful of draws.
  #
  # THE FLOOR IS `MINIMUM_SIDE` OR AN EVEN SHARE, whichever is smaller: a place
  # too small to divide at `MINIMUM_SIDE` is never divided that finely, because
  # `#column_choices` will not have asked for it -- and a room that is the whole
  # of a tiny footprint is still a room.
  def share(length, parts)
    smallest = [ MINIMUM_SIDE, length / parts ].min
    sizes = Array.new(parts, smallest)

    (length - smallest * parts).times { sizes[Roll.one_of((0...parts).to_a, rng: rng)] += 1 }

    sizes
  end

  # Where each part starts, from a list of how wide each one is.
  def offsets(sizes) = sizes.each_with_object([ 0 ]) { |size, all| all << all.last + size }

  # THE PATH THE BACKBONE FOLLOWS: along one line of the grid, back along the
  # next. Consecutive entries are always neighbours, and every cell appears
  # exactly once -- which is the whole of why connectivity is a guarantee here
  # rather than a search (see the header). Which way it runs is rolled, so two
  # storeys of one building are not the same walk.
  def serpentine(columns, rows)
    if Roll.one_of([ true, false ], rng: rng)
      (0...rows).flat_map { |row| ordered(columns, row).map { |column| [ column, row ] } }
    else
      (0...columns).flat_map { |column| ordered(rows, column).map { |row| [ column, row ] } }
    end
  end

  # A line of the grid, reversed on every other line -- the turn at the end of
  # the row that makes a serpentine a single path instead of a comb.
  def ordered(count, line) = line.even? ? (0...count).to_a : (0...count).to_a.reverse

  # THE ROOMS OF ONE STOREY, created in the order they are laid out. Numbered
  # across the WHOLE interior rather than per storey, so no two rooms of one
  # place ever share a placeholder.
  def create_rooms!(boxes)
    boxes.map do |box|
      @numbered = (@numbered || 0) + 1
      create_room!(box, @numbered)
    end
  end

  # ONE ROOM, BORN THE WAY EVERY OTHER ROOM IN THE APP IS BORN.
  # `Location::Generator.create_stub!` is the one path, so an interior's rooms
  # get their `danger` rolled by `Location::Danger` exactly as a stub named by a
  # neighbour does, and there is no second place that knows what a new room is.
  #
  # THE BOX IS A SECOND WRITE and has to be: all five columns go on at once or
  # `Location#a_box_is_whole` refuses the row, and a stub is created before it
  # has anywhere to be.
  def create_room!(box, number)
    room = Location::Generator.create_stub!(story, name: self.class.placeholder_name(place, number),
                                                   teaser: teaser_for(box))
    room.update!(parent_location: place, **box.to_h, **conditions(box.z))
    # THE FIRST ROOM WRITTEN IS THE WAY IN, which is what `.entry_room` reads
    # back off the records afterwards. Held here so the cap check below does not
    # ask the database which room that was on every door it opens.
    @entry ||= room
    room
  end

  # WHAT A ROOM OF THIS BUILDING IS BORN AS, over and above what
  # `Location::Generator.create_stub!` already rolled for it: the danger the
  # building's own pick leans towards on THIS storey, and the building's hazard if
  # the die gives it one. Both are `Location::Danger`'s -- one file decides where
  # monsters come from and what a room does to you, whether the room is a stub off
  # a road or the third floor of an inn.
  #
  # EMPTY WHEN NOBODY WAS ASKED, and that is what keeps a world already on disk
  # re-derivable: no parameters, no draws, and the room keeps the danger
  # `.create_stub!` rolled and no hazard at all. See the header for why the two
  # states are different.
  #
  # THE STOREY IS THE ONLY THING THE GRADIENT NEEDS, because the gradient IS the
  # slope of these two columns down the building -- there is no gradient column
  # and there is not going to be one, so the rooms are the record of it.
  def conditions(storey)
    return {} if parameters.nil?

    { danger: Location::Danger.in_a_place(parameters, storey: storey, rng: rng) }
      .merge(Location::Danger.hazard_in_a_place(parameters, storey: storey, rng: rng))
  end

  # THE WAY IN, AS THIS INSTANCE READS IT: the first room `#create_room!` wrote
  # while a layout is running, and `.entry_room`'s answer off the RECORDS on any
  # other caller. They are the same room -- a place is laid out once and in one
  # order, so the order the rows were written in IS the answer.
  #
  # IT FALLS BACK RATHER THAN ONLY REMEMBERING, because the reserved slot has to
  # be a rule about the ROWS and not about how they were reached. That is
  # `#close_connectivity!`'s own premise, and it may be handed a place this
  # instance did not lay out -- an interior somebody else broke. With nothing
  # but the ivar the entry room had the ordinary cap there, so a repair could
  # spend the one slot the layout kept free for the way IN and nothing would
  # report it.
  #
  # THE FALLBACK IS NEVER TAKEN DURING A LAYOUT and costs it no query:
  # `#room_to_spare?` is reached only after `#create_rooms!` has run, so the
  # ivar is already set by the time anything asks.
  def entry = @entry ||= self.class.entry_room(place)

  # WHAT THE ENGINE KNOWS ABOUT A ROOM NOBODY HAS WRITTEN: how big it is and
  # which floor it is on. See `.placeholder_name` for why it says no more.
  def teaser_for(box)
    "A room inside #{place.name}, #{box.width} by #{box.depth} paces on storey #{box.z}."
  end

  # THE DOORS THAT MAKE A FLOOR ONE FLOOR: one between each pair of rooms
  # adjacent in the serpentine, which is every room joined to the next in a
  # single path. Two doors per room at most, which is what leaves the budget for
  # stairs.
  def open_backbone!(storey)
    storey.each_cons(2) { |one, other| connect!(one, other, WALKING) }
  end

  # THE WAYS UP -- AND SO THE WAYS DOWN, which is one set of rows and not two. A
  # stairwell joins a room on one floor to the room DIRECTLY ABOVE PART OF IT --
  # `Location::Box#shares_ground?`, which is the whole of what the captain's
  # third ruling means by floors being kept aligned. Both storeys tile the same
  # footprint, so every room on the lower floor has at least one room above it
  # and a candidate always exists.
  #
  # `below` AND `above` ARE THE TWO STOREYS IN HEIGHT ORDER and never in the
  # order the rooms were written: `#by_height` is what hands them over that way,
  # so a cellar is paired with the ground floor rather than with the roof. The
  # pair is symmetric in what it WRITES -- a door is two rows -- so the naming
  # here is about which candidates are searched and not about a direction going
  # on a record.
  def raise_stairs!(below, above)
    Roll.one_of(STAIRWELLS.to_a, rng: rng).times do
      candidates = below.product(above).select { |one, other| stairs_possible?(one, other) }
      break if candidates.empty?

      connect!(*Roll.one_of(candidates, rng: rng), STAIRS)
    end
  end

  def stairs_possible?(one, other)
    one.box.shares_ground?(other.box) && !connected?(one, other) && room_to_spare?(one) && room_to_spare?(other)
  end

  # THE DOORS THE BACKBONE DID NOT NEED. Every pair of rooms that share a wall
  # gets a die, in a fixed order, whether or not there is budget left to open it
  # -- so the draws do not depend on what the stairs happened to spend, and the
  # layout stays re-derivable.
  def open_extra_doors!(storey)
    storey.combination(2).each do |one, other|
      next unless one.box.shares_a_wall?(other.box)
      next unless Roll.die(DOOR_DIE, rng: rng) <= EXTRA_DOOR_SHARE

      connect!(one, other, WALKING)
    end
  end

  # EVERY ROOM REACHABLE FROM THE ENTRY, ASKED OF THE ROWS. The construction
  # above already guarantees it, so on a layout this file built this finds
  # nothing to do -- and it runs anyway, because the guarantee is about the
  # records and an argument about the code is not a record. Anything stranded is
  # joined to what is reachable, by a door if the two share a wall and by stairs
  # if one is directly above the other.
  #
  # IT STOPS RATHER THAN RAISING when `#joinable` has nothing left to offer --
  # no stranded room shares a wall or stands under one that is reached, or every
  # pair that does has an end at its exit cap. Raising would be this file taking
  # a room off a player mid-turn to report a fault about a map; `Story::Doctor`
  # reports the rooms (`interior_with_an_unreachable_room`) and the building
  # still opens.
  #
  # `break unless connect!` IS A SAFETY NET AND NOT THE ORDINARY EXIT, which it
  # used to be: a pair already carrying ONE row would be offered, refused, and
  # offered again for ever, so the loop broke on it -- leaving every OTHER
  # stranded room unjoined for the sake of one half-written door. `#joinable`
  # now declines such a pair, so the only pairs reaching here are pairs this can
  # write, and the guard is what stops the loop if that ever stops being true.
  def close_connectivity!(rooms)
    entry = rooms.first
    return if entry.nil?

    loop do
      reached = reachable_from(entry, rooms)
      stranded = rooms - reached
      break if stranded.empty?

      pair = joinable(reached, stranded)
      break if pair.nil?
      break unless connect!(*pair, pair.first.z == pair.last.z ? WALKING : STAIRS)
    end
  end

  # The rooms of this interior that can be walked to from `entry` through the
  # interior's OWN doors. Edges out of the place are not followed: a room that
  # is only reachable by leaving the building and coming back in is a room this
  # layout failed to connect.
  def reachable_from(entry, rooms)
    by_id = rooms.index_by(&:id)
    seen = [ entry ]
    queue = [ entry ]

    while (room = queue.shift)
      LocationConnection.from_location(room).pluck(:connected_location_id).each do |id|
        neighbour = by_id[id]
        next if neighbour.nil? || seen.include?(neighbour)

        seen << neighbour
        queue << neighbour
      end
    end

    seen
  end

  # The first pair -- one room already reachable, one not -- that could be
  # joined: sharing a wall on one storey, or one directly above the other. In
  # record order, so a repair is as re-derivable as the layout it is repairing.
  #
  # A PAIR THAT ALREADY CARRIES A ROW IS NOT A CANDIDATE. It can only be a HALF
  # written door -- one row from the stranded room and none back, which is why
  # `#reachable_from` never walked it -- and adding the missing row is not this
  # file's to do: `Story::Doctor` reports it as `one_way_connection` and
  # `Story::Repair` finishes it, on the record that already says what the edge
  # is. What this file does is join rooms nothing connects, and these two are
  # connected; offering them would only be offering `#connect!` something it
  # refuses.
  def joinable(reached, stranded)
    reached.product(stranded).find do |one, other|
      next false if connected?(one, other)
      next false unless room_to_spare?(one) && room_to_spare?(other)

      (one.box.shares_a_wall?(other.box) || (one.z - other.z).abs == 1 && one.box.shares_ground?(other.box))
    end
  end

  # A DOOR IS TWO ROWS, both carrying the same values -- `Location::Generator#connect!`'s
  # rule and its reason: `LocationConnection`'s enums are direction-neutral, so
  # the way back is the same edge said the other way round.
  #
  # Answers whether it wrote one, so `#close_connectivity!` cannot loop on a pair
  # it is not allowed to join.
  def connect!(one, other, travel_method)
    return false if connected?(one, other)
    return false unless room_to_spare?(one) && room_to_spare?(other)

    distance = distance_for(one.box.paces_to(other.box))
    [ [ one, other ], [ other, one ] ].each do |from, to|
      LocationConnection.create!(location: from, connected_location: to,
                                 distance: distance, travel_method: travel_method)
    end

    true
  end

  def connected?(one, other)
    LocationConnection.exists?(location: one, connected_location: other) ||
      LocationConnection.exists?(location: other, connected_location: one)
  end

  # WHETHER THIS ROOM MAY TAKE ANOTHER WAY OUT. Read from the records on every
  # check rather than counted once, which is `Location::Generator#room_for_exits`'
  # rule and its reason: this writes as it goes.
  #
  # THE ENTRY ROOM'S CAP IS ONE LOWER -- see the header for what the spare slot
  # is being kept for.
  def room_to_spare?(room)
    cap = Location::ExitsSchema::MAX_EXITS
    cap -= 1 if room == entry

    LocationConnection.from_location(room).count < cap
  end

  # PACES INTO ONE OF `LocationConnection::DISTANCES`' OWN KEYS, using that
  # table's own minutes: the shortest label whose walk is at least as long as
  # this one. The last key is the floor for a place bigger than any label
  # describes, so this always answers something the column will accept.
  def distance_for(paces)
    minutes = [ (paces + PACES_PER_MINUTE - 1) / PACES_PER_MINUTE, 1 ].max

    LocationConnection::DISTANCES.find { |_, walk| walk >= minutes }&.first ||
      LocationConnection::DISTANCES.keys.last
  end
end
