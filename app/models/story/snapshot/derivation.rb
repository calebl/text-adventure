# THE GENERATION-TIME WORLD OF A STORY THAT NEVER TOOK A SNAPSHOT, read back
# out of the records. Best effort, and it says out loud where the effort ran
# out.
#
# Every story in the captain's database predates `stories.generation_snapshot`,
# so without this the feature he asked for would only work on worlds generated
# after it shipped -- which is none of the ones he wanted to run fresh.
#
# == THE LINE, AND THE ONE TIMESTAMP IT IS DRAWN AT
#
# `#cutoff` is the moment somebody first PLAYED this story: the earliest of its
# playthroughs and of its scenes that are not the opening arrival. Both, not
# just the first playthrough -- three of the captain's four stories hold scenes
# older than their oldest surviving playthrough row, because a playthrough can
# be deleted and its scenes belong to the location rather than to it.
#
# Everything created before that moment is generation. Everything created at or
# after it is play, and is left behind.
#
# THE OPENING ROOM AND THE OPENING ARRIVAL ARE GENERATION whatever their
# timestamps say, and the second half of that is not pedantry: `rake
# game:repair` wrote the opening arrival for two of the captain's stories days
# after they were first played, so the row is younger than the cutoff and is
# still the moment the story begins. `WorldSeed::Loader#validate!` refuses a
# file without one, so this is also the difference between a snapshot and a
# snapshot that loads.
#
# == WHICH REALIZED ROOMS WERE REALIZED BEFORE ANYBODY PLAYED
#
# The hard half, because nothing on `locations` records when a room was
# realized. `detail_level` says only that it HAS been; `updated_at` is bumped by
# every visit (`last_protagonist_visit` is a column on the row) so it is an
# upper bound and nothing more; and the room's own connection rows are written
# from BOTH ends -- realizing room B and naming A as one of its exits writes a
# row on A -- so they date the neighbour's realization as readily as this one's.
#
# WHAT DOES DATE IT IS THE NEIGHBOURS THEMSELVES. `Location::Generator#connect_exit!`
# creates a stub for an exit name that does not resolve, and connects it to the
# room whose exits call invented it AND TO NOTHING ELSE. So a location born at
# or after the cutoff was born of its neighbour's realization, and that
# neighbour was realized during play. Read the other way round, which is how it
# is used here:
#
#   A room created before the cutoff is exported REALIZED when it is the
#   opening room, or when no location it connects to was created at or after
#   the cutoff. Otherwise it is exported as a STUB -- name, teaser, danger and
#   the exits call's fields -- and its realized detail is left behind.
#
# On the captain's four stories that answer is right in every case that can be
# checked against a checked-in seed file: the three seeded worlds keep the rooms
# their files declare realized and demote none of them, and the one generated
# world keeps its opening room and demotes the two rooms play realized.
#
# WHERE IT CAN BE WRONG, said here because `#notes` says it to the person
# running the command: a room realized during play whose exits named only rooms
# that already existed invents no neighbour, so nothing dates it and it is kept
# realized. `#notes` names every room kept realized without that proof, so the
# manifest a `DRY_RUN=1` prints is something to read rather than to trust.
#
# == WHAT IS NOT FILTERED BY ITS OWN TIMESTAMP, AND WHY
#
# ITEMS ARE KEPT OR DROPPED WITH THEIR OWNER, never on `items.created_at`.
# `rake game:backfill_items` rewrote every item row in the database when the
# world and playthrough layers were split, so an item's own age says when that
# backfill ran and not when the world was made -- every template in two of the
# captain's stories is younger than the cutoff and every one of them is seeded
# world data. The owner is the honest question: a thing lying in a room this
# derivation keeps realized is that room's, a thing in a room it demotes to a
# stub belongs to the realization it is throwing away, and a thing in somebody's
# hands is theirs. Only `Item.templates` is ever in the document at all --
# `WorldSeed::Exporter` sees to that -- so no playthrough's own copy can reach
# it.
#
# CHARACTERS ARE FILTERED BY THEIR OWN TIMESTAMP, because unlike items they are
# written by exactly one thing -- `Character::Registry` at a room's realization,
# or `Story::FirstScreen` for the protagonist -- and nothing has ever rewritten
# them wholesale.
#
# EXCEPT THE PROTAGONIST, who is generation whatever their row's age says, for
# the opening arrival's reason one section up: `Story::FirstScreen` writes one
# now, and a story older than that ruling got one from `rake game:repair`
# filling in what generation failed to write. `The Iron Gate Descends` is
# exactly that story -- it is the one named in `Story::FirstScreen`'s header as
# the reason the ruling exists, and its protagonist row is a day younger than
# its first playthrough. Keeping them costs nothing that could be play: the
# player character carries no whereabouts (see `Character#location`), so there
# is no state on the row for play to have written.
class Story::Snapshot::Derivation
  attr_reader :story

  def initialize(story)
    @story = story
    @exporter = WorldSeed::Exporter.new(story)
  end

  # THE MOMENT PLAY STARTED, or nil for a story nobody has played. Both halves
  # of the question, for the reason in the header.
  def cutoff
    return @cutoff if defined?(@cutoff)

    @cutoff = [
      story.playthroughs.minimum(:created_at),
      story.scenes.where(is_opening: false).minimum(:created_at)
    ].compact.min
  end

  # Nobody has played this world, so the whole of it IS its generation state and
  # there is nothing to derive. Said out loud rather than treated as a failure:
  # a plain export is the right answer here and refusing to give one would be
  # refusing the easy case.
  def unplayed? = cutoff.nil?

  # WHY THIS STORY CANNOT BE DERIVED, one sentence each, empty when it can.
  # Every one of them is a state where a guess would produce a file that either
  # will not load or is not this world's beginning -- and a wrong fork is worse
  # than no fork, because it looks like a measurement.
  def refusals
    @refusals ||= [ missing_opening_arrival, opening_room_not_realized, play_older_than_the_story ].compact
  end

  # WHAT THE DERIVATION IS UNSURE OF, one sentence each. Printed by
  # `rake game:fork` and `rake game:snapshot` under `DRY_RUN=1` so the manifest
  # can be read before it is acted on -- which is the whole reason the dry run
  # exists.
  def notes
    document
    @notes
  end

  # WHAT WAS KEPT AND WHAT WAS LEFT BEHIND, per table, for the dry run to print.
  # Rows rather than percentages: "3 of 15 locations" is something he can check
  # against `rake game:list`.
  def manifest
    derived = document

    {
      "locations" => count(derived["locations"], story.locations.count),
      "  of them realized" => count(
        Array(derived["locations"]).select { |row| row["detail_level"] == "realized" },
        story.locations.realized.count
      ),
      "characters" => count(derived["characters"], story.characters.count),
      "items" => count(item_rows(derived), Item.in_story(story).templates.count),
      "connections (edges)" => count(derived["connections"], edge_count),
      "mechanics" => count(derived["mechanics"], story.world_mechanics.count)
    }
  end

  # The generation-time world as a `WorldSeed::Exporter` document, filtered.
  # One exporter, one format: this narrows what that class produced rather than
  # writing a second one, so a snapshot and a seed file cannot come to disagree
  # about what a world is.
  def document
    return @document if defined?(@document)

    @notes = []
    @document = build
  end

  private

  def build
    document = @exporter.document
    @notes.concat(@exporter.warnings.map { |warning| "exporter: #{warning}" })

    if unplayed?
      @notes << "nothing has been played, so the whole world is its generation state and this is a plain export."
      return document
    end

    @notes << "the line is drawn at #{cutoff.utc.iso8601}, the earliest of this story's playthroughs and of its " \
              "scenes that are not the opening arrival."

    document.merge(
      "opening_scene" => opening_scene_document(document),
      "locations" => locations_document(document),
      "characters" => characters_document(document),
      "connections" => connections_document(document),
      "mechanics" => mechanics_document(document)
    ).compact
  end

  # == THE THREE REFUSALS

  def missing_opening_arrival
    return nil if story.opening_scene.present?

    "no opening arrival: `WorldSeed::Loader` refuses a world without one, so there is nothing here that would " \
      "load. `rake game:doctor` reports it and `rake game:repair` writes one."
  end

  # A stub opening room is refused by `WorldSeed::Loader#validate!`, and it is
  # also the one demotion this derivation must never make: a fork whose first
  # room is a stub is a fork the browser will not start.
  def opening_room_not_realized
    opening = story.opening_location
    return "no locations at all: there is no world here to fork." if opening.nil?
    return nil if opening.realized?

    "the opening room #{opening.name.inspect} is a stub, so a file made from this story would not load. " \
      "`rake game:doctor` reports it as an unplayable story."
  end

  # Timestamps that say somebody played this world before it existed. Nothing
  # sane produces that, and every answer below it would be derived from a line
  # drawn in the wrong place.
  def play_older_than_the_story
    return nil if unplayed? || story.created_at.nil? || cutoff > story.created_at

    "the earliest play (#{cutoff.utc.iso8601}) is not after the story itself (#{story.created_at.utc.iso8601}), " \
      "so there is no generation-time state these records can be read for."
  end

  # == THE KEPT SETS, ALL KEYED ON THE NAME THE DOCUMENT USES

  def generation_locations
    @generation_locations ||= story.locations.where(created_at: ...cutoff).order(:id).to_a
  end

  def kept_location_names
    @kept_location_names ||= generation_locations.map(&:name).to_set
  end

  # Realized at generation, by the neighbour rule in the header.
  def realized_names
    @realized_names ||= generation_locations.select { |location| realized_at_generation?(location) }
                                            .map(&:name).to_set
  end

  def realized_at_generation?(location)
    return false unless location.realized?
    return true if location == story.opening_location

    born_of_it = neighbours_of(location).select { |neighbour| neighbour.created_at >= cutoff }
    return false if born_of_it.any?

    @notes << "#{location.name.inspect} is kept realized, and nothing dates its realization: it invented no " \
              "neighbour, so if play realized it this snapshot carries that room already written."
    true
  end

  def neighbours_of(location)
    neighbours_by_location.fetch(location.id, [])
  end

  # Both directions, because an edge is two rows and either one names the far
  # side. Read in one query rather than per room.
  def neighbours_by_location
    @neighbours_by_location ||= begin
      rows = LocationConnection.where(location: story.locations).includes(:connected_location)
      rows.group_by(&:location_id).transform_values { |group| group.map(&:connected_location) }
    end
  end

  # THE PEOPLE THE WORLD WAS MADE WITH, plus the protagonist whenever they were
  # written -- see the header for why the player character is not dated.
  def generation_character_names
    @generation_character_names ||= begin
      names = story.characters.where(created_at: ...cutoff).pluck(:fullname).to_set
      protagonist = story.protagonist
      if protagonist && !names.include?(protagonist.fullname)
        @notes << "#{protagonist.fullname.inspect} is younger than the line, and is kept anyway: they are the " \
                  "player, which is world data whenever it was written. This story was generated before " \
                  "`rake game:new` made one."
        names << protagonist.fullname
      end
      names
    end
  end

  # == THE FILTERED DOCUMENTS

  def locations_document(document)
    Array(document["locations"]).filter_map do |row|
      name = row["name"]
      next unless kept_location_names.include?(name)
      next keep_parent(row) if realized_names.include?(name)

      demote(keep_parent(row), generation_locations.detect { |location| location.name == name })
    end
  end

  # A ROOM WITHOUT THE REALIZATION PLAY GAVE IT: what
  # `Location::Generator.create_stub!` writes and what the exits call that
  # invented it said, and nothing else. The description and the lore go; so do
  # the things in it, which the realization put there; so does the box, which
  # `Location::Interior` draws when the place is laid out and which would
  # otherwise leave a fork holding the floor plan of a building nobody has
  # walked into. `danger`, `hazard` and `mobile` stay -- a stub is born with its
  # danger rolled, and the other two are written only by a world file.
  #
  # A ROOM THAT WAS ALREADY A STUB KEEPS WHAT IS LYING IN IT, and the difference
  # matters: only a REALIZATION furnishes a room, so a thing in a room nobody
  # ever realized was put there by a world file and is the world's. `#notes`
  # names any of them whose own row is younger than the line, because
  # `rake game:backfill_items` rewrote every item in the database and their ages
  # are the backfill's rather than the world's -- which is a thing to read, not
  # a thing this can decide.
  def demote(row, location)
    return note_late_items(row) unless location&.realized?

    row.except("description", "lore", "items", *Location::Box::COLUMNS).merge("detail_level" => "stub")
  end

  def note_late_items(row)
    late = Array(row["items"]).map { |item| item["name"] } & late_item_names
    if late.any?
      @notes << "#{row["name"].inspect} was never realized and holds #{late.join(", ")}, whose rows are younger " \
                "than the line; item ages are `rake game:backfill_items`'s rather than the world's, so they are " \
                "kept. Delete them from the fork if play put them there."
    end
    row
  end

  def late_item_names
    @late_item_names ||= Item.in_story(story).templates.where(created_at: cutoff..).pluck(:name)
  end

  # A place inside a place this snapshot does not carry is inside nothing, and
  # `WorldSeed::Loader#validate_boxes!` refuses a position with no plane to read
  # it in. The extent survives -- an outermost place with a footprint and no
  # position is one of `Location::Box`'s two whole shapes.
  def keep_parent(row)
    parent = row["parent"]
    return row if parent.nil? || kept_location_names.include?(parent)

    @notes << "#{row["name"].inspect} was inside #{parent.inspect}, which play created; it is exported at the " \
              "outermost level."
    row.except("parent", *Location::Box::POSITION)
  end

  def characters_document(document)
    Array(document["characters"]).filter_map do |row|
      next unless generation_character_names.include?(row["fullname"])

      place(row)
    end
  end

  # SOMEBODY STANDING IN A ROOM THIS SNAPSHOT DOES NOT WRITE. They were made
  # before play started, so they are the world's; where play left them is not.
  # The placement goes and the person stays, which is the shape a seed file
  # already has for a character with no `location` key.
  #
  # A ROOM DEMOTED TO A STUB COUNTS AS ONE THIS SNAPSHOT DOES NOT WRITE, and not
  # only for tidiness: `Story::Doctor` reports `character_in_a_stub` -- somebody
  # standing in a room whose description will be written without knowing they
  # are there -- and a fork is supposed to come out of this clean.
  def place(row)
    where = row["location"]
    return row if where.nil? || realized_names.include?(where)

    @notes << "#{row["fullname"].inspect} was standing in #{where.inspect}, which this snapshot does not write; " \
              "they are exported with no placement."
    row.except("location", *Location::Spot::COLUMNS)
  end

  # A LAW THE WORLD DID NOT HAVE YET. A `WorldMechanic` row is written by a seed
  # load or by hand and never by play, so its own age is honest -- which makes
  # this the same line every other table is under, and it is load-bearing rather
  # than tidy: `The Lunar Cartographer`'s nightly rearrangement was added to its
  # file after the world was first seeded, and the graph as it stood at
  # generation was every room mobile and nothing fixed. Carrying the mechanic
  # into a fork of that moment produces a file `WorldSeed::Loader#validate_mechanics!`
  # refuses -- correctly, because a shuffle with nothing to swap is a law that
  # silently never runs.
  def mechanics_document(document)
    Array(document["mechanics"]).select { |row| generation_mechanic_names.include?(row["name"]) }.presence
  end

  def generation_mechanic_names
    @generation_mechanic_names ||= story.world_mechanics.where(created_at: ...cutoff).pluck(:name).to_set
  end

  def connections_document(document)
    Array(document["connections"]).select do |row|
      Array(row["between"]).all? { |name| kept_location_names.include?(name) }
    end.presence
  end

  # The opening arrival is generation whatever its own timestamp says, but its
  # cast is not: `WorldSeed::Loader#validate_opening_scene!` refuses a scene
  # casting somebody the file does not declare, so anybody play created comes
  # out of it.
  def opening_scene_document(document)
    scene = document["opening_scene"]
    return nil if scene.nil?

    cast = Array(scene["characters"])
    kept = cast.select { |name| generation_character_names.include?(name) }
    if kept.size < cast.size
      @notes << "the opening arrival cast #{(cast - kept).join(", ")}, whom play created; they are out of its cast."
    end

    scene.merge("characters" => kept)
  end

  # == MANIFEST HELPERS

  def count(kept, total)
    kept = Array(kept).size
    "#{kept} kept, #{total - kept} left behind"
  end

  def item_rows(document)
    Array(document["locations"]).flat_map { |row| Array(row["items"]) } +
      Array(document["characters"]).flat_map { |row| Array(row["items"]) }
  end

  # One per undirected edge, which is what the document counts: the table holds
  # two rows for each.
  def edge_count
    LocationConnection.where(location: story.locations)
                      .pluck(:location_id, :connected_location_id)
                      .map(&:sort).uniq.size
  end
end
