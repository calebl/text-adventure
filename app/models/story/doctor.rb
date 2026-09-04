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
      *exits,
      *opening_scene,
      *connection_rows,
      *cast,
      *whereabouts,
      *scene_rows,
      *playthrough_rows,
      *item_rows
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
  # WHERE THE CAST IS, and the three ways that answer goes wrong.
  #
  # `Character.present_in(location)` is the closed set `talk` resolves against,
  # so a whereabouts is not decoration: a character with none is somebody the
  # player can never speak to, however central they are to the world. That is
  # the defect this column was added for -- The Tide Post recorded the
  # protagonist alone in a world about a man chained to it -- and this is the
  # sweep that finds the rest of them.
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

    [ *characters_nowhere(cast), *characters_in_a_stub(cast), *characters_outside_the_story(cast),
      *rooms_over_the_cast_cap, *story_over_the_cast_cap, *characters_the_seed_placed_elsewhere ]
  end

  # Nobody has said where they are. `rake game:backfill_whereabouts` recovers
  # what the old arrival casts can still answer for and refuses to guess at the
  # rest, which is why this is `manual` -- and a seeded world can mean it, so
  # the message says what the state IS rather than calling it a defect.
  # `The Unrecorded Hour` leaves Perrin Lasco nowhere on purpose: the premise of
  # that world is that he has been removed from it.
  def characters_nowhere(cast)
    cast.select(&:nowhere?).map do |character|
      finding(:character_nowhere, :warning,
              "#{character.fullname} is nowhere: `Character.present_in` never offers them, so nobody can " \
              "speak to them in any room. Recover what the old arrival casts hold with " \
              "`rake game:backfill_whereabouts`, place them in a seed file's `characters[].location`, or " \
              "move them with `Character#move_to!` -- and a character whose room was deleted lands here too, " \
              "because destroying a Location nullifies this column rather than the person",
              :manual, subject: character)
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
  def characters_the_seed_placed_elsewhere
    seeded_whereabouts.filter_map do |fullname, room|
      character = story.characters.find_by("LOWER(fullname) = ?", fullname.downcase)
      next if character.nil? || character.location&.name == room

      finding(:character_moved_from_the_seed, :warning,
              "#{character.fullname} is #{character.whereabouts}, and #{seed_basename} puts them in " \
              "#{room.inspect}. Nothing in the app moves a character except `Character#move_to!`, so either " \
              "somebody called it or the world was seeded before the file said this",
              :safe, subject: character)
    end
  end

  # A malformed world file is `WorldSeed::Loader`'s to complain about, not this
  # class's -- a doctor that raised on one would stop reporting everything else
  # about the story -- which is why the read and its rescue live in
  # `WorldSeed.checked_in_document`, shared with `Item::InventoryBackfill`.
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
    story.scenes.where(story_timestamp: nil).where(is_opening: false).order(:id).map do |scene|
      finding(:scene_without_timestamp, :warning,
              "scene ##{scene.id} has no story_timestamp, so the story's clock cannot see it; when in the fiction it " \
              "happened is not on record anywhere",
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
  # Duplicates and collisions are `manual`: which of two things called "the
  # ledger" the player meant is not derivable, and deleting one of them is
  # deleting world data. Being over the cap is `manual` for the same reason --
  # nothing on record says which item is the surplus one.
  def item_rows
    findings = []
    items = story_items.includes(:location, :character, :playthrough).order(:id).to_a
    names = items.map { |item| item.name.to_s.downcase }.uniq.size

    findings.concat(items_nowhere)
    findings.concat(items_in_several_places(items))
    findings.concat(shared_inventory(items))
    findings.concat(duplicate_items(items))
    findings.concat(rooms_over_the_item_cap)
    findings.concat(items_colliding_with_a_name(items))

    if names > Item::Registry::MAX_PER_STORY
      findings << finding(:story_over_item_cap, :warning,
                          "holds #{names} distinctly named items, past the #{Item::Registry::MAX_PER_STORY} one world may have "                           "(Item::Registry::MAX_PER_STORY); nothing breaks, but the registry will furnish no further room "                           "in it and the ontology it was bounding is no longer bounded",
                          :manual)
    end

    findings
  end

  # An item in none of its three places. `Item#in_exactly_one_place` refuses to
  # save one, so this can only arrive through raw SQL or a schema older than
  # that validation -- and such a row belongs to no story at all, which is why it is
  # reported once against every story rather than attributed to one: there is
  # nothing on the row that says whose it was.
  def items_nowhere
    orphans = Item.where(character_id: nil, location_id: nil, playthrough_id: nil).order(:id).to_a
    return [] if orphans.empty?

    [ finding(:items_nowhere, :warning,
              "#{orphans.size} item#{"s" unless orphans.one?} in the database "               "(##{orphans.first(5).map(&:id).join(", #")}#{", ..." if orphans.size > 5}) "               "#{orphans.one? ? "is" : "are"} neither held by anybody nor lying anywhere, so no closed set can ever "               "offer #{orphans.one? ? "it" : "them"}; the row has nothing on it saying which story it belonged to",
              :manual) ]
  end

  # AN ITEM IN MORE THAN ONE OF ITS THREE PLACES. `Item#in_exactly_one_place`
  # refuses to save one, so like `items_nowhere` this can only arrive through
  # raw SQL or a schema older than the rule -- and it is the state that makes a
  # `take` unanswerable, since the thing is takeable and already taken.
  def items_in_several_places(items)
    astray = items.select { |item| Item::PLACES.count { |place| item[place].present? } > 1 }
    return [] if astray.empty?

    [ finding(:items_in_several_places, :warning,
              "#{astray.size} item#{"s" unless astray.one?} (#{astray.map(&:name).join(", ")}) " \
              "#{astray.one? ? "is" : "are"} in more than one place at once -- lying in a room and in a pair of " \
              "hands together -- so a `take` of #{astray.one? ? "it" : "them"} is both offered and already done",
              :manual, subject: astray.first) ]
  end

  # THE SHARED INVENTORY THIS COLUMN CLOSED. An item held by the protagonist
  # that some playthrough's turn log records TAKING is not the story's starting
  # inventory: it is one player's, left on the story's one protagonist row by a
  # build of the app in which every play of a world shared one pair of hands.
  #
  # `safe` -- the answer is on record, in `scenes.resolved_action` and
  # `scenes.acted_on`. `rake game:repair` runs `Item::InventoryBackfill` for the
  # story, which attributes what the takes can answer for and refuses to guess
  # the rest. What it refuses is reported here again on the next run rather than
  # quietly dropped.
  def shared_inventory(items)
    return [] if story.protagonist.nil?

    items.filter_map do |item|
      next unless item.character_id == story.protagonist.id && taken_items.key?(item.id)

      finding(:protagonist_holds_a_taken_item, :warning,
              "#{item.name.inspect} is held by #{story.protagonist.fullname}, but playthrough " \
              "##{taken_items[item.id]}'s turn log records taking it -- so it is that player's and not the " \
              "story's starting inventory. Before `items.playthrough_id` every play of a world shared one " \
              "inventory, and a new game opened holding the last one's things",
              :safe, subject: item)
    end
  end

  # `{ item id => the playthrough whose chain last took it }`, out of the same
  # reading `Item::InventoryBackfill` does -- one instance, so the doctor and
  # the repair cannot disagree about who took what.
  def taken_items
    @taken_items ||= Item::InventoryBackfill.new(story).run(dry_run: true)
                                            .select(&:attributed?)
                                            .to_h { |answer| [ answer.item.id, answer.playthrough.id ] }
  end

  # Two things in one world answering to one name. `Playthrough::Classifier`
  # resolves a typed line against a list of names, so the player types the name
  # and gets whichever the ordering hands over.
  #
  # THE STARTING INVENTORY AND ITS COPIES ARE ONE THING. Every playthrough
  # carries its own copy of what the story starts the player with
  # (`Playthrough#take_up_the_starting_inventory`), so a world played four times
  # holds five rows called "Ward Office 12 daybook" and none of them is a
  # collision: no closed set ever offers two, because a party sees only its own.
  # The copies are dropped here and the world's own row speaks for them.
  def duplicate_items(items)
    starting = story.starting_inventory.pluck(:name).map { |name| name.to_s.downcase }.to_set
    items = items.reject { |item| item.carried? && starting.include?(item.name.to_s.downcase) }

    items.group_by { |item| item.name.to_s.downcase }.filter_map do |name, group|
      next if group.one? || name.blank?

      finding(:duplicate_items, :warning,
              "#{group.size} items are called #{group.first.name.inspect} "               "(#{group.map(&:whereabouts).join("; ")}); the classifier resolves a take or a drop by name, so which one "               "the player gets is an ordering accident",
              :manual, subject: group.last)
    end
  end

  # A room holding more than `Item::Registry` would ever put in one. The
  # registry counts against the records on every admission, so this is a seeded
  # room or a room a player has been dropping things in -- neither of which is
  # broken, and both of which are worth saying out loud, because the room will
  # accept nothing more.
  def rooms_over_the_item_cap
    counts = Item.where(location: story.locations, character_id: nil).group(:location_id).count

    counts.filter_map do |location_id, count|
      next if count <= Item::Registry::MAX_PER_ROOM

      finding(:room_over_item_cap, :warning,
              "#{story.locations.find(location_id).name.inspect} has #{count} items lying in it, past the "               "#{Item::Registry::MAX_PER_ROOM} one room may have (Item::Registry::MAX_PER_ROOM)",
              :manual, subject: story.locations.find(location_id))
    end
  end

  # An item sharing its name with a person or a place. Two of the classifier's
  # closed sets then answer to one word, and which action the turn takes is
  # decided inside the classifier rather than by the player.
  def items_colliding_with_a_name(items)
    people = story.characters.pluck(:fullname, :nickname).flatten.compact_blank.index_by(&:downcase)
    places = story.locations.pluck(:name).compact_blank.index_by(&:downcase)

    items.filter_map do |item|
      name = item.name.to_s.downcase
      kind, matched = ([ "character", people[name] ] if people.key?(name)) || ([ "location", places[name] ] if places.key?(name))
      next if kind.nil?

      finding(:item_named_after_something_else, :warning,
              "the item #{item.name.inspect} (#{item.whereabouts}) shares its name with the #{kind} #{matched.inspect}, "               "so the classifier's closed sets answer to one word twice and which one a typed line resolves to is not "               "the player's choice",
              :manual, subject: item)
    end
  end

  # Every item in this story, on whichever of the three sides of `Item`'s
  # one-place rule it sits -- `Item.in_story`, the one place those queries live.
  def story_items
    Item.in_story(story)
  end

  def earliest_scene_timestamp
    return @earliest_scene_timestamp if defined?(@earliest_scene_timestamp)

    @earliest_scene_timestamp = story.scenes.minimum(:story_timestamp)
  end
end
