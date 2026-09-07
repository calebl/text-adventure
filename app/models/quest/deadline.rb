# WHEN THE ENGINE STOPS ASKING AND PUTS THE THING THERE ITSELF.
#
# THE CAPTAIN'S CALL 2, 2026-09-06: **"a: yes, on a deadline, through the
# ordinary create_stub! path."** And his Call 1 on the same board: a generated
# story must **always** be completable. A prompt asking a model to build toward
# the prince is a HOPE, and the standing constraint is that the app resolves and
# the model renders -- so the prompt block is the inform half and this file is
# the verify half, and neither depends on the other being right.
#
# THIS IS THE STORY-LEVEL SIBLING OF A FLOOR THAT ALREADY EXISTS.
# `Location::Generator#write_exits!` takes a way out it would otherwise refuse,
# rather than sealing the player in, because *"a room with no way out at all is
# worse than a room with one it should not have."* Said one level up: **a story
# that cannot reach its own end is worse than one whose fourth room happens to
# be the dungeon.**
#
# --- when ------------------------------------------------------------------
#
# COUNTED IN ROOMS OPENED, not in turns and not on the clock, because
# realization is the moment the world GROWS and growing is the thing that was
# supposed to have produced the target. `PHASES` names the two states and
# `GRACE_ROOMS` is the boundary; both are read from here and written nowhere
# else.
#
# --- where, and this is the half geometry changed --------------------------
#
# THE CAPTAIN'S Q5, 2026-09-06: **"b -- wait for the floor index"**, overruling
# the recommendation that hop count was good enough. He was right and the
# measurement says so: in story 7, Blackfang Tunnel and `surface` are BOTH two
# hops from the opening room -- a tie between the bottom of the dungeon and the
# way out of it -- so a ladder built on graph depth would have encoded that
# ambiguity into the one rule that decides where the prince ends up. `z` is a
# signed storey index (`Location::Box`), so -2 is not 0 and there is nothing to
# tie.
#
# SO THE ANCHOR IS THE DEEPEST ROOM THE PARTY CAN ALREADY REACH -- lowest `z`,
# then furthest from where the game opens, then lowest id, and only among rooms
# with a doorway to spare. INTO THE REACHABLE SET and never beside it: a target
# hung off a room nothing leads to would satisfy every check here and fail
# `Story::Doctor`'s `quest_target_unreachable`, which is the instrument that
# would catch it.
#
# --- what it places, and the prince ruling ---------------------------------
#
# *"I think the prince should be in a Room inside a Location, not in an
# unrealized location"* -- 2026-09-06. So a person is never bolted onto the
# graph as a stub of their own. What the engine builds is a PLACE: a stub
# through the ordinary `Location::Generator.create_stub!` path, laid out by
# `Location::Interior`'s rolled-footprint branch -- the branch written for *"a
# caller that does not exist yet"*, and this is that caller -- with its cellars
# asked for rather than rolled, because `BASEMENTS` is zero-weighted and an
# interior descends only when somebody asks. The target then stands in the
# DEEPEST ROOM of it, which is what "deepest" meant all along.
#
# A `reach_location` TARGET IS THE PLACE. A `speak_to` target is somebody in the
# deepest room of one. A `hold_item` target is a thing lying in the deepest room
# the party can reach. A `time_passed` step is never placed at all -- the clock
# already exists, so there is nothing for the world to grow.
#
# --- what it is not --------------------------------------------------------
#
# NOT A MODEL CALL. Not one, anywhere in this file: the name and the teaser come
# off the arc, the geometry off a seeded `Roll`, and the placement off the
# records. That is what makes it assertable offline and re-derivable.
#
# NOT A ROUTE. One door, off a room the party can already stand in. Nothing
# gates, nothing forces, the player may walk the other way, and the step is
# reached only when they actually get there. The stub rolls its own `danger`
# like every other and is indistinguishable from one a model named, which is the
# principle `ta-shuffle-grows` states for its own new stubs.
#
# NOT A CORRECTION TO THE MODEL. The model was never wrong; until the prompt
# block lands it was never asked.
#
# ONE THING PER REALIZATION, deliberately: the arc's FIRST unbound step and no
# other. A world that sprouted every unbound target the moment it went overdue
# would be the railroad this design spends its whole shape avoiding.
class Quest::Deadline
  # HOW MANY ROOMS THE MODEL GETS BEFORE THE ENGINE STOPS ASKING.
  #
  # THREE, AND THE REASONING IS A WALK RATHER THAN AN ARGUMENT: the captain
  # generated *The Iron Gate Descends*, explored it, and the room that closed
  # the story off was the FOURTH one written -- Blackfang Tunnel, the deepest
  # room of the dungeon, given two ways out with both of them leading back up.
  # So three is the last room at which waiting is still the better fiction, and
  # the fourth is the one the engine has to be able to answer for.
  #
  # IT IS A PARAMETER AND SHOULD BE TUNED IN PLAY, not defended on paper. It is
  # named here rather than measured in a comment because a measured number in a
  # comment goes stale silently; what this constant is worth is what the next
  # generated world says it is worth.
  GRACE_ROOMS = 3

  # THE RELAXATION PHASES, NAMED, and counted in rooms opened. Two today, and
  # the table is the shape rather than the count: a rung between them -- *place
  # it, but only where the model has already dug downward* -- is a row here and
  # a branch in `#anchor`, not a rewrite.
  PHASES = {
    "asking" => "the story block names what the arc needs and the engine waits for a model to build it",
    "placing" => "the engine places it itself, off the deepest room the party can already reach"
  }.freeze

  # WHAT THE ENGINE ASKS FOR WHEN IT BUILDS THE PLACE ITSELF, as picks out of
  # `Location::Parameters`' closed vocabulary and never as numbers.
  #
  # CELLARS ASKED FOR RATHER THAN ROLLED, and that is the whole of why there are
  # picks here at all: `Location::Interior::BASEMENTS` is zero-weighted, so a
  # caller that asks nobody gets a building with no downstairs. An arc's target
  # is the thing at the bottom -- that is what a deadline is FOR -- so this is
  # the one caller in the app that says so.
  #
  # `Location::Parameters.from` AND NOT A SECOND TABLE OF NUMBERS: the labels
  # below are keys into that class's own tables, so what "two levels down" means
  # is stated in exactly one place.
  PICKS = { "storeys_below" => "two levels down" }.freeze

  # WHERE IN THE PROMPT LIFE THIS RUNS: after a room has been described and its
  # ways out written, which is the moment `Location::Generator#realize!` calls
  # it. The room that was just realized is the anchor's first candidate, because
  # it is the newest thing the player can stand in.
  def self.after_realizing!(location)
    new(location.story, anchor: location).run!
  end

  # WHETHER THIS WORLD HAS RUN OUT OF PATIENCE. Read by `Story::Doctor` as well,
  # which is why it is a class method: a story with unbound steps is the
  # ORDINARY state of a young generated world and a defect in an old one, and
  # this is the one line that says which.
  def self.overdue?(story) = rooms_opened(story) > GRACE_ROOMS

  def self.phase_for(story) = overdue?(story) ? "placing" : "asking"

  # ROOMS OPENED. Every realized location, interior rooms included: a room
  # somebody walked into and a model described is a room opened, whatever
  # contains it.
  def self.rooms_opened(story) = story.locations.realized.count

  attr_reader :story, :anchor_hint

  def initialize(story, anchor: nil)
    @story = story
    @anchor_hint = anchor
  end

  # Places the arc's first unbound target, or does nothing at all -- which is
  # every realization in every world with no arc, and every realization of a
  # young one.
  #
  # Returns the row it wrote, or nil.
  def run!
    return nil unless self.class.overdue?(story)

    step = due_step
    return nil if step.nil?

    room = anchor
    return nil if room.nil?

    case step.trigger_kind
    when "reach_location" then place_a_place!(step, room)
    when "speak_to" then place_a_person!(step, room)
    when "hold_item" then place_a_thing!(step, room)
    end
  end

  private

  # THE FIRST BEAT OF THE MAIN ARC THE WORLD HAS NOT GROWN A ROW FOR. The main
  # arc only: a side quest is discovered rather than planned, so nothing is owed
  # a deadline for one.
  def due_step
    arc = story.main_quest
    return nil if arc.nil? || arc.doomed?

    arc.steps.detect { |step| step.unbound? && step.wants_a_row? && step.target_name.present? }
  end

  # THE DEEPEST ROOM THE PARTY CAN ALREADY REACH, WITH A DOORWAY TO SPARE.
  #
  # `z` FIRST, which is the captain's Q5 (see the header) -- a cellar is not the
  # street just because both are two hops out. Then furthest from where the game
  # opens, so a tie between two rooms on one floor goes to the one deeper into
  # the world. Then lowest id, so the answer is the same in any process.
  #
  # A ROOM WITH NO BOX READS AS STOREY 0, which is every room in a flat world:
  # they are all ground level, so they all tie and the hop count separates them.
  #
  # ONLY REACHABLE ROOMS, and only rooms that can take another door. A place
  # with an inside is never one -- a laid-out place is not somewhere anybody
  # stands (`Location#laid_out?`), and hanging the way in off a container is the
  # one shape `Location::Generator#open_the_way_in!` exists to make impossible.
  def anchor
    return @anchor if defined?(@anchor)

    @anchor = candidates.min_by { |room| [ room.z.to_i, -hops.fetch(room.id, 0), room.id ] }
  end

  def candidates
    story.locations.where(id: hops.keys).order(:id).reject do |room|
      room.laid_out? || LocationConnection.from_location(room).count >= Location::ExitsSchema::MAX_EXITS
    end
  end

  # HOW FAR EVERY REACHABLE ROOM IS FROM WHERE THE GAME OPENS, breadth first
  # over the connection rows in both directions -- a door is two rows and a walk
  # crosses one the table only half recorded. It is also the reachability set:
  # a room absent from it is one no player could ever be standing in.
  def hops
    @hops ||= begin
      root = story.locations.realized.order(:id).first
      root.nil? ? {} : walk_from(root.id)
    end
  end

  def walk_from(root_id)
    seen = { root_id => 0 }
    queue = [ root_id ]

    until queue.empty?
      id = queue.shift
      adjacency.fetch(id, []).each do |neighbour|
        next if seen.key?(neighbour)

        seen[neighbour] = seen[id] + 1
        queue << neighbour
      end
    end

    seen
  end

  def adjacency
    @adjacency ||= LocationConnection.joins(:location).where(locations: { story_id: story.id })
                                     .pluck(:location_id, :connected_location_id)
                                     .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(from, to), index|
      index[from] << to
      index[to] << from
    end.transform_values { |ids| ids.uniq.sort }
  end

  # A BUILDING, THROUGH THE ORDINARY PATH, WITH ITS INSIDE ALREADY DRAWN.
  #
  # THE STUB IS BORN THE WAY EVERY STUB IS BORN -- `Location::Generator.create_stub!`,
  # which rolls its `danger` and binds the arc (`Quest::Binder`) as a side
  # effect, exactly as it does for a stub a model named. Then the doorway, then
  # the layout, then the transplant that moves the doorway onto the entry room.
  #
  # THE ORDER IS THE POINT AND IT IS `Location::Generator#lay_out_interior!`'s:
  # the way in has to EXIST before `#open_the_way_in!` can move it, and the
  # rooms have to exist before it has anywhere to move it to. One transaction,
  # because a place half built has rooms leading nowhere.
  def place_a_place!(step, room)
    Location.transaction do
      place = Location::Generator.create_stub!(story, name: step.target_name, teaser: teaser_for(step))
      open_the_door!(room, place)
      lay_out!(place)
      place
    end
  end

  # SOMEBODY IN THE DEEPEST ROOM OF A BUILDING THE ENGINE JUST BUILT -- the
  # prince ruling, taken literally. The place is named for the step's own words
  # rather than for the person, because a step that wanted a PLACE would have
  # said so: what this one wants is somebody to be somewhere.
  #
  # THROUGH `Character::Registry#admit!`, which is the one thing in the app that
  # puts a person in a room -- so the caps hold, a taken name is refused, the
  # race and the body are the engine's own rolls, and the binding happens where
  # every other binding happens. This class hands it a name and a sheet and
  # decides nothing else about who they are.
  def place_a_person!(step, room)
    Location.transaction do
      place = Location::Generator.create_stub!(story, name: holding_name(step), teaser: teaser_for(step))
      open_the_door!(room, place)
      lay_out!(place)

      cell = deepest_room(place) || place
      Character::Registry.new(cell).admit!([ sheet_for(step) ]).detect { |person| person.fullname == step.target_name }
    end
  end

  # A THING, LYING IN THE DEEPEST ROOM THE PARTY CAN REACH. No building: a thing
  # is not somebody, so there is nothing for a floor plan to be written around,
  # and the room the player is standing in when the deadline fires is exactly as
  # good a place for it as one two doors on.
  #
  # THROUGH `Item::Registry#admit!`, on the same terms as the person above.
  def place_a_thing!(step, room)
    Item::Registry.new(room).admit!([ { "name" => step.target_name, "description" => thing_description(step) } ]).first
  end

  def lay_out!(place)
    Location::Interior.lay_out!(place, parameters: Location::Parameters.from(PICKS))
    Location::Generator.new(place).open_the_way_in!
    place
  end

  # THE ROOM AT THE BOTTOM, and it is `z` again for the header's reason. Lowest
  # storey, then furthest from the way in by id order, which for a serpentine
  # layout is the far end of the deepest floor.
  def deepest_room(place)
    place.child_locations.order(:id).min_by { |child| [ child.z.to_i, -child.id ] }
  end

  # A DOOR, WRITTEN BOTH WAYS, with the labels the engine has rather than ones a
  # model picked. There is no geometry between two outermost places to derive a
  # distance from (`Location::Interior`'s two travel-time rules), so the
  # quietest true answer is the nearest one: this is a way on from the room the
  # player is standing in.
  def open_the_door!(room, place)
    [ [ room, place ], [ place, room ] ].each do |from, to|
      next if LocationConnection.exists?(location: from, connected_location: to)

      LocationConnection.create!(location: from, connected_location: to,
                                 distance: LocationConnection::DISTANCES.keys.first,
                                 travel_method: Location::Interior::WALKING)
    end
  end

  # WHAT A NEW PLACE IS CALLED WHEN THE STEP NAMED A PERSON. The arc's own
  # sentence is what the world knows about it, so that is what the teaser says
  # and the name is built off the step rather than invented.
  def holding_name(step) = "Where #{step.target_name} Is"

  def teaser_for(step) = step.teaser.presence || step.summary

  def thing_description(step) = step.teaser.presence || "#{step.target_name}. #{step.summary}"

  # THE SHEET THE ENGINE WRITES, AND IT IS THE ENGINE'S OWN WORDS.
  #
  # `Character::Registry` refuses a person with a hole in their sheet, so a row
  # cannot exist without these six -- and the deadline makes no model call, so
  # there is nobody to ask. What it has is the arc: the step's summary, its
  # teaser and the quest's premise are sentences somebody wrote ABOUT this
  # person, which is more than a placeholder and less than a character.
  #
  # PLACEHOLDER-QUALITY ON PURPOSE, and said out loud so nobody reads it as an
  # attempt at characterisation: it is `Location::Interior`'s room numbers one
  # table over -- enough for the row to exist and be talked to, honest about
  # being unwritten, and replaceable. What the player actually reads is
  # `InteractionAgent`'s answer, which is handed these lines as facts about
  # somebody the world has not filled in yet.
  def sheet_for(step)
    unwritten = "Nobody has written this down yet; the world placed #{step.target_name} because the story needed them."

    {
      "fullname" => step.target_name,
      "appearance" => step.teaser.presence || unwritten,
      "personality" => unwritten,
      "backstory" => step.quest.premise.presence || step.summary,
      "likes" => unwritten,
      "dislikes" => unwritten,
      "fears" => unwritten
    }
  end
end
