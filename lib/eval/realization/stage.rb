# THE MOMENT A ROOM WAS ABOUT TO BE WRITTEN, REBUILT FROM A SEED FILE.
#
# A realization prompt is almost entirely made of the world AROUND the room:
# the universe, the story's preface and summary, every place that already
# exists and which of them have been written, every name already spoken for,
# what this room can already reach, and how many people and things the
# registries will still admit. So a case that stored its own copy of those would
# be measuring a prompt the app does not build -- the same argument
# `Eval::Prompt::Corpus` makes for staging a position instead of writing the
# facts down. A case therefore names a WORLD and a ROOM IN IT, and this class
# puts the world back and winds that room back to the moment before it was
# written.
#
# THE THREE GUARANTEES ARE `Eval::Classifier::Stage`'S, and they are the reason
# this can be pointed at a machine somebody has been playing on:
#
#   1. ITS OWN COPY OF THE WORLD, loaded under a title of this class's own and
#      inside a transaction that is rolled back. Nothing outside the run is read
#      for the prompt, moved, or deleted -- including the surgery below, which
#      is what makes it safe to describe as deleting rooms.
#   2. NO MODEL CALL TO GET INTO POSITION. The whole of the setup is a seed load
#      and row surgery. The ONLY calls a case makes are the two being measured.
#   3. THE WORLD DOES NOT MOVE UNDERNEATH IT. No `Scene` is written and no turn
#      is played, so `WorldMechanic` never runs and the doorways are the ones
#      the file lists -- which is why this bench can build rooms in
#      `The Lunar Cartographer`, the world `Eval::Prompt::STORIES` has to
#      refuse. See `Eval::Realization::STORIES`.
#
# AND THE TITLE IS PUT BACK, always, for `Eval::Classifier::Stage`'s reason one
# step stronger: `Location::Generator#story_context` states the story's TITLE,
# its genre, its preface and its summary in the detail prompt, so a run staged
# on `The Salt Assizes (realization bench: vestry)` would be measuring a prompt
# no player ever gets -- and inviting the model to write the words "realization
# bench" into a room's lore.
#
# THE SURGERY, AND WHY IT IS DECLARED RATHER THAN DERIVED. Winding a room back
# means knowing which of its edges it wrote itself and which rooms did not exist
# yet, and NEITHER IS RECOVERABLE FROM THE RECORDS: connections carry no
# timestamp, and a room's `created_at` says when the row appeared and not what
# the world looked like around it. An earlier draft of this class tried to infer
# it from id order and produced a state that never existed. So the case says it,
# in the keys below, each one checked against the file by
# `Eval::Realization::Corpus`:
#
#   `room`          the stub to build. Wound back to a stub: no description, no
#                   lore, nothing lying in it.
#   `reached_from`  the ONE neighbour whose own realization created this stub,
#                   which is the way back. Absent for an opening room, which has
#                   none.
#   `also_reaches`  the other neighbours this stub could ALREADY reach, and the
#                   default is none. A room realized by being walked into has
#                   exactly one edge, so an ordinary case declares nothing here
#                   and every edge but the way back is removed. A SEEDED stub
#                   can legitimately have more -- a lane laid down with the
#                   circle at the end of it -- and those cases are the only
#                   place `exit_already_reachable` and `exit_over_the_allowance`
#                   meet a room with more than one way out and an allowance
#                   below the cap. Declared rather than kept-by-default for the
#                   reason the whole of this surgery is declared: which edges a
#                   stub really had is not recoverable from the records, so a
#                   case that wants them says so and the validator checks each
#                   one is really an edge.
#   `absent`        rooms that did not exist at this moment -- destroyed, so
#                   they are not in the "places that already exist" list and not
#                   in the taken names.
#   `unwritten`     rooms that existed but had not been written -- wound back to
#                   stubs, so the prompt does not mark them "already written --
#                   do not open a new way into it". This one changes what a
#                   correct answer IS, which is why it is a key and not a
#                   guess.
#
# WHAT IS DELIBERATELY LEFT ALONE: anybody standing in the room. A stub may
# legitimately have somebody in it -- a seed file places them -- and a person
# already here takes up one of `Character::Registry::MAX_PER_ROOM`'s slots and
# puts their name in the "already spoken for" list. Both of those are states the
# generator really meets, and removing the cast to tidy the case up would remove
# the two most interesting things about it.
class Eval::Realization::Stage
  # ONE COPY OF THE WORLD PER CASE, and the case's id is in the title because
  # that is what makes them separate copies. `WorldSeed::Loader` is idempotent
  # on the story TITLE, so two cases cut from one file under one title would be
  # two views of ONE world -- and this class DELETES ROOMS, so one case's
  # surgery would be performed on every other case's world.
  LABEL = "realization bench".freeze

  def self.title_for(kase, label: LABEL) = "#{kase.story} (#{label}: #{kase.id})"

  class Unstageable < StandardError; end

  # A STUB, STOOD UP, WITH THE FACTS THE PROMPT WILL BE BUILT FROM READ BACK OFF
  # THE RECORDS.
  #
  # It holds the `Location::Generator` rather than building one per reader, and
  # that is load-bearing rather than tidy: the generator memoizes
  # `Character::Registry#slots`, which ROLLS the race, age and sex of everybody
  # this call may name and states them in the prompt. A second generator would
  # roll a second set, and the facts stored beside the answer would describe
  # different people from the ones the model was asked for.
  Standing = Data.define(:kase, :story, :location, :generator) do
    def cast_registry = generator.cast_registry
    def item_registry = generator.registry

    def people_allowance = cast_registry.allowance
    def item_allowance = [ item_registry.room_for_items, item_registry.world_for_items ].min
    def exit_allowance = generator.room_for_exits

    # WHO THE ENGINE HAS ALREADY DECIDED THE NEXT PEOPLE ARE, exactly as the
    # prompt states them, and whether each was drawn from the world's monsters.
    # Read through the registry's own memoized `#slots`, so this is the list the
    # prompt was built from and not a second roll.
    def slots
      cast_registry.slots.first(people_allowance).map do |details|
        race = details[:race]
        { "race" => race&.name, "monstrous" => !!race&.monstrous?,
          "age" => details[:age], "sex" => details[:sex] }
      end
    end

    # THE PLACES THE EXITS PROMPT OFFERS, with the two facts that decide whether
    # naming one is a correct answer: whether it has been WRITTEN, and whether
    # this room can already reach it. A written place this room cannot reach is
    # the one the prompt tells the model to leave out and the engine refuses
    # anyway (`Location::Generator#connect_exit!`).
    def places
      story.locations.where.not(id: location.id).order(:id).map do |place|
        { "name" => place.name, "realized" => place.realized?, "connected" => connected?(place) }
      end
    end

    def reachable = location.exits.order(:id).pluck(:name)

    # THE ROOM'S OWN FLOOR PLAN AS RECORDS, or nil for a room that is not inside
    # a laid-out place -- which is every room in every flat world. It is the
    # same `Location::Plan` the detail prompt is built from, asked once here so
    # the checker and the prompt cannot be reading two derivations of one
    # building (`Eval::Realization::Scorer#judge_door_the_records_do_not_hold`).
    def plan = Location::Plan.for(location)&.to_h

    # THE NAMES THE PROMPT SAYS ARE SPOKEN FOR, read the way the prompt reads
    # them -- `Location::Generator#known_names_note` truncates to twenty of each,
    # and a checker that used the untruncated list would flag the model for
    # reusing a name it was never shown.
    def taken_names
      (story.characters.order(:id).limit(20).pluck(:fullname) +
        item_registry.story_items.order(:id).limit(20).pluck(:name)).compact_blank
    end

    # EVERY NAME IN THE WORLD, truncation and all. What the REGISTRIES check a
    # proposal against, which is not the same list as the one above -- and the
    # difference between the two is a defect the model cannot be blamed for and
    # the room pays for anyway.
    def all_names
      { "people" => story.characters.pluck(:fullname, :nickname).flatten.compact_blank,
        "places" => story.locations.pluck(:name),
        "things" => Item.in_story(story).pluck(:name).uniq }
    end

    def to_s
      format("%s / %s (%s) -- back to [%s], %d people, %d things, %d ways out",
             story.title, location.name, location.danger, reachable.join(", "),
             people_allowance, item_allowance, exit_allowance)
    end

    private

    def connected?(place)
      LocationConnection.exists?(location: location, connected_location: place) ||
        LocationConnection.exists?(location: place, connected_location: location)
    end
  end

  # Stages every case named and yields them all at once, inside ONE rolled-back
  # transaction, and RETURNS WHAT THE BLOCK RETURNED.
  #
  # `Eval::Concurrency.rolled_back` and NOT `ActiveRecord::Base.transaction`:
  # read that module's header before changing this line. The short of it is that
  # `within_new_transaction` holds the connection lock for its whole block, and
  # the rollback here is a direct `unpin_connection!` that raises nothing -- so a
  # real exception still travels out of here with the transaction rolled back on
  # its way.
  def self.open(cases, label: LABEL, &block)
    Eval::Concurrency.rolled_back do
      block.call(cases.to_h { |kase| [ kase.id, new(kase, label: label).stand! ] })
    end
  end

  attr_reader :kase

  def initialize(kase, label: LABEL)
    @kase = kase
    @label = label
  end

  def stand!
    story = load_world!
    remove_the_absent!(story)
    unwrite!(story)
    stub = wind_back!(story)

    Standing.new(kase: kase, story: story, location: stub, generator: Location::Generator.new(stub))
  end

  private

  def load_world!
    file = Eval::Realization.world_file(kase.story)
    if file.nil?
      raise Unstageable, "#{kase.id}: there is no world file for #{kase.story.inspect} under " \
                         "#{Eval::Realization::WORLD_ROOTS.join(" or ")}"
    end

    document = WorldSeed.parse(File.read(file))
    document["story"]["title"] = self.class.title_for(kase, label: @label)
    story = WorldSeed::Loader.new(document, source: file.to_s).load!
    # FOUND BY ITS OWN TITLE, THEN CARRYING THE WORLD'S. The rename is inside
    # the transaction that is rolled back, so nothing outside this run ever sees
    # either title -- and the prompt gets the title a player would see.
    story.update!(title: kase.story)
    story
  end

  # ROOMS THAT DID NOT EXIST YET, removed. The connections go first and
  # explicitly: `Location`'s edges are a `has_and_belongs_to_many` join, and
  # leaving the join rows to a callback is the kind of thing that works until
  # somebody changes the association.
  def remove_the_absent!(story)
    kase.absent.each do |name|
      room = find_room!(story, name, "absent")
      if room == story.opening_location
        raise Unstageable, "#{kase.id}: #{name.inspect} is where the story opens, so it existed before " \
                           "anything else in this world did"
      end

      LocationConnection.where(location: room).delete_all
      LocationConnection.where(connected_location: room).delete_all
      room.destroy!
    end
  end

  # ROOMS THAT EXISTED BUT HAD NOT BEEN WRITTEN. Their edges and their contents
  # stay: a stub reached from two places is an ordinary stub, and a seed file's
  # items belong to the world rather than to the writing of the room.
  def unwrite!(story)
    kase.unwritten.each do |name|
      room = find_room!(story, name, "unwritten")
      raise Unstageable, "#{kase.id}: #{name.inspect} is the room this case builds" if room.name == kase.room

      room.update!(description: nil, lore: nil, detail_level: :stub)
    end
  end

  # THE ROOM ITSELF, WOUND BACK TO THE STUB IT WAS. No description, no lore,
  # nothing lying in it, and the way in -- plus whatever else the case declared
  # this stub could already reach.
  #
  # AN INTERIOR ROOM KEEPS EVERY EDGE IT HAS, and that is not an exception to
  # the winding back but the whole of what winding back means, applied to a room
  # whose doors nobody wrote. Every other stub's edges arrived WITH its
  # realization -- a neighbour named it, and the case declares which -- so
  # dropping them is putting the world back. The doors and stairs of a room
  # inside a laid-out place were all decided before it, in one call, from
  # geometry (`Location::Interior`), and `Location::Generator#write_exits!` will
  # ask a model for none of them. Dropping one would stage a room the layout
  # never wrote, hand `Location::Plan` a floor plan with a wall missing out of
  # it, and measure a prompt the app cannot build.
  def wind_back!(story)
    room = find_room!(story, kase.room, "room")

    keep = kase.reached_from.presence && find_room!(story, kase.reached_from, "reached_from")
    if keep && !edge?(room, keep)
      raise Unstageable, "#{kase.id}: #{kase.room.inspect} and #{kase.reached_from.inspect} are not " \
                         "connected in this world, so that is not the way this room was reached"
    end

    # ASKED FOR ITS RAISE AND NOT FOR ITS RETURN VALUE ON AN INTERIOR ROOM, which
    # is why it is hoisted above the guard. Nothing of this room's is dropped,
    # but a case declaring an `also_reaches` the world does not have is still
    # the failure that key exists to make impossible -- and a validation that
    # only runs on some case shapes is not one.
    reached = already_reached(story, room)

    drop_edges_except!(room, [ keep, *reached ].compact) unless interior_room?(room)
    room.items.destroy_all
    room.update!(description: nil, lore: nil, detail_level: :stub, danger: kase.danger.presence || room.danger)
    room.reload
  end

  # THE NEIGHBOURS A CASE DECLARED THIS STUB ALREADY REACHED, each checked to be
  # a real edge -- a case that claimed one the world does not have would stage a
  # room with fewer ways out than its own `why` describes, which is the failure
  # this key exists to make impossible.
  def already_reached(story, room)
    kase.also_reaches.map do |name|
      other = find_room!(story, name, "also_reaches")
      if other == room
        raise Unstageable, "#{kase.id}: #{name.inspect} is the room this case builds, so it cannot " \
                           "also be somewhere the room already reaches"
      end
      unless edge?(room, other)
        raise Unstageable, "#{kase.id}: #{kase.room.inspect} and #{name.inspect} are not connected in " \
                           "this world, so this stub could not already reach it"
      end

      other
    end
  end

  # WHETHER THIS IS A ROOM INSIDE A LAID-OUT PLACE, asked exactly as
  # `Location::Generator#interior_room?` asks it -- both halves, a box read in a
  # parent's own plane -- because it is the same question and a second answer
  # here would be a second thing to keep in step with the generator.
  def interior_room?(room) = room.placed? && room.parent_location_id.present?

  def drop_edges_except!(room, keep)
    scope = LocationConnection.where(location: room).or(LocationConnection.where(connected_location: room))
    keep.each { |other| scope = scope.where.not(location: other).where.not(connected_location: other) }
    scope.delete_all
  end

  def edge?(room, other)
    LocationConnection.exists?(location: room, connected_location: other) ||
      LocationConnection.exists?(location: other, connected_location: room)
  end

  def find_room!(story, name, key)
    room = story.locations.find_by(name: name)
    raise Unstageable, "#{kase.id}: #{kase.story.inspect} has no room called #{name.inspect} (#{key})" if room.nil?

    room
  end
end
