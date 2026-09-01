# THE WINDOW INTO THE MACHINE: everything one playthrough generated and decided
# behind the prose, assembled out of records that already exist.
#
# READ ONLY, and that is a rule rather than a habit. Nothing in here asks a
# model anything, writes a row, or advances a playthrough -- in particular it
# does NOT call `Story#catch_up_world!`, because looking at a world must not
# move it. `test/models/playthrough/debug_test.rb` pins that with a table-wide
# before/after snapshot; keep it passing.
#
# THE ONE IDEA IT IS ORGANISED AROUND is the standing constraint (AGENTS.md):
# the app closes a set, the model picks from it, and the loop then acts on the
# RESOLVED RECORD rather than on the label that came back. So every turn here
# is reported as the branch the records say was taken, with the evidence that
# says so spelled out, alongside the closed set the classifier will offer next
# turn. Both halves, because the difference between them is the thing worth
# watching.
#
# WHAT IT CANNOT SHOW is named rather than quietly missing:
#
#   * prompts, raw responses, token counts and which model actually answered.
#     Every agent builds a bare `RubyLLM::Chat`; the `chats` / `messages` /
#     `tool_calls` tables exist and are wired with `acts_as_chat` but nothing
#     ever writes to them. That is `ta-chat-persist`, and this view gains all
#     of it for free when that lands.
#   * the classifier's intent LABEL. It is decided in memory inside
#     `Playthrough::Turn#play` and never stored. The resolved branch below is
#     derived from records instead, which is the half that governs the game.
#   * what the player typed on a turn that was not a conversation. Only
#     `Interaction#user_input` keeps it; a `Scene` has no column for the input
#     that produced it, which is `ta-api-iface`'s first outstanding item.
class Playthrough::Debug
  # One turn of the log, as the records tell it.
  #
  # `branch` is DERIVED, never read back -- see `#branch_for`. `evidence` is
  # the reasoning in the open, so a wrong answer here is visible as a wrong
  # answer rather than as a confident label.
  Turn = Data.define(:scene, :branch, :evidence, :elapsed_minutes, :cost_reading,
                     :typed, :interactions, :cast) do
    def opening? = branch == :opening
  end

  # One way out of where the player is standing, in both directions.
  #
  # `back` is nil when the return edge is missing, which is a defect rather
  # than a shape the world has: `Location::Generator` writes connections in
  # both directions from one answer, so a one-way exit means one of the two
  # writes did not land.
  Exit = Data.define(:location, :out, :back) do
    def one_way? = back.nil?
    def stub? = location.stub?
  end

  # A world mechanic and where it stands on the story's clock.
  Mechanic = Data.define(:mechanic, :owed, :next_at, :events)

  # Whether the view is reachable at all.
  #
  # Local by default -- development and test -- because this is a window for
  # the person building the game, and the app has no auth whatsoever: a
  # playthrough is bound to a browser by one unguessable token, so shipping a
  # debug panel to anyone holding a playthrough link would hand a player the
  # machine along with the story. `TA_DEBUG_VIEW` is the deliberate override in
  # either direction, so looking at a deployed world is a variable rather than
  # a code change.
  def self.enabled?
    return ActiveModel::Type::Boolean.new.cast(ENV["TA_DEBUG_VIEW"]).present? if ENV.key?("TA_DEBUG_VIEW")

    Rails.env.local?
  end

  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  def story = playthrough.story
  def universe = story.universe
  def location = playthrough.current_location

  # THE TURN LOG, oldest first, each one reported as the branch it took.
  #
  # The scene chain is `Playthrough#scene_chain` -- the same walk backwards
  # from `current_scene` the play page renders -- so this view and the prose
  # cannot disagree about which turns belong to this playthrough.
  def turns
    @turns ||= begin
      scenes = playthrough.scene_chain
      preload(scenes)
      scenes.map { |scene| build_turn(scene) }
    end
  end

  # The turn he just took: what this whole view is organised around.
  def latest_turn = turns.last

  # Everything before it, newest first, so the log reads away from the present.
  def earlier_turns = turns[0...-1].to_a.reverse

  # THE CLOSED SET the classifier will offer the model on the next turn.
  #
  # Asked of `Playthrough::Classifier` itself rather than worked out again:
  # these are its own two candidate methods, and both are plain reads. A second
  # opinion about what counts as an exit or who counts as present is exactly
  # the drift the classifier's own comments warn about.
  def classifier
    @classifier ||= Playthrough::Classifier.new(playthrough)
  end

  def candidate_exits = @candidate_exits ||= classifier.exits_here
  def candidate_cast = @candidate_cast ||= classifier.characters_here

  # The enum `Playthrough::IntentSchema.for` would be built over: the answers
  # the model is physically able to give, plus `nothing`.
  def candidate_enum
    names = candidate_exits.map(&:name) +
            candidate_cast.flat_map { |character| [ character.fullname, character.nickname ] }

    names.map(&:to_s).map(&:strip).reject(&:empty?).uniq + [ Playthrough::IntentSchema::NOTHING ]
  end

  # The classifier's prompt as it would be built for the next turn.
  #
  # RECONSTRUCTED FROM RECORDS, not captured -- nothing captures what was
  # actually sent, which is the honest gap named at the top of this class. It
  # earns its place anyway because this is the one prompt in the app the
  # standing constraint is about: it is where the app closes the set, and
  # seeing it is seeing the set.
  def classifier_prompt(command = "<what you type next>")
    classifier.command_prompt(command, candidate_exits, candidate_cast)
  end

  # WHERE HE IS STANDING, and what leads out of it in both directions.
  def exits
    return [] if location.nil?

    @exits ||= location.exits.order(:id).map do |neighbour|
      Exit.new(
        location: neighbour,
        out: LocationConnection.find_by(location: location, connected_location: neighbour),
        back: LocationConnection.find_by(location: neighbour, connected_location: location)
      )
    end
  end

  # THE WORLD'S OWN CLOCK. `Story#clock` is the high-water mark across every
  # playthrough, because the world moves for everybody; `Playthrough#story_now`
  # is where this player stands. They differ as soon as one world is played
  # twice, and seeing both is the point.
  def story_clock = story.clock
  def story_now = playthrough.story_now

  # Every mechanic, with what it still owes and when it fires next. `owed` is
  # normally empty: `Playthrough::Turn#play` catches the world up before it
  # reads the command, so anything here is a night the world has not paid --
  # which happens when the story's clock moved without a turn being played.
  def mechanics
    story.world_mechanics.order(:id).map do |mechanic|
      Mechanic.new(
        mechanic: mechanic,
        owed: mechanic.pending_boundaries(story_clock),
        next_at: mechanic.next_boundary_after(mechanic.last_run_at || story.start_time),
        events: mechanic.world_events.in_story_order.to_a
      )
    end
  end

  # The audit trail, newest first. NOT a narration source (see WorldEvent) --
  # it is here precisely because it is the only place a rearranged town leaves
  # a mark the player never reads.
  def world_events
    story.world_events.includes(:world_mechanic, :locations).in_story_order.reverse
  end

  # THE MAP, every place the world has named. Stubs included and counted: an
  # unexplored exit is a real record with a name and a teaser, and the ratio of
  # stubs to realized places is the clearest single number about how much of
  # this world has actually been written.
  def places
    @places ||= story.locations.includes(:connected_locations).order(:id).to_a
  end

  def stub_count = places.count(&:stub?)
  def realized_count = places.count(&:realized?)

  def cast
    @cast ||= story.characters.includes(:race).order(:id).to_a
  end

  # Every conversation this story has ever kept, newest first. The five
  # structured fields are the whole reason `Interaction` exists and the player
  # only ever reads them rendered into prose.
  def interactions
    # Qualified: `interactions` comes through `characters`, so a bare
    # `created_at` is ambiguous across the join.
    story.interactions.includes(:character, :location, :scene)
         .order(Interaction.arel_table[:created_at].desc)
  end

  private

  # WHICH BRANCH THE TURN TOOK, decided from the records the branch left behind
  # rather than from any label -- there is no stored label to read, and the
  # loop dispatches on the resolved record anyway.
  #
  #   opening       `is_opening`. World data: the arrival every playthrough of
  #                 this story starts on.
  #   conversation  `Playthrough::Turn#talk_to` is the only thing that writes
  #                 an `Interaction`.
  #   arrival       the location changed, which only a move can do -- or the
  #                 chain starts here, which is the fallback opening scene
  #                 `PlaythroughsController` writes for a world with none.
  #   narration     everything else: `Scene::Narrator` answers the command in
  #                 place, and records no cast.
  def branch_for(scene, previous)
    return :opening if scene.is_opening?
    return :conversation if scene.interactions.any?
    return :arrival if previous.nil?
    return :arrival if scene.location_id != previous.location_id

    :narration
  end

  # The reasoning, in the open. Anything surprising is reported as surprising
  # rather than smoothed over: a narrated turn that somehow recorded a cast is
  # the sort of thing this view exists to make visible.
  def evidence_for(scene, previous, branch, elapsed, cost)
    lines = []

    case branch
    when :opening
      lines << "scenes.is_opening -- world data, shared by every playthrough of this story"
      lines << "deliberately does not stamp Location#last_protagonist_visit (see Scene)"
    when :conversation
      lines << "#{scene.interactions.size} Interaction row#{"s" unless scene.interactions.one?} -- only Playthrough::Turn#talk_to writes one"
    when :arrival
      lines << if previous.nil?
        "first scene in the chain, and not is_opening -- the fallback opening PlaythroughsController writes"
      else
        "location changed: #{previous.location.name} -> #{scene.location.name}"
      end
      lines << "cast recorded (#{scene.characters.size}) -- only Scene::Generator records one" if scene.characters.any?
    when :narration
      lines << "no Interaction, no cast, same location -- Scene::Narrator answered the command in place"
      lines << "ANOMALY: a narrated turn recorded #{scene.characters.size} character(s); Scene::Narrator records none" if scene.characters.any?
    end

    lines << "story time +#{format_minutes(elapsed)}: #{cost}" if cost
    lines << "no summary written -- Scene::Generator writes one, Scene::Narrator does not" if scene.summary.blank?
    lines
  end

  # WHAT THE TURN COST IN STORY TIME, checked against the fixed tables that are
  # supposed to have decided it. A cost that matches nothing is worth seeing:
  # every turn is either a journey priced by `LocationConnection` or a beat
  # priced by `Scene::TURN_MINUTES`, and the wall clock is not on that list.
  def cost_reading_for(scene, previous, elapsed)
    return nil if elapsed.nil?

    # The edge is checked FIRST on a turn that moved, and the order is not
    # cosmetic: `Scene::TURN_MINUTES["action"]` is 5 minutes and so is a short
    # walk on foot, so a table-first reading credits a journey to a beat in the
    # room. A turn that did not move cannot have walked an edge, so there the
    # table is the only honest answer.
    moved = previous && previous.location_id != scene.location_id
    readings = moved ? [ :edge, :table ] : [ :table, :edge ]

    readings.each do |source|
      answer = source == :edge ? edge_reading(scene, previous, elapsed) : table_reading(elapsed)
      return answer if answer
    end

    "matches no fixed table -- neither Scene::TURN_MINUTES nor any edge into here"
  end

  def table_reading(elapsed)
    fixed = Scene::TURN_MINUTES.find { |_kind, minutes| minutes == elapsed }

    "Scene::TURN_MINUTES[#{fixed.first.inspect}]" if fixed
  end

  def edge_reading(scene, previous, elapsed)
    edge = previous && LocationConnection.find_by(
      location: previous.location, connected_location: scene.location
    )
    return nil if edge.nil?
    return nil unless LocationConnection.travel_minutes(edge.distance, edge.travel_method) == elapsed

    "the edge walked -- #{edge.distance}, #{edge.travel_method}"
  end

  def build_turn(scene)
    previous = scene.previous_scene
    elapsed = elapsed_minutes(scene, previous)
    cost = cost_reading_for(scene, previous, elapsed)
    branch = branch_for(scene, previous)

    Turn.new(
      scene: scene,
      branch: branch,
      evidence: evidence_for(scene, previous, branch, elapsed, cost),
      elapsed_minutes: elapsed,
      cost_reading: cost,
      # Only a conversation keeps it. See the class comment.
      typed: scene.interactions.filter_map(&:user_input).first,
      interactions: scene.interactions.to_a,
      cast: scene.characters.to_a
    )
  end

  def elapsed_minutes(scene, previous)
    return nil if previous.nil? || scene.story_timestamp.nil? || previous.story_timestamp.nil?

    ((scene.story_timestamp - previous.story_timestamp) / 60.0).round(2)
  end

  def format_minutes(minutes)
    return "?" if minutes.nil?

    minutes == minutes.to_i ? "#{minutes.to_i} min" : "#{minutes} min"
  end

  # The turn partial reads interactions and the cast on every scene, and the
  # log is the whole playthrough.
  def preload(scenes)
    ActiveRecord::Associations::Preloader.new(
      records: scenes,
      associations: [ :location, :characters, { interactions: :character } ]
    ).call
  end
end
