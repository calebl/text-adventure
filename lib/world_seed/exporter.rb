# Dumps a generated world to a checked-in seed file.
#
# The whole graph goes out: the Universe and its races, the Story, its
# characters (and their items), every Location the story has -- realized or
# stub -- the edges between them, and the story's own `mechanics`. What is
# deliberately left behind is progress rather than world: Playthroughs,
# `last_protagonist_visit`, `WorldEvent`s, a mechanic's `last_run_at` and every
# Scene BUT ONE are somebody's way through the world, not the world. #warnings
# says so out loud when there is any, so nothing is dropped silently.
#
# THE ONE SCENE THAT CROSSES THAT LINE is the story's opening arrival, and it
# is worth saying why, because the line is otherwise a good one. Every other
# scene is a record of somebody having been somewhere: it exists because a
# player walked in, it belongs to their linked list, and seeding it into a fresh
# database would be seeding a playthrough. The opening arrival is not that. No
# player made it happen -- it is the moment the story begins, the same for
# everyone who ever plays it, and it is the answer to a question the world is
# supposed to know: what does it read like to be standing here at the start.
# Leaving it out meant the one arrival in the game nobody narrates, and a talk
# branch that could not be reached in a seeded world because no scene recorded
# anybody standing in the opening room.
#
# A Scene has no natural key, so `scenes.is_opening` is the marker and the
# loader's key both: exactly one per story, enforced by Scene's own validation.
#
# Connections are stored as two directional rows per edge, both carrying the
# same values -- LocationConnection's enums are direction-neutral precisely so
# that holds. The file therefore lists each edge ONCE, as an unordered
# `between: [a, b]` pair, and the loader writes both rows back. A file that
# listed both directions would double the hand-editing and could be edited into
# an asymmetric state the model does not support. If the database ever holds
# only one direction of an edge, that is reported in #warnings and the reverse
# row is created the next time the file is loaded.
class WorldSeed::Exporter
  UNIVERSE_FIELDS = %i[
    physics technology weapons geographies civilizations history economics politics religion
  ].freeze

  CHARACTER_FIELDS = %i[
    nickname age sex is_protagonist is_companion
    backstory personality appearance likes dislikes fears
  ].freeze

  attr_reader :story

  def initialize(story)
    @story = story
    @warnings = []
  end

  # Writes the seed file and returns its path. Defaults to a filename derived
  # from the story title, so re-exporting after a schema change overwrites the
  # file it produced last time instead of leaving two.
  def write!(path: nil)
    path = Pathname.new(path || WorldSeed::DIRECTORY.join("#{WorldSeed.slug(story.title)}.yml"))
    path.dirname.mkpath
    contents = preserved_header(path) || header
    path.write(contents + WorldSeed.dump(document))
    path
  end

  # Everything the export could not carry, and everything a human has to fix
  # before the file will load. Populated by #document.
  def warnings
    @warnings.uniq
  end

  # The whole world as a plain Hash, keys in the order they are written.
  def document
    warn_about_unexported!

    {
      "format" => WorldSeed::FORMAT,
      "universe" => universe_document,
      "story" => story_document,
      # Written directly after the story because it reads directly after the
      # preface: these two paragraphs are the first thing any player sees, and
      # the file should put them where somebody editing them will find them.
      # It refers to a location and to characters the file declares further
      # down; the loader resolves those by name after both are loaded.
      "opening_scene" => opening_scene_document,
      "characters" => characters_document,
      "locations" => locations_document,
      "connections" => connections_document,
      # Last, and after the graph it operates on: a mechanic's parameters only
      # mean anything once you have read which locations are `mobile` and which
      # edges join a mobile place to a fixed one.
      "mechanics" => mechanics_document
    }.compact
  end

  private

  # Progress is not world. Say what was left behind rather than letting a
  # played-in story quietly export as a fresh one -- and say it loudly when the
  # one scene that IS world is missing, because the loader refuses such a file.
  def warn_about_unexported!
    scenes = story.scenes.where(is_opening: false).count
    playthroughs = story.playthroughs.count

    @warnings << "#{scenes} scene(s) not exported: a scene is a moment in a playthrough, not part of the world." if scenes.positive?
    @warnings << "#{playthroughs} playthrough(s) not exported: seeding a world does not seed somebody's progress through it." if playthroughs.positive?

    events = story.world_events.count
    @warnings << "#{events} world event(s) not exported: what the world has already done to itself is this story's history, not its rules. The mechanics that produced them ARE exported, with their `last_run_at` left behind." if events.positive?

    # SAID DELIBERATELY, not by omission. Conversation history is squarely
    # progress: a `Chat` is what one player said to one character on one
    # playthrough, and seeding it would seed somebody's half of a conversation
    # into a world nobody has played yet. It gets no exception the way the
    # opening arrival does, and for the mirror-image reason -- the opening is
    # the same for everyone who ever plays; a conversation is the same for
    # nobody.
    conversations = Chat.where(playthrough: story.playthroughs).count
    if conversations.positive?
      @warnings << "#{conversations} conversation(s) not exported: what a player said to a character, and what it cost, " \
                   "is their progress through the world rather than the world."
    end

    # A ROW THAT SAYS BOTH THINGS. `deliberately_absent` with a whereabouts is
    # a contradiction no code path in the app writes -- `Character#move_to!`
    # clears the marker -- so it arrives through raw SQL or a hand-edited file
    # that grew a `location` for somebody it also marks absent. The file is
    # written as the records stand and this says so, because the loader will
    # refuse it and the person editing the file has to know which half is true.
    story.characters.deliberately_absent.somewhere.each do |character|
      @warnings << "#{character.fullname} is marked absent on purpose AND standing in #{character.location.name}: " \
                   "this file carries both keys and WILL NOT LOAD. Delete whichever one is not true."
    end

    if opening_scene.nil?
      @warnings << "no opening arrival: this story has no scene marked `is_opening`, so the file has no " \
                   "`opening_scene` and WILL NOT LOAD. Write one by hand, or generate the story with a " \
                   "`rake game:new` new enough to call Scene::Generator.opening."
    end

    report_partial_stats
  end

  # Re-exporting overwrites the file, which would throw away a header somebody
  # wrote by hand -- and these files are authored, so that header is usually
  # the record of what was changed after the last export. The leading comment
  # block of an existing file is kept as it stands. Comments further down the
  # file are NOT: YAML comments do not survive a round trip through the parser.
  # Anything worth keeping belongs in the header or in the README.
  def preserved_header(path)
    return nil unless path.exist?

    existing = path.each_line.take_while { |line| line.start_with?("#") || line.strip.empty? }.join
    return nil if existing.blank?

    @warnings << "kept the comment header already at the top of #{path.basename}; comments further down the file are gone."
    existing
  end

  def header
    <<~HEADER
      # #{story.title} -- a seeded, playable world.
      #
      # Exported from a generated world with `rake 'game:export[#{story.id}]'`, and
      # HAND-EDITABLE from here on: this file is the authored artifact, not a dump.
      # See db/seeds/worlds/README.md for the format and the rules the loader checks.
      #
      # Loaded offline by db/seeds.rb. No model call, no API key, no network.
    HEADER
  end

  def universe_document
    universe = story.universe

    UNIVERSE_FIELDS.index_with { |field| text(universe.public_send(field)) }.stringify_keys.merge(
      "races" => universe.races.order(:name).map do |race|
        document = { "name" => race.name }
        # THE MONSTROUS HALF OF THE WORLD'S OWN RACE LIST, omitted rather than
        # written false -- the same rule `opening`, `mobile`, `absent` and
        # `readable` follow. A file says which races are monsters and stays
        # quiet about the peoples. Written between the name and the description
        # because the description is a block scalar several lines long, and a
        # one-word fact about a race belongs where a reader can see it beside
        # the name it is about.
        document["monstrous"] = true if race.monstrous?
        document["description"] = text(race.description)
        document
      end
    )
  end

  def story_document
    {
      "title" => story.title,
      "genre" => story.genre,
      # A world has a fixed in-story clock. Seeding is not a new playthrough,
      # so the moment the story opens in is part of the world.
      "start_time" => story.start_time&.utc&.iso8601,
      "preface" => text(story.preface),
      "summary" => text(story.summary)
    }
  end

  # The one Scene that is world (see the class comment). Everything on it is
  # written by natural key -- the location and the cast by name -- because ids
  # differ on every load. `story_timestamp` is deliberately absent: an opening
  # arrival happens at the story's `start_time`, which the file already carries,
  # so restating it would be a second place to edit and a second place to drift.
  def opening_scene_document
    scene = opening_scene
    return nil if scene.nil?

    {
      "location" => scene.location.name,
      "characters" => scene.characters.order(:id).map(&:fullname),
      "description" => text(scene.description),
      "summary" => text(scene.summary)
    }
  end

  def opening_scene
    return @opening_scene if defined?(@opening_scene)

    @opening_scene = story.opening_scene
  end

  def characters_document
    story.characters.order(:id).map do |character|
      document = { "fullname" => character.fullname, "race" => character.race.name }
      # WHERE THE WORLD PUTS THEM, and omitted rather than written null when
      # the records put them nowhere -- the same rule `opening` and `mobile`
      # follow on a location. The key is what makes a seeded cast reachable:
      # `Character.present_in` is the closed set `talk` resolves against, so a
      # world exported without it loads with nobody standing anywhere.
      document["location"] = character.location.name if character.location
      # NOWHERE ON PURPOSE, and written only when the record says so -- the
      # same "omitted rather than written false" rule `opening`, `mobile` and
      # `readable` follow. It is mutually exclusive with `location` above
      # (`WorldSeed::Loader#validate!` refuses the pair), and it cannot be
      # emitted alongside one from a record the app wrote: `Character#move_to!`
      # clears the marker whenever it puts somebody in a room. A row that
      # somehow holds both is exported as it stands and reported below, because
      # an exporter that silently dropped half of a contradiction would hide
      # the thing the file's reader needs to fix.
      document["absent"] = true if character.deliberately_absent?
      # WHETHER THIS PERSON ATTACKS THE PARTY, omitted rather than written
      # false, like every other flag here. It is exported beside `stats` and
      # not derived from the race on the way out: `Character.hostile_by_default?`
      # is the answer for somebody the ENGINE writes, and a file may hold a tame
      # beast of a monstrous race -- so the column is what gets written down.
      # `WorldSeed::Loader#validate_hostility!` refuses a `hostile: true` with
      # no `stats`, which is why the two keys are worth reading together.
      document["hostile"] = true if character.hostile?
      # WHAT THE ENGINE ROLLED FOR THIS BODY, so re-seeding a world gives back
      # the same people rather than re-rolling them. Omitted rather than written
      # null when the sheet is not whole -- the same "omitted rather than
      # written false" rule `opening`, `mobile`, `absent` and `readable` follow
      # -- and an omitted key means the loader leaves the columns alone, which
      # for a fresh row is the nothing `rake game:doctor` reports.
      #
      # ALL FIVE KEYS OR NONE, which is `WorldSeed::Loader::STAT_KEYS` and what
      # `WorldSeed::Loader#validate_stats!` will load. The record allows a body
      # with no abilities -- the two predicates do not merge, see `Character` --
      # so a row halfway through `rake game:backfill_stat_blocks` exports no
      # `stats` at all rather than a mapping the loader would refuse, and says
      # so in `#warnings`.
      document["stats"] = stats_document(character) if character.stat_block? && character.abilities?
      CHARACTER_FIELDS.each { |field| document[field.to_s] = value(character.public_send(field)) }
      items = items_document(character)
      document["items"] = items if items.any?
      document
    end
  end

  # THE FIVE NUMBERS, in `WorldSeed::Loader::STAT_KEYS` order so the file reads
  # the way the sheet does: what the body is, then what it can do.
  def stats_document(character)
    WorldSeed::Loader::STAT_KEYS.to_h { |key| [ key, character.public_send(key) ] }
  end

  # HALF A SHEET, SAID OUT LOUD. A file cannot carry it (the loader takes all
  # five or none), so the honest export is to omit `stats` and name the person:
  # writing the two columns alone would produce a file that refuses to load, and
  # dropping it silently would lose a hand-authored hit die.
  def report_partial_stats
    story.characters.order(:id).each do |character|
      next if character.stat_block? == character.abilities?

      @warnings << "#{character.fullname} has #{character.stat_block? ? "a stat block and no abilities" : "abilities and no stat block"}: " \
                   "no `stats` key was written, because a file carries all five numbers or none. " \
                   "`rake game:backfill_stat_blocks` rolls what is missing, then re-export."
    end
  end

  def locations_document
    opening = story.opening_location

    locations.map do |location|
      document = { "name" => location.name, "detail_level" => location.detail_level }
      document["opening"] = true if location == opening
      # Omitted rather than written false, like `opening`: the file should say
      # which places move and stay quiet about the ones that do not.
      document["mobile"] = true if location.mobile?
      # HOW LIKELY THIS ROOM IS TO BE BORN WITH THE WORLD'S MONSTERS IN IT.
      # Omitted when it is `Location::SAFE`, which is what every room already
      # written is and what an absent key loads back as -- the same "omitted
      # rather than written out" rule the flags above follow, said for a key
      # with four values instead of two.
      document["danger"] = location.danger unless location.danger == Location::SAFE
      # WHAT THE PLACE DOES TO SOMEBODY STANDING IN IT. Omitted rather than
      # written null when there is none, which is the rule every key above it
      # follows -- and here it is also what the loader reads back as "this room
      # does nothing to you", so the round trip is exact. The die goes with the
      # key and only with it: both models refuse the pair the other way round,
      # so a file carrying one alone would not load.
      if location.hazard.present?
        document["hazard"] = location.hazard
        document["hazard_die"] = location.hazard_die
      end
      document["teaser"] = text(location.teaser)
      if location.realized?
        document["description"] = text(location.description)
        document["lore"] = text(location.lore)
      end
      # What is lying in the room, which is the closed set `take` resolves
      # against. Items somebody is holding are exported under that character,
      # by the same method -- an item is in exactly one place, so it is written
      # exactly once.
      #
      # NO PLAYTHROUGH'S OWN COPY IS EXPORTED AT ALL, and since the layer split
      # that is one rule rather than a list of cases: a seed file describes the
      # WORLD, and an instance -- lying in a room in one game, in an NPC's hands
      # in one game, or in one party's own hands -- is that player's progress. It
      # belongs in a seed file no more than a turn log does. The protagonist's
      # own TEMPLATES are exported -- they are the story's STARTING INVENTORY,
      # which every playthrough begins with a copy of. See
      # `Story#starting_inventory` and `#items_document`, which is where
      # `.templates` is written.
      items = items_document(location)
      document["items"] = items if items.any?
      document
    end
  end

  # WHAT IS ON IT AND WHAT IS WRITTEN ON IT. `readable` is omitted rather than
  # written `false`, like `opening` and `mobile`: the file says which things have
  # writing on them and stays quiet about the ones that do not. `inscription`
  # goes with it and only with it -- `Item` refuses the pair the other way round,
  # so a file that carried one alone would not load.
  #
  # `.templates` IS WHAT MAKES THIS THE WORLD. `location.items` and
  # `character.items` reach both layers, so without it a world played twice
  # would export a room's chair three times -- once as the world's and once per
  # game that had walked in -- and re-loading the file would refuse the
  # duplicate names.
  def items_document(owner)
    owner.items.templates.order(:name).map do |item|
      document = { "name" => item.name, "description" => text(item.description) }
      # HOW HARD THE WORLD SAYS IT IS TO SHIFT. Omitted when it is `Item::HANDY`,
      # which is what every row already written is and what an absent key loads
      # back as -- the same "omitted rather than written out" rule
      # `locations.danger` and the flags above it follow.
      document["bulk"] = item.bulk unless item.bulk == Item::HANDY
      if item.readable?
        document["readable"] = true
        document["inscription"] = text(item.inscription) if item.inscription.present?
      end
      document["properties"] = text(item.properties)
      document
    end
  end

  # One entry per undirected edge, ordered by where its endpoints appear in the
  # locations list, so the file reads outward from the opening location.
  def connections_document
    order = locations.each_with_index.to_h { |location, index| [ location.id, index ] }
    rows = LocationConnection.where(location: locations).includes(:location, :connected_location)
    by_pair = rows.group_by { |row| [ row.location_id, row.connected_location_id ].sort }

    by_pair.keys.sort_by { |pair| pair.map { |id| order.fetch(id, Float::INFINITY) } }.map do |pair|
      edge_document(pair, by_pair.fetch(pair), order)
    end
  end

  # A world's own laws. `last_run_at` is NOT exported: how far a mechanic has got
  # through a story is progress, and exporting it would tell a fresh database
  # that nights nobody has played had already happened. `nil` when a story has
  # none, so `#document`'s `compact` drops the key entirely.
  def mechanics_document
    rows = story.world_mechanics.order(:name).map do |mechanic|
      {
        "name" => mechanic.name,
        "kind" => mechanic.kind,
        "cadence" => mechanic.cadence,
        "description" => text(mechanic.description)
      }
    end

    rows.presence
  end

  def edge_document(pair, rows, order)
    row = rows.min_by { |candidate| order.fetch(candidate.location_id, Float::INFINITY) }
    names = pair.sort_by { |id| order.fetch(id, Float::INFINITY) }.map { |id| location_names.fetch(id) }

    warn_about(row, rows, names)

    document = { "between" => names, "distance" => row.distance, "travel_method" => row.travel_method }
    document.merge(hazard_document(rows))
  end

  # THE ONE DIRECTED ROW THAT CARRIES A HAZARD, written back as the three keys
  # the loader reads. `hazard_from` is that row's OWN location -- the room you
  # are leaving -- which is the whole of what `between:`'s unordered pair cannot
  # say. Empty for the ordinary doorway, which is every doorway in every world
  # but one, so `#document`'s shape is unchanged for a world with no hazards.
  #
  # BOTH DIRECTIONS HAZARDOUS IS NOT EXPORTABLE and is warned about rather than
  # halved: the file has one `hazard_from`, so a database whose two rows both
  # carry one is a shape only raw SQL can make and a person has to decide what
  # it meant. This is `#warn_about`'s own rule for a disagreeing pair.
  def hazard_document(rows)
    hazardous = rows.select { |row| row.hazard.present? }
    return {} if hazardous.empty?

    row = hazardous.first
    if hazardous.size > 1
      @warnings << "#{rows.map { |candidate| candidate.location.name }.join(" <-> ")}: both directions carry a " \
                   "hazard and a file can only say one; exported #{row.location.name}'s. Fix it by hand before loading."
    end

    { "hazard" => row.hazard, "hazard_die" => row.hazard_die, "hazard_from" => row.location.name }
  end

  def warn_about(row, rows, names)
    edge = names.join(" <-> ")

    if rows.one?
      @warnings << "#{edge}: only one direction exists in the database; loading this file writes both."
    elsif rows.map { |candidate| [ candidate.distance, candidate.travel_method ] }.uniq.size > 1
      @warnings << "#{edge}: the two directions disagree; exported the values on #{row.location.name}'s row."
    end

    unless LocationConnection::DISTANCES.key?(row.distance)
      @warnings << "#{edge}: distance #{row.distance.inspect} is not one of LocationConnection::DISTANCES -- fix it by hand before loading."
    end

    unless LocationConnection::TRAVEL_METHODS.key?(row.travel_method)
      @warnings << "#{edge}: travel_method #{row.travel_method.inspect} is not one of LocationConnection::TRAVEL_METHODS -- fix it by hand before loading."
    end
  end

  # Opening location first: Story#opening_location is the story's lowest-id
  # location, so the order locations appear in the file is the order the loader
  # creates them in and has to put the opening first.
  def locations
    @locations ||= begin
      all = story.locations.order(:id).to_a
      opening = story.opening_location
      ([ opening ] + all.reject { |location| location == opening }).compact
    end
  end

  def location_names
    @location_names ||= locations.index_by(&:id).transform_values(&:name)
  end

  def text(value)
    value.to_s.strip.presence
  end

  def value(attribute)
    attribute.is_a?(String) ? text(attribute) : attribute
  end
end
