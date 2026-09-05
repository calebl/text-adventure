# What is wrong with a story, in sentences a person can act on.
#
# A world here outlives the schema that made it. `rake game:new` writes records
# that stay in the database while features land around them, so a story
# generated before opening arrivals existed still sits next to one generated
# after, and the difference only shows up when somebody tries to play it --
# usually as a stack trace, mid-turn, which is the least useful possible form
# for it to take.
#
# So this asks the questions the play path asks, ahead of the play path, and
# answers them in English. EVERY CHECK MIRRORS SOMETHING REAL: the comment on
# each one names the code that would otherwise be the first to notice. When
# that code changes, the check changes with it -- a doctor that reports on a
# precondition the game no longer has is worse than no doctor.
#
# What it deliberately does NOT do is decide anything. It reports; `Story::Repair`
# acts on what it reports, and only on the findings whose remedy is honest.
class Story::Doctor
  # `fatal` means the story cannot be played at all -- `PlaythroughsController`
  # refuses it, or the first turn raises. `warning` means it opens and something
  # in it is still wrong.
  SEVERITIES = %i[fatal warning].freeze

  # What could be done about it, and this is the line the whole tool turns on:
  #
  #   safe     the right value is derivable from records that already exist.
  #   generate the right value can be written, but only by asking a model --
  #            which costs a call and an API key, so it is opt-in.
  #   manual   there is no honest answer. Backfilling it would mean inventing
  #            world data to make a validation pass, and this never does that.
  REMEDIES = %i[safe generate manual].freeze

  Finding = Data.define(:code, :severity, :message, :remedy, :subject) do
    # `subject` is the record the repair acts on -- the location to write exits
    # for, the connection to mirror. Nil for a finding about the story itself.
    def initialize(subject: nil, **rest) = super

    def fatal? = severity == :fatal

    # Whether Story::Repair can act on this. A `generate` finding only counts
    # once the caller has said out loud that a model call is acceptable.
    def repairable?(generate: false)
      remedy == :safe || (generate && remedy == :generate)
    end
  end

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # Every story in the database, oldest first, each with its doctor.
  def self.all(scope = Story.all)
    scope.includes(:universe).order(:created_at, :id).map { |story| new(story) }
  end

  def findings
    @findings ||= [
      *story_fields,
      *universe_fields,
      *opening_location,
      *duplicate_locations,
      *exits,
      *opening_scene,
      *connection_rows,
      *re_asserted_doorways,
      *cast,
      *whereabouts,
      *scene_rows,
      *playthrough_rows,
      *item_rows,
      *stat_blocks,
      *abilities,
      *hostility,
      *hazards,
      *vitals_rows
    ]
  end

  # THE ONE QUESTION THE INDEX PAGE AND `PlaythroughsController#create` ALREADY
  # ASK, asked here in full. Both of them stop at "is there a realized location
  # to start in"; a story can clear that and still fail on its first turn, which
  # is why this is the whole fatal set rather than that one check.
  def playable? = findings.none?(&:fatal?)

  def healthy? = findings.empty?

  def fatal = findings.select(&:fatal?)

  def warnings = findings.reject(&:fatal?)

  # One line for a list: the title, and either what is wrong or that nothing is.
  def headline
    return "healthy" if healthy?
    return "unplayable: #{fatal.first.message}" unless playable?

    "playable, #{warnings.size} warning#{"s" unless warnings.one?}"
  end

  # Where a playthrough would actually start, decided exactly as
  # `PlaythroughsController#opening_location` decides it: the first REALIZED
  # location, because a stub has a name and a teaser and nothing to read.
  def play_location
    @play_location ||= story.locations.realized.order(:id).first
  end

  # `{ fullname => room name }` out of the checked-in world file for this
  # story, or empty for a story that is not one of them -- which is every
  # generated world and every engine-sweep copy.
  def seeded_whereabouts
    @seeded_whereabouts ||= begin
      document = seed_document
      Array(document && document["characters"])
        .filter_map { |row| [ row["fullname"], row["location"] ] if row["location"].present? }
        .to_h
    end
  end

  # `{ natural key => the name the file writes }` for this story's rooms, out
  # of the checked-in world file, or empty for a story that is not one of them.
  #
  # KEYED ON `WorldSeed.natural_key` because that is the key `WorldSeed::Loader`
  # matches a room under, so this answers the only question a duplicate-room
  # finding needs: does the FILE say these two rows are one room, and what does
  # it call it. A story with no file answers nothing and its duplicates are
  # reported `manual`.
  def seeded_location_names
    @seeded_location_names ||= Array(seed_document && seed_document["locations"])
                               .filter_map { |row| [ WorldSeed.natural_key(row["name"]), row["name"] ] if row["name"].present? }
                               .to_h
  end

  # `{ natural key => the name the file writes }` for this story's items, on
  # both sides of `Item::PLACES`, out of the checked-in world file. Empty for a
  # story that is not one of them, which makes every duplicate in a generated
  # world `manual` -- as it must be, since nothing is on record about which of
  # two rows the world meant.
  def seeded_item_names
    @seeded_item_names ||= begin
      document = seed_document
      owners = Array(document && document["locations"]) + Array(document && document["characters"])

      owners.flat_map { |owner| Array(owner["items"]) }
            .filter_map { |item| [ WorldSeed.natural_key(item["name"]), item["name"] ] if item["name"].present? }
            .to_h
    end
  end

  # The doorways the checked-in file gives each `mobile: true` room: the edges
  # it declares with exactly one mobile end, counted per mobile room, as
  # `{ room name => count }`. What `WorldMechanic::ShuffleConnections` moves and
  # what it preserves -- it repoints the far end and keeps the count.
  def seeded_mobile_arity
    @seeded_mobile_arity ||= begin
      document = seed_document
      mobile = Array(document && document["locations"]).select { |row| row["mobile"] }.map { |row| row["name"] }.to_set

      Array(document && document["connections"]).filter_map do |row|
        pair = Array(row["between"]).select { |name| mobile.include?(name) }
        pair.first if pair.one?
      end.tally
    end
  end

  # The unordered endpoint pairs the checked-in file declares, as a set of
  # sorted name pairs. Read by the arity finding to tell the doorway a re-seed
  # re-asserted from the one the world's own mechanic moved.
  def seeded_doorways
    @seeded_doorways ||= Array(seed_document && seed_document["connections"])
                         .map { |row| Array(row["between"]).sort }
                         .to_set
  end

  # WHETHER ANYBODY HAS EVER BEEN IN THIS ROOM: a scene that happened here, a
  # party standing here, or a stamped visit. The line between world and
  # progress, drawn where `WorldSeed::Exporter` draws it, and the one a fold of
  # two rows that are one room stops at -- `Story::Repair` reads it here rather
  # than deciding for itself, so the two cannot disagree about which of the pair
  # has the history.
  #
  # An OPENING arrival counts, though it is world data: destroying the row that
  # holds it would take the story's one opening scene with it.
  def stood_in?(room)
    room.last_protagonist_visit.present? ||
      room.scenes.exists? ||
      Playthrough.where(current_location: room).exists?
  end

  # Whether anybody has handled this item: a party carrying it, or a turn log
  # recording the take or the drop that moved it (`scenes.acted_on`). The item
  # half of `#stood_in?`, and the line a `safe` fold of a duplicate stops at.
  # Since the layer split the first clause is a statement about the LAYER: one
  # of the world's own rows has no playthrough on it by definition, so what is
  # really being asked is whether any turn log records acting on this row. It is
  # kept whole rather than trimmed because the question is "has anybody touched
  # it", and a row that somehow carried a playthrough would be somebody's
  # whatever the turn log said.
  def untouched?(item)
    item.playthrough_id.nil? && !Scene.where(acted_on: item).exists?
  end

  # EVERY LOCATION OF THE STORY STILL REACHABLE FROM EVERY OTHER WITH THIS ONE
  # EDGE GONE, checked the same way `WorldMechanic::ShuffleConnections#connected?`
  # checks its own arrangements: a breadth-first walk over a few dozen nodes.
  #
  # It is here rather than in `Story::Repair` because it decides the REMEDY as
  # well as the repair. A doorway whose far side leads nowhere else cannot be
  # closed at all -- The Celestial Spire in the captain's own database is a stub
  # reachable only from the rooftops -- and a finding that promised `safe` and
  # then refused every time would be worse than one that says what it is.
  def whole_without?(row)
    ids = story.locations.order(:id).pluck(:id)
    return true if ids.size <= 1

    dropped = [ row.location_id, row.connected_location_id ].sort
    adjacency = Hash.new { |hash, key| hash[key] = [] }
    LocationConnection.where(location_id: ids).pluck(:location_id, :connected_location_id).each do |pair|
      next if pair.sort == dropped

      adjacency[pair.first] << pair.last
    end

    reached = Set.new([ ids.first ])
    frontier = [ ids.first ]
    while (id = frontier.pop)
      adjacency[id].each { |neighbour| frontier << neighbour if reached.add?(neighbour) }
    end

    reached.size == ids.size
  end

  # THE ROWS A DUPLICATE FINDING IS ABOUT, recomputed from the natural key.
  # Read by `Story::Repair`, so the doctor and the repair cannot disagree about
  # which rows are the pair -- the same reason they share `#taken_items`.
  def duplicate_location_rows(key)
    Location.where(story_id: story.id).order(:id).select { |room| WorldSeed.natural_key(room.name) == key }
  end

  # THE WORLD'S OWN ROWS ONLY, exactly as `#duplicate_items` asks the question:
  # a playthrough's copy shares its template's name and is nobody's collision,
  # so a repair that folded one would be folding somebody's game.
  def duplicate_item_rows(key)
    story_items.templates.to_a.select { |item| WorldSeed.natural_key(item.name) == key }
  end

  # The fullnames the checked-in file marks `absent: true` -- nowhere on
  # purpose -- or empty for a story that is not one of the checked-in worlds.
  # The counterpart of `#seeded_whereabouts` and read for the same reason: what
  # the file says is on record, so a finding about it can be `safe`.
  def seeded_absences
    @seeded_absences ||= Array(seed_document && seed_document["characters"])
                         .filter_map { |row| row["fullname"] if row["absent"] == true }
                         .to_set
  end

  private

  def finding(code, severity, message, remedy, subject: nil)
    Finding.new(code: code, severity: severity, message: message, remedy: remedy, subject: subject)
  end

  # `Story#clock` falls back to `start_time`, and every scene a turn writes is
  # stamped from it (`Playthrough#story_time_after`). Without one the first turn
  # raises on `nil + minutes`, so this is fatal rather than untidy.
  #
  # It is also the one story field with a derivable answer: a story started no
  # later than its own earliest scene.
  def story_fields
    findings = []

    if story.start_time.nil?
      remedy = earliest_scene_timestamp ? :safe : :manual
      findings << finding(:missing_start_time, :fatal,
                          "has no start_time, so the story has no clock and the first turn raises on `nil + minutes`" +
                            (remedy == :safe ? " (its earliest scene is at #{earliest_scene_timestamp.utc.iso8601}, which is the answer)" : ""),
                          remedy)
    end

    story.valid?
    missing = story.errors.attribute_names.map(&:to_s) - [ "start_time" ]
    if missing.any?
      findings << finding(:missing_story_fields, :warning,
                          "is missing #{missing.to_sentence}, which every generation prompt in the game reads; " \
                          "there is nothing to derive prose from, so this has to be written by hand or the story deleted",
                          :manual)
    end

    findings
  end

  # `Universe#prompt_details` is re-sent on every downstream call for the life
  # of the world, and `Character::Generator` picks a race out of this list.
  def universe_fields
    universe = story.universe
    return [ finding(:missing_universe, :fatal, "has no universe, so no prompt in the game can be built", :manual) ] if universe.nil?

    findings = []
    universe.valid?
    missing = universe.errors.attribute_names.map(&:to_s)

    if missing.include?("races")
      findings << finding(:universe_without_races, :warning,
                          "universe ##{universe.id} has no races, so no character can be generated for this story",
                          :manual)
    end

    fields = missing - [ "races" ]
    if fields.any?
      findings << finding(:incomplete_universe, :warning,
                          "universe ##{universe.id} is missing #{fields.to_sentence}, which every prompt built from it sends blank",
                          :manual)
    end

    findings
  end

  # THE CHECK THE APP ALREADY MAKES, in two parts. `PlaythroughsController`
  # refuses a story with no realized location and the index hides its Play
  # button; separately, `Story#opening_location` is the LOWEST-ID location, and
  # that is the one `Scene::Generator.opening` and `WorldSeed::Exporter` mean by
  # "the opening". The two can disagree, and when they do the story plays from
  # somewhere the rest of the code does not think it opens in.
  def opening_location
    if story.locations.none?
      return [ finding(:no_locations, :fatal,
                       "has no locations at all: there is nowhere to open in, and nothing on record to derive one from",
                       :manual) ]
    end

    if play_location.nil?
      return [ finding(:no_realized_location, :fatal,
                       "has no realized location -- every place in it is still a stub, so there is nothing to read on arrival " \
                       "and PlaythroughsController refuses it",
                       :generate) ]
    end

    declared = story.opening_location
    return [] if declared == play_location

    [ finding(:opening_location_is_a_stub, :warning,
              "opens in #{play_location.name.inspect}, but the story's own opening location is the stub " \
              "#{declared.name.inspect} -- which is the one game:export writes as `opening` and Scene::Generator.opening realizes",
              :generate, subject: declared) ]
  end

  # TWO ROWS THAT ARE ONE ROOM. `WorldSeed::Loader` matches a location on
  # `WorldSeed.natural_key` -- case, whitespace and a leading article are not
  # part of the name -- and before it did, editing "Supply Closet" to "The
  # Supply Closet" in a seed file created a second room beside the first and
  # gave the office a doorway onto each. The captain's database holds that pair,
  # which is what this exists to name.
  #
  # It is not only a seeding defect: `Playthrough::Classifier` resolves a move
  # against the names of the rooms that lead out of here, so which of two rooms
  # answering to one name the player walks into is an ordering accident -- the
  # same argument `duplicate_items` makes about a take.
  #
  # SAFE ONLY WHEN THE FILE SAYS THEY ARE ONE ROOM and only one of the rows has
  # anybody's history in it. Then the fold is the file's own statement rather
  # than a judgement: `rake game:repair` moves what is on the empty row -- what
  # is lying in it, anybody standing in it, its doorways -- onto the row with
  # the history, and removes what is left. Nothing play created is destroyed.
  # Two rows both carrying scenes are two histories and nothing can merge those
  # honestly; a generated world has no file to prove anything. Both `manual`.
  def duplicate_locations
    story.locations.order(:id).group_by { |room| WorldSeed.natural_key(room.name) }.filter_map do |key, group|
      next if group.one? || key.blank?

      seeded = seeded_location_names[key]
      stood_in = group.select { |room| stood_in?(room) }
      remedy = seeded.present? && stood_in.size <= 1 ? :safe : :manual

      finding(:duplicate_locations, :warning,
              "#{group.size} locations are one room to a re-seed " \
              "(#{group.map { |room| "##{room.id} #{room.name.inspect}" }.join(", ")})" \
              "#{duplicate_location_verdict(seeded, stood_in)}",
              remedy, subject: group.first)
    end
  end

  # What makes the pair foldable, or what stops it. Split out for the same
  # reason `#duplicate_item_verdict` is: the answers are different facts.
  def duplicate_location_verdict(seeded, stood_in)
    if seeded.blank?
      ": no checked-in file declares any of them, so which of them is the room is not on record"
    elsif stood_in.size > 1
      ": #{seed_basename} declares one, #{seeded.inspect}, but somebody has stood in " \
        "#{stood_in.size} of them and two histories cannot be folded into one"
    else
      ": #{seed_basename} declares one, #{seeded.inspect}, and " \
        "#{stood_in.any? ? "only ##{stood_in.first.id} has anybody's history in it" : "nobody has stood in any of them"}"
    end
  end

  # THE FILE'S OWN DOORWAY, BACK ON RECORD AFTER THE WORLD HAD MOVED IT, which
  # is the shape a re-seed used to leave on every world that moves.
  # `WorldMechanic::ShuffleConnections` repoints the far end of each
  # mobile <-> anchored edge and preserves the count; `WorldSeed::Loader` then
  # re-wrote the file's own pair, so the lane ended up opening onto both -- and
  # a later night reported one of them as having moved when a player standing
  # there saw no such thing. That is the phantom event the captain read, and
  # his own Mournwell Lane carries it.
  #
  # WHAT IS PROVABLE HERE IS THE PAIR, NOT THE COUNT, and that distinction is
  # the whole check. A mobile room's arity is NOT the file's on a played world:
  # `Location::Generator#write_exits!` creates a stub neighbour when the room is
  # realized, so the captain's lane legitimately leads onto two anchored places
  # the file never mentioned. What the file can prove is that the doorway it
  # declares is one the mechanic MOVES -- so finding that exact pair on record
  # after a night has run means something wrote it back, and the only thing that
  # writes an edge from a file is a re-seed.
  #
  # THE LIMIT, STATED. A permutation may legitimately land the file's own
  # endpoint back on the room, and nothing on record tells that from a re-seed.
  # It is reported anyway, because the cost of being wrong is one doorway
  # closing on a world that moves its doorways every night, and it is only ever
  # reported for a room that leads SEVERAL ways into the fixed city -- a room
  # with one is left alone, since closing that one would strand it.
  def re_asserted_doorways
    return [] if seeded_doorways.empty? || shuffle_has_run.blank?

    anchored = story.locations.where(mobile: false).pluck(:id)

    story.locations.where(mobile: true).order(:id).flat_map do |room|
      rows = LocationConnection.where(location: room, connected_location_id: anchored)
                               .includes(:connected_location).order(:id).to_a
      next [] if rows.size < 2

      wanted = [ seeded_mobile_arity[room.name].to_i, 1 ].max

      rows.select { |row| seeded_doorways.include?([ room.name, row.connected_location.name ].sort) }.map do |row|
        strands = !whole_without?(row)
        remedy = rows.size - 1 >= wanted && !strands ? :safe : :manual

        finding(:mobile_doorway_re_asserted, :warning,
                "#{room.name.inspect} is `mobile` and opens onto #{row.connected_location.name.inspect}, which is the " \
                "doorway #{seed_basename} declares for it -- and #{shuffle_has_run.name.inspect} has run since " \
                "(#{shuffle_has_run.last_run_at.utc.iso8601}), which repoints the far end of exactly these. So the " \
                "file's own pair is on record because a re-seed wrote it back over the arrangement the world had " \
                "moved to, and the room now leads #{rows.size} ways into the fixed city" \
                "#{". Closing it would leave part of the world reachable from nowhere, so it stays until somebody decides what #{row.connected_location.name.inspect} should open onto" if strands}",
                remedy, subject: row)
      end
    end
  end

  # The world's own connection shuffle, if it has ever run. Blank otherwise,
  # and that is the gate: until a night has passed, the file's own pair being
  # on record is simply the file, correctly loaded.
  def shuffle_has_run
    return @shuffle_has_run if defined?(@shuffle_has_run)

    mechanic = story.world_mechanics.find_by(kind: "shuffle_connections")
    @shuffle_has_run = mechanic&.last_run_at ? mechanic : nil
  end

  # A realized room with no way out is the documented cost of saving the
  # description before asking for the exits (AGENTS.md, "Generating the world"):
  # `realize!` returns an already-realized location untouched, so a room whose
  # exits call failed stays exitless forever and `write_exits!` is the recovery.
  def exits
    return [] if play_location.nil?

    story.locations.realized.order(:id).filter_map do |location|
      next if location.exits.any?

      if location == play_location
        finding(:opening_has_no_exits, :fatal,
                "opens in #{location.name.inspect}, which has no exits: the player arrives and can never move",
                :generate, subject: location)
      else
        finding(:location_has_no_exits, :warning,
                "#{location.name.inspect} is realized with no exits, so a player who walks in cannot walk out",
                :generate, subject: location)
      end
    end
  end

  # A world carries its own opening arrival. Without one, `PlaythroughsController`
  # falls back to the room's own description standing in for the moment the story
  # starts, and `rake game:export` refuses to write the story at all.
  def opening_scene
    openings = story.scenes.openings.order(:id).to_a

    if openings.empty?
      return [] if play_location.nil?

      return [ finding(:no_opening_scene, :warning,
                       "has no opening arrival, so every playthrough starts with #{play_location.name.inspect}'s own " \
                       "description standing in for one, and `rake game:export` will not write it",
                       :generate) ]
    end

    findings = []

    if openings.size > 1
      findings << finding(:several_opening_scenes, :warning,
                          "has #{openings.size} scenes marked `is_opening` (##{openings.map(&:id).join(", #")}); a story opens once, " \
                          "and the seed loader matches on that flag, so keep one and clear the rest by hand",
                          :manual)
    end

    scene = openings.first
    if scene.story_timestamp.nil?
      findings << finding(:opening_scene_without_timestamp, :warning,
                          "opening scene ##{scene.id} has no story_timestamp; an opening arrival happens at the story's start_time",
                          story.start_time ? :safe : :manual, subject: scene)
    end

    findings
  end

  # Connections are two directional rows per edge, written from one answer and
  # carrying the same values -- which is only correct because everything stored
  # on them is direction-neutral (see LocationConnection). So a missing reverse
  # row and a disagreeing pair both have an answer already on record.
  def connection_rows
    rows = LocationConnection.where(location: story.locations).includes(:location, :connected_location).order(:id)
    by_pair = rows.group_by { |row| [ row.location_id, row.connected_location_id ].sort }

    by_pair.flat_map { |_pair, pair_rows| connection_findings(pair_rows) }
  end

  def connection_findings(rows)
    findings = []
    row = rows.first
    edge = "#{row.location.name} <-> #{row.connected_location.name}"

    if rows.one?
      findings << finding(:one_way_connection, :warning,
                          "#{edge}: only #{row.location.name} has the connection, so the player can walk there and not back",
                          :safe, subject: row)
    elsif rows.map { |candidate| [ candidate.distance, candidate.travel_method ] }.uniq.size > 1
      findings << finding(:connection_directions_disagree, :warning,
                          "#{edge}: the two directions disagree (#{rows.map { |r| "#{r.distance} #{r.travel_method}" }.uniq.join(" vs ")}); " \
                          "the same edge is walked both ways, so one of them is wrong",
                          :safe, subject: row)
    end

    # Reported once per EDGE rather than once per row: both rows of an edge
    # carry the same wrong value, and saying so twice reads as two problems.
    # Pre-enum worlds have prose in these columns -- "a short walk down the
    # flooded lanes" -- and picking which of the five distances that meant is a
    # judgement, so the message names the legal set and stops there.
    bad_distances = rows.map(&:distance).uniq.reject { |value| LocationConnection::DISTANCES.key?(value) }
    bad_methods = rows.map(&:travel_method).uniq.reject { |value| LocationConnection::TRAVEL_METHODS.key?(value) }

    bad_distances.each do |value|
      findings << finding(:unknown_distance, :warning,
                          "#{edge}: distance #{value.inspect} is not one of LocationConnection::DISTANCES " \
                          "(#{LocationConnection::DISTANCES.keys.join(", ")}), so no travel time can be derived from it",
                          :manual, subject: rows.find { |candidate| candidate.distance == value })
    end

    bad_methods.each do |value|
      findings << finding(:unknown_travel_method, :warning,
                          "#{edge}: travel_method #{value.inspect} is not one of LocationConnection::TRAVEL_METHODS " \
                          "(#{LocationConnection::TRAVEL_METHODS.keys.join(", ")}), so no travel time can be derived from it",
                          :manual, subject: rows.find { |candidate| candidate.travel_method == value })
    end

    findings
  end

  # The protagonist is who the player IS. Nothing crashes without one --
  # `Scene::Generator#characters_present` and `Playthrough::Turn#talk_to` both
  # compact the list -- but the arrival cast never includes the player and
  # `Scene::Narrator` cannot say who they are. Which of several characters
  # ought to be the player is not derivable, so this reports and stops.
  def cast
    findings = []
    protagonists = story.characters.protagonists.order(:id).to_a

    if protagonists.empty?
      # The advice depends on whether there is anybody to promote. Telling
      # somebody to mark a character that does not exist is worse than useless.
      remedy_note =
        if story.characters.none?
          "It has no characters at all -- add one with " \
            "`rails runner \"Story.find(#{story.id}).create_character\"`, then mark them"
        else
          "Mark one with " \
            "`rails runner \"Story.find(#{story.id}).characters.first.update!(is_protagonist: true)\"`"
        end

      findings << finding(:no_protagonist, :warning,
                          "has no character marked `is_protagonist`, so the player is nobody: the arrival cast never includes " \
                          "them and the narrator cannot name them. #{remedy_note}",
                          :manual)
    elsif protagonists.size > 1
      findings << finding(:several_protagonists, :warning,
                          "has #{protagonists.size} characters marked `is_protagonist` (#{protagonists.map(&:fullname).join(", ")}); " \
                          "the player is exactly one person",
                          :manual)
    end

    story.characters.includes(:race).order(:id).each do |character|
      if character.race.nil?
        findings << finding(:character_without_race, :warning,
                            "#{character.fullname} has no race, so the talk branch raises when it builds their character sheet",
                            :manual, subject: character)
      elsif character.race.universe_id != story.universe_id
        findings << finding(:character_race_from_another_universe, :warning,
                            "#{character.fullname}'s race #{character.race.name.inspect} belongs to universe " \
                            "##{character.race.universe_id}, not this story's ##{story.universe_id}; the record cannot be saved " \
                            "and picking a different race would be inventing who they are",
                            :manual, subject: character)
      end
    end

    findings
  end

  # ------------------------------------------------------------------------
  # WHERE THE CAST IS, and the ways that answer goes wrong.
  #
  # `Character.present_in(location)` is the closed set `talk` resolves against,
  # so a whereabouts is not decoration: a character with none is somebody the
  # player can never speak to, however central they are to the world. That is
  # the defect this column was added for -- The Tide Post recorded the
  # protagonist alone in a world about a man chained to it -- and this is the
  # sweep that finds the rest of them.
  #
  # NOWHERE ON PURPOSE IS NOT ONE OF THEM. `characters.deliberately_absent` is a
  # world's own statement that somebody has been removed from it, and the three
  # checks that read it (`#characters_nowhere`, `#characters_absent_in_the_seed`,
  # `#characters_absent_but_somewhere`) exist so that this sweep reports the
  # accidental nowhere and stays silent about the deliberate one. It reported
  # `The Unrecorded Hour` on every single run before the marker existed.
  #
  # THE PARTY IS NOT ASKED ABOUT. The protagonist and anyone `is_companion`
  # travel with the playthrough (`playthroughs.current_location_id`), because
  # two people playing one world stand in two rooms at once. A story-level
  # column cannot hold that, so nowhere is the CORRECT state for them and
  # reporting it would be reporting the design.
  # ------------------------------------------------------------------------
  def whereabouts
    cast = story.characters.includes(:location).where(is_protagonist: false)
                .where(is_companion: [ false, nil ]).order(:id).to_a

    [ *characters_nowhere(cast), *characters_absent_in_the_seed(cast), *characters_absent_but_somewhere(cast),
      *characters_in_a_stub(cast), *characters_outside_the_story(cast),
      *rooms_over_the_cast_cap, *story_over_the_cast_cap, *characters_the_seed_placed_elsewhere ]
  end

  # Nobody has said where they are. `rake game:backfill_whereabouts` recovers
  # what the old arrival casts can still answer for and refuses to guess at the
  # rest, which is why this is `manual`.
  #
  # NOWHERE ON PURPOSE IS NOT REPORTED AT ALL. `The Unrecorded Hour` leaves
  # Perrin Lasco nowhere because the premise of that world is that he has been
  # removed from it, and this reported him on every single run of the doctor --
  # a warning about a world working exactly as written, which is how a person
  # learns to stop reading warnings. `characters.deliberately_absent` is the
  # difference, and the finding is DROPPED rather than downgraded because there
  # is no level below `warning` here: `SEVERITIES` is `fatal` and `warning`,
  # and the doctor's contract is that a story with nothing wrong reports
  # nothing (`#healthy?`). A healthy-note level would make every healthy story
  # print something, which is a different tool.
  def characters_nowhere(cast)
    cast.select { |character| character.nowhere? && !character.deliberately_absent? && !seeded_absences.include?(character.fullname) }.map do |character|
      finding(:character_nowhere, :warning,
              "#{character.fullname} is nowhere: `Character.present_in` never offers them, so nobody can " \
              "speak to them in any room. Recover what the old arrival casts hold with " \
              "`rake game:backfill_whereabouts`, place them in a seed file's `characters[].location`, or " \
              "move them with `Character#move_to!` -- and a character whose room was deleted lands here too, " \
              "because destroying a Location nullifies this column rather than the person. If they are nowhere " \
              "ON PURPOSE, say so: `absent: true` in a seed file, or `Character#absent!`",
              :manual, subject: character)
    end
  end

  # THE FILE ALREADY SAYS THIS IS DELIBERATE AND THE ROW PREDATES THE MARKER.
  # The one-time case: a world seeded before `characters.deliberately_absent`
  # existed carries an unmarked nowhere character whose checked-in file says
  # `absent: true`, so the doctor would report the world working as written.
  # Safe for exactly the reason `character_moved_from_the_seed` is safe -- the
  # answer is on record in a file in the repository -- and `rake game:repair`
  # writes it, as does re-seeding.
  def characters_absent_in_the_seed(cast)
    cast.select { |character| character.nowhere? && !character.deliberately_absent? && seeded_absences.include?(character.fullname) }.map do |character|
      finding(:character_absent_in_the_seed, :warning,
              "#{character.fullname} is nowhere and #{seed_basename} marks them `absent: true` -- nowhere on " \
              "purpose -- but the record does not carry the marker, so this story was seeded before it existed. " \
              "`rake game:repair` writes it, and so does re-seeding",
              :safe, subject: character)
    end
  end

  # NOWHERE ON PURPOSE, AND STANDING IN A ROOM. A contradiction: the marker
  # says nobody may be offered this person to talk to and the whereabouts puts
  # them in the closed set for that room. No code path in the app writes it --
  # `Character#move_to!` clears the marker when it places somebody, and
  # `Character::Registry` refuses to place a marked character at all -- so this
  # arrives through raw SQL, or through a re-seed of a file that grew a
  # `location` for somebody it also marks absent (which `WorldSeed::Loader`
  # now refuses outright).
  #
  # Safe, and the marker is the half that wins: it is the world's own statement
  # about the person, and it is the half a checked-in file can corroborate.
  # `rake game:repair` puts them back to nowhere.
  def characters_absent_but_somewhere(cast)
    cast.select { |character| character.deliberately_absent? && character.somewhere? }.map do |character|
      finding(:character_absent_but_somewhere, :warning,
              "#{character.fullname} is marked absent on purpose and is standing in " \
              "#{character.location.name.inspect}; the record says both that nobody may be offered them to " \
              "speak to and that they are in that room's closed set. Nothing in the app writes this -- " \
              "`Character#move_to!` clears the marker when it places somebody",
              :safe, subject: character)
    end
  end

  # Standing in a room nobody has written. Legal, and it plays: walking in
  # realizes the room and the arrival introduces them. Worth saying anyway,
  # because `Location::Generator` writes that description without knowing
  # anybody is in it -- so the room comes out described as empty with somebody
  # standing in the middle of it, and the prose and the records disagree from
  # the moment the room exists.
  def characters_in_a_stub(cast)
    cast.select { |character| character.location&.stub? }.map do |character|
      finding(:character_in_a_stub, :warning,
              "#{character.fullname} is in #{character.location.name.inspect}, which nobody has written yet. " \
              "The room realizes when somebody walks in, and its description is written without knowing " \
              "#{character.pronoun_forms.subject} is there",
              :manual, subject: character)
    end
  end

  # A whereabouts pointing out of this story. `Character#location_belongs_to_story`
  # refuses to save one, so this arrives only through raw SQL or a schema older
  # than that validation -- the same shape and the same reasoning as
  # `#items_nowhere`, and worth a line because the row plays: the closed set
  # for that room is built from `Character.present_in`, which does not ask
  # whose story the room belongs to.
  def characters_outside_the_story(cast)
    cast.select { |character| character.location && character.location.story_id != story.id }.map do |character|
      finding(:character_outside_the_story, :warning,
              "#{character.fullname} is in #{character.location.name.inspect}, which belongs to story " \
              "##{character.location.story_id} and not this one; the record cannot be saved and no closed set " \
              "in this story will ever offer them",
              :manual, subject: character)
    end
  end

  # A ROOM HOLDING MORE PEOPLE THAN THE ENGINE WOULD EVER PLACE IN ONE. The exact
  # counterpart of `#rooms_over_the_item_cap`, and neither is broken: a seed file
  # may hand-author a crowd and `Character#move_to!` is an explicit decision.
  # It is worth saying out loud because `Character::Registry` will place nobody
  # else there, and because the room's whole cast -- fullname AND nickname
  # apiece -- goes into `Playthrough::IntentSchema`'s closed enum on every turn.
  def rooms_over_the_cast_cap
    counts = story.characters.where.not(location_id: nil).group(:location_id).count

    counts.filter_map do |location_id, count|
      next if count <= Character::Registry::MAX_PER_ROOM

      room = story.locations.find(location_id)
      finding(:room_over_cast_cap, :warning,
              "#{room.name.inspect} has #{count} people standing in it, past the " \
              "#{Character::Registry::MAX_PER_ROOM} the engine will ever place in one room " \
              "(Character::Registry::MAX_PER_ROOM); every one of them goes into the classifier's closed enum " \
              "on every turn",
              :manual, subject: room)
    end
  end

  # A WORLD PAST THE CAST IT WAS MEANT TO BE BOUNDED BY, the exact counterpart
  # of `story_over_item_cap`. Not broken either: a hand-authored world may carry
  # a crowd. What it means is that `Character::Registry` will people no further
  # room in it -- rooms generate with nobody in them from here on -- and that
  # the ontology the cap was bounding is no longer bounded.
  def story_over_the_cast_cap
    count = story.characters.count
    return [] if count <= Character::Registry::MAX_PER_STORY

    [ finding(:story_over_cast_cap, :warning,
              "has #{count} characters, past the #{Character::Registry::MAX_PER_STORY} one world may hold " \
              "(Character::Registry::MAX_PER_STORY); nothing breaks, but no further room in it will be " \
              "generated with anybody in it",
              :manual) ]
  end

  # THE WORLD FILE SAYS SOMEWHERE ELSE. Only asked of a story that IS one of
  # the checked-in worlds, matched on title the way `WorldSeed::Loader` matches
  # everything else, and only about characters the file actually places -- an
  # absent `location` in the file means nowhere and is already reported above.
  #
  # It is the premise check the seeded worlds needed: `The Salt Assizes` is
  # about a man chained to the tide post, and a database in which he is not
  # there is a database in which the world's own premise is unreachable. Safe
  # rather than manual because the answer is on record in a checked-in file:
  # `rake game:repair` puts them back, and so does re-seeding.
  # THE FILE SAYS NOWHERE ON PURPOSE AND THE ROW IS IN A ROOM is the same
  # finding read from the other side, and it is here rather than beside
  # `character_absent_but_somewhere` because the two answer different
  # questions: that one reads the marker on the record, this one reads the
  # file, and only this one can see a story seeded before the marker existed.
  # A file-absent character who IS nowhere is silent -- that is the file and
  # the record agreeing, which is the whole point of the marker.
  def characters_the_seed_placed_elsewhere
    placed = seeded_whereabouts.filter_map do |fullname, room|
      character = story.characters.find_by("LOWER(fullname) = ?", fullname.downcase)
      next if character.nil? || character.location&.name == room

      finding(:character_moved_from_the_seed, :warning,
              "#{character.fullname} is #{character.whereabouts}, and #{seed_basename} puts them in " \
              "#{room.inspect}. Nothing in the app moves a character except `Character#move_to!`, so either " \
              "somebody called it or the world was seeded before the file said this",
              :safe, subject: character)
    end

    absent = seeded_absences.filter_map do |fullname|
      character = story.characters.find_by("LOWER(fullname) = ?", fullname.downcase)
      next if character.nil? || character.nowhere?
      # Already reported by `#characters_absent_but_somewhere`, which reads the
      # record rather than the file; one row, one finding.
      next if character.deliberately_absent?

      finding(:character_moved_from_the_seed, :warning,
              "#{character.fullname} is #{character.whereabouts}, and #{seed_basename} marks them " \
              "`absent: true` -- nowhere on purpose. Either somebody called `Character#move_to!` or the " \
              "world was seeded before the file said this",
              :safe, subject: character)
    end

    placed + absent
  end

  # A malformed world file is `WorldSeed::Loader`'s to complain about, not this
  # class's -- a doctor that raised on one would stop reporting everything else
  # about the story -- which is why the read and its rescue live in
  # `WorldSeed.checked_in_document`, shared with `Item::LayerBackfill`.
  def seed_document
    return @seed_document if defined?(@seed_document)

    @seed_document = WorldSeed.checked_in_document(story.title)
  end

  def seed_basename
    "db/seeds/worlds/#{WorldSeed.slug(story.title)}.yml"
  end

  # `story_timestamp` is what the story's clock is derived from. A scene without
  # one is invisible to `Story#clock`; only the opening arrival has a derivable
  # answer, because an opening happens at the story's start_time by definition.
  def scene_rows
    without_timestamp = story.scenes.where(story_timestamp: nil).where(is_opening: false).order(:id).map do |scene|
      finding(:scene_without_timestamp, :warning,
              "scene ##{scene.id} has no story_timestamp, so the story's clock cannot see it; when in the fiction it " \
              "happened is not on record anywhere",
              :manual, subject: scene)
    end

    without_timestamp + unknown_readers
  end

  # A `scenes.resolved_by` outside `Playthrough::Grammar::PATHS`. It is checked
  # for the reason every check in this class is: a world here outlives the code
  # that made it, and `Scene`'s inclusion validation only binds a row this app
  # saves -- a row written by hand, by an `update_all`, or by an earlier build is
  # under no rule at all.
  #
  # NIL IS NOT A FINDING and must not become one. The column is nullable by
  # history: an opening arrival was read by nobody and keeps nil for ever, and
  # every turn played before 2026-09-05 is stamped `model` by
  # `Update::Steps::StampResolvedBy` rather than reported one at a time here.
  #
  # `engine_view` IS a finding on a scene even though it is in the list, and that
  # is the one thing worth saying out loud: no engine-view command writes a
  # `Scene` at all -- `harm`, `check` and the read-outs are
  # `Playthrough::Mechanics`'s own instruments -- so a turn claiming one was read
  # by a path that writes no turns. `manual`, because which reader really
  # answered a turn is not derivable from anything left on the row.
  def unknown_readers
    story.scenes.where.not(resolved_by: [ nil, *Scene::TURN_READERS ]).order(:id).map do |scene|
      finding(:scene_with_an_unknown_reader, :warning,
              "scene ##{scene.id} says it was resolved by #{scene.resolved_by.inspect}, which is not one of the " \
              "readers that write a turn (#{Scene::TURN_READERS.join(", ")}); nothing can attribute that turn's " \
              "reading to a path, so `rake game:score` and the classifier bench both have to leave it out",
              :manual, subject: scene)
    end
  end

  # A location destroyed under a playthrough nullifies its `current_location`
  # (Location has_many :playthroughs, dependent: :nullify). The player is then
  # standing nowhere: `Playthrough::Classifier#exits_here` returns nothing, so
  # every turn falls through to the narrator and they can never move again.
  def playthrough_rows
    story.playthroughs.includes(current_scene: :location).order(:id).filter_map do |playthrough|
      next if playthrough.current_location

      scene_location = playthrough.current_scene&.location
      if scene_location
        finding(:playthrough_without_location, :warning,
                "playthrough ##{playthrough.id} is standing nowhere, though its current scene is in " \
                "#{scene_location.name.inspect}; until it points at a location that player can never move",
                :safe, subject: playthrough)
      else
        finding(:playthrough_adrift, :warning,
                "playthrough ##{playthrough.id} has neither a location nor a scene, so there is nothing on record saying " \
                "where that player was",
                :manual, subject: playthrough)
      end
    end
  end

  # WHAT THE ITEM REGISTRY CAN GET WRONG, asked of the records after the fact.
  # `Item::Registry` refuses every one of these at the moment it writes, so a
  # world generated since it landed should never show one -- which is exactly
  # why the checks are here. A world here outlives the code that made it: rows
  # written by a seed file, by hand, or by an earlier build of the app are
  # under no rule at all, and the first thing that notices is the classifier
  # resolving one word two ways mid-turn.
  #
  # EVERY ONE OF THEM NAMES ITS LAYER, and since the captain's ruling of
  # 2026-09-04 that is the first thing the reader needs. THE WORLD'S OWN ROWS
  # are what the caps bound, what two of a name is a collision in, and what a
  # seed file writes; ONE PLAYTHROUGH'S OWN COPIES are that game's progress, and
  # two of a name across two games is not a collision at all -- no closed set
  # ever offers a party anything but its own. So the caps, the duplicates and
  # the name collisions ask about templates, and the two findings below them ask
  # about copies. `Item#whereabouts` says which layer a row is in, so a message
  # that prints it cannot be read against the wrong one.
  #
  # Duplicates and collisions are `manual`: which of two things called "the
  # ledger" the player meant is not derivable, and deleting one of them is
  # deleting world data. Being over the cap is `manual` for the same reason --
  # nothing on record says which item is the surplus one.
  def item_rows
    findings = []
    items = story_items.includes(:location, :character, :playthrough).order(:id).to_a
    templates = items.select(&:template?)
    names = templates.map { |item| item.name.to_s.downcase }.uniq.size

    findings.concat(items_nowhere)
    findings.concat(items_in_several_places(items))
    findings.concat(shared_inventory(templates))
    findings.concat(copies_without_a_template(items))
    findings.concat(missing_copies)
    findings.concat(copies_lagging_their_template)
    findings.concat(touched_copies_lagging)
    findings.concat(duplicate_items(templates))
    findings.concat(rooms_over_the_item_cap)
    findings.concat(items_colliding_with_a_name(templates))

    if names > Item::Registry::MAX_PER_STORY
      findings << finding(:story_over_item_cap, :warning,
                          "the world itself holds #{names} distinctly named items, past the "                           "#{Item::Registry::MAX_PER_STORY} one world may have (Item::Registry::MAX_PER_STORY); nothing breaks, "                           "but the registry will furnish no further room in it and the ontology it was bounding is no "                           "longer bounded. Each playthrough's own copies are not counted -- they are the same things, "                           "once per player",
                          :manual)
    end

    findings
  end

  # ONE OF THE WORLD'S OWN ROWS IN NEITHER OF ITS TWO PLACES.
  # `Item#in_exactly_one_place` refuses to save one, so this can only arrive
  # through raw SQL or a schema older than that validation -- and such a row
  # belongs to no story at all, which is why it is reported once against every
  # story rather than attributed to one: there is nothing on the row that says
  # whose it was.
  #
  # A PLAYTHROUGH'S OWN COPY IN NEITHER PLACE IS NOT THIS. It is in the party's
  # hands, which is where most of them are, so the query is narrowed to the
  # world layer rather than counting the ordinary state as a defect.
  def items_nowhere
    orphans = Item.templates.where(character_id: nil, location_id: nil).order(:id).to_a
    return [] if orphans.empty?

    [ finding(:items_nowhere, :warning,
              "#{orphans.size} of the world's own item row#{"s" unless orphans.one?} in the database "               "(##{orphans.first(5).map(&:id).join(", #")}#{", ..." if orphans.size > 5}) "               "#{orphans.one? ? "is" : "are"} neither held by anybody nor lying anywhere, so no closed set can ever "               "offer #{orphans.one? ? "it" : "them"}; the row has nothing on it saying which story it belonged to",
              :manual) ]
  end

  # AN ITEM IN BOTH OF ITS PLACES AT ONCE -- lying in a room and in a pair of
  # hands together. `Item#in_exactly_one_place` refuses to save one in either
  # layer, so like `items_nowhere` this can only arrive through raw SQL or a
  # schema older than the rule, and it is the state that makes a `take`
  # unanswerable: the thing is takeable and already taken.
  def items_in_several_places(items)
    astray = items.select { |item| Item::PLACES.count { |place| item[place].present? } > 1 }
    return [] if astray.empty?

    [ finding(:items_in_several_places, :warning,
              "#{astray.size} item#{"s" unless astray.one?} (#{astray.map { |item| "#{item.name} -- #{item.whereabouts}" }.join("; ")}) " \
              "#{astray.one? ? "is" : "are"} in more than one place at once -- lying in a room and in a pair of " \
              "hands together -- so a `take` of #{astray.one? ? "it" : "them"} is both offered and already done",
              :manual, subject: astray.first) ]
  end

  # THE SHARED INVENTORY THE LAYERS CLOSED. One of the world's own rows held by
  # the protagonist that some playthrough's turn log records TAKING is not the
  # story's starting inventory: it is one player's copy, left in the world layer
  # by a build of the app in which a take moved the world's only row.
  #
  # `safe` -- the answer is on record, in `scenes.resolved_action` and
  # `scenes.acted_on`. `rake game:repair` runs `Item::LayerBackfill` for this
  # one row, which gives the taker its copy, puts the world's own row back in
  # the room the take happened in, and refuses to guess the rest. What it
  # refuses is reported here again on the next run rather than quietly dropped.
  def shared_inventory(templates)
    return [] if story.protagonist.nil?

    templates.filter_map do |item|
      next unless item.character_id == story.protagonist.id && taken_items.key?(item.id)

      finding(:protagonist_holds_a_taken_item, :warning,
              "#{item.name.inspect} is one of the world's own rows, held by #{story.protagonist.fullname}, but " \
              "playthrough ##{taken_items[item.id]}'s turn log records taking it -- so it is that player's copy " \
              "and not the story's starting inventory. Before the layer split a take moved the world's only row, " \
              "so picking a thing up took it out of the world for everybody",
              :safe, subject: item)
    end
  end

  # `{ item id => the playthrough whose chain last took it }`, out of the same
  # reading `Item::LayerBackfill` does -- one instance, so the doctor and the
  # repair cannot disagree about who took what.
  def taken_items
    @taken_items ||= Item::LayerBackfill.new(story).run(dry_run: true).answers
                                        .select { |answer| answer.attributed? && answer.item.template? }
                                        .to_h { |answer| [ answer.item.id, answer.playthrough.id ] }
  end

  # A PLAYTHROUGH'S OWN COPY OF NOTHING. `items.template_id` is what tells this
  # game's ward stamp from a fresh thing of the same name, and it is nullable
  # on purpose -- deleting one of the world's own rows nullifies its copies
  # rather than reaching into a game in progress and taking the thing out of
  # somebody's hands. So this is a REPORT and not a defect: the row is a real
  # thing that player really holds, and only its provenance is gone.
  #
  # `manual` because there is nothing to derive it from. A copy of a template
  # that no longer exists cannot be re-linked, and guessing by name is the one
  # thing every backfill in this app refuses to do.
  def copies_without_a_template(items)
    orphans = items.select { |item| item.instance? && item.template_id.nil? }
    return [] if orphans.empty?

    [ finding(:instance_without_a_template, :warning,
              "#{orphans.size} of the playthroughs' own item row#{"s" unless orphans.one?} " \
              "(#{orphans.first(5).map { |item| "#{item.name} -- #{item.whereabouts}" }.join("; ")}" \
              "#{"; ..." if orphans.size > 5}) #{orphans.one? ? "is" : "are"} a copy of one of the world's own " \
              "rows that no longer exists, so nothing says what #{orphans.one? ? "it is" : "they are"} a copy of. " \
              "Nobody loses anything by it: the row is still in that player's game",
              :manual, subject: orphans.first) ]
  end

  # A COPY OF WHAT THE WORLD USED TO SAY. A seed file is edited after somebody
  # has played -- the tide-slate is given `readable: true` and an inscription --
  # and a re-seed writes that onto the world's own row and, correctly, stops
  # there: the layer split exists so re-asserting a file cannot reach into a
  # game in progress. The copies made before the edit therefore go on carrying
  # what the file used to say, and the player reads a blank slate for ever.
  #
  # `safe` for a copy NO TURN HAS ACTED ON: the value is on the template, in the
  # same table, and `Item::TemplateRefresh` writes only the text columns. One
  # finding per playthrough, because that is the unit the repair acts on.
  #
  # A COPY SOMEBODY HAS HANDLED IS NOT THIS -- see `#touched_copies_lagging`.
  def copies_lagging_their_template
    template_refresh.untouched.group_by(&:playthrough_id).filter_map do |playthrough_id, lags|
      playthrough = story.playthroughs.find_by(id: playthrough_id)
      next if playthrough.nil?

      finding(:copy_lags_its_template, :warning,
              "playthrough ##{playthrough.id} holds #{lags.size} cop#{lags.one? ? "y" : "ies"} of one of the " \
              "world's own rows carrying what the world used to say " \
              "(#{lags.first(5).map(&:to_s).join("; ")}#{"; ..." if lags.size > 5}); the world's row was edited " \
              "after that game copied it -- by a seed file, most likely -- and no turn has touched the copy",
              :safe, subject: playthrough)
    end
  end

  # THE SAME LAG ON A ROW SOMEBODY HAS HANDLED. `manual`, and it is the whole
  # reason the finding above can be `safe`: a copy some turn took or put down is
  # that player's, and nothing on record says whether its text is stale or
  # deliberate. It is reported and left exactly where it stands.
  def touched_copies_lagging
    lags = template_refresh.touched
    return [] if lags.empty?

    [ finding(:touched_copy_lags_its_template, :warning,
              "#{lags.size} cop#{lags.one? ? "y" : "ies"} of the world's own rows " \
              "(#{lags.first(5).map(&:to_s).join("; ")}#{"; ..." if lags.size > 5}) carr#{lags.one? ? "ies" : "y"} " \
              "text the world's row no longer has, and a turn has acted on #{lags.one? ? "it" : "them"} -- so " \
              "nothing can say whether the copy is stale or is what that player has. Left alone",
              :manual, subject: lags.first.copy) ]
  end

  # One instance for the whole doctor, so the two findings and `Story::Repair`
  # read one answer.
  def template_refresh
    @template_refresh ||= Item::TemplateRefresh.new(story)
  end

  # A ROOM A PLAYER HAS BEEN IN AND HAS NO COPY OF. Every game holds its own
  # copy of what is lying in each room it has walked through
  # (`Item::Snapshot`), so a template lying in a visited room that this
  # playthrough has no copy of is a snapshot that was never taken -- a database
  # older than the layers, or one whose backfill has not been run.
  #
  # `safe` -- there is nothing to derive and nothing to guess. `rake game:repair`
  # takes the snapshot, which is a copy of a row that already exists.
  #
  # A ROOM THE PARTY EMPTIED IS NOT THIS. The guard is per template rather than
  # per room, so a copy the player took and carried off still counts as held --
  # which is the whole reason `Item::Snapshot` guards the way it does.
  def missing_copies
    Item::LayerBackfill.new(story).run(dry_run: true).snapshots.filter_map do |snapshot|
      next if snapshot.copies.empty?

      finding(:playthrough_missing_a_copy, :warning,
              "playthrough ##{snapshot.playthrough.id} has been in #{snapshot.rooms.size} room(s) and holds no copy " \
              "of #{snapshot.copies.size} of the world's own item row(s) it has stood in front of " \
              "(#{snapshot.copies.first(5).map(&:name).join(", ")}#{", ..." if snapshot.copies.size > 5}); that " \
              "player's floor is emptier than the world's",
              :safe, subject: snapshot.playthrough)
    end
  end

  # Two of THE WORLD'S OWN THINGS answering to one name.
  # `Playthrough::Classifier` resolves a typed line against a list of names, so
  # the player types the name and gets whichever the ordering hands over.
  #
  # GROUPED ON `WorldSeed.natural_key`, the key `WorldSeed::Loader` now matches
  # an item under, because that is where the pair came from: a seed file whose
  # item name was edited was, to a loader keyed on the written name, an item
  # that did not exist, and the captain's database held two
  # `Ward Office 12 daybook` rows in one pair of hands because of it.
  #
  # IT ASKS THE WORLD LAYER, and that REPLACED a special case rather than adding
  # one. A world played four times holds five rows called "ward stamp" and
  # exactly one of them is the world's; the other four are one per game, and no
  # closed set ever offers a party anything but its own. This used to reject the
  # starting inventory's copies by name (`#duplicate_item_candidates`, gone with
  # the layer split) -- asking the question of the templates answers it for
  # every kind of copy at once, including the ones a party dropped in a room.
  #
  # SAFE ONLY WHEN THE FILE NAMES ONE OF THEM AND NOBODY HAS TOUCHED THE REST.
  # The file declares one item under that key, and the loader has already
  # written the file's own description, place and inscription onto the row it
  # named -- so what is left over is a row nothing refers to, and
  # `rake game:repair` removes it. A leftover a turn log records taking, or one
  # some game still holds a copy of, is somebody's and no fold of it is honest:
  # `manual`.
  def duplicate_items(templates)
    templates.group_by { |item| WorldSeed.natural_key(item.name) }.filter_map do |key, group|
      next if group.one? || key.blank?

      seeded = seeded_item_names[key]
      survivor = group.detect { |item| item.name == seeded }
      leftovers = survivor ? group - [ survivor ] : []
      remedy = survivor && leftovers.all? { |item| untouched?(item) } ? :safe : :manual

      finding(:duplicate_items, :warning,
              "#{group.size} of the world's own items are one thing to a re-seed " \
              "(#{group.map { |item| "##{item.id} #{item.name.inspect} #{item.whereabouts}" }.join("; ")}); " \
              "the classifier resolves a take or a drop by name, so which one the player gets is an ordering " \
              "accident#{duplicate_item_verdict(seeded, leftovers, remedy)}",
              remedy, subject: survivor || group.last)
    end
  end

  # The sentence after the finding: what makes this pair foldable, or what
  # stops it. Split out because the two answers are different facts and reading
  # them inside the interpolation was worse than reading them here.
  def duplicate_item_verdict(seeded, leftovers, remedy)
    if remedy == :safe
      ". #{seed_basename} declares one, #{seeded.inspect}, and nothing refers to the " \
        "#{leftovers.one? ? "other row" : "#{leftovers.size} other rows"}"
    elsif seeded.present?
      ". #{seed_basename} declares #{seeded.inspect}, and a player has handled one of the others, so it is theirs"
    else
      ". No checked-in file declares any of them, so which one is the world's is not on record"
    end
  end

  # A room holding more of THE WORLD'S OWN things than `Item::Registry` would
  # ever put in one. The registry counts against the records on every admission,
  # so this is a seeded room -- neither broken, and worth saying out loud,
  # because the room will accept nothing more.
  #
  # A PARTY DROPPING FOUR THINGS ON THIS FLOOR IS NOT THIS. Those are that
  # game's own copies and they bound nothing; the cap is on the world.
  def rooms_over_the_item_cap
    counts = Item.templates.where(location: story.locations, character_id: nil).group(:location_id).count

    counts.filter_map do |location_id, count|
      next if count <= Item::Registry::MAX_PER_ROOM

      finding(:room_over_item_cap, :warning,
              "#{story.locations.find(location_id).name.inspect} has #{count} of the world's own items lying in it, "               "past the #{Item::Registry::MAX_PER_ROOM} one room may have (Item::Registry::MAX_PER_ROOM)",
              :manual, subject: story.locations.find(location_id))
    end
  end

  # An item sharing its name with a person or a place. Two of the classifier's
  # closed sets then answer to one word, and which action the turn takes is
  # decided inside the classifier rather than by the player. Asked of the
  # world's own rows, because a copy has its template's name and reporting both
  # would name one collision twice.
  def items_colliding_with_a_name(templates)
    people = story.characters.pluck(:fullname, :nickname).flatten.compact_blank.index_by(&:downcase)
    places = story.locations.pluck(:name).compact_blank.index_by(&:downcase)

    templates.filter_map do |item|
      name = item.name.to_s.downcase
      kind, matched = ([ "character", people[name] ] if people.key?(name)) || ([ "location", places[name] ] if places.key?(name))
      next if kind.nil?

      finding(:item_named_after_something_else, :warning,
              "the item #{item.name.inspect} (#{item.whereabouts}) shares its name with the #{kind} #{matched.inspect}, "               "so the classifier's closed sets answer to one word twice and which one a typed line resolves to is not "               "the player's choice",
              :manual, subject: item)
    end
  end

  # ------------------------------------------------------------------------
  # THE BODIES, and the ways a stat block goes wrong.
  #
  # `characters.level` and `characters.hit_die` are the world's answer to how
  # tough somebody is, and `Character#max_hp` is derived from the pair. A
  # character with neither is somebody `Playthrough::Vitals` can write no row
  # for, so nothing in the game can ever say anything about their body -- and
  # every character in a database older than the columns is one of them.
  #
  # THE REMEDY IS `:safe` AND IT IS THE ONE PLACE IN THIS FILE THAT STRETCHES
  # THE WORD, so it is stated rather than left to be discovered. Everywhere else
  # `safe` means "the right value is already on record somewhere else". Nothing
  # on record implies a hit die. It is `safe` because the ENGINE is the sole
  # author of that number by the captain's ruling of 2026-09-04 -- *"A model
  # cannot set an NPC's numbers, the engine rolls them"* -- so writing one is
  # not inventing world data to make a validation pass, it is the engine doing
  # the only thing that was ever going to decide it. The roll is deterministic
  # (`Character::StatBlock.for_existing`), so a rehearsal and the repair agree,
  # and `rake game:backfill_stat_blocks` does the same thing for a whole story
  # at once. See `Story::Repair`'s header, which carries the same note.
  def stat_blocks
    story.characters.order(:id).filter_map do |character|
      next if character.stat_block?
      # A FOE WITH NO BODY IS REPORTED AS A FOE WITH NO BODY, once. It is the
      # same missing sheet, but it is a louder fact -- a monster nothing can
      # hurt is a world that cannot resolve a fight -- so
      # `#hostile_without_a_stat_block` below says it instead, with the same
      # `:safe` repair behind it. One row, one finding: two findings about the
      # same nil would be the noise `rake game:doctor` exists to cut.
      next if character.hostile?

      finding(:character_without_a_stat_block, :warning,
              "#{character.fullname} has #{character.level.present? || character.hit_die.present? ? "half a stat block" : "no stat block"} " \
              "(level #{character.level.inspect}, hit die #{character.hit_die.inspect}), so the engine has no maximum " \
              "for their body and no playthrough can record anything happening to them",
              :safe, subject: character)
    end
  end

  # ------------------------------------------------------------------------
  # THE THREE ABILITIES, and they are reported SEPARATELY from the stat block
  # above rather than folded into it.
  #
  # `Character#abilities?` is its own predicate for a reason stated in that
  # class's header: `#stat_block?` gates `#max_hp` and through it every
  # `playthrough_vitals` row in the database, so widening it to want the
  # abilities would make every existing maximum nil and every existing game's
  # condition unreadable in the window between the migration and the backfill.
  # The two facts are separate, so the two findings are.
  #
  # `:safe` FOR THE SAME REASON `character_without_a_stat_block` IS, and the
  # same stretch of the word: nothing on record implies a strength. It is safe
  # because the ENGINE is the sole author of that number by the captain's
  # rulings of 2026-09-04 -- *"A model cannot set an NPC's numbers, the engine
  # rolls them"*, and *"let's go with the 3 abilities"* -- so rolling 3d6 is not
  # inventing world data to make a validation pass, it is the only thing that
  # was ever going to decide it. `Character::StatBlock.for_existing` is
  # deterministic, so a rehearsal and the repair agree.
  def abilities
    story.characters.order(:id).flat_map do |character|
      [ *missing_abilities(character), *abilities_out_of_range(character) ]
    end
  end

  # NOBODY HAS ROLLED THEM. Every character in a database older than the columns
  # is one of these, and so is a row with a partial set -- which
  # `Character#abilities_are_whole` refuses to save, so it arrived through raw
  # SQL or a schema older than the validation.
  def missing_abilities(character)
    return [] if character.abilities?

    held = Character::ABILITIES.select { |ability| character[ability].present? }
    [ finding(:character_without_abilities, :warning,
              "#{character.fullname} has #{held.any? ? "only #{held.size} of #{Character::ABILITIES.size} abilities " \
              "(#{held.join(", ")})" : "no abilities"}, so the engine cannot roll a check for them at all",
              :safe, subject: character) ]
  end

  # A NUMBER 3d6 COULD NEVER HAVE COME UP. `Character` refuses one outside
  # `ABILITY_RANGE`, so this arrived through raw SQL or a schema older than the
  # validation -- and re-rolling the three is the only honest fix, because there
  # is no record anywhere that says what the intended number was.
  def abilities_out_of_range(character)
    Character::ABILITIES.filter_map do |ability|
      score = character[ability]
      next if score.nil? || Character::ABILITY_RANGE.include?(score)

      finding(:ability_out_of_range, :warning,
              "#{character.fullname} has #{ability} #{score.inspect}, outside the " \
              "#{Character::ABILITY_RANGE.first}..#{Character::ABILITY_RANGE.last} that 3d6 rolls, so it came " \
              "from somewhere that is not the engine",
              :safe, subject: character)
    end
  end

  # ------------------------------------------------------------------------
  # A WORLD THAT CONTAINS AN ENEMY, and the three shapes that are wrong. All
  # three are about WORLD data -- `characters.hostile`, `races.monstrous` and
  # `locations.danger` -- which is the layer `hit_die` is on and the layer no
  # model and no typed line writes.
  def hostility
    [ *hostile_without_a_stat_block, *monstrous_races_with_no_monsters, *rooms_with_an_unknown_danger ]
  end

  # ------------------------------------------------------------------------
  # A WORLD THAT HURTS YOU FOR STANDING IN IT, and the two shapes that are
  # wrong. Both are WORLD data -- `locations.hazard` and
  # `location_connections.hazard` -- which is the layer `hit_die` and `danger`
  # are on and the layer no model and no typed line writes.
  def hazards
    [ *rooms_with_an_unknown_hazard, *doorways_with_an_unknown_hazard ]
  end

  # A HAZARD THE ENGINE HAS NO TABLE FOR. `Location::HAZARDS` is the closed set
  # of what a room may DO to somebody; `Location` refuses a value outside it and
  # `WorldSeed::Loader#validate_hazards!` refuses a file that carries one, so a
  # row here arrived through raw SQL or a schema older than the validation. It
  # reads as no hazard at all in the meantime (`Location#hazard_entry` answers
  # nil for a key it does not have, and `#hazard_at?` is false), so nothing is
  # broken -- it is a room whose author meant something the engine cannot hear.
  #
  # NO REPAIR, deliberately, and it is the same argument
  # `location_with_an_unknown_danger` makes: there are four words it could have
  # been and nothing on record says which, and clearing the column is not a
  # neutral guess -- it is the answer that makes safe a room somebody meant to
  # cost hit points. A person edits the world file and re-seeds.
  def rooms_with_an_unknown_hazard
    story.locations.hazardous.order(:id).filter_map do |room|
      next if Location::HAZARDS.key?(room.hazard)

      finding(:location_with_an_unknown_hazard, :warning,
              "#{room.name} has hazard #{room.hazard.inspect}, which is not one of " \
              "#{Location::HAZARDS.keys.join(", ")}, so standing in it costs nothing and its author meant it to",
              :manual, subject: room)
    end
  end

  # THE SAME THING ON A DOORWAY, and it is its own finding rather than a second
  # subject on the one above because the two read different tables and a reader
  # sent to `locations` for a row in `location_connections` is a reader sent to
  # the wrong place. NO REPAIR, for the reason above.
  def doorways_with_an_unknown_hazard
    LocationConnection.joins(:location).where(locations: { story_id: story.id })
                      .hazardous.includes(:location, :connected_location).order(:id).filter_map do |edge|
      next if LocationConnection::HAZARDS.key?(edge.hazard)

      finding(:connection_with_an_unknown_hazard, :warning,
              "the way from #{edge.location.name} into #{edge.connected_location.name} has hazard " \
              "#{edge.hazard.inspect}, which is not one of #{LocationConnection::HAZARDS.keys.join(", ")}, " \
              "so walking it costs nothing and its author meant it to",
              :manual)
    end
  end

  # A FOE NOTHING CAN FIGHT. `characters.hostile` says this person attacks the
  # party and a fight is arithmetic over `Character#max_hp`, so a hostile row
  # with no stat block is a monster that can neither be hurt nor recorded as
  # hurting anybody -- `Playthrough#vitals_for` answers nil for them and every
  # consumer says nothing.
  #
  # `:safe`, and the same repair `character_without_a_stat_block` gets: the
  # ENGINE is the sole author of those numbers by the captain's ruling of
  # 2026-09-04, so rolling one is not inventing world data to make a validation
  # pass. `WorldSeed::Loader#validate_hostility!` refuses a FILE that does this,
  # so a row here came from a database older than the columns or from raw SQL.
  def hostile_without_a_stat_block
    story.characters.hostile.order(:id).filter_map do |character|
      next if character.stat_block?

      finding(:hostile_without_a_stat_block, :warning,
              "#{character.fullname} is hostile #{character.whereabouts} and has no stat block, so there is no "               "maximum for their body and nothing in this world can fight them",
              :safe, subject: character)
    end
  end

  # A BESTIARY WITH NOTHING IN IT. `races.monstrous` is what a dangerous room
  # draws its inhabitants from (`Character::Registry#slots`), so a world that
  # marks a race monstrous and holds nobody of it has a bestiary that can only
  # ever be filled by rooms nobody has walked into yet -- which is legitimate
  # for a world still being explored and worth saying out loud for one that is
  # not.
  #
  # NO REPAIR, and that is stated rather than left as an omission: writing a
  # monster is writing a character, which is world data nothing on record
  # implies -- a name, a sheet, a room, a body. `Story::Repair` has no handler
  # for it, so `rake game:repair` lists it under what nothing can honestly do
  # anything about, and a person adds one to the seed file or plays far enough
  # for a dangerous room to be born with one.
  def monstrous_races_with_no_monsters
    story.universe.races.monstrous.order(:name).filter_map do |race|
      next if story.characters.where(race: race).exists?

      finding(:monstrous_race_with_no_monsters, :warning,
              "the universe calls #{race.name.inspect} a monstrous race and this world has nobody of it, so its "               "bestiary is empty until a dangerous room is born with one",
              :manual)
    end
  end

  # A DANGER THE ENGINE HAS NO TABLE FOR. `Location::DANGERS` is the closed set
  # of what a room may be; `Location` refuses a value outside it and
  # `WorldSeed::Loader#validate_dangers!` refuses a file that carries one, so a
  # row here arrived through raw SQL or a schema older than the validation. It
  # reads as `Location::SAFE` in the meantime (`Location#danger_share` answers
  # zero for a key it does not have), so nothing is broken -- it is a room whose
  # author meant something the engine cannot hear.
  #
  # NO REPAIR, deliberately. There are four words it could have been and nothing
  # on record says which, and "safe" is not a neutral guess: it is the answer
  # that empties the room of the monsters somebody meant to put in it. A person
  # edits the world file and re-seeds.
  def rooms_with_an_unknown_danger
    story.locations.order(:id).filter_map do |room|
      next if Location::DANGERS.key?(room.danger)

      finding(:location_with_an_unknown_danger, :warning,
              "#{room.name} has danger #{room.danger.inspect}, which is not one of "               "#{Location::DANGERS.keys.join(", ")}, so nothing born in it can be one of this world's monsters",
              :manual, subject: room)
    end
  end

  # ------------------------------------------------------------------------
  # THE CONDITION ROWS, and the three shapes that are wrong.
  #
  # `playthrough_vitals` is one row per (playthrough, character): the captain's
  # ruling of 2026-09-04 applied to people, the same split `items.playthrough_id`
  # makes. An ABSENT row means unhurt, so nothing here reports a missing row for
  # an NPC -- that is the ordinary state of almost everybody in every world.
  def vitals_rows
    rows = Playthrough::Vitals.where(playthrough: story.playthroughs)
                              .includes(:character, :playthrough).order(:id).to_a

    [ *vitals_without_a_template(rows), *hp_above_maximum(rows), *vitals_for_an_unmet_character(rows),
      *protagonists_without_vitals, *provoked_without_a_meeting(rows), *dead_bodies_holding_things(rows),
      *playthroughs_dead_but_not_ended ]
  end

  # A FIGHT WITH SOMEBODY THAT GAME HAS NEVER STOOD IN A ROOM WITH.
  #
  # `playthrough_vitals.provoked_at` is written in one place --
  # `Playthrough::Turn#provoke!`, inside the transaction that writes the first
  # blow -- and a blow needs the party and the body in one room, so a provoked
  # row for a stranger is a row nothing in the app can have written. It is the
  # loud half of `#vitals_for_an_unmet_character` (which skips provoked rows for
  # exactly this reason): an unmet row says nothing happened, and a provoked one
  # says a FIGHT did.
  #
  # NO REPAIR, and that is the difference. The unmet finding is `safe` because
  # deleting the row loses nothing -- an absent row means unhurt. Deleting this
  # one would erase a fight the records say happened, and clearing the mark
  # alone would tell a live foe to stop fighting. A person looks at it.
  def provoked_without_a_meeting(rows)
    rows.filter_map do |row|
      character = row.character
      next unless row.provoked?
      next if character.nil? || character.is_protagonist? || character.is_companion?
      next if character.location_id && rooms_walked(row.playthrough).include?(character.location_id)

      finding(:provoked_without_a_meeting, :warning,
              "playthrough ##{row.playthrough_id} records a fight with #{character.fullname}, who is " \
              "#{character.whereabouts} -- a room that game has never stood in, so no blow in the app can " \
              "have been thrown at them",
              :manual, subject: row)
    end
  end

  # A BODY AT ZERO STILL HOLDING THINGS. `Playthrough::Turn#spill!` puts a dead
  # person's copies on the floor of the room they are standing in, in the same
  # transaction as the last hit point, so a row here is a game that was killed
  # in before that statement existed -- or a copy that arrived afterwards
  # (`Item::Snapshot` copies a room's people's hands on every visit, and a
  # template added to a corpse's hands by a re-seed would land there).
  #
  # `safe`: the repair is `#spill!` itself, and every value it writes is already
  # on record -- the room is `characters.location_id` and the layer is the row's
  # own. It touches this game's copies only; the world's rows stay in the dead
  # person's hands, where the file put them.
  def dead_bodies_holding_things(rows)
    rows.filter_map do |row|
      character = row.character
      next unless row.dead? && character&.location_id
      held = row.playthrough.items_held_by(character).to_a
      next if held.empty?

      finding(:dead_body_holding_things, :warning,
              "playthrough ##{row.playthrough_id} has #{character.fullname} dead in #{character.location.name} " \
              "and still holding #{held.map(&:name).join(", ")}; a body lets go of what it held",
              :safe, subject: row)
    end
  end

  # THE PLAYER AT ZERO WITH THE GAME STILL RUNNING. `Playthrough::Turn#harm!`
  # writes the last hit point and `playthroughs.ended_at` in one transaction, so
  # the two cannot come apart in play -- and `Playthrough#over?`'s own comment
  # has been promising this finding since the column landed: *"`rake game:doctor`
  # reports a disagreement rather than either half repairing the other
  # silently."* This is that report.
  #
  # `safe`: the answer is on record. The game ended when the body reached zero,
  # and the moment it happened is the playthrough's own story clock.
  def playthroughs_dead_but_not_ended
    story.playthroughs.includes(:character).order(:id).filter_map do |playthrough|
      protagonist = playthrough.character
      next if protagonist.nil? || playthrough.over?

      row = Playthrough::Vitals.find_by(playthrough: playthrough, character: protagonist)
      next unless row&.dead?

      finding(:playthrough_dead_but_not_ended, :warning,
              "playthrough ##{playthrough.id} records #{protagonist.fullname} at zero hit points and is not " \
              "marked ended, so a dead player can still type into it",
              :safe, subject: playthrough)
    end
  end

  # A CONDITION FOR A BODY THE WORLD NO LONGER HAS. `Character has_many :vitals,
  # dependent: :destroy` takes these with the person, so a surviving one arrived
  # through raw SQL or a schema older than that association -- and there is
  # nothing to say about it, because `Character#max_hp` is what a condition is
  # measured against. The item layer's exact analogue
  # (`instance_without_a_template`), and `manual` for the same reason: a row
  # nothing says the meaning of cannot be re-linked, and guessing by name is the
  # one thing every backfill in this app refuses to do.
  def vitals_without_a_template(rows)
    orphans = rows.select { |row| row.character.nil? }
    return [] if orphans.empty?

    [ finding(:vitals_without_a_template, :warning,
              "#{orphans.size} condition row#{"s" unless orphans.one?} (##{orphans.first(5).map(&:id).join(", #")}" \
              "#{", ..." if orphans.size > 5}) belong#{"s" if orphans.one?} to a character this world no longer has, " \
              "so there is no maximum to read #{orphans.one? ? "it" : "them"} against",
              :manual, subject: orphans.first) ]
  end

  # A BODY HOLDING MORE THAN IT CAN. `Playthrough::Vitals#hp_within_the_stat_block`
  # refuses to save one, so the way this arrives is a re-seed LOWERING somebody's
  # hit die under a game already in progress -- which is a legitimate file edit,
  # and this is the row it leaves behind.
  #
  # `safe`: the answer is on record, on the template. `rake game:repair` clamps
  # to `Character#max_hp` and nothing else about the game changes.
  def hp_above_maximum(rows)
    rows.filter_map do |row|
      ceiling = row.character&.max_hp
      next if ceiling.nil? || row.hp_current <= ceiling

      finding(:hp_above_maximum, :warning,
              "playthrough ##{row.playthrough_id} records #{row.character.fullname} at #{row.hp_current} hit points, " \
              "past the #{ceiling} their stat block allows (level #{row.character.level}, d#{row.character.hit_die}); " \
              "a re-seed that lowers a hit die under a game in progress leaves exactly this",
              :safe, subject: row)
    end
  end

  # A CONDITION FOR SOMEBODY THAT GAME HAS NEVER STOOD IN A ROOM WITH.
  # `Playthrough::Vitals::Snapshot` writes a row at first contact and nowhere
  # else, so a row for a stranger is one nothing in the app can have written --
  # and it is a row that says something happened to somebody two people never
  # met.
  #
  # `safe` because deleting it loses nothing: an absent row means unhurt, which
  # is what an unmet person is by definition. The PARTY is never one of these --
  # the protagonist and any companion are wherever the playthrough is rather
  # than in a room, so they are excluded the way `cast_unmoved` excludes them.
  def vitals_for_an_unmet_character(rows)
    rows.filter_map do |row|
      character = row.character
      next if character.nil? || character.is_protagonist? || character.is_companion?
      # A PROVOKED ROW IS THE LOUDER FINDING AND HAS ITS OWN CODE. This one is
      # `safe` because deleting the row loses nothing; deleting a row that
      # records a fight would lose the fight. See `#provoked_without_a_meeting`.
      next if row.provoked?
      next if character.location_id && rooms_walked(row.playthrough).include?(character.location_id)

      finding(:vitals_for_an_unmet_character, :warning,
              "playthrough ##{row.playthrough_id} holds a condition for #{character.fullname}, who is " \
              "#{character.whereabouts} -- a room that game has never stood in, so nothing in the app can have " \
              "written it",
              :safe, subject: row)
    end
  end

  # THE ONE BODY WHOSE ZERO ENDS A GAME, with no row saying where it stands.
  # An absent row means unhurt, which is a perfectly good answer for an NPC and
  # a gap for the player: `Playthrough::Vitals::Snapshot#of_the_party!` writes
  # one when the playthrough is created, so a game without one predates the
  # table.
  #
  # `safe` -- the row is derived from a stat block that already exists, which is
  # `playthrough_missing_a_copy`'s argument one table over. A playthrough whose
  # protagonist has NO stat block is not reported here: that is
  # `character_without_a_stat_block`, said once about the person rather than
  # once per game of them.
  def protagonists_without_vitals
    protagonist = story.protagonist
    return [] if protagonist.nil? || !protagonist.stat_block?

    with_rows = Playthrough::Vitals.where(playthrough: story.playthroughs, character: protagonist)
                                   .pluck(:playthrough_id).to_set

    story.playthroughs.where(character: protagonist).order(:id).filter_map do |playthrough|
      next if with_rows.include?(playthrough.id)

      finding(:protagonist_without_vitals, :warning,
              "playthrough ##{playthrough.id} has no condition row for #{protagonist.fullname}, so nothing records " \
              "how much is left of the one body whose zero ends that game",
              :safe, subject: playthrough)
    end
  end

  # EVERY ROOM ONE GAME HAS STOOD IN, by id: where it is now, and where every
  # turn in its chain happened. Memoized per playthrough because
  # `#vitals_for_an_unmet_character` asks it once per row and a game has one
  # answer.
  def rooms_walked(playthrough)
    @rooms_walked ||= {}
    @rooms_walked[playthrough.id] ||=
      ([ playthrough.current_location_id ] + playthrough.scene_chain.map(&:location_id)).compact.to_set
  end

  # Every row in this story, both layers, on whichever of the three legs it sits
  # -- `Item.in_story`, the one place those queries live.
  def story_items
    Item.in_story(story)
  end

  def earliest_scene_timestamp
    return @earliest_scene_timestamp if defined?(@earliest_scene_timestamp)

    @earliest_scene_timestamp = story.scenes.minimum(:story_timestamp)
  end
end
