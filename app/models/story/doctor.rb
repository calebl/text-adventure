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
      *scene_rows,
      *playthrough_rows
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

  def earliest_scene_timestamp
    return @earliest_scene_timestamp if defined?(@earliest_scene_timestamp)

    @earliest_scene_timestamp = story.scenes.minimum(:story_timestamp)
  end
end
