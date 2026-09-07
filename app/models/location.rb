class Location < ApplicationRecord
  belongs_to :story
  # Containment, and since the captain's second ruling of 2026-09-06 this is
  # what a PLACE is: a `Location` with children, whose children are its rooms,
  # and the party always stands in a child. A parent is a container the player
  # never occupies, which is what leaves every downstream reader untouched --
  # `Character.present_in`, `Item.lying_in` and `Scene#location` all still read
  # a room.
  #
  # WHO WRITES IT. A SEED FILE MAY, as of this slice: `WorldSeed::Loader` reads
  # a location's `parent` key and wires it after every room exists, so a
  # hand-authored world can declare an interior. `Location::Generator` still
  # does not -- it creates every stub from an exit, which says where you can
  # walk and not what is inside what -- and the interior layout generator that
  # will is slice 2 (`ta-interior-layout`). It is also the frame every number in
  # `Location::Box` is read in, so nothing may re-parent a room during a walk:
  # `EngineSweep::Invariants#geometry_unmoved` asserts that.
  #
  # NOTHING IN THE APP WRITES A RING. A place inside itself, at one hop or five,
  # is a containment graph with no outermost place -- nothing that walks it
  # upward has a stopping condition. `WorldSeed::Loader#validate_no_parent_cycles!`
  # refuses a file that writes one, and there is no other writer; a ring on the
  # records therefore came through raw SQL, and `rake game:doctor` reports it
  # (`locations_containing_each_other`) rather than this being a validation that
  # queried another row on every save. `#containment_ring` is the reader.
  belongs_to :parent_location, class_name: "Location", optional: true
  #
  # NULLIFIED rather than destroyed, the answer `has_many :characters` gives
  # three declarations down and for its reason: a thing lying in a room belongs
  # to the room, and everything that outlives the room is let go instead.
  # Destroying a place leaves its rooms parentless -- outside anything, which is
  # a state `Location` allows and `rake game:doctor` reports as
  # `location_with_a_box_and_no_parent`. Destroying them with it would cascade a
  # deletion nobody asked for; `restrict` -- which is what the foreign key does
  # on its own -- would make `rake game:delete` refuse any world with an
  # interior, and depend on the order `Story` happens to destroy its locations
  # in. Nullifying answers all three at once.
  has_many :child_locations, class_name: "Location", foreign_key: "parent_location_id", dependent: :nullify
  has_many :scenes, dependent: :destroy
  # What is lying here. An item is either in somebody's hands or in a place
  # (Item), and the ones in a place are the closed set `take` resolves
  # against -- so they belong to the durable world and go when it does.
  has_many :items, dependent: :destroy
  # Who is standing here -- the closed set `talk` resolves against
  # (`Character.present_in`). NULLIFIED rather than destroyed, which is the
  # opposite of the items above it and for a reason: a thing lying in a room
  # belongs to the room, and a person outlives the building. Destroying a
  # location leaves its cast nowhere, which is a state `Character` allows and
  # `rake game:doctor` reports.
  has_many :characters, dependent: :nullify
  has_many :playthroughs, foreign_key: :current_location_id, dependent: :nullify, inverse_of: :current_location
  # EVERY BLOW THROWN IN THIS ROOM. Destroyed with it, because
  # `playthrough_blows.location_id` is NOT NULL -- a fight happened SOMEWHERE
  # and there is no honest nullified state for a blow whose room is gone. It is
  # the same answer `has_many :scenes` gives one line up and for the same
  # reason: a room's own history goes with the room.
  has_many :blows, class_name: "Playthrough::Blow", dependent: :destroy, inverse_of: :location
  # EVERY HAZARD PAID IN THIS ROOM. Destroyed with it for `blows`' reason one
  # line up: `playthrough_tolls.location_id` is NOT NULL -- a toll was paid
  # SOMEWHERE -- and a room's own history goes with the room.
  has_many :tolls, class_name: "Playthrough::Toll", dependent: :destroy, inverse_of: :location
  has_and_belongs_to_many :connected_locations,
                          class_name: "Location",
                          join_table: "location_connections",
                          foreign_key: "location_id",
                          association_foreign_key: "connected_location_id"

  # The world's own changes that touched this place -- see WorldEvent. Declared
  # on both sides so that destroying either end clears the join rows: a Story
  # destroys its locations before its world events, and the join has a foreign
  # key on both columns.
  has_and_belongs_to_many :world_events

  has_and_belongs_to_many :inverse_connected_locations,
                          class_name: "Location",
                          join_table: "location_connections",
                          foreign_key: "connected_location_id",
                          association_foreign_key: "location_id"

  # A location is generated in two steps, so it exists in two states. A *stub*
  # is a name and a one-line teaser: it is created the moment a neighbouring
  # location names it as an exit, so "three doors lead out" always corresponds
  # to three real records the player can walk into. A *realized* location has
  # been written out in full and is what the player actually reads.
  #
  # Scopes are off because Rails would define a class method named `stub`,
  # which shadows minitest's Object#stub across every test in the suite.
  enum :detail_level, { stub: "stub", realized: "realized" },
       default: :stub, validate: true, scopes: false

  scope :stubs, -> { where(detail_level: :stub) }
  scope :realized, -> { where(detail_level: :realized) }
  # Places that move. A parameter of the world, read by WorldMechanic's
  # operations and by nothing else -- a mobile location is an ordinary location
  # in every other respect, and the thing that moves is the graph around it
  # rather than the place itself.
  scope :mobile, -> { where(mobile: true) }
  scope :anchored, -> { where(mobile: false) }

  # HOW LIKELY THIS PLACE IS TO BE BORN WITH THE WORLD'S MONSTERS IN IT, and it
  # is a key into this table rather than a number on the row --
  # `LocationConnection::DISTANCES`' shape, chosen for that shape's reason: the
  # labels are what a person writing a world reads, the numbers are what the
  # engine rolls, and a free number is a field something outside the engine
  # could fill in wrongly. Nothing in any schema or prompt asks for one.
  #
  # THE VALUE IS FACES OF A d6. When a room is realized, each person the
  # realization may write is drawn either from the universe's `peoples` or from
  # its `monstrous_races`, and this many faces of `DANGER_DIE` send that draw to
  # the bestiary (`Location::Danger`). So "uneasy" is one person in six and
  # "dangerous" is one in two.
  #
  # `deadly` IS A SEED FILE'S WORD AND THE ENGINE NEVER ROLLS IT --
  # `Location::Danger::ROLLED` is what a room born in a generated world may come
  # out as. A room where every inhabitant is a monster is a decision somebody
  # made about a world, not an accident of a die.
  #
  # THE CAPTAIN'S SEVENTH RULING, 2026-09-04 evening: *"go with your rule for
  # now. eventually I want the universe generator to provide more input into
  # this."* That standing intent -- which races are monstrous, how dangerous a
  # region is, where the lairs are -- is a later slice and deliberately not
  # here. So is monsters wandering on the story clock, which is the
  # `WorldMechanic` layer's.
  # WHAT EVERY ROOM ALREADY WRITTEN IS, and the column's default. Named rather
  # than spelt out at each reader for the reason every other key in this app is:
  # one string, one place.
  SAFE = "safe"

  DANGERS = {
    SAFE => 0,
    "uneasy" => 1,
    "dangerous" => 3,
    "deadly" => 6
  }.freeze

  # THE DIE THE ROOM'S DANGER IS THROWN AGAINST. One die, one table, one
  # comparison -- `Character::CHECK_DIE`'s shape one column over.
  DANGER_DIE = 6

  scope :dangerous, -> { where.not(danger: SAFE) }

  # WHAT A PLACE DOES TO SOMEBODY STANDING IN IT. The whole catalogue, and
  # adding an entry is adding a line here -- not a field a model gets to fill
  # in. `DANGERS`' shape one constant up and `WorldMechanic::KINDS`' doctrine
  # said for a room: a seed file supplies the KEY and the DIE, and the
  # behaviour is in Ruby where it can be read.
  #
  #   save   the ability a body rolls d20-under to get clear of it
  #          (`Character#check`, the one kernel), or NIL for a thing nobody can
  #          dodge. `save: nil` is a real hazard and not an omission: there is
  #          no dexterity against having nothing to breathe.
  #   when   the moment it is applied. `:on_arrival` is paid once, by whoever
  #          walks in, in `Playthrough::Turn#move_to` after the room is realized
  #          and after the snapshot. `:every_turn` is paid in the same step 7
  #          `Playthrough::Riposte` runs in, on the room the turn BEGAN in --
  #          so arriving somewhere is free and standing there is not, which is
  #          the shape a fight already has.
  #   words  what the engine says about it, once, in one place. The narrator is
  #          TOLD this (`Playthrough::Moment`); it does not decide it.
  #
  # NOTHING HERE IS A RULE ENGINE, deliberately: `data/ta-direction/report.md`
  # §12 rules out a predicate DSL or a general consequence table, and this is
  # not one. There are exactly two hazard branches in the app
  # (`Playthrough::Hazards`), the table is their parameters, and an entry with a
  # new `when:` would need a new branch written for it.
  HAZARDS = {
    "flooded" => { save: :strength,  when: :on_arrival, words: "the water takes your legs" },
    "unlit"   => { save: :dexterity, when: :on_arrival, words: "you go down in the dark" },
    "silent"  => { save: :will,      when: :every_turn, words: "the quiet gets into you" },
    "airless" => { save: nil,        when: :every_turn, words: "there is nothing here to breathe" }
  }.freeze

  # THE MOMENTS A HAZARD CAN BE PAID AT, and there are two because there are two
  # branches. Named so a table entry with a third one fails loudly here rather
  # than quietly never firing.
  HAZARD_MOMENTS = %i[on_arrival every_turn].freeze

  # WHAT A HAZARD MAY BE THROWN WITH. `Character::HIT_DICE`'s shape and its
  # reason: a closed list is what makes a number outside it evidence that it
  # came from somewhere that is not the engine. d4 is here and is not a hit die
  # -- nothing has a d4 body, and a room that takes a hand's width off you is
  # the commonest hazard worth writing.
  HAZARD_DICE = [ 4, 6, 8, 10 ].freeze

  scope :hazardous, -> { where.not(hazard: nil) }

  # A key outside `HAZARDS`, or half a hazard, cannot be written by anything in
  # the app. `rake game:doctor` reports what a database already carries
  # (`location_with_an_unknown_hazard`) rather than guessing which entry was
  # meant, exactly as it does for `danger`.
  validates :hazard, inclusion: { in: HAZARDS.keys }, allow_nil: true
  validates :hazard_die, inclusion: { in: HAZARD_DICE }, allow_nil: true
  validate :a_hazard_is_whole

  # A key outside `DANGERS` cannot be written by anything in the app: the four
  # labels are the whole of what a danger is, and a fifth arrived from somewhere
  # that is not the engine. `rake game:doctor` reports the row a database
  # already carries (`location_with_an_unknown_danger`) rather than this
  # guessing which of the four was meant.
  validates :danger, presence: true, inclusion: { in: DANGERS.keys }

  # HOW POPULATED THIS PLACE IS, as one of `Location::Population`'s words or as
  # nothing at all. `allow_nil` is the whole of the difference from `danger`
  # above: nil means NOBODY PICKED A WORD, which is the state the opening room,
  # every room of a laid-out interior, every seeded room whose file leaves the
  # key out and every row older than the column are all honestly in -- and the
  # engine rolls a word for those rather than reading one. `nobody` is a
  # different thing from nil and cannot be conflated with it: it is a choice the
  # engine honours. See `Location::Population`'s header and the migration's.
  validates :population, inclusion: { in: Location::Population::LABELS }, allow_nil: true

  validates :name, presence: true
  # A stub has neither yet -- that is the point of a stub. A realized location
  # without them is still broken, so the requirement holds where it matters.
  validates :description, presence: true, if: :realized?
  validates :lore, presence: true, if: :realized?

  # HOW MANY FACES OF `DANGER_DIE` SEND A NEW INHABITANT TO THE BESTIARY. Zero
  # for a room with a key `DANGERS` does not have -- the honest nothing, and the
  # reason nothing rolls off an unknown key while `rake game:doctor` reports it.
  def danger_share = DANGERS.fetch(danger, 0)

  # Whether anything born here can be one of the world's monsters at all.
  def dangerous? = danger_share.positive?

  # WHAT THIS PLACE DOES TO SOMEBODY STANDING IN IT, as the table entry rather
  # than as the key -- the one reader, so nothing else in the app fetches out of
  # `HAZARDS` and no second caller can disagree about which ability saves. Nil
  # for a room with no hazard, which is almost every room in every world, and
  # nil for a key the table does not have: `rake game:doctor` reports that row
  # and nothing rolls off it in the meantime.
  def hazard_entry = HAZARDS[hazard]

  def hazardous? = !hazard_entry.nil? && hazard_die.present?

  # Whether this room's hazard is paid at `moment`, which is one of
  # `HAZARD_MOMENTS`. False for a room with none, so the two branches in
  # `Playthrough::Hazards` each ask one question and neither has a nil check.
  def hazard_at?(moment) = hazardous? && hazard_entry.fetch(:when) == moment

  # --- the shape of the place -----------------------------------------------
  #
  # `Location::Box` owns the design in full -- the four rulings of 2026-09-06,
  # why coordinates are local to a parent, why a storey is an index, why the
  # arithmetic is integer, and why there are TWO whole shapes rather than one.
  # What is here is only what needs a record.

  # Places with an inside: a plane their children's positions are read in. This
  # is the extent alone, so it holds for the outermost place of an interior as
  # well as for a room within one.
  scope :with_a_footprint, -> { where.not(width: nil).where.not(depth: nil) }

  # Rooms that have been PLACED -- all five columns, so they sit somewhere on a
  # storey of their parent. Almost no row in any database is one, which is the
  # point of the columns being nullable.
  scope :with_a_box, -> { with_a_footprint.where.not(x: nil).where.not(y: nil).where.not(z: nil) }

  # HALF A LAYOUT IS REFUSED, as one thing, for the reason `#a_hazard_is_whole`
  # refuses half a hazard and `Character#a_stat_block_is_whole` refuses half a
  # sheet: a row carrying two of the three position columns, or a position with
  # no extent, is a column set that looks as though it said something and did
  # not, and every reader of it would have to guess at the rest.
  # `rake game:doctor` reports a row a database already carries
  # (`location_with_a_partial_box`), which is what makes a database older than
  # this validation diagnosable rather than unloadable.
  #
  # WHAT IS NOT VALIDATED HERE is everything that reads a SECOND row -- that a
  # placed room has a parent, that the parent has a footprint of its own, that
  # two siblings do not overlap. All three are real faults, all three are
  # reported by `Story::Doctor` and refused in a file by `WorldSeed::Loader`;
  # they are not validations because a validation that queries another row runs
  # on every save of every location in the app, to catch a fault only two
  # writers can commit.
  validate :a_box_is_whole
  # A ROOM WITH NO FLOOR. Zero paces across is not a small room, it is a room
  # nothing can stand in and no door can open onto -- so it is refused here
  # rather than left for slice 2's layout to divide by. `x`, `y` and `z` carry
  # no such rule on purpose: an origin and a storey index are signed, and a room
  # west of its parent's origin or a basement below it are both ordinary.
  validates :width, :depth, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :x, :y, :z, numericality: { only_integer: true }, allow_nil: true

  # This room's own five numbers as a value, or NIL for a place that is not
  # PLACED -- which includes a place carrying a footprint alone, because a
  # footprint has nowhere to be. See `Location::Box.of`.
  def box = Location::Box.of(self)

  # Whether this place has an inside at all: an extent, which is the plane its
  # children's positions are read in. TRUE FOR A FOOTPRINT AS WELL AS A BOX,
  # which is what makes it the question `Story::Doctor` asks of a parent.
  def interior? = !width.nil? && !depth.nil?

  # Whether this room sits somewhere -- all five columns. `#interior?` says the
  # place has a plane; this says it has been put on one.
  def placed? = !box.nil?

  # WHETHER THIS IS A PLACE TO BE LAID OUT INSIDE -- a row carrying a FOOTPRINT
  # and no position, which is what the outermost place of an interior carries
  # (`Location::Box`). It is the ONE question `Location::Generator` asks before
  # handing a stub to `Location::Interior`, so the whole of "which locations get
  # an inside" is this line.
  #
  # IT IS DELIBERATELY NARROW, and narrowing it is the point rather than a
  # limitation. Today only a SEED FILE writes a footprint, so today only a
  # seeded or fixture place answers true and NOTHING in a generated world
  # changes behaviour: `Location::Generator#create_stub!` writes no extent, so
  # every stub a generated world has ever had still answers false. WHICH
  # generated stubs should become places -- a tavern yes, a stretch of road no
  # -- is a decision about the Iron Gate's scope and is not made here; when it
  # is made, it is made by whatever writes the footprint, and this predicate
  # does not move.
  #
  # A ROOM IS NOT A PLACE by this predicate, because a room carries all five
  # columns and `#placed?` is true of it. So an interior does not lay out an
  # interior inside itself, which is what keeps `Location::Interior`'s guarantee
  # -- every room reachable from the entry -- a statement about one containment
  # level rather than a recursion nobody has designed.
  def place? = interior? && !placed?

  # AND WHETHER ITS INSIDE HAS BEEN BUILT -- a place that has rooms in it. It is
  # `#place?` plus the records, and it is a predicate rather than a phrase
  # repeated at each reader because THREE separate rules turn on it and all
  # three would be wrong asked of `#place?` alone:
  #
  #   * A LAID-OUT PLACE IS NEVER THE FAR END OF A DOORWAY, which is the
  #     captain's Call 5 of 2026-09-07 -- the way in lands on the entry room
  #     (`Location::Generator#open_the_way_in!`), and `Story::Doctor` reports a
  #     row that says otherwise (`connection_terminating_on_a_place`).
  #   * IT IS NOT ASKED FOR WAYS OUT, because its ways out are its rooms'
  #     (`Location::Generator#write_exits!`).
  #   * IT IS NOT SOMEWHERE A PLAYER CAN BE SEALED INTO. `Story::Doctor#exits`
  #     reports a realized room with no way out as a player who walked in and
  #     cannot walk out; nobody stands in a container, so that sentence is not
  #     true of one.
  #
  # A STUB PLACE THAT HAS NOT BEEN WALKED INTO IS NOT ONE, and that is the
  # distinction the whole predicate exists for: a footprint with no rooms is a
  # building waiting for somebody to open the door (`Story::Doctor#places_with_a_footprint_and_no_rooms`
  # says so at length), and the doorway to it is the way in, waiting.
  def laid_out? = place? && child_locations.exists?

  # THE PLACE THIS ROOM IS INSIDE, or nil for a room that is inside nothing --
  # which is every room in every flat world. It is `#place?`'s question asked
  # from the other end, and it is a reader rather than an association call
  # because `parent_location` alone is not the answer: PLAIN CONTAINMENT is a
  # parent with no layout, a district a street sits in, and a street is not "in"
  # its district the way a taproom is in an inn. Only a room the engine PLACED
  # -- a box read in that parent's own plane -- is inside a place.
  #
  # WHO READS IT: the play page, which says where the party is standing, and
  # `Location::Plan`, which tells a model which building this room is a room of.
  # Both need the room and the place separately rather than one folded into the
  # other -- what the PLAYER is shown is the captain's call, and both halves are
  # on the records either way round.
  def containing_place = placed? ? parent_location : nil

  # WHETHER THESE TWO ROOMS ARE IN THE SAME PLACE AT ONCE, and it is here rather
  # than on `Location::Box` because it is the half of the question that needs
  # records: coordinates are local to a parent, so two boxes under DIFFERENT
  # parents are read in different planes and comparing them is meaningless. It
  # answers false rather than raising, because "these two do not overlap" is the
  # honest answer for two rooms in two different buildings -- and a caller
  # sweeping every pair in a story (`Story::Doctor`) would otherwise have to
  # group them itself before it could ask.
  #
  # False for a room that has not been placed, for the same reason: a room with
  # no position is nowhere, and nowhere overlaps nothing.
  #
  # A ROOM IS ONLY ITSELF, and that is asked on IDENTITY rather than on `id`
  # alone: two rooms built and not yet saved both carry a nil id, and `nil ==
  # nil` would make a whole candidate layout one room laid on itself.
  def overlaps?(other)
    return false if parent_location_id.nil? || parent_location_id != other.parent_location_id
    return false if equal?(other) || (id.present? && id == other.id)

    mine, theirs = box, other.box
    return false if mine.nil? || theirs.nil?

    mine.overlaps?(theirs)
  end

  # THE RING OF PLACES THIS ONE IS CAUGHT IN, or NIL for the ordinary case --
  # a chain of parents that ends at a place inside nothing. A self-parent is the
  # one-hop ring and not a separate answer.
  #
  # THE WALK CARRIES WHAT IT HAS SEEN and stops at the first repeat, so a ring
  # cannot loop the reader that is looking for it -- which is the whole hazard of
  # asking this question at all. What comes back is the ring itself and not the
  # tail that led into it: the places from the first repeat onward, so two rooms
  # hanging off one ring answer with the same ring and a caller can report it
  # once.
  def containment_ring
    seen = []
    walker = self

    while walker
      return seen.drop(seen.index(walker)) if seen.include?(walker)

      seen << walker
      walker = walker.parent_location
    end

    nil
  end

  # The places you can walk to from here. Connections are stored directionally
  # but written in both directions when a location is realized, so this one
  # association is the whole exit list.
  def exits
    connected_locations
  end

  # How long the protagonist has been away, IN STORY TIME.
  #
  # `last_protagonist_visit` holds a moment on `Story#clock`, not a wall clock,
  # and that is the whole of the fix for the defect this used to have: it read
  # `Time.current - last_protagonist_visit`, so a player who closed the tab for
  # a week and came back was told in fiction that they had been gone a week.
  # Nothing about a story's own passage of time has anything to do with when
  # somebody had a browser open.
  #
  # `now` defaults to the story's clock so any caller gets the right answer
  # without knowing that; `Scene::Generator` passes the arrival's own story
  # timestamp instead, because an arrival happens at the end of the journey
  # rather than at the moment the turn started.
  def time_since_last_visit(now = story.clock)
    return nil unless last_protagonist_visit
    return nil if now.nil?

    now - last_protagonist_visit
  end

  # `at` is story time, and it is required rather than defaulted for the reason
  # above: every caller knows which story moment the protagonist arrived at, and
  # a default would quietly reintroduce the wall clock.
  def mark_protagonist_visit!(at)
    update!(last_protagonist_visit: at)
  end

  private

  # See `validate :a_box_is_whole` above for why this is one rule over five
  # columns rather than five rules, and `Location::Box.shape` for the three
  # whole answers it is holding this row to.
  def a_box_is_whole
    return unless Location::Box.partial?(self)

    written = Location::Box::COLUMNS.select { |column| self[column].present? }
    errors.add(:base, "carries #{written.join(", ")}, which is neither a footprint " \
                      "(#{Location::Box::EXTENT.join(", ")}), nor a box (all of " \
                      "#{Location::Box::COLUMNS.join(", ")}), nor nothing at all")
  end

  # HALF A HAZARD IS REFUSED, and it is refused as ONE thing for the reason
  # `Character#a_stat_block_is_whole` refuses half a sheet: the key says what
  # happens and the die says how much, and a row carrying one of them is a
  # column that looks as though it said something and did not. `Location::Hazard`
  # would roll nothing off it and the room would silently be safe.
  def a_hazard_is_whole
    return if hazard.blank? == hazard_die.blank?

    errors.add(:hazard, "and hazard_die go together: a hazard is a key and a die, or it is neither")
  end
end
