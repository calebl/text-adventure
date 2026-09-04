# Loads a checked-in world into the database. Offline and idempotent: no model
# call, no API key, no network, and running it twice leaves exactly what running
# it once left.
#
# Idempotency is on natural keys, never on `id` -- ids differ on every load:
#
#   Story      title                     (the file's identity; keep them unique)
#   Universe   the story's universe      (the table has no natural key of its own)
#   Race       (universe, name)          unique index
#   Character  (story, fullname)         unique index
#   Location   (story, name)             case-insensitively, matching
#                                        Location::Generator#find_location
#   Connection (location, connected)     unique index, written both ways
#   Item       (story, name)             NOT (owner, name): an item moves, and a
#                                        world that has been played has items
#                                        somewhere other than where the file
#                                        puts them. Keying on the owner would
#                                        re-seed a dropped daybook as a second
#                                        daybook; keying on the story finds the
#                                        one that exists and puts it back.
#   Scene      (story, is_opening)       the story's one opening arrival, which
#                                        is the only Scene that is world rather
#                                        than progress -- see WorldSeed::Exporter
#   Mechanic   (story, name)             unique index; a world's own laws are
#                                        world data, so they are seeded with it
#
# The loader adds and updates; it does not delete rows the file no longer
# mentions. So renaming a location in the file and re-seeding leaves the old one
# behind -- drop the database for a clean rebuild.
class WorldSeed::Loader
  class InvalidWorld < StandardError; end

  attr_reader :document, :source

  def self.load_all(io: $stdout)
    WorldSeed.files.map do |path|
      story = load_file(path)
      io&.puts "Seeded world #{story.title.inspect} (story ##{story.id}, #{story.locations.count} locations, #{story.characters.count} characters)"
      story
    end
  end

  def self.load_file(path)
    new(WorldSeed.parse(File.read(path)), source: path).load!
  end

  def initialize(document, source: nil)
    @document = document
    @source = source
  end

  # Returns the Story. Everything happens in one transaction, so a file that
  # fails validation half way through leaves no partial world behind.
  def load!
    validate!

    Story.transaction do
      universe = load_universe!
      story = load_story!(universe)
      locations = load_locations!(story)
      load_connections!(locations)
      load_characters!(story, universe)
      load_mechanics!(story)
      # Last, because it names a location AND a cast by natural key and both
      # have to exist first. It is written near the top of the FILE, where
      # somebody editing the prose will find it; load order and key order are
      # not the same thing.
      load_opening_scene!(story, locations)
      story
    end
  end

  private

  def load_universe!
    universe = existing_story&.universe || Universe.new
    universe.assign_attributes(universe_document.except("races"))

    universe_document.fetch("races").each do |attributes|
      race = universe.races.detect { |candidate| candidate.name == attributes.fetch("name") } ||
             universe.races.build(name: attributes.fetch("name"))
      race.description = attributes.fetch("description")
    end

    universe.save!
    universe
  end

  def load_story!(universe)
    story = existing_story || universe.stories.new
    story.assign_attributes(story_document)
    story.save!
    story
  end

  # The opening location is created first because Story#opening_location is the
  # story's lowest-id location. A file whose opening room is a stub would load
  # into a story the browser refuses to start, so that is rejected in #validate!.
  def load_locations!(story)
    location_documents.to_h do |attributes|
      name = attributes.fetch("name")
      location = find_location(story, name) || story.locations.new(name: name)
      location.assign_attributes(attributes.except("name", "opening", "items"))
      location.save!
      load_items!(story, attributes["items"], character: nil, location: location)

      [ name, location ]
    end
  end

  # Both directions, from one entry. See WorldSeed::Exporter's comment on why
  # the file holds an unordered pair.
  def load_connections!(locations)
    connection_documents.each do |attributes|
      from, to = attributes.fetch("between").map { |name| locations.fetch(name) }
      values = attributes.slice("distance", "travel_method")

      [ [ from, to ], [ to, from ] ].each do |(origin, destination)|
        connection = LocationConnection.find_or_initialize_by(location: origin, connected_location: destination)
        connection.assign_attributes(values)
        connection.save!
      end
    end
  end

  # WHERE THE FILE PUTS THEM, and `location` is the key that carries it.
  #
  # A world's cast is world data exactly as its items are, so the file is the
  # writer: `Character.present_in` is the closed set `talk` resolves against,
  # and until it had a source a seeded world's people existed nowhere and could
  # only be spoken to in whichever room the opening arrival's cast happened to
  # name. The Salt Assizes is the case that named it -- its premise is Neb
  # Halloran chained to the tide post, and nothing recorded him there.
  #
  # THE KEY IS OPTIONAL AND AN ABSENT ONE MEANS NOWHERE, which is a real state
  # and is left alone rather than guessed at: `rake game:doctor` reports a
  # seeded character the file did not place.
  #
  # `absent: true` IS THE FILE SAYING IT MEANT THAT. A missing key still means
  # "nobody has said where they are" and is still reported; the marker says
  # "nowhere, and that is the story", which is what `The Unrecorded Hour` has
  # always meant about Perrin Lasco. It writes `characters.deliberately_absent`
  # and `#validate!` refuses the pair with a `location`, because a file cannot
  # mean both. Written on every load in both directions -- `absent: true` sets
  # it, an absent key clears it -- so deleting the marker from the file and
  # re-seeding takes it off the record, exactly as the placements, the
  # connections and the items re-assert themselves over a played world.
  #
  # It is written straight rather than
  # through `Character::Registry` for the same reason the items above it are
  # written straight -- a seed file IS the decision, so the registry's "do not
  # move somebody who is already somewhere" rule would make re-seeding unable
  # to put a played world's cast back where the file says they belong. That is
  # the same "the file re-asserts itself over a played world" rule the
  # connections and the items already follow.
  def load_characters!(story, universe)
    character_documents.each do |attributes|
      race = universe.races.detect { |candidate| candidate.name == attributes.fetch("race") }
      character = story.characters.find_by("LOWER(fullname) = ?", attributes.fetch("fullname").downcase) ||
                  story.characters.new(fullname: attributes.fetch("fullname"))
      where = attributes["location"].presence && find_location(story, attributes["location"])

      character.assign_attributes(
        attributes.except("race", "items", "location", "absent")
                  .merge(race: race, location: where, deliberately_absent: attributes["absent"] == true)
      )
      character.save!

      load_items!(story, attributes["items"], character: character, location: nil)
    end
  end

  # THE THINGS IN THE WORLD, on whichever side of `Item`'s one-place rule they
  # sit: `place` is `character:` for something somebody is holding and
  # `location:` for something lying in a room, and the other half is written nil
  # so that re-seeding cannot leave an item in two places at once.
  #
  # A PROTAGONIST'S ITEMS ARE THE STORY'S STARTING INVENTORY. They stay held by
  # the protagonist row, carried by nobody, and every playthrough of the world
  # begins with a COPY of each -- `Story#starting_inventory` and
  # `Playthrough#take_up_the_starting_inventory` have the argument. So the file
  # keeps writing exactly what it wrote before and the meaning of the row is
  # what changed: world data rather than one shared pair of hands.
  #
  # Items under a LOCATION are what a HAND-WRITTEN world carries so that
  # anything in it is takeable. A generated room furnishes itself now
  # (`Item::Registry`, written at realization), so this is no longer the only
  # way a thing gets onto a floor -- but a seeded room is realized by the file
  # rather than by a model call, so what is lying in one is whatever the file
  # says and nothing else. The registry leaves seeded rooms alone.
  #
  # MATCHED ON (story, name), NOT ON THE OWNER, because an item is the one thing
  # in these files that MOVES: `Playthrough::Turn#carry!` and `#put_down!` write
  # `items.playthrough_id` and `items.location_id` on every take and drop.
  # Keying on the owner would look for the daybook in the hands the file puts it
  # in, not find it because the player left it on a shelf, and seed a second one.
  # Keying on the story finds the one that exists and puts it back where the
  # file says it belongs -- the same "the file re-asserts itself over a played
  # world" rule the connections already follow.
  # `playthrough: nil` is written on every leg for the reason the callers write
  # the other one: `Item` is in exactly one of three places, and re-seeding a
  # world somebody is playing finds room items in a party's hands. Leaving the
  # column set would save a row that is in two places at once, which `Item`
  # refuses.
  def load_items!(story, documents, **place)
    Array(documents).each do |attributes|
      name = attributes.fetch("name")
      item = find_item(story, name) || Item.new(name: name)
      item.assign_attributes(attributes.except("name").merge(playthrough: nil, **place))
      item.save!
    end
  end

  # An item of this story by name: held by one of its people, lying anywhere in
  # it, or -- last -- carried by a party playing it.
  #
  # THE WORLD'S OWN ROWS COME FIRST AND THAT ORDER IS THE POINT. A protagonist
  # item in one of these files is the story's STARTING INVENTORY, and every
  # playthrough carries a copy of it (`Playthrough#carried`). Finding a copy
  # would re-assert the file onto one player's row and take the daybook out of
  # their hands, while the world's own starting inventory stayed wherever it
  # was. The carried leg is still searched, because a ROOM item a player is
  # holding right now is on `playthrough_id` and re-seeding has always put such
  # a thing back where the file says it belongs.
  def find_item(story, name)
    by_name = Item.where(name: name)

    by_name.where(character_id: story.characters.select(:id))
           .or(by_name.where(location_id: story.locations.select(:id)))
           .first ||
      by_name.where(playthrough_id: story.playthroughs.select(:id)).first
  end

  # A world's own laws: which fixed Ruby operation runs on which cadence, and the
  # in-fiction reason. `kind` and `cadence` are keys into `WorldMechanic::KINDS`
  # and `::CADENCES`, so the file supplies parameters and never behaviour --
  # which places move is `locations[].mobile`, loaded with the locations above.
  #
  # `last_run_at` is deliberately absent from the file. It is a mechanic's
  # progress through a story, not part of the world, and a seeded `last_run_at`
  # would tell a fresh database that nights it has never played had already
  # happened.
  def load_mechanics!(story)
    mechanic_documents.each do |attributes|
      name = attributes.fetch("name")
      mechanic = story.world_mechanics.find_by(name: name) || story.world_mechanics.new(name: name)
      mechanic.assign_attributes(attributes.except("name"))
      mechanic.save!
    end
  end

  # The story's opening arrival: the moment the player is standing in when they
  # start, narrated once at world-building time so nobody waits on a model call
  # for the first screen of the game.
  #
  # Matched on `(story, is_opening)` -- a Scene has no natural key of its own and
  # a story has exactly one opening, which Scene validates. `story_timestamp`
  # comes from the story's `start_time` rather than from the file: the opening
  # arrival happens at the moment the story begins, by definition.
  #
  # Creating it does NOT stamp `Location#last_protagonist_visit` (Scene skips the
  # after_create for an opening). Seeding a world is not somebody standing in a
  # room; `PlaythroughsController#create` stamps it when a player actually
  # arrives, and without that skip the first walk back into the opening room
  # would be narrated as a return after however long the file had been on disk.
  def load_opening_scene!(story, locations)
    attributes = opening_scene_document

    scene = story.scenes.find_by(is_opening: true) || story.scenes.new(is_opening: true)
    scene.assign_attributes(
      location: locations.fetch(attributes.fetch("location")),
      description: attributes.fetch("description"),
      summary: attributes["summary"],
      story_timestamp: story.start_time
    )
    scene.characters = Array(attributes["characters"]).map do |fullname|
      story.characters.find_by("LOWER(fullname) = ?", fullname.downcase)
    end
    scene.save!

    # The caller keeps this Story object and reads straight back out of it --
    # `rake game:export` on a freshly loaded world does exactly that -- so the
    # has_one has to see the row just written rather than the nil it would have
    # cached on the way in.
    story.association(:opening_scene).reload
    scene
  end

  # Everything checked here is a mistake a hand-edit can make. The point is to
  # name the mistake rather than let it surface as a validation error three
  # records later, or -- worse -- as a world that loads and cannot be played.
  def validate!
    format = document["format"]
    raise InvalidWorld, "#{where}: unknown format #{format.inspect}; this loader understands #{WorldSeed::FORMAT}" unless format == WorldSeed::FORMAT

    openings = location_documents.select { |attributes| attributes["opening"] }
    raise InvalidWorld, "#{where}: exactly one location must be marked `opening: true` (found #{openings.size})" unless openings.one?
    raise InvalidWorld, "#{where}: the opening location #{openings.first.fetch("name").inspect} must be realized, or the story cannot be played" unless openings.first["detail_level"] == "realized"

    names = location_documents.map { |attributes| attributes.fetch("name") }
    duplicates = names.group_by { |name| name.downcase }.select { |_, group| group.size > 1 }.keys
    raise InvalidWorld, "#{where}: duplicate location names: #{duplicates.join(", ")}" if duplicates.any?

    item_names = (character_documents + location_documents).flat_map { |attributes| Array(attributes["items"]).map { |item| item.fetch("name") } }
    duplicates = item_names.group_by { |name| name.downcase }.select { |_, group| group.size > 1 }.keys
    raise InvalidWorld, "#{where}: duplicate item names: #{duplicates.join(", ")} -- an item is matched on (story, name), so two of a name are one item" if duplicates.any?

    validate_inscriptions!

    connection_documents.each do |attributes|
      pair = Array(attributes["between"])
      raise InvalidWorld, "#{where}: a connection needs `between: [a, b]`, got #{pair.inspect}" unless pair.size == 2
      unknown = pair - names
      raise InvalidWorld, "#{where}: connection #{pair.join(" <-> ")} names a location the file does not declare: #{unknown.join(", ")}" if unknown.any?
    end

    race_names = universe_document.fetch("races").map { |attributes| attributes.fetch("name") }
    character_documents.each do |attributes|
      race = attributes.fetch("race")
      raise InvalidWorld, "#{where}: character #{attributes.fetch("fullname").inspect} has race #{race.inspect}, which this universe does not have" unless race_names.include?(race)

      # A whereabouts pointing at a room the file does not declare is the one
      # mistake this key can make, and it is silent: the character loads with
      # no location and the room they were meant to be standing in is empty.
      # `location` is deliberately not required -- nowhere is a real state and
      # `rake game:doctor` reports it -- so only a WRONG name is refused.
      standing = attributes["location"]

      # NOWHERE ON PURPOSE AND STANDING IN A ROOM is a file that means both
      # things at once, and the record cannot hold both -- `absent: true` is an
      # assertion that nobody can be offered this person to talk to, and a
      # `location` is an assertion that they are in the closed set for that
      # room. Refused here rather than resolved, because which one the author
      # meant is not derivable.
      if attributes["absent"] == true && standing.present?
        raise InvalidWorld, "#{where}: character #{attributes.fetch("fullname").inspect} is `absent: true` and also placed in " \
                            "#{standing.inspect} -- `absent` means nowhere on purpose, so the two cannot both be true"
      end

      next if standing.blank? || names.any? { |name| name.casecmp?(standing) }

      raise InvalidWorld, "#{where}: character #{attributes.fetch("fullname").inspect} is placed in #{standing.inspect}, " \
                          "which this file does not declare as a location"
    end

    validate_opening_scene!(names, openings.first.fetch("name"))
    validate_mechanics!
  end

  # WORDS ON A THING WITH NOTHING WRITTEN ON IT, caught here rather than three
  # records later. `Item` validates the same pair inside the transaction, so a
  # file with the fault never loads either way -- but the record's error names a
  # column and this one names the file and the item, which is what somebody
  # editing YAML needs. Same reason the mechanics are checked here.
  def validate_inscriptions!
    (character_documents + location_documents).each do |owner|
      Array(owner["items"]).each do |item|
        next if item["inscription"].blank? || item["readable"] == true

        raise InvalidWorld,
              "#{where}: item #{item.fetch("name").inspect} has an `inscription` and is not `readable: true` -- " \
              "an inscription is the words on a thing that has writing on it, so the two go together"
      end
    end
  end

  # A mechanic that cannot run is the worst kind of seed-file typo: the world
  # loads, the game plays, and the thing the file says happens every night never
  # happens. So the parameters are checked against the fixed tables in code, and
  # a `shuffle_connections` is checked against the graph the file actually
  # declares -- it needs at least two edges joining a `mobile` location to one
  # that is not, because it repoints one endpoint of each and there has to be
  # something to swap.
  def validate_mechanics!
    names = mechanic_documents.map { |attributes| attributes["name"] }
    raise InvalidWorld, "#{where}: every mechanic needs a `name` -- it is the key re-seeding matches on" if names.any?(&:blank?)

    duplicates = names.group_by(&:itself).select { |_, group| group.size > 1 }.keys
    raise InvalidWorld, "#{where}: duplicate mechanic names: #{duplicates.join(", ")}" if duplicates.any?

    mechanic_documents.each do |attributes|
      name = attributes.fetch("name")
      kind = attributes["kind"]
      cadence = attributes["cadence"]

      raise InvalidWorld, "#{where}: mechanic #{name.inspect} has kind #{kind.inspect}; the catalogue is #{WorldMechanic::KINDS.keys.join(", ")}" unless WorldMechanic::KINDS.key?(kind)
      raise InvalidWorld, "#{where}: mechanic #{name.inspect} has cadence #{cadence.inspect}; the cadences are #{WorldMechanic::CADENCES.keys.join(", ")}" unless WorldMechanic::CADENCES.key?(cadence)

      next unless kind == "shuffle_connections"
      next if shufflable_edge_count >= 2

      raise InvalidWorld, "#{where}: mechanic #{name.inspect} shuffles connections, but the file declares " \
                          "#{shufflable_edge_count} connection(s) between a `mobile: true` location and one that is not. " \
                          "It needs at least two, or nothing can move."
    end
  end

  # Counted from the FILE rather than from the database, so a hand edit is
  # caught before it loads. Edges with two mobile ends are not shufflable and
  # that is deliberate: a building whose rooms are all mobile travels as one
  # piece with its own doors intact.
  def shufflable_edge_count
    @shufflable_edge_count ||= begin
      mobile = location_documents.select { |attributes| attributes["mobile"] }.map { |attributes| attributes.fetch("name") }.to_set

      connection_documents.count do |attributes|
        pair = Array(attributes["between"])
        pair.count { |name| mobile.include?(name) } == 1
      end
    end
  end

  # A format 2 world carries its own opening arrival, and it is required rather
  # than optional on purpose: without one the first thing a player reads is the
  # opening room's own description standing in for an arrival nobody narrated,
  # and no scene records anybody in the room, so there is nobody in a freshly
  # seeded world to talk to. Both are the defects this key exists to close, and
  # a key that is usually there closes neither.
  def validate_opening_scene!(location_names, opening_location_name)
    scene = document["opening_scene"]
    raise InvalidWorld, "#{where}: a world needs an `opening_scene` -- the narrated moment the story starts in" if scene.blank?

    location = scene["location"]
    raise InvalidWorld, "#{where}: the opening_scene names location #{location.inspect}, which this file does not declare" unless location_names.include?(location)
    raise InvalidWorld, "#{where}: the opening_scene is in #{location.inspect} but the story opens in #{opening_location_name.inspect}; the player reads it standing in the opening location" unless location == opening_location_name
    raise InvalidWorld, "#{where}: the opening_scene needs a `description` -- it is what the player reads first" if scene["description"].blank?

    cast = Array(scene["characters"])
    known = character_documents.map { |attributes| attributes.fetch("fullname") }
    unknown = cast - known
    raise InvalidWorld, "#{where}: the opening_scene casts #{unknown.join(", ")}, whom this file does not declare" if unknown.any?
  end

  def where
    source ? Pathname.new(source).basename.to_s : "world"
  end

  def existing_story
    return @existing_story if defined?(@existing_story)

    @existing_story = Story.find_by(title: story_document.fetch("title"))
  end

  def find_location(story, name)
    story.locations.where("LOWER(name) = ?", name.downcase).first
  end

  def universe_document
    document.fetch("universe")
  end

  def story_document
    document.fetch("story")
  end

  def location_documents
    Array(document["locations"])
  end

  def connection_documents
    Array(document["connections"])
  end

  def character_documents
    Array(document["characters"])
  end

  def opening_scene_document
    document.fetch("opening_scene")
  end

  def mechanic_documents
    Array(document["mechanics"])
  end
end
