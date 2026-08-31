# Dumps a generated world to a checked-in seed file.
#
# The whole graph goes out: the Universe and its races, the Story, its
# characters (and their items), every Location the story has -- realized or
# stub -- and the edges between them. What is deliberately left behind is
# progress rather than world: Scenes, Playthroughs and `last_protagonist_visit`
# are somebody's way through the world, not the world. #warnings says so out
# loud when there is any, so nothing is dropped silently.
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
      "characters" => characters_document,
      "locations" => locations_document,
      "connections" => connections_document
    }
  end

  private

  # Progress is not world. Say what was left behind rather than letting a
  # played-in story quietly export as a fresh one.
  def warn_about_unexported!
    scenes = story.scenes.count
    playthroughs = story.playthroughs.count

    @warnings << "#{scenes} scene(s) not exported: a scene is a moment in a playthrough, not part of the world." if scenes.positive?
    @warnings << "#{playthroughs} playthrough(s) not exported: seeding a world does not seed somebody's progress through it." if playthroughs.positive?
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
        { "name" => race.name, "description" => text(race.description) }
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

  def characters_document
    story.characters.order(:id).map do |character|
      document = { "fullname" => character.fullname, "race" => character.race.name }
      CHARACTER_FIELDS.each { |field| document[field.to_s] = value(character.public_send(field)) }
      items = character.items.order(:name).map do |item|
        { "name" => item.name, "description" => text(item.description), "properties" => text(item.properties) }
      end
      document["items"] = items if items.any?
      document
    end
  end

  def locations_document
    opening = story.opening_location

    locations.map do |location|
      document = { "name" => location.name, "detail_level" => location.detail_level }
      document["opening"] = true if location == opening
      document["teaser"] = text(location.teaser)
      if location.realized?
        document["description"] = text(location.description)
        document["lore"] = text(location.lore)
      end
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

  def edge_document(pair, rows, order)
    row = rows.min_by { |candidate| order.fetch(candidate.location_id, Float::INFINITY) }
    names = pair.sort_by { |id| order.fetch(id, Float::INFINITY) }.map { |id| location_names.fetch(id) }

    warn_about(row, rows, names)

    { "between" => names, "distance" => row.distance, "travel_method" => row.travel_method }
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
