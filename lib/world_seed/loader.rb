# Loads a checked-in world into the database. Offline and idempotent: no model
# call, no API key, no network, and running it twice leaves exactly what running
# it once left.
#
# Idempotency is on natural keys, never on `id` -- ids differ on every load:
#
#   Story      title                     (the file's identity; keep them unique)
#   Universe   the story's universe      (the table has no natural key of its own)
#   Race       (universe, name)          unique index
#   Character  (story, fullname)         unique index; `stats` is the file's own
#                                        answer for a body, re-asserted like a
#                                        placement and left alone when absent
#   Location   (story, name)             case-insensitively first, matching
#                                        Location::Generator#find_location, and
#                                        then on WorldSeed.natural_key, which is
#                                        what recognizes a room the file renamed
#   Connection (location, connected)     unique index, written both ways -- and
#                                        a mobile room's doorway is matched on
#                                        ARITY as well, because the world's own
#                                        mechanic moves the far end of it
#   Item       (story, name)             NOT (owner, name): an item moves, and a
#                                        world that has been played has items
#                                        somewhere other than where the file
#                                        puts them. Keying on the owner would
#                                        re-seed a dropped daybook as a second
#                                        daybook; keying on the story finds the
#                                        one that exists and puts it back. On
#                                        WorldSeed.natural_key after that, for
#                                        the same reason a location is.
#   Scene      (story, is_opening)       the story's one opening arrival, which
#                                        is the only Scene that is world rather
#                                        than progress -- see WorldSeed::Exporter
#   Mechanic   (story, name)             unique index; a world's own laws are
#                                        world data, so they are seeded with it
#
# RE-SEEDING A WORLD SOMEBODY HAS PLAYED, which is what this file's rules are
# actually about. The captain re-seeds his long-lived development database to
# pick up a file change and then keeps playing the same stories for days, so
# "add and never look" is not a tidiness problem here: it is how one world came
# to hold two supply closets with the office opening onto both, and how a
# nightly connection shuffle came to be re-asserted as a SECOND doorway off
# every mobile lane.
#
# THE RULE IS: RECONCILE WHAT THE FILE CAN PROVE, SAY OUT LOUD WHAT IT CANNOT,
# AND DELETE NOTHING. Three reconciliations, and each one is a fact the file
# already carries rather than a guess:
#
#   A RENAMED ROW IS THE SAME ROW. Identity is `WorldSeed.natural_key`, one
#   step wider than the written name -- case, whitespace and a leading article
#   are not part of it -- so editing "Supply Closet" to "The Supply Closet"
#   renames the row that exists instead of creating a second one beside it.
#   Locations and items both; the file's spelling wins, which is the same
#   "the file re-asserts itself" rule the placements follow.
#
#   A DOORWAY THE WORLD'S OWN MECHANIC MOVED HAS NOT GONE MISSING.
#   `WorldMechanic::ShuffleConnections` repoints the anchored end of every
#   mobile <-> anchored edge and preserves each room's degree, so a file edge
#   whose pair is no longer on record is USUALLY not a missing doorway but a
#   moved one. Where the mobile end already carries every doorway the file
#   gives it, the file's pair is left unwritten and said so. Which anchored
#   place a mobile room has come to rest against is progress, like
#   `last_run_at` and `last_protagonist_visit`, and the file deliberately
#   carries none of those.
#
#   WHAT IT CANNOT PROVE IS A RENAME NO NORMALIZED NAME RECOGNIZES -- "The
#   Supply Closet" edited to "The Broom Cupboard" is, to any loader, a room
#   that does not exist yet. Nothing in the file says which room it replaced,
#   and merging two rooms on a guess would destroy play rather than duplicate
#   it. So the loader creates the new row, and WARNS: `#warnings` names every
#   location and item a re-seed created in a story that has been played, and
#   points at `rake game:doctor`, which reports the pair it can recognize
#   (`duplicate_locations`, `duplicate_items`,
#   `mobile_location_over_its_seeded_arity`) with a safe repair.
#
# It still adds and updates and never deletes: a row play created is never
# touched. `rake game:delete` plus `bin/rails db:seed` is the clean rebuild.
#
# AND SINCE THE CAPTAIN'S RULING OF 2026-09-04, "a row play created" is a whole
# LAYER rather than a judgement call. Every playthrough holds its own copy of
# the world's things (`Item::Snapshot`), and this loader writes the world layer
# and only the world layer -- `Item.templates` in `#find_item` and
# `#find_renamed_item`, `playthrough: nil, template: nil` on every row it saves.
# So re-asserting the file can no longer take a thing out of somebody's hands
# mid-game: it puts the world's own row back and leaves every game alone.
class WorldSeed::Loader
  class InvalidWorld < StandardError; end

  attr_reader :document, :source

  def self.load_all(io: $stdout)
    WorldSeed.files.map do |path|
      loader = new(WorldSeed.parse(File.read(path)), source: path)
      story = loader.load!
      io&.puts "Seeded world #{story.title.inspect} (story ##{story.id}, #{story.locations.count} locations, #{story.characters.count} characters)"
      loader.reconciled.each { |line| io&.puts "  reconciled: #{line}" }
      loader.warnings.each { |line| io&.puts "  WARNING: #{line}" }
      story
    end
  end

  def self.load_file(path)
    new(WorldSeed.parse(File.read(path)), source: path).load!
  end

  def initialize(document, source: nil)
    @document = document
    @source = source
    @reconciled = []
    @warnings = []
  end

  # WHAT THE LOAD PUT RIGHT WITHOUT BEING TOLD, one line each: a row it
  # recognized under a new name, a doorway it left where the world's own
  # mechanic had moved it. Read after `#load!`, printed by `#load_all`, and
  # asserted by `WorldSeed::LoaderTest` -- a reconciliation that happened
  # silently would be indistinguishable from the accumulation it replaced.
  def reconciled
    @reconciled ||= []
  end

  # WHAT IT COULD NOT TELL APART, and the only half of a re-seed that is still
  # capable of leaving a world with two of something. Every entry is a row a
  # re-seed created in a story somebody has PLAYED, which is either a genuine
  # addition to the file or a rename no normalized name recognizes -- and
  # nothing in the file says which.
  def warnings
    @warnings ||= []
  end

  # Returns the Story. Everything happens in one transaction, so a file that
  # fails validation half way through leaves no partial world behind.
  def load!
    validate!

    # Read BEFORE anything is written, because both answers change the moment
    # `load_story!` saves: whether this is a re-seed at all, and whether the
    # world it is landing on has been played. Together they decide whether a
    # created row is worth warning about -- a first seed creates everything by
    # definition, and a world nobody has played can be dropped and rebuilt.
    @re_seeding = existing_story.present?
    @played = @re_seeding && played?(existing_story)

    Story.transaction do
      universe = load_universe!
      story = load_story!(universe)
      locations = load_locations!(story)
      load_connections!(story, locations)
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
  #
  # THE NAME IS NOW WRITTEN rather than excluded, which is what makes a rename
  # converge instead of accumulate: `find_location` recognizes the row under
  # its old spelling and this puts the file's spelling on it. The row keeps its
  # id, so its doorways, its scenes, its `last_protagonist_visit` and anybody
  # standing in it are all untouched -- which is the whole difference between
  # renaming the room and creating a second one beside it.
  def load_locations!(story)
    location_documents.to_h do |attributes|
      name = attributes.fetch("name")
      location = find_location(story, name) || story.locations.new(name: name)
      note_rename("location", location, name)
      note_creation("location", name) unless location.persisted?
      location.assign_attributes(attributes.except("opening", "items").merge("name" => name))
      location.save!
      load_items!(story, attributes["items"], character: nil, location: location)

      [ name, location ]
    end
  end

  # Both directions, from one entry. See WorldSeed::Exporter's comment on why
  # the file holds an unordered pair.
  #
  # AN EDGE THE FILE DECLARES AND THE RECORDS NO LONGER HAVE IS NOT
  # AUTOMATICALLY A MISSING DOORWAY. `WorldMechanic::ShuffleConnections`
  # repoints the anchored end of every mobile <-> anchored edge, deleting the
  # old row and writing a new one, and it preserves every room's degree while
  # doing it. So on a world whose nights have run, the file's pair is gone and
  # a DIFFERENT pair off the same mobile room is there instead -- and writing
  # the file's pair back gives the room a second doorway that the mechanic then
  # reports as having moved on a later night. That is the phantom
  # "Mournwell Lane now opens onto X instead of Y" the captain read.
  #
  # So a shufflable file edge is written only where the mobile end is SHORT of
  # the doorways the file gives it. `#moved_doorways` does the counting; the
  # rest of this method is what it always was.
  def load_connections!(story, locations)
    @story = story
    @edges = connection_documents.map do |attributes|
      from, to = attributes.fetch("between").map { |name| locations.fetch(name) }
      { attributes: attributes, from: from, to: to }
    end

    on_record, absent = @edges.partition { |edge| edge_on_record?(edge) }
    on_record.each { |edge| write_edge!(edge) }

    budget = moved_doorways(absent)
    absent.each do |edge|
      mobile = mobile_end(edge)
      if mobile && budget[mobile.id].to_i.positive?
        budget[mobile.id] -= 1
        reconciled << "left #{mobile.name.inspect} opening where the world put it rather than re-writing the file's " \
                      "doorway to #{other_end(edge, mobile).name.inspect} -- it already leads every way out the file gives it, " \
                      "and #{shuffle_mechanic.name.inspect} moves the far end of those"
        next
      end

      write_edge!(edge)
    end
  end

  def write_edge!(edge)
    values = edge.fetch(:attributes).slice("distance", "travel_method")

    [ [ edge[:from], edge[:to] ], [ edge[:to], edge[:from] ] ].each do |(origin, destination)|
      connection = LocationConnection.find_or_initialize_by(location: origin, connected_location: destination)
      connection.assign_attributes(values)
      connection.save!
    end
  end

  def edge_on_record?(edge)
    LocationConnection.where(location: edge[:from], connected_location: edge[:to])
                      .or(LocationConnection.where(location: edge[:to], connected_location: edge[:from]))
                      .exists?
  end

  # HOW MANY DOORWAYS OFF EACH MOBILE ROOM THE WORLD HAS ALREADY MOVED, as
  # `{ location id => count }`, and it is a count rather than a pairing because
  # a permutation does not leave one behind: the mechanic's arrangement says
  # which anchored place each doorway has come to rest against, and the file
  # only ever said how many there are.
  #
  #   wanted  the doorways the file gives this mobile room, out of the edges it
  #           declares with exactly one mobile end
  #   present the doorways the records give it -- the same directional rows
  #           `ShuffleConnections#anchor_edges` shuffles
  #
  # `present - (wanted - absent)` is what the room has that the file did not
  # name: the doorways the mechanic moved. Nothing is skipped where that is
  # zero or negative, so a genuinely missing edge is still written, a file that
  # ADDS a doorway to a mobile room still gets it, and a world whose nights
  # have never run reconciles nothing at all.
  def moved_doorways(absent)
    return {} if shuffle_mechanic.nil? || shuffle_mechanic.last_run_at.nil?

    absent_by_mobile = absent.filter_map { |edge| mobile_end(edge)&.id }.tally

    absent_by_mobile.to_h do |id, absent_count|
      wanted = shufflable_file_edges.count { |edge| mobile_end(edge)&.id == id }
      present = LocationConnection.where(location_id: id, connected_location_id: anchored_ids).count

      [ id, [ present - (wanted - absent_count), absent_count ].min ]
    end
  end

  # The world's own connection shuffle, or nil. Read rather than assumed:
  # leaving a file edge unwritten is only honest where something in the world
  # is entitled to have moved it, and this mechanic is the only such thing.
  def shuffle_mechanic
    return @shuffle_mechanic if defined?(@shuffle_mechanic)

    @shuffle_mechanic = @story.world_mechanics.find_by(kind: "shuffle_connections")
  end

  # Every file edge with exactly one mobile end -- the ones the mechanic moves.
  # Read off the rows just saved by `#load_locations!`, so the file's `mobile`
  # flags are what decides it either way.
  def shufflable_file_edges
    @shufflable_file_edges ||= @edges.select { |edge| mobile_end(edge) }
  end

  def mobile_end(edge)
    mobile = [ edge[:from], edge[:to] ].select(&:mobile?)
    mobile.one? ? mobile.first : nil
  end

  def other_end(edge, one)
    edge[:from] == one ? edge[:to] : edge[:from]
  end

  def anchored_ids
    @anchored_ids ||= @story.locations.where(mobile: false).pluck(:id)
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
        attributes.except("race", "items", "location", "absent", "stats")
                  .merge(race: race, location: where, deliberately_absent: attributes["absent"] == true,
                         **stat_block(attributes))
      )
      character.save!

      load_items!(story, attributes["items"], character: character, location: nil)
    end
  end

  # WHAT THE FILE SAYS THIS BODY IS, and the file is the decision -- the same
  # rule `location` and `absent` above are under. `characters[].stats` carries
  # `level` and `hit_die`; `Character` validates both against its own tables, so
  # a hit die of 7 is refused rather than loaded.
  #
  # AN ABSENT KEY IS NOT A ROLL. A file that says nothing about a body leaves
  # both columns exactly as they are -- which for a fresh row is nil, a state
  # `rake game:doctor` reports and `rake game:backfill_stat_blocks` fills in. It
  # is deliberately NOT rolled here, for the reason every other absent key in
  # this loader is left alone: a re-seed must not quietly rewrite a world every
  # time somebody edits a different part of the file, and a hand-authored world
  # that wants a particular body says so.
  #
  # THE FILE RE-ASSERTS ITSELF over a played world when the key IS there,
  # exactly as the placements and the items do. Lowering somebody's hit die
  # under a game in progress is legitimate and leaves that game's condition row
  # above its new maximum, which `rake game:doctor` reports
  # (`hp_above_maximum`) with a safe repair.
  def stat_block(attributes)
    stats = attributes["stats"]
    return {} unless stats.is_a?(Hash)

    { level: stats["level"], hit_die: stats["hit_die"] }.compact
  end

  # THE THINGS IN THE WORLD, on whichever side of `Item`'s place rule they sit:
  # `place` is `character:` for something somebody is holding and `location:`
  # for something lying in a room, and the other half is written nil so that
  # re-seeding cannot leave an item in two places at once.
  #
  # IT WRITES THE WORLD LAYER AND NEVER AN INSTANCE, and since the captain's
  # ruling of 2026-09-04 that is the whole of what "the file re-asserts itself
  # over a played world" now means. A seed file describes a WORLD: what a room
  # was built holding, what a person was written carrying. Every playthrough
  # takes its own copy of that at first contact (`Item::Snapshot`), and those
  # copies are the games in progress -- so a re-seed that reached into them
  # would take a thing out of somebody's hands mid-game to put it back on a
  # shelf that already has one. `playthrough: nil` and `template: nil` are
  # written on every leg to say it in the row.
  #
  # WHAT THAT COSTS, stated: an already-copied instance keeps the description
  # the file gave it when the party first walked in, so editing a room's item
  # text reaches every game that has not been there yet and no game that has.
  # That is inherent in copying and it is the right way round -- the alternative
  # is a file edit rewriting what a player is holding.
  #
  # A PROTAGONIST'S ITEMS ARE THE STORY'S STARTING INVENTORY. They stay held by
  # the protagonist row, in the world layer, and every playthrough of the world
  # begins with a COPY of each in the PARTY'S own hands --
  # `Story#starting_inventory` and `Item::Snapshot#of_the_party!` have the
  # argument. So the file keeps writing exactly what it wrote before and the
  # meaning of the row is what changed: world data rather than one shared pair
  # of hands.
  #
  # Items under a LOCATION are what a HAND-WRITTEN world carries so that
  # anything in it is takeable. A generated room furnishes itself now
  # (`Item::Registry`, written at realization), so this is no longer the only
  # way a thing gets onto a floor -- but a seeded room is realized by the file
  # rather than by a model call, so what is lying in one is whatever the file
  # says and nothing else. The registry leaves seeded rooms alone.
  #
  # MATCHED ON (story, name), NOT ON THE OWNER, because a template can still
  # move: `rake game:backfill_items` puts one back where a pre-layer take
  # carried it off from, and a hand-edited database can put one anywhere.
  # Keying on the owner would look for the daybook in the hands the file puts it
  # in, not find it, and seed a second one. Keying on the story finds the one
  # that exists and puts it back where the file says it belongs -- the same rule
  # the connections already follow.
  def load_items!(story, documents, **place)
    Array(documents).each do |attributes|
      name = attributes.fetch("name")
      item = find_item(story, name) || Item.new(name: name)
      note_rename("item", item, name)
      note_creation("item", name) unless item.persisted?
      item.assign_attributes(attributes.merge("name" => name, playthrough: nil, template: nil, **place))
      item.save!
    end
  end

  # ONE OF THE WORLD'S OWN ROWS of this story by name: held by one of its people
  # or lying anywhere in it, and those are a template's only two places.
  #
  # `.templates` IS THE WHOLE GUARD. Every playthrough holds a copy of the
  # world's things under the same name, so a search that could return one would
  # re-assert the file onto one player's row -- putting the daybook back on the
  # shelf out of somebody's hands, while the world's own daybook stayed wherever
  # it was. Before the layer split the carried leg had to be searched, because a
  # room item a player was holding WAS the world's only row; it is not any more,
  # and searching it now would be the defect rather than the fix.
  #
  # `#find_renamed_item` is the last resort and it is the same statement one
  # step wider: a row the file has renamed is still that row.
  def find_item(story, name)
    by_name = Item.where(name: name).templates

    by_name.where(character_id: story.characters.select(:id))
           .or(by_name.where(location_id: story.locations.select(:id)))
           .first ||
      find_renamed_item(story, name)
  end

  # THE SAME ITEM UNDER THE NAME THE FILE USED TO GIVE IT. Without this, an
  # item whose name was edited -- a capital letter is enough -- is a row that
  # does not exist yet, and the world ends up with two of it: the captain's
  # database held two `Ward Office 12 daybook` rows in the protagonist's hands
  # for exactly this reason.
  #
  # `.templates` AGAIN, and here it replaces a rule rather than adding one. This
  # used to search all three legs in `#find_item`'s own order and prefer a row
  # with no playthrough on it, because a seeded protagonist item is the story's
  # starting inventory and every playthrough carries a copy of it under the same
  # name -- so finding a copy first would rename one player's row and leave the
  # world's own row spelt the old way. Since the layer split the world's own
  # rows are the only ones this can see at all, so the preference has nothing
  # left to choose between: what it was guarding against is now unreachable.
  #
  # A COPY KEEPS THE NAME IT WAS COPIED WITH, which is the same trade the
  # descriptions make one method up: a file edit reaches every game that has not
  # met the thing yet and no game that has. `items.template_id` is what still
  # ties them together, so `rake game:doctor` reads the copy as this
  # playthrough's copy of the renamed row rather than as a stray.
  def find_renamed_item(story, name)
    key = WorldSeed.natural_key(name)

    Item.in_story(story).templates.detect { |item| WorldSeed.natural_key(item.name) == key }
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

    # ON THE NATURAL KEY rather than on the downcased name, because that is now
    # the key a re-seed matches a row under: two rooms the loader could not tell
    # apart would make a rename ambiguous, and it would pick one of them.
    names = location_documents.map { |attributes| attributes.fetch("name") }
    duplicates = names.group_by { |name| WorldSeed.natural_key(name) }.select { |_, group| group.size > 1 }.values
    if duplicates.any?
      raise InvalidWorld, "#{where}: these location names are one name to a re-seed (WorldSeed.natural_key): " \
                          "#{duplicates.map { |group| group.join(" / ") }.join("; ")}"
    end

    item_names = (character_documents + location_documents).flat_map { |attributes| Array(attributes["items"]).map { |item| item.fetch("name") } }
    duplicates = item_names.group_by { |name| WorldSeed.natural_key(name) }.select { |_, group| group.size > 1 }.values
    if duplicates.any?
      raise InvalidWorld, "#{where}: these item names are one name to a re-seed (WorldSeed.natural_key): " \
                          "#{duplicates.map { |group| group.join(" / ") }.join("; ")} -- an item is matched on " \
                          "(story, name), so two of a name are one item"
    end

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

      validate_stats!(attributes)

      next if standing.blank? || names.any? { |name| name.casecmp?(standing) }

      raise InvalidWorld, "#{where}: character #{attributes.fetch("fullname").inspect} is placed in #{standing.inspect}, " \
                          "which this file does not declare as a location"
    end

    validate_opening_scene!(names, openings.first.fetch("name"))
    validate_mechanics!
  end

  # A BODY THE ENGINE COULD NEVER HAVE ROLLED, caught here rather than three
  # records later. `Character` validates the same two columns inside the
  # transaction, so a file with the fault never loads either way -- but the
  # record's error names a column and this one names the file and the person,
  # which is what somebody editing YAML needs. Same reason the inscriptions are
  # checked here.
  #
  # HALF A BLOCK IS REFUSED TOO: `Character#max_hp` needs both, so a `stats:`
  # with only a level is a key that looks as though it said something and did
  # not.
  def validate_stats!(attributes)
    stats = attributes["stats"]
    return if stats.nil?

    who = attributes.fetch("fullname").inspect
    unless stats.is_a?(Hash) && stats.keys.sort == %w[hit_die level]
      raise InvalidWorld, "#{where}: character #{who} has `stats: #{stats.inspect}` -- it is a mapping of " \
                          "`level` and `hit_die`, and both together or neither"
    end

    unless Character::LEVELS.include?(stats["level"])
      raise InvalidWorld, "#{where}: character #{who} has level #{stats["level"].inspect}; " \
                          "a level is #{Character::LEVELS.first}..#{Character::LEVELS.last}"
    end

    return if Character::HIT_DICE.include?(stats["hit_die"])

    raise InvalidWorld, "#{where}: character #{who} has hit die #{stats["hit_die"].inspect}; " \
                        "the engine rolls one of #{Character::HIT_DICE.join(", ")}"
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

      if shufflable_edge_count < 2
        raise InvalidWorld, "#{where}: mechanic #{name.inspect} shuffles connections, but the file declares " \
                            "#{shufflable_edge_count} connection(s) between a `mobile: true` location and one that is not. " \
                            "It needs at least two, or nothing can move."
      end

      # TWO EDGES ARE NOT ENOUGH IF THEY HANG OFF THE SAME MOBILE ROOM, and
      # that is the rule PR 85 wrote into db/seeds/worlds/README.md as
      # authoring guidance and left uncheckable. `ShuffleConnections` judges an
      # arrangement on the ADJACENCY it induces -- which places end up joined --
      # so swapping one lane's own two exits leaves the lane opening onto
      # exactly the two places it already did, and every such candidate is
      # refused as a no-op. A world with all its shufflable edges on one mobile
      # room therefore loads, validates, plays, and never moves: the worst kind
      # of seed-file typo, and the same one the arity rule above exists to
      # catch, counted on the right thing.
      next if shufflable_mobile_rooms.size >= 2

      raise InvalidWorld, "#{where}: mechanic #{name.inspect} shuffles connections, and every one of its " \
                          "#{shufflable_edge_count} shufflable connections hangs off the same `mobile: true` location " \
                          "(#{shufflable_mobile_rooms.to_a.join(", ")}). Permuting one room's own exits among themselves " \
                          "leaves it opening onto the same places, which the mechanic refuses as a no-op, so nothing " \
                          "can ever move. Spread them over at least two mobile locations."
    end
  end

  # The `mobile: true` locations the file's shufflable edges hang off, by name.
  # Counted from the FILE, like the edges themselves.
  def shufflable_mobile_rooms
    @shufflable_mobile_rooms ||= begin
      mobile = mobile_names

      connection_documents.filter_map do |attributes|
        pair = Array(attributes["between"]).select { |name| mobile.include?(name) }
        pair.first if pair.one?
      end.to_set
    end
  end

  def mobile_names
    @mobile_names ||= location_documents.select { |attributes| attributes["mobile"] }.map { |attributes| attributes.fetch("name") }.to_set
  end

  # Counted from the FILE rather than from the database, so a hand edit is
  # caught before it loads. Edges with two mobile ends are not shufflable and
  # that is deliberate: a building whose rooms are all mobile travels as one
  # piece with its own doors intact.
  def shufflable_edge_count
    @shufflable_edge_count ||= begin
      mobile = mobile_names

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

  # A location of this story, by the name the file gives it -- and then by the
  # name the file USED to give it.
  #
  # The case-insensitive match comes first and is matched exactly as
  # `Location::Generator#find_location` matches it, so nothing about how the
  # generator and the loader agree on a room has changed. The natural-key pass
  # behind it is what recognizes a rename: see `WorldSeed.natural_key` for how
  # far it goes and why it goes no further. `#validate!` refuses a file whose
  # own rooms collide on that key, so there is never more than one answer.
  def find_location(story, name)
    exact = story.locations.where("LOWER(name) = ?", name.downcase).first
    return exact if exact

    # `Location.where(story_id:)` and not `story.locations`, deliberately: a
    # bare association read LOADS AND CACHES it, and this runs in the middle of
    # writing the very rows it would be caching. A caller that read
    # `story.locations` afterwards -- `EngineSweep::Invariants` does -- would get
    # the loader's half-written snapshot instead of the records.
    key = WorldSeed.natural_key(name)
    found = Location.where(story_id: story.id).pluck(:id, :name).detect { |(_, candidate)| WorldSeed.natural_key(candidate) == key }

    found && Location.find(found.first)
  end

  # A row recognized under a different written name, said out loud. The rename
  # itself is done by the caller's `assign_attributes` -- this only reports it,
  # so a load that quietly renamed something is not a shape this class has.
  def note_rename(kind, record, name)
    return unless record.persisted?
    return if record.name == name

    reconciled << "#{kind} #{record.name.inspect} is #{name.inspect} in the file, so the row was renamed rather " \
                  "than a second #{kind} created beside it (##{record.id}, unchanged otherwise)"
  end

  # A ROW A RE-SEED CREATED IN A WORLD SOMEBODY HAS PLAYED, which is the one
  # thing left that can still leave two of something. It is either a genuine
  # addition to the file or a rename `WorldSeed.natural_key` cannot see, and
  # nothing in the file distinguishes them -- so it is reported rather than
  # resolved, because the resolution would be a guess that destroyed play.
  def note_creation(kind, name)
    return unless @played

    warnings << "created #{kind} #{name.inspect}, which this story did not have. The world has been played, so if " \
                "that is a RENAME of #{kind == "location" ? "a room" : "something"} already in it, the old row is " \
                "still there with everything hanging off it -- `rake game:doctor` names a pair it can recognize"
  end

  # Has anybody played this world? Playthroughs, or a Scene that is not the
  # opening arrival -- the same line `WorldSeed::Exporter` draws between world
  # and progress.
  def played?(story)
    story.playthroughs.exists? || story.scenes.where(is_opening: false).exists?
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
