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
#                                        Location::Generator#find_or_create_stub
#   Connection (location, connected)     unique index, written both ways
#   Item       (character, name)
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
      location.assign_attributes(attributes.except("name", "opening"))
      location.save!

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

  def load_characters!(story, universe)
    character_documents.each do |attributes|
      race = universe.races.detect { |candidate| candidate.name == attributes.fetch("race") }
      character = story.characters.find_by("LOWER(fullname) = ?", attributes.fetch("fullname").downcase) ||
                  story.characters.new(fullname: attributes.fetch("fullname"))

      character.assign_attributes(attributes.except("race", "items").merge(race: race))
      character.save!

      Array(attributes["items"]).each do |item_attributes|
        item = character.items.find_by(name: item_attributes.fetch("name")) ||
               character.items.new(name: item_attributes.fetch("name"))
        item.assign_attributes(item_attributes.except("name"))
        item.save!
      end
    end
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
    end
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
end
