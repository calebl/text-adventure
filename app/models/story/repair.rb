# Fixes what can be fixed about a story, and says plainly what cannot.
#
# THE WHOLE OF THIS CLASS IS ONE RULE: never invent data to make a validation
# pass. A generated world is expensive and it is the captain's; a repair that
# quietly wrote a plausible description or picked a plausible race would leave a
# story that passes every check and contradicts itself, which is worse than the
# broken one it replaced. So a repair only ever does one of two things:
#
#   SAFE      writes a value that is already on record somewhere else. The
#             reverse of a connection whose values are direction-neutral by
#             design; an opening arrival's timestamp, which IS the story's
#             start_time; a playthrough's location, which its own current scene
#             names. No model, no key, no judgement.
#
#   GENERATE  asks a model to write something the world genuinely does not
#             contain yet -- a room, its exits, the opening arrival. That is a
#             legitimate repair and it is how the world was built in the first
#             place, but it costs a call and an API key, so it is opt-in and
#             the count of calls is stated before any of them is made.
#
# Everything else is reported by `Story::Doctor` with remedy `:manual` and left
# alone. `rake game:doctor` says which stories those are; the honest answer for
# most of them is `rake game:delete`.
class Story::Repair
  # One thing this did or refused to do. `status` is :repaired, :skipped or
  # :failed -- a repair that raises is caught and reported rather than taking
  # the rest of the run down with it, because the run is over several findings
  # and the ones after a failure are still worth attempting.
  Result = Data.define(:code, :status, :message) do
    def repaired? = status == :repaired
  end

  # Which findings this knows how to act on, and what each one costs in model
  # calls. A finding code that is not in here is reported and never touched --
  # adding a repair means adding an entry AND a handler, so the two cannot drift.
  HANDLERS = {
    missing_start_time: { calls: 0, handler: :repair_missing_start_time },
    opening_scene_without_timestamp: { calls: 0, handler: :repair_opening_scene_timestamp },
    one_way_connection: { calls: 0, handler: :repair_one_way_connection },
    connection_directions_disagree: { calls: 0, handler: :repair_disagreeing_connection },
    playthrough_without_location: { calls: 0, handler: :repair_playthrough_location },
    character_moved_from_the_seed: { calls: 0, handler: :repair_seeded_whereabouts },
    no_realized_location: { calls: 2, handler: :repair_no_realized_location },
    opening_location_is_a_stub: { calls: 2, handler: :repair_opening_location_stub },
    opening_has_no_exits: { calls: 1, handler: :repair_missing_exits },
    location_has_no_exits: { calls: 1, handler: :repair_missing_exits },
    no_opening_scene: { calls: 1, handler: :repair_no_opening_scene }
  }.freeze

  attr_reader :story, :generate

  # `generate: false` is the default on purpose: the cheap half runs without a
  # key, and nothing spends the captain's tokens unless he asked for it.
  def initialize(story, generate: false)
    @story = story
    @generate = generate
  end

  def doctor
    @doctor ||= Story::Doctor.new(story)
  end

  # The findings this run would act on, in the order it would act on them.
  def plan
    doctor.findings.select { |finding| actionable?(finding) }
  end

  # Findings that carry a model-call repair this run is NOT going to make,
  # because `generate` is off. `rake game:repair` prints these as the offer.
  def deferred
    return [] if generate

    doctor.findings.select { |finding| finding.remedy == :generate && HANDLERS.key?(finding.code) }
  end

  # Findings nothing can honestly do anything about.
  def manual
    doctor.findings.reject { |finding| HANDLERS.key?(finding.code) && finding.repairable?(generate: true) }
  end

  # How many model calls `#apply!` will make. Printed before any of them is.
  def model_calls
    plan.sum { |finding| HANDLERS.fetch(finding.code).fetch(:calls) }
  end

  # Runs the plan and returns a Result per finding.
  #
  # Deliberately NOT one transaction. A generated repair is several model calls
  # and the world's own writers persist as they go -- `Location::Generator`
  # saves the description before it asks for the exits precisely so a failure
  # keeps the expensive half. Wrapping the run would throw that away on the last
  # failure, which is the opposite of what this is for.
  def apply!
    plan.map do |finding|
      begin
        message = send(HANDLERS.fetch(finding.code).fetch(:handler), finding)
        Result.new(code: finding.code, status: :repaired, message: message)
      rescue => e
        Result.new(code: finding.code, status: :failed, message: "#{e.class}: #{e.message}")
      end
    end
  ensure
    @doctor = nil
  end

  private

  def actionable?(finding)
    HANDLERS.key?(finding.code) && finding.repairable?(generate: generate)
  end

  # A story started no later than its earliest scene. Derived, not chosen.
  def repair_missing_start_time(_finding)
    at = story.scenes.minimum(:story_timestamp)
    story.update!(start_time: at)
    "set start_time to #{at.utc.iso8601}, the story's earliest scene"
  end

  # An opening arrival happens at the story's start_time by definition -- that
  # is why the seed format does not carry a timestamp for it at all.
  def repair_opening_scene_timestamp(finding)
    finding.subject.update!(story_timestamp: story.start_time)
    "stamped opening scene ##{finding.subject.id} with the story's start_time"
  end

  # Both rows of an edge carry the same values, which is only correct because
  # everything on them is direction-neutral. `time_to_travel` is derived by
  # LocationConnection rather than copied.
  def repair_one_way_connection(finding)
    row = finding.subject
    LocationConnection.create!(
      location: row.connected_location,
      connected_location: row.location,
      distance: row.distance,
      travel_method: row.travel_method
    )
    "wrote the way back from #{row.connected_location.name} to #{row.location.name}"
  end

  # The exporter resolves a disagreement the same way: keep the row on the
  # location nearer the opening, because that is the direction the world was
  # written outward from.
  def repair_disagreeing_connection(finding)
    row = finding.subject
    reverse = LocationConnection.find_by(location: row.connected_location, connected_location: row.location)
    reverse.update!(distance: row.distance, travel_method: row.travel_method)
    "made #{reverse.location.name} -> #{reverse.connected_location.name} agree with the way out (#{row.distance}, #{row.travel_method})"
  end

  # Where that player is standing is on record: it is where their last scene
  # happened.
  def repair_playthrough_location(finding)
    playthrough = finding.subject
    location = playthrough.current_scene.location
    playthrough.update!(current_location: location)
    "put playthrough ##{playthrough.id} back in #{location.name}, where its current scene happens"
  end

  # Where the world file says that person stands. On record and checked in --
  # `characters[].location` in `db/seeds/worlds/*.yml` -- so this is the same
  # kind of repair the connection reversal is: a value that already exists
  # somewhere else, written back. It is the same thing re-seeding does, minus
  # re-asserting the rest of the file over a world somebody has played.
  #
  # `Character#move_to!` and not the registry, because this IS the explicit
  # decision: the file says so.
  def repair_seeded_whereabouts(finding)
    character = finding.subject
    room = doctor.seeded_whereabouts[character.fullname]
    location = story.locations.find_by(name: room)
    raise ArgumentError, "the world file places #{character.fullname} in #{room.inspect}, which this story has no location called" if location.nil?

    character.move_to!(location)
    "put #{character.fullname} back in #{location.name}, where the world file places them"
  end

  # Two model calls: the room's description and lore, then its exits.
  def repair_no_realized_location(_finding)
    location = Location::Generator.opening(story)
    "realized #{location.name.inspect} as the opening location"
  end
  alias_method :repair_opening_location_stub, :repair_no_realized_location

  # One model call. `write_exits!` is public for exactly this recovery: a room
  # realized when the exits call failed is realized forever, and `realize!`
  # returns it untouched.
  def repair_missing_exits(finding)
    location = finding.subject
    Location::Generator.new(location).write_exits!
    "wrote #{location.exits.reload.count} way(s) out of #{location.name}"
  end

  # One model call, and the same one `rake game:new` makes.
  def repair_no_opening_scene(_finding)
    scene = Scene::Generator.opening(story)
    "narrated the opening arrival in #{scene.location.name} (scene ##{scene.id})"
  end
end
