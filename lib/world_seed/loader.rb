# Loads a checked-in world into the database. Offline and idempotent: no model
# call, no API key, no network, and running it twice leaves exactly what running
# it once left.
#
# Idempotency is on natural keys, never on `id` -- ids differ on every load:
#
#   Story      title                     (the file's identity; keep them unique)
#   Universe   the story's universe      (the table has no natural key of its own)
#   Race       (universe, name)          unique index; `monstrous` is written on
#                                        every load, in both directions
#   Character  (story, fullname)         unique index; `stats` is the file's own
#                                        answer for a body, re-asserted like a
#                                        placement and left alone when absent.
#                                        `hostile` is written on every load, in
#                                        both directions, like `absent`
#   Location   (story, name), then the    case-insensitively first, matching
#              place and the box          Location::Generator#find_location; then
#                                        on WorldSeed.natural_key, which
#                                        recognizes a room the FILE renamed; then
#                                        on the place and the box a file draws a
#                                        room in, which recognizes one the ENGINE
#                                        renamed -- and only for a row this file
#                                        names nowhere else.
#                                        WorldSeed.find_location owns all three.
#                                        `danger` is written on every load,
#                                        in both directions, and an absent key is
#                                        Location::SAFE
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
#                                        the same reason a location is. `bulk`
#                                        is written on every load, in both
#                                        directions, and an absent key is
#                                        Item::HANDY
#   Scene      (story, is_opening)       the story's one opening arrival, which
#                                        is the only Scene that is world rather
#                                        than progress -- see WorldSeed::Exporter
#   Mechanic   (story, name)             unique index; a world's own laws are
#                                        world data, so they are seeded with it
#   Quest      (story, title)            unique index; a world's own ARC is
#                                        world data on exactly the terms its
#                                        laws are. Its steps key on (quest,
#                                        position) and its outcomes on (quest,
#                                        name), and the whole block is
#                                        RE-ASSERTED -- a step the file drops is
#                                        deleted, because an arc is a shape
#                                        rather than an accumulation. What is
#                                        NOT re-asserted is any playthrough's
#                                        beats: those are progress
#   WorldEvent (story, source, summary)  ONLY the `schedule:` block -- a row
#                                        saying a thing WILL happen, which is
#                                        world data. The LOG of what already
#                                        did is not, is never exported, and is
#                                        never touched here. An unfired
#                                        seeded row the file has dropped is
#                                        deleted; a FIRED one stays, because
#                                        that one is history
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
#   AND A ROOM OF A PLACE IS THE SAME ROOM AT THE SAME COORDINATES, whatever it
#   has come to be called -- BUT ONLY WHERE THIS DOCUMENT NAMES NO OTHER ROOM
#   THAT ROW COULD BE. That is the half of the rule above the written name
#   cannot reach: `Location::RoomName` names a room of a laid-out place when
#   somebody first walks into it, so a stub the file declares as
#   `The Custom House room 1` can be a row called `the counting room` by the
#   time the file is loaded over it again -- a rename nothing about the two
#   strings could recognize, and the row's name appears nowhere in the file.
#   A row the file DOES name is that declaration's, and the coordinates have
#   nothing to add: without that limit, which of two declarations got the played
#   row came down to which of them the document happened to list first.
#   `WorldSeed.find_location` has the argument in full.
#
#   AND THE FILE'S SPELLING WINS EXCEPT OVER A NUMBER. The one exception to the
#   two rules above, and the only place in this file where the document does not
#   get the last word: a placeholder is PROVISIONAL, so a file still carrying
#   `The Custom House room 1` for a row somebody has named is not asserting a
#   name and does not overwrite one. `WorldSeed.keeps_its_own_name?` carries
#   what putting the number back would cost -- a room realized under its number
#   is never offered a name again.
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

  # THE WHOLE OF WHAT `characters[].stats` IS: the level, the hit die and the
  # three abilities, read off `Character::ABILITIES` rather than named again so
  # the file's shape and the record's cannot come to disagree about what a body
  # is. All five together or none -- see `#validate_stats!` and `#stat_block`.
  STAT_KEYS = [ "level", "hit_die", *Character::ABILITIES.map(&:to_s) ].freeze

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
      load_containment!(locations)
      load_connections!(story, locations)
      load_characters!(story, universe)
      load_mechanics!(story)
      # AFTER THE GRAPH AND THE CAST, because every step names one of them by
      # natural key and binding is a lookup -- an arc loaded first would come
      # out entirely unbound and the doctor would report a world the file
      # actually specified completely.
      load_quests!(story)
      # AND WHAT THE WORLD HAS ALREADY DECIDED WILL HAPPEN. It names nothing, so
      # it could go anywhere; it goes beside the arc because a scheduled row and
      # a quest outcome's ramification are one stream (`WorldEvent`).
      load_schedule!(story)
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

    races = universe_document.fetch("races").map do |attributes|
      race = universe.races.detect { |candidate| candidate.name == attributes.fetch("name") } ||
             universe.races.build(name: attributes.fetch("name"))
      race.description = attributes.fetch("description")
      # A UNIVERSE'S BESTIARY IS THE MONSTROUS HALF OF ITS OWN RACE LIST, and
      # `monstrous: true` is the file saying which half. Written in BOTH
      # DIRECTIONS on every load -- the shape `absent` has on a character rather
      # than the shape `mobile` has on a room -- so deleting the key from a file
      # and re-seeding takes the flag off the record. It has to run that way
      # round: leaving a stale `monstrous` on a race the file no longer marks
      # would keep a dangerous room drawing its people out of a pool the world
      # no longer has.
      race.monstrous = attributes["monstrous"] == true
      race
    end

    universe.save!
    # A RACE THAT ALREADY EXISTED AND CHANGED IS SAVED EXPLICITLY, and this line
    # is a fix rather than a flourish. `has_many` without `autosave: true` saves
    # the NEW records in a collection when the parent is saved and leaves the
    # changed ones exactly as they were on disk -- so before this, editing a
    # race's description in a seed file and re-seeding did nothing at all, and
    # `monstrous` would have inherited the same silence. It is the same "the
    # file re-asserts itself over a played world" rule every other loader here
    # keeps; races were the one table quietly outside it.
    races.each { |race| race.save! if race.changed? }
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
  #
  # EXCEPT WHERE THE FILE IS OFFERING A PLACEHOLDER AND THE ROW HAS A NAME, and
  # `WorldSeed.keeps_its_own_name?` is where the whole of that reasoning lives:
  # a number `Location::Interior` wrote is provisional, so a file still carrying
  # one is not asserting anything for the row's own name to lose. `#written_name`
  # is the one place the two answers are chosen between, so nothing downstream
  # of it has to know there were two.
  def load_locations!(story)
    location_documents.to_h do |attributes|
      name = attributes.fetch("name")
      location = find_location(story, name) || story.locations.new(name: name)
      written = written_name(location, attributes, name)
      note_rename("location", location, name, written: written)
      note_creation("location", name) unless location.persisted?
      # HOW DANGEROUS THE FILE SAYS THIS PLACE IS, written in both directions on
      # every load -- the shape `absent` and `hostile` have on a character
      # rather than the pass-through `mobile` has one key over, and the
      # difference is worth stating. A room's danger decides which pool the
      # people born in it are drawn from; a stale "dangerous" left on a row the
      # file no longer marks would keep the world writing monsters into a room
      # its author had made safe, and there would be no way to undo it from the
      # file. An absent key is `Location::SAFE`, which is the column's default
      # and what every room already written is.
      # AND HOW POPULATED THE FILE SAYS IT IS, written in both directions on
      # every load for `danger`'s reason one key up: a stale `a crowd` left on a
      # row the file no longer marks would go on writing people into a room its
      # author had emptied, with no way to undo it from the file. An absent key
      # is NIL AND NOT `nobody`, and the two are different -- nil is *nobody
      # picked a word*, which is the state the engine rolls one for, and
      # `nobody` is a file saying this place is empty. `Location::Population`'s
      # header has both, and the reason a seeded room usually notices neither:
      # the label is read when a room is REALIZED, and a seeded room that
      # carries a description was realized by its author.
      # AND WHAT THE PLACE DOES TO SOMEBODY STANDING IN IT, written in both
      # directions on every load for `danger`'s reason one key over: a stale
      # `flooded` left on a row the file no longer marks would go on costing
      # players hit points in a room its author had made safe, with no way to
      # undo it from the file. An absent key is NO HAZARD, which is what every
      # room already written is and what the nullable column says.
      # AND WHERE IN ITS PARENT IT SITS, IF THE FILE LAYS ONE OUT. Written in
      # both directions on every load for `danger`'s reason two keys up: a
      # stale box left on a row the file no longer lays out would go on putting
      # a room somewhere its author had taken it out of, with no way to undo it
      # from the file. An absent set of keys is NO INTERIOR, which is what every
      # room in every checked-in world is (the captain's fourth ruling of
      # 2026-09-06) and what the five nullable columns say.
      #
      # `parent` IS EXCLUDED because it is a name and not a column: containment
      # is wired in `#load_containment!` after every room exists, since a file
      # may name a parent that is declared further down.
      location.assign_attributes(
        attributes.except("opening", "items", "parent")
                  .merge("name" => written, "danger" => attributes["danger"].presence || Location::SAFE,
                         "population" => attributes["population"].presence,
                         "hazard" => attributes["hazard"].presence, "hazard_die" => attributes["hazard_die"])
                  .merge(Location::Box::COLUMNS.to_h { |column| [ column, attributes[column] ] })
      )
      location.save!
      load_items!(story, attributes["items"], character: nil, location: location)

      [ name, location ]
    end
  end

  # WHAT IS INSIDE WHAT, and it is a SECOND PASS on purpose: a file may put a
  # room before the place that contains it, and a loader that wired containment
  # while it created rows would be holding the file to an ordering nothing else
  # in the format asks for. `#load_connections!` one method down is a second
  # pass for exactly the same reason.
  #
  # WRITTEN IN BOTH DIRECTIONS, like the box the parent is the frame for:
  # deleting a `parent` key from a file and re-seeding takes the room back out
  # of the building. Without that, a room could be put inside something and
  # never taken out again from the file, which is the failure every "both
  # directions" comment in this file is about.
  #
  # MATCHED ON `WorldSeed.natural_key`, which is the key every other cross
  # reference in this file resolves on, so "the Rusted Anchor" and "Rusted
  # Anchor" name one place. `#validate_boxes!` has already refused a `parent`
  # that names a room the file does not declare, so the lookup cannot miss.
  def load_containment!(locations)
    by_key = locations.transform_keys { |name| WorldSeed.natural_key(name) }

    location_documents.each do |attributes|
      location = locations.fetch(attributes.fetch("name"))
      parent = attributes["parent"]
      wanted = parent.present? ? by_key.fetch(WorldSeed.natural_key(parent)) : nil
      next if location.parent_location_id == wanted&.id

      location.update!(parent_location: wanted)
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

  # BOTH ROWS, AND THE HAZARD ON EXACTLY ONE OF THEM.
  #
  # `hazard_from:` names the room you are LEAVING when the hazard is paid, and
  # it is the one piece of new seed-format shape the whole hazard design needs:
  # `between:` is an unordered pair (see `WorldSeed::Exporter`), so there is
  # otherwise no way for a file to say which of the two directions costs
  # something. The row whose `location` is that room carries the key and the
  # die; the other row is written with NEITHER -- explicitly nil rather than
  # left alone, so a re-seed that moves a hazard to the other direction takes it
  # off the first, exactly as `#load_locations!` clears a room's.
  #
  # A ONE-WAY HAZARD IS NOT A ONE-WAY EXIT: both rows are still written and both
  # still lead both ways. See `LocationConnection::HAZARDS`.
  def write_edge!(edge)
    attributes = edge.fetch(:attributes)
    values = attributes.slice("distance", "travel_method")
    hazard_from = attributes["hazard_from"].presence

    [ [ edge[:from], edge[:to] ], [ edge[:to], edge[:from] ] ].each do |(origin, destination)|
      connection = LocationConnection.find_or_initialize_by(location: origin, connected_location: destination)
      hazardous = hazard_from.present? && WorldSeed.natural_key(origin.name) == WorldSeed.natural_key(hazard_from)
      connection.assign_attributes(
        values.merge("hazard" => hazardous ? attributes["hazard"] : nil,
                     "hazard_die" => hazardous ? attributes["hazard_die"] : nil)
      )
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
        attributes.except("race", "items", "location", "absent", "stats", "hostile")
                  .merge(race: race, location: where, deliberately_absent: attributes["absent"] == true,
                         # WHETHER THIS PERSON ATTACKS THE PARTY, and the file
                         # is the decision -- so a hand-authored world can hold
                         # a tame beast of a monstrous race as easily as a
                         # hostile one of a people. Written in both directions
                         # on every load, like `absent` above and for the same
                         # reason: deleting `hostile: true` from a file and
                         # re-seeding disarms the monster, and a flag that only
                         # ever went one way would make that impossible.
                         #
                         # THE DERIVED RULE IS NOT APPLIED HERE.
                         # `Character.hostile_by_default?` is the answer for
                         # somebody the ENGINE writes, where there is nobody to
                         # ask; a file has already been asked.
                         hostile: attributes["hostile"] == true,
                         **stat_block(attributes))
                  # AND WHERE IN THE ROOM THEY STAND, written in both directions
                  # for the reason the box keys and the items' own pair are:
                  # deleting the keys from a file and re-seeding takes the person
                  # out of that corner again. An absent pair is unplaced.
                  .merge(Location::Spot::COLUMNS.to_h { |column| [ column, attributes[column] ] })
      )
      character.save!

      load_items!(story, attributes["items"], character: character, location: nil)
    end
  end

  # WHAT THE FILE SAYS THIS BODY IS, and the file is the decision -- the same
  # rule `location` and `absent` above are under. `characters[].stats` carries
  # `level`, `hit_die` and the three abilities; `Character` validates every one
  # of them against its own tables, so a hit die of 7 or a strength of 19 is
  # refused rather than loaded.
  #
  # AN ABSENT KEY IS NOT A ROLL. A file that says nothing about a body leaves
  # all five columns exactly as they are -- which for a fresh row is nil, a
  # state `rake game:doctor` reports and `rake game:backfill_stat_blocks` fills
  # in. It is deliberately NOT rolled here, for the reason every other absent
  # key in this loader is left alone: a re-seed must not quietly rewrite a world
  # every time somebody edits a different part of the file, and a hand-authored
  # world that wants a particular body says so.
  #
  # THE FILE RE-ASSERTS ITSELF over a played world when the key IS there,
  # exactly as the placements and the items do. Lowering somebody's hit die
  # under a game in progress is legitimate and leaves that game's condition row
  # above its new maximum, which `rake game:doctor` reports
  # (`hp_above_maximum`) with a safe repair. Editing an ability disturbs nothing
  # at all: no playthrough row is derived from one, because `Character#max_hp`
  # has no ability term in it.
  def stat_block(attributes)
    stats = attributes["stats"]
    return {} unless stats.is_a?(Hash)

    STAT_KEYS.to_h { |key| [ key.to_sym, stats[key] ] }.compact
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
      # HOW HARD THE FILE SAYS THIS THING IS TO SHIFT, written in both
      # directions on every load -- `locations.danger`'s shape one table over
      # and for its argument: a stale `immovable` left on a row the file no
      # longer marks would keep the thing unthrowable for ever with no way to
      # undo it from the file. An absent key is `Item::HANDY`, which is the
      # column's default and what almost everything is.
      # AND WHERE IN THE ROOM THE FILE LAYS IT, written in both directions on
      # every load -- the box keys' own rule on `locations` and its reason: a
      # stale position left on a row the file no longer places would keep the
      # thing in a corner its author had moved it out of, with no way to undo it
      # from the file. An absent pair is UNPLACED, which is what every row in
      # every checked-in world is (`Location::Spot`).
      item.assign_attributes(
        attributes.merge("name" => name, "bulk" => attributes["bulk"].presence || Item::HANDY,
                         playthrough: nil, template: nil, **place)
                  .merge(Location::Spot::COLUMNS.to_h { |column| [ column, attributes[column] ] })
      )
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

  # THE WORLD'S OWN ARC, and it is world data on exactly the terms the mechanics
  # above are: a seed file says where this story is going, and no player ever
  # writes a row in any of the three tables (`EngineSweep::Invariants#quest_unmoved`).
  #
  # RE-ASSERTED WHOLE, WHICH IS DIFFERENT FROM EVERY OTHER LOADER HERE AND
  # DELIBERATE. Locations, items and characters are RECONCILED and never
  # deleted, because a played world has rows the file cannot prove anything
  # about -- somebody moved them. An arc has no such rows: a step is a
  # statement the file makes, and a step the file has stopped making is not a
  # beat somebody walked, it is a plot point the author took out. Leaving it
  # would give a re-seeded world an arc nobody can finish, which is exactly the
  # defect this whole slice exists to prevent. What a PLAYER did -- their beats
  # and their ending -- is `playthrough_beats` and `playthrough_endings`, is
  # never in the file, and is never touched here.
  #
  # AND BINDING IS THE SAME SIDE EFFECT IT IS EVERYWHERE ELSE. A step names a
  # place, a person or a thing and this looks it up in the story that was just
  # loaded, through `Quest::Binder` -- the one statement of what a step will
  # take, so a seeded arc and a generated one bind under one rule. A file may
  # legitimately name something it does not declare: that is an UNBOUND step,
  # which is a state the doctor reports rather than a file that will not load.
  def load_quests!(story)
    by_title = {}

    # THE ARCS WITH NO PARENT FIRST, so a side quest's parent is on the records
    # before it is named. `#validate_quests!` has already refused a `parent:`
    # that names nothing, so this cannot silently orphan one.
    quest_documents.sort_by { |attributes| attributes["parent"].present? ? 1 : 0 }.each do |attributes|
      title = attributes.fetch("title")
      quest = story.quests.find_by(title: title) || story.quests.new(title: title)
      quest.assign_attributes(
        premise: attributes.fetch("premise"),
        status: attributes["status"].presence || "open",
        # A SIDE QUEST IS A CHILD (`Quest`), and `contributes` is a separate
        # question the file may answer about one: whether finishing it moves
        # the main arc. Absent means yes, which is what a side quest usually is.
        parent_quest: by_title[attributes["parent"]],
        contributes: attributes.key?("contributes") ? attributes["contributes"] == true : true,
        origin: "seeded"
      )
      quest.save!
      by_title[title] = quest

      load_quest_steps!(quest, Array(attributes["steps"]))
      load_quest_outcomes!(quest, Array(attributes["outcomes"]))
    end
  end

  # THE BEATS, IN THE ORDER THE FILE LISTS THEM -- `position` is the index and
  # not a key the file writes, for the reason a connection is written once as an
  # unordered pair: a number a person has to keep in step with a list is a
  # number a person gets wrong, and the list already says the order.
  def load_quest_steps!(quest, documents)
    documents.each_with_index do |attributes, index|
      position = index + 1
      step = quest.steps.find_by(position: position) || quest.steps.new(position: position)
      step.assign_attributes(
        summary: attributes.fetch("summary"),
        trigger_kind: attributes.fetch("trigger"),
        target_name: attributes["target"],
        teaser: attributes["teaser"],
        minutes: attributes["minutes"]
      )
      # THE TARGET IS RE-RESOLVED ON EVERY LOAD, in both directions: a file that
      # renames a step's target unbinds the row it used to point at and binds
      # the one it now names. Without that, editing `target:` in a played world
      # would leave the arc pointing where it used to.
      step.target = nil
      step.bound_at = nil
      step.save!

      bind_quest_step!(quest.story, step)
    end

    quest.steps.where.not(position: 1..documents.size).destroy_all
  end

  # THE ENDINGS. Several per quest -- the captain's note of 2026-09-06 -- keyed
  # on `name`, which is the short label a person writes and re-asserts one
  # under. `default: true` marks the one the world was born with; a file that
  # marks none leaves `Quest#default_outcome` reading the first, and one that
  # marks two is reported by `rake game:doctor` rather than refused halfway
  # through a load.
  def load_quest_outcomes!(quest, documents)
    names = documents.map { |attributes| attributes.fetch("name") }

    documents.each do |attributes|
      name = attributes.fetch("name")
      ramification = attributes["ramification"] || {}
      outcome = quest.outcomes.find_by(name: name) || quest.outcomes.new(name: name)
      outcome.assign_attributes(
        summary: attributes.fetch("summary"),
        is_default: attributes["default"] == true,
        # `when:` IS THE RULE THAT SELECTS THIS ENDING, out of
        # `Quest::Outcome::CONDITIONS`, and absent means *the default falls
        # through to me* -- see that class. Spelled `when` in the file because
        # that is the English of it; the column is `condition`, which is what a
        # closed table of them is called everywhere else in this app.
        condition: attributes["when"],
        minutes: attributes["minutes"],
        ramification_summary: ramification["summary"],
        ramification_minutes: ramification["after_minutes"]
      )
      outcome.save!
    end

    quest.outcomes.where.not(name: names).destroy_all
  end

  # WHAT THIS WORLD HAS ALREADY DECIDED WILL HAPPEN -- the captain's Call 8 of
  # 2026-09-06, *"a bomb is going to go off or a volcano is going to explode 1
  # week in the future"*, as world data. A file supplies the hour and the
  # sentence; the engine supplies the firing (`Story#catch_up_world!`), which is
  # `WorldMechanic`'s own doctrine applied to a one-off instead of to a cadence.
  #
  # KEYED ON THE SENTENCE, because that is the only thing a person writes about
  # one: there is no name and no position, and `after_minutes` is a number
  # somebody may well tune between two loads.
  #
  # AN UNFIRED ROW THE FILE HAS STOPPED DECLARING GOES, on `#load_quests!`'
  # reasoning: a schedule is a statement the file makes, and a statement it has
  # withdrawn is a catastrophe the author took out. A row that has ALREADY FIRED
  # STAYS, and that is the one difference: it is no longer a schedule, it is
  # history, and history is not the file's to retract.
  def load_schedule!(story)
    summaries = schedule_documents.map { |attributes| attributes.fetch("summary") }

    schedule_documents.each do |attributes|
      summary = attributes.fetch("summary")
      event = story.world_events.from_a_world_file.find_by(summary: summary) ||
              story.world_events.new(summary: summary, source: WorldEvent::SEEDED)
      # THE HOUR IS COUNTED FROM THE STORY'S OWN BEGINNING, never from whenever
      # the file was loaded: a world re-seeded a month later has the same bomb
      # at the same hour, which is `Quest::Binder`'s `at: story.start_time` rule
      # for the same reason.
      event.assign_attributes(occurred_at: story.start_time,
                              scheduled_for: story.start_time + attributes.fetch("after_minutes").minutes)
      event.save!
    end

    story.world_events.from_a_world_file.pending.where.not(summary: summaries).destroy_all
  end

  # THE ROW THIS STEP NAMES, IF THE WORLD HAS ONE. Through `Quest::Binder`, so
  # the name rule is stated once for every path that binds an arc. Story time
  # is the story's own `start_time`: a seeded arc was bound when the world was
  # written, not when somebody happened to load the file.
  def bind_quest_step!(story, step)
    return if step.time_passed? || step.target_name.blank?

    record = case step.trigger_kind
    when "reach_location" then WorldSeed.find_location(story, step.target_name)
    when "speak_to" then story.characters.find_by("LOWER(fullname) = ?", step.target_name.downcase)
    when "hold_item" then find_item(story, step.target_name)
    end

    Quest::Binder.bind!(record, at: story.start_time) if record
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
    validate_bulks!
    validate_dangers!
    validate_populations!
    validate_hazards!
    validate_boxes!
    validate_positions!

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
      validate_hostility!(attributes)

      next if standing.blank? || names.any? { |name| name.casecmp?(standing) }

      raise InvalidWorld, "#{where}: character #{attributes.fetch("fullname").inspect} is placed in #{standing.inspect}, " \
                          "which this file does not declare as a location"
    end

    validate_opening_scene!(names, openings.first.fetch("name"))
    validate_mechanics!
    validate_quests!
    validate_schedule!
  end

  # EVERYTHING A HAND-EDITED ARC CAN GET WRONG, named here rather than surfacing
  # three records later -- `#validate_mechanics!`'s rule, one table over.
  #
  # WHAT IS DELIBERATELY NOT CHECKED: whether a step's `target` is something
  # this file declares. An UNBOUND step is a legal and expected state -- it is
  # the whole point of the arc's two states (`Quest::Step`) -- and a generated
  # world is born full of them. `rake game:doctor` is what says a world's arc
  # has outrun its rows; a loader that refused one could not load a world the
  # generator wrote.
  def validate_quests!
    titles = quest_documents.map { |attributes| attributes.fetch("title") }
    duplicates = titles.group_by { |title| title }.select { |_, group| group.size > 1 }.keys
    raise InvalidWorld, "#{where}: two quests are called #{duplicates.join(", ")}; a quest is keyed on (story, title)" if duplicates.any?

    # ONE MAIN ARC PER STORY, which `Quest#single_main_arc_per_story` also
    # refuses -- here as well because the record's error names a column and
    # this one names the file and the two quests, which is what somebody
    # editing YAML needs.
    mains = quest_documents.reject { |attributes| attributes["parent"].present? }.map { |attributes| attributes.fetch("title") }
    raise InvalidWorld, "#{where}: #{mains.join(" and ")} both read as the main arc; a story has one, and a side quest names its `parent:`" if mains.size > 1

    quest_documents.each do |attributes|
      parent = attributes["parent"]
      next if parent.blank? || titles.include?(parent)

      raise InvalidWorld, "#{where}: quest #{attributes.fetch("title").inspect} names `parent: #{parent.inspect}`, which this file does not declare"
    end

    quest_documents.each do |attributes|
      title = attributes.fetch("title").inspect
      status = attributes["status"].presence || "open"
      unless Quest::STATUSES.include?(status)
        raise InvalidWorld, "#{where}: quest #{title} has `status: #{status.inspect}`; there is: #{Quest::STATUSES.join(", ")}"
      end

      steps = Array(attributes["steps"])
      raise InvalidWorld, "#{where}: quest #{title} has no steps; an arc with no beats is one nobody can start" if steps.empty?

      steps.each_with_index { |step, index| validate_one_quest_step!(title, step, index + 1) }
      validate_quest_outcomes!(title, Array(attributes["outcomes"]))
    end
  end

  def validate_one_quest_step!(title, attributes, position)
    where_it_is = "quest #{title} step #{position}"
    trigger = attributes["trigger"]
    unless Quest::TRIGGERS.include?(trigger)
      raise InvalidWorld, "#{where}: #{where_it_is} has `trigger: #{trigger.inspect}`; there is: #{Quest::TRIGGERS.join(", ")}"
    end

    raise InvalidWorld, "#{where}: #{where_it_is} has no `summary`, which is the one line the narrator is told" if attributes["summary"].blank?

    if trigger == "time_passed"
      minutes = attributes["minutes"]
      unless minutes.is_a?(Integer) && minutes.positive?
        raise InvalidWorld, "#{where}: #{where_it_is} is `time_passed` and needs `minutes:` as a whole number of story minutes, got #{minutes.inspect}"
      end
      raise InvalidWorld, "#{where}: #{where_it_is} is `time_passed` and cannot also name a `target`" if attributes["target"].present?
    else
      raise InvalidWorld, "#{where}: #{where_it_is} is `#{trigger}` and needs a `target:` -- the name the arc waits for" if attributes["target"].blank?
      raise InvalidWorld, "#{where}: #{where_it_is} is `#{trigger}` and cannot carry `minutes:`" if attributes["minutes"].present?
    end
  end

  # AN ARC WITH NO ENDING IS AN ARC NOTHING CAN FINISH, which is the fourth of
  # the captain's five properties. Refused in the FILE rather than only reported
  # by the doctor, because a hand-authored world is a decision: nobody writes
  # three beats and means for them to lead nowhere.
  def validate_quest_outcomes!(title, documents)
    raise InvalidWorld, "#{where}: quest #{title} has no outcomes; reaching its last step would end nothing" if documents.empty?

    names = documents.map { |attributes| attributes.fetch("name") }
    duplicates = names.group_by { |name| name }.select { |_, group| group.size > 1 }.keys
    raise InvalidWorld, "#{where}: quest #{title} has two outcomes called #{duplicates.join(", ")}" if duplicates.any?

    documents.each do |attributes|
      raise InvalidWorld, "#{where}: quest #{title} outcome #{attributes.fetch("name").inspect} has no `summary`" if attributes["summary"].blank?

      validate_one_quest_outcome!(title, attributes)
    end

    defaults = documents.count { |attributes| attributes["default"] == true }
    return if defaults == 1

    raise InvalidWorld, "#{where}: quest #{title} marks #{defaults} outcomes `default: true`; exactly one is the ending the world was born with"
  end

  # THE RULE THAT SELECTS ONE ENDING, and the number and the ramification that
  # go with it. Refused in the FILE for `#validate_quest_outcomes!`' reason: a
  # hand-authored ending is a decision, and a misspelt `when:` that loaded
  # quietly would be an ending nobody could ever reach and nobody would notice
  # until the doctor said so a month later.
  #
  # A MISSING `when:` IS NOT AN ERROR. It is what the DEFAULT is, and on a
  # non-default outcome it is a world with an ending nothing selects -- legal,
  # reported by `rake game:doctor` (`outcome_nothing_can_reach`), and the state
  # every world with a second ending was in before conditions existed.
  def validate_one_quest_outcome!(title, attributes)
    name = attributes.fetch("name").inspect
    where_it_is = "quest #{title} outcome #{name}"
    condition = attributes["when"]

    if condition.present? && !Quest::Outcome::CONDITIONS.key?(condition)
      raise InvalidWorld, "#{where}: #{where_it_is} has `when: #{condition.inspect}`; there is: #{Quest::Outcome::CONDITIONS.keys.join(", ")}"
    end

    if condition.present? && attributes["default"] == true
      raise InvalidWorld, "#{where}: #{where_it_is} is `default: true` and also names `when: #{condition.inspect}`; " \
                          "the default is the ending an arc falls through to, which is what having no rule means"
    end

    if Quest::Outcome::NEEDS_MINUTES.include?(condition)
      minutes = attributes["minutes"]
      unless minutes.is_a?(Integer) && minutes.positive?
        raise InvalidWorld, "#{where}: #{where_it_is} is `when: #{condition}` and needs `minutes:` as a whole number of story minutes, got #{minutes.inspect}"
      end
    elsif attributes["minutes"].present?
      raise InvalidWorld, "#{where}: #{where_it_is} carries `minutes:` and `when: #{condition.inspect}` takes no number"
    end

    validate_one_ramification!(where_it_is, attributes["ramification"])
  end

  # ONE SCHEDULED ROW AN ENDING PUTS ON THE STREAM: an hour and a sentence, both
  # or neither. `Quest::Outcome` refuses a half-written one too; this is the
  # message somebody editing YAML needs, which names the file and the ending.
  def validate_one_ramification!(where_it_is, document)
    return if document.nil?

    raise InvalidWorld, "#{where}: #{where_it_is} has a `ramification:` that is not a mapping" unless document.is_a?(Hash)

    minutes = document["after_minutes"]
    unless minutes.is_a?(Integer) && minutes.positive?
      raise InvalidWorld, "#{where}: #{where_it_is}'s `ramification:` needs `after_minutes:` as a whole number of story minutes, got #{minutes.inspect}"
    end

    return if document["summary"].present?

    raise InvalidWorld, "#{where}: #{where_it_is}'s `ramification:` has no `summary`, which is the whole of what the scheduled row says"
  end

  # WHAT THIS WORLD HAS ALREADY DECIDED WILL HAPPEN -- Call 8's bomb, as world
  # data. Two keys and nothing else: the sentence, which is also the row's
  # identity, and how long after the story opens it comes due.
  def validate_schedule!
    summaries = schedule_documents.map do |attributes|
      raise InvalidWorld, "#{where}: a `schedule:` entry is not a mapping" unless attributes.is_a?(Hash)

      summary = attributes["summary"]
      raise InvalidWorld, "#{where}: a `schedule:` entry has no `summary`, which is what the event says and how it is keyed" if summary.blank?

      minutes = attributes["after_minutes"]
      unless minutes.is_a?(Integer) && minutes.positive?
        raise InvalidWorld, "#{where}: scheduled event #{summary.inspect} needs `after_minutes:` as a whole number of story minutes, got #{minutes.inspect}"
      end

      summary
    end

    duplicates = summaries.group_by { |summary| summary }.select { |_, group| group.size > 1 }.keys
    return if duplicates.none?

    raise InvalidWorld, "#{where}: two scheduled events say #{duplicates.map(&:inspect).join(", ")}; a scheduled event is keyed on its own sentence"
  end

  # A BODY THE ENGINE COULD NEVER HAVE ROLLED, caught here rather than three
  # records later. `Character` validates the same two columns inside the
  # transaction, so a file with the fault never loads either way -- but the
  # record's error names a column and this one names the file and the person,
  # which is what somebody editing YAML needs. Same reason the inscriptions are
  # checked here.
  #
  # A PARTIAL BLOCK IS REFUSED TOO, and it is refused as ONE thing: a `stats:`
  # key is all five of `STAT_KEYS` or it is not there. `Character#max_hp` needs
  # the level and the die, `Character#check` needs the three abilities, and a
  # mapping carrying some of them is a key that looks as though it said
  # something and did not. The record refuses the two halves separately
  # (`#a_stat_block_is_whole`, `#abilities_are_whole`); the FILE is held to the
  # whole sheet, because a hand-authored world is the decision and a
  # half-authored one is an editing slip.
  def validate_stats!(attributes)
    stats = attributes["stats"]
    return if stats.nil?

    who = attributes.fetch("fullname").inspect
    unless stats.is_a?(Hash) && stats.keys.sort == STAT_KEYS.sort
      raise InvalidWorld, "#{where}: character #{who} has `stats: #{stats.inspect}` -- it is a mapping of " \
                          "#{STAT_KEYS.map { |key| "`#{key}`" }.join(", ")}, and all of them together or none"
    end

    unless Character::LEVELS.include?(stats["level"])
      raise InvalidWorld, "#{where}: character #{who} has level #{stats["level"].inspect}; " \
                          "a level is #{Character::LEVELS.first}..#{Character::LEVELS.last}"
    end

    unless Character::HIT_DICE.include?(stats["hit_die"])
      raise InvalidWorld, "#{where}: character #{who} has hit die #{stats["hit_die"].inspect}; " \
                          "the engine rolls one of #{Character::HIT_DICE.join(", ")}"
    end

    validate_abilities!(who, stats)
  end

  # AN ABILITY THE ENGINE COULD NEVER HAVE ROLLED. 3d6 cannot come up 2 or 19,
  # so `Character::ABILITY_RANGE` is the roll's own bounds and a number outside
  # it came from somewhere that is not the engine.
  def validate_abilities!(who, stats)
    Character::ABILITIES.each do |ability|
      score = stats[ability.to_s]
      next if Character::ABILITY_RANGE.include?(score)

      raise InvalidWorld, "#{where}: character #{who} has #{ability} #{score.inspect}; an ability is " \
                          "#{Character::ABILITY_RANGE.first}..#{Character::ABILITY_RANGE.last}, which is what 3d6 rolls"
    end
  end

  # A FOE WITH NO BODY, caught here rather than the first time somebody swings
  # at it. `characters.hostile` says this person attacks the party, and a fight
  # is arithmetic over `Character#max_hp` -- so a hostile character with no
  # `stats` is a monster nothing can hurt and that can never be hurt back. The
  # record allows it (both stat columns are nullable, because a database older
  # than them is a real state), and `rake game:doctor` reports one it finds
  # (`hostile_without_a_stat_block`); a FILE is held to the stronger rule,
  # because a hand-authored world is the decision and this one is an editing
  # slip. Same reasoning as `#validate_stats!`, one key over.
  def validate_hostility!(attributes)
    return unless attributes["hostile"] == true
    return if attributes["stats"].is_a?(Hash)

    raise InvalidWorld, "#{where}: character #{attributes.fetch("fullname").inspect} is `hostile: true` with no " \
                        "`stats` -- a foe needs a body, because a fight is arithmetic over its hit points"
  end

  # A DANGER THE ENGINE HAS NO TABLE FOR. `Location::DANGERS` is the closed set
  # of what a room may be -- the labels are what an author reads and the numbers
  # are what the engine rolls -- so a fifth word is a typo, and it is named here
  # with the file and the room rather than surfacing as a validation error on a
  # column. Same reason the stats and the inscriptions are checked here.
  def validate_dangers!
    location_documents.each do |attributes|
      danger = attributes["danger"]
      next if danger.blank? || Location::DANGERS.key?(danger)

      raise InvalidWorld, "#{where}: location #{attributes.fetch("name").inspect} has `danger: #{danger.inspect}`; " \
                          "there is: #{Location::DANGERS.keys.join(", ")}"
    end
  end

  # A POPULATION WORD THE ENGINE HAS NO BAND FOR. `Location::Population::BANDS`
  # is the closed set of how populated a place may be -- the labels are what an
  # author and a model read, the counts are what the engine rolls inside -- so a
  # fourth word is a typo, and it is named here with the file and the room for
  # `#validate_dangers!`'s reason one method up.
  #
  # A BLANK KEY IS NOT A TYPO and passes: it means the file does not say, which
  # is a real answer and the one every checked-in world gives. See
  # `#load_locations!` on why that is not the same as `nobody`.
  def validate_populations!
    location_documents.each do |attributes|
      population = attributes["population"]
      next if population.blank? || Location::Population::BANDS.key?(population)

      raise InvalidWorld, "#{where}: location #{attributes.fetch("name").inspect} has " \
                          "`population: #{population.inspect}`; " \
                          "there is: #{Location::Population::LABELS.join(", ")}"
    end
  end

  # A HAZARD THE ENGINE HAS NO TABLE FOR, OR HALF OF ONE, on either a room or a
  # doorway. `Location::HAZARDS` and `LocationConnection::HAZARDS` are the two
  # closed catalogues -- the labels are what an author reads and the numbers are
  # what the engine rolls -- so a word outside them is a typo, and it is named
  # here with the file and the room rather than surfacing as a validation error
  # on a column. Same reason the dangers and the inscriptions are checked here.
  #
  # HALF A HAZARD IS THE OTHER MISTAKE and it is the silent one: a `hazard:`
  # with no `hazard_die:` reads as though the file said something and the room
  # is simply not hazardous. `Location` and `LocationConnection` both refuse the
  # pair too, so a file with the fault never loads either way; this names it.
  #
  # AND `hazard_from:` MUST NAME ONE OF THE EDGE'S OWN TWO ENDS. It is the whole
  # of how a file says which direction costs something, so a name outside the
  # pair -- a typo, or the room next door -- would load an edge with no hazard
  # on it at all and no complaint.
  def validate_hazards!
    location_documents.each do |attributes|
      validate_one_hazard!(Location::HAZARDS, attributes, "location #{attributes.fetch("name").inspect}")
    end

    connection_documents.each do |attributes|
      pair = Array(attributes["between"])
      where_it_is = "connection #{pair.join(" <-> ")}"
      validate_one_hazard!(LocationConnection::HAZARDS, attributes, where_it_is)

      from = attributes["hazard_from"]
      if attributes["hazard"].present? && from.blank?
        raise InvalidWorld, "#{where}: #{where_it_is} has a `hazard` and no `hazard_from` -- a doorway's hazard is " \
                            "one-way, so the file has to say which of the two rooms you are leaving when it is paid"
      end
      next if from.blank? || pair.any? { |name| WorldSeed.natural_key(name) == WorldSeed.natural_key(from) }

      raise InvalidWorld, "#{where}: #{where_it_is} has `hazard_from: #{from.inspect}`, which is not one of its own " \
                          "two ends (#{pair.join(", ")})"
    end
  end

  # A LAYOUT A FILE CAN GET WRONG, and a file is held to every rule the records
  # allow -- `#validate_stats!`'s argument for a body, said for a place. A
  # hand-authored world IS the decision about what is inside what; a half-laid
  # out one is an editing slip, and the slip is silent. A position on a room
  # with no `parent` reads against nothing at all, and two rooms in the same
  # place at once load without complaint and are only ever noticed by somebody
  # drawing the map.
  #
  # `Location::Box` owns what a whole shape IS -- an extent alone is a
  # FOOTPRINT, the plane a place's children are read in; all five is a BOX, a
  # room placed on a storey of its parent; anything else is partial. What is
  # here is the six rules a FILE is held to on top of that:
  #
  #   whole      one of `Location::Box.shape`'s three whole answers. `Location`
  #              refuses a partial one too, so a file with one never loads
  #              either way; this names the file and the room.
  #   integers   whole numbers, with a positive width and depth. A room zero
  #              paces across is a room nothing can stand in.
  #   framed     a BOX needs a `parent`, because coordinates are local to a
  #              parent and there is no global space. A footprint does not, and
  #              must not be made to: something has to sit at the top of the
  #              containment tree.
  #   footprint  and that parent needs an extent of its own, or the plane the
  #              child's position is read in does not exist.
  #   declared   `parent` names one of this file's own locations, and not
  #              itself, and not a cycle -- a room cannot be inside a place that
  #              is inside it.
  #   apart      no two boxes under one parent on one storey overlap. Across
  #              storeys is not an overlap at all: 2.5D, so each floor is its
  #              own plane (the captain's third ruling of 2026-09-06).
  #
  # `rake game:doctor` reports these faults on a database that already carries
  # them -- all but the half of `declared` that is a question about a file and
  # not about a row, that a `parent` names a location THIS FILE declares -- which
  # is what makes a world written before any of this diagnosable rather than
  # unloadable. The file is held to the stronger rule.
  def validate_boxes!
    location_documents.each do |attributes|
      validate_one_box!(attributes)
      validate_one_parent!(attributes)
    end

    validate_no_parent_cycles!
    validate_boxes_do_not_overlap!
  end

  def validate_one_box!(attributes)
    room = attributes.fetch("name").inspect
    written = Location::Box::COLUMNS.reject { |column| attributes[column].nil? }
    return if written.empty?

    if Location::Box.partial?(attributes)
      raise InvalidWorld, "#{where}: location #{room} carries #{written.join(", ")}, which is neither a " \
                          "footprint (#{Location::Box::EXTENT.join(", ")}) nor a box (all of " \
                          "#{Location::Box::COLUMNS.join(", ")}) -- a place missing part of either has no shape " \
                          "the engine can read"
    end

    written.each do |column|
      value = attributes[column]
      raise InvalidWorld, "#{where}: location #{room} has `#{column}: #{value.inspect}`; a box is whole " \
                          "numbers of paces" unless value.is_a?(Integer)
    end

    Location::Box::EXTENT.each do |column|
      next if attributes[column].positive?

      raise InvalidWorld, "#{where}: location #{room} has `#{column}: #{attributes[column]}` -- a place is at " \
                          "least one pace across, and one that is not is a place nothing can stand in"
    end
  end

  # WHAT A `parent` HAS TO NAME, and the rules a BOX brings with it. Checked here
  # rather than in `#load_containment!` because that runs inside the transaction
  # and reports by column; somebody editing YAML needs the file and the room.
  def validate_one_parent!(attributes)
    room = attributes.fetch("name")
    parent = attributes["parent"]
    placed = Location::Box.shape(attributes) == :box

    if parent.blank?
      return unless placed

      raise InvalidWorld, "#{where}: location #{room.inspect} has a position and is inside nothing -- " \
                          "#{Location::Box::POSITION.join(", ")} are read in the parent's own plane, so a placed " \
                          "room needs a `parent`. A place at the top of an interior carries " \
                          "#{Location::Box::EXTENT.join(" and ")} alone."
    end

    found = location_documents.detect { |candidate| WorldSeed.natural_key(candidate.fetch("name")) == WorldSeed.natural_key(parent) }
    if found.nil?
      raise InvalidWorld, "#{where}: location #{room.inspect} has `parent: #{parent.inspect}`, which this file " \
                          "does not declare as a location"
    end

    if WorldSeed.natural_key(found.fetch("name")) == WorldSeed.natural_key(room)
      raise InvalidWorld, "#{where}: location #{room.inspect} is its own `parent`"
    end

    return unless placed
    return if Location::Box::EXTENT.none? { |column| found[column].nil? }

    raise InvalidWorld, "#{where}: location #{room.inspect} is placed inside #{found.fetch("name").inspect}, " \
                        "which has no footprint of its own -- so the plane its position is read in does not exist"
  end

  # A ROOM INSIDE A PLACE THAT IS INSIDE IT. Refused rather than loaded, because
  # a cycle is a containment graph with no outermost place: nothing that walks
  # it upwards -- a description, a map, a repair -- has a stopping condition.
  def validate_no_parent_cycles!
    parents = location_documents.to_h do |attributes|
      [ WorldSeed.natural_key(attributes.fetch("name")),
        attributes["parent"].presence&.then { |name| WorldSeed.natural_key(name) } ]
    end

    parents.each_key do |start|
      seen = [ start ]
      walker = parents[start]
      while walker
        if seen.include?(walker)
          raise InvalidWorld, "#{where}: these locations contain each other: #{(seen + [ walker ]).join(" -> ")}"
        end

        seen << walker
        walker = parents[walker]
      end
    end
  end

  # TWO ROOMS IN THE SAME PLACE AT ONCE, decided exactly the way
  # `Story::Doctor#overlapping_sibling_rooms` decides it, off the same
  # `Location::Box` -- so the file and the database cannot disagree about what
  # an overlap is.
  def validate_boxes_do_not_overlap!
    placed = location_documents.select { |attributes| Location::Box.of(attributes) }

    placed.group_by { |attributes| [ WorldSeed.natural_key(attributes.fetch("parent")), attributes.fetch("z") ] }
          .each_value do |siblings|
      siblings.combination(2).each do |one, other|
        next unless Location::Box.of(one).overlaps?(Location::Box.of(other))

        raise InvalidWorld, "#{where}: #{one.fetch("name").inspect} (#{Location::Box.of(one)}) and " \
                            "#{other.fetch("name").inspect} (#{Location::Box.of(other)}) are both inside " \
                            "#{one.fetch("parent").inspect} and are in the same place at once"
      end
    end
  end

  # WHERE IN A ROOM A FILE MAY PUT A THING OR A PERSON, and it is OPT-IN like
  # every box key: a file that writes neither `x` nor `y` on an item or a
  # character is saying "unplaced", which is what every row of all three
  # checked-in worlds is and what the two nullable columns mean
  # (`Location::Spot`).
  #
  # `#validate_boxes!`' ARGUMENT, SAID FOR A THING RATHER THAN A ROOM: a
  # hand-authored world IS the decision about what is where, and every one of
  # these mistakes is silent. A position on an item in somebody's hands reads
  # against nothing; a position in a room with no box reads against a plane that
  # does not exist; a position through the wall loads without complaint and is
  # only ever noticed by somebody drawing the floor plan.
  #
  # THE FOUR RULES A FILE IS HELD TO, on top of what `Location::Spot` says a
  # position IS:
  #
  #   whole      both numbers or neither -- `Location::Spot.shape`'s two whole
  #              answers. `Item` and `Character` refuse a partial one too, so a
  #              file with one never loads either way; this names the file and
  #              the row.
  #   integers   whole numbers of paces, like a box's five.
  #   on a floor a position needs a room to be read in. An item nested under a
  #              `characters[]` entry is in a pair of hands and has none; a
  #              character with no `location` is nowhere and has none.
  #   inside     that room carries a BOX -- all five columns, so it has a plane
  #              -- and the two numbers are on its floor
  #              (`Location::Box#contains?`, half-open like everything else).
  #
  # `rake game:doctor` reports all four on a database that already carries them,
  # so a world written before any of this is diagnosable rather than unloadable.
  # The file is held to the stronger rule.
  def validate_positions!
    boxes = location_documents.to_h { |attributes| [ WorldSeed.natural_key(attributes.fetch("name")), attributes ] }

    location_documents.each do |attributes|
      room = attributes.fetch("name")
      Array(attributes["items"]).each { |item| validate_one_position!(item, "item", "name", room, boxes) }
    end

    character_documents.each do |attributes|
      person = attributes.fetch("fullname")
      Array(attributes["items"]).each do |item|
        next if Location::Spot.shape(item) == :none

        raise InvalidWorld, "#{where}: item #{item.fetch("name").inspect} is in #{person.inspect}'s hands and " \
                            "carries #{Location::Spot::COLUMNS.join(", ")} -- a position is read in the plane of " \
                            "the room a thing is LYING in, and something being carried is in no room"
      end

      validate_one_position!(attributes, "character", "fullname", attributes["location"], boxes)
    end
  end

  # ONE ROW'S TWO NUMBERS, against the room the file puts it in. `room` is a
  # name and may be nil -- a character with no `location` is nowhere -- which is
  # the "on a floor" rule for a person.
  def validate_one_position!(attributes, kind, name_key, room, boxes)
    return if Location::Spot.shape(attributes) == :none

    subject = "#{kind} #{attributes.fetch(name_key).inspect}"

    if Location::Spot.partial?(attributes)
      written = Location::Spot::COLUMNS.select { |column| attributes[column] }
      raise InvalidWorld, "#{where}: #{subject} carries #{written.join(", ")} and not the other of " \
                          "#{Location::Spot::COLUMNS.join(", ")} -- a position is both numbers or neither"
    end

    Location::Spot::COLUMNS.each do |column|
      next if attributes[column].is_a?(Integer)

      raise InvalidWorld, "#{where}: #{subject} has `#{column}: #{attributes[column].inspect}`; a position is " \
                          "whole numbers of paces"
    end

    if room.blank?
      raise InvalidWorld, "#{where}: #{subject} carries #{Location::Spot::COLUMNS.join(", ")} and is in no room -- " \
                          "a position is read in the plane of the room a row is in, and nowhere is not one"
    end

    found = boxes[WorldSeed.natural_key(room)]
    box = found && Location::Box.of(found)
    if box.nil?
      raise InvalidWorld, "#{where}: #{subject} is #{Location::Spot.of(attributes)} in #{room.inspect}, which " \
                          "carries no box -- so the plane its position is read in does not exist"
    end

    return if box.contains?(Location::Spot.of(attributes))

    raise InvalidWorld, "#{where}: #{subject} is #{Location::Spot.of(attributes)} in #{room.inspect}, which is " \
                        "#{box} -- so it is outside the room it is in"
  end

  def validate_one_hazard!(catalogue, attributes, where_it_is)
    hazard = attributes["hazard"]
    die = attributes["hazard_die"]
    return if hazard.blank? && die.blank?

    unless catalogue.key?(hazard)
      raise InvalidWorld, "#{where}: #{where_it_is} has `hazard: #{hazard.inspect}`; there is: #{catalogue.keys.join(", ")}"
    end

    return if Location::HAZARD_DICE.include?(die)

    raise InvalidWorld, "#{where}: #{where_it_is} has `hazard_die: #{die.inspect}`; a hazard is a key AND a die, " \
                        "and the dice are: #{Location::HAZARD_DICE.join(", ")}"
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

  # A BULK THE ENGINE HAS NO TABLE FOR. `Item::BULK` is the closed set of what a
  # thing may weigh -- the labels are what an author reads and the numbers are
  # what the engine subtracts from a thrower's strength -- so a fifth word is a
  # typo. `Item` validates the same key inside the transaction, so a file with
  # the fault never loads either way; the record's error names a column and this
  # one names the FILE and the ITEM, which is what somebody editing YAML needs.
  # Same reason the inscriptions, the stats and the dangers are checked here.
  def validate_bulks!
    (character_documents + location_documents).each do |owner|
      Array(owner["items"]).each do |item|
        bulk = item["bulk"]
        next if bulk.blank? || Item::BULK.key?(bulk)

        raise InvalidWorld, "#{where}: item #{item.fetch("name").inspect} has `bulk: #{bulk.inspect}`; " \
                            "there is: #{Item::BULK.keys.join(", ")}"
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

  # A location of this story, by the name the file gives it -- then by the name
  # the file USED to give it, and then by the place and the box the file draws
  # it in, which is how a room the ENGINE renamed is still recognized.
  #
  # `WorldSeed.find_location` owns all three passes and is shared with
  # `Story::Doctor` and `Story::Repair` on purpose: three readers of one
  # question that disagreed would report, repair and re-seed three different
  # worlds. Read its header for what each pass buys.
  #
  # THE FILE'S OWN DECLARATION IS HANDED OVER HERE rather than at each call
  # site, so every lookup this loader makes -- a room, a room's parent, the room
  # a character stands in -- widens the same way. `#validate!` refuses a file
  # whose own rooms collide on `WorldSeed.natural_key`, so there is never more
  # than one declaration to hand over.
  def find_location(story, name)
    WorldSeed.find_location(story, name, declared_locations)
  end

  # THE FILE'S OWN LOCATIONS BY `WorldSeed.natural_key`, handed over whole
  # rather than one declaration at a time: `WorldSeed.find_location`'s widest
  # pass reads the box off the declaration for the name it was asked about AND
  # the set of every name this document spoke for, and those two have to come
  # from one document or a row could be claimed twice. `#validate!` refuses a
  # file whose own rooms collide on that key, so the index is one to one.
  def declared_locations
    @declared_locations ||= location_documents.index_by { |attributes| WorldSeed.natural_key(attributes["name"]) }
  end

  # WHAT THIS LOAD CALLS A ROW THE FILE DECLARES: the file's name, which is the
  # rule, or the name the row already carries in the one case
  # `WorldSeed.keeps_its_own_name?` describes. Read on the row rather than on
  # the pass that found it, for the reason that predicate gives.
  def written_name(location, attributes, name)
    WorldSeed.keeps_its_own_name?(location, attributes) ? location.name : name
  end

  # A row recognized under a different written name, said out loud -- AND WHICH
  # WAY THE TWO NAMES WERE RECONCILED, because since `Location::RoomName` the
  # answer is not always the file's. The write itself is the caller's
  # `assign_attributes`; this only reports it, so a load that quietly renamed
  # something is not a shape this class has -- and a load that quietly DECLINED
  # to rename something would not be either, which is the second branch.
  def note_rename(kind, record, name, written: name)
    return unless record.persisted?
    return if record.name == name

    reconciled << if record.name == written
      "#{kind} #{record.name.inspect} is #{name.inspect} in the file, which is one of its place's provisional " \
        "numbers, so the row kept the name it has (##{record.id}, unchanged otherwise)"
    else
      "#{kind} #{record.name.inspect} is #{name.inspect} in the file, so the row was renamed rather " \
        "than a second #{kind} created beside it (##{record.id}, unchanged otherwise)"
    end
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

  def quest_documents
    Array(document["quests"])
  end

  def schedule_documents
    Array(document["schedule"])
  end
end
