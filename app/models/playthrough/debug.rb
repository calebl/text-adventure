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
# WHAT IT NOW SHOWS, and did not: every prompt sent, every answer that came
# back, what each cost and which model actually wrote it. `BaseAgent` persists
# a `Chat` per conversation and stamps each message with the turn it was
# exchanged on (`messages.scene_id`), so a turn's cost is a sum over records
# rather than a thing nobody kept. Two of the three gaps this class used to
# name close with it, because the classifier's own exchange holds both the raw
# typed command and the intent label the loop decided in memory.
#
# AND ONE THING NEITHER THE APP NOR A MODEL PRODUCED: what the player thought
# of each turn. `Playthrough::Feedback` is recorded a click at a time on the
# play page, with the turn's provenance FROZEN onto it, so this page can answer
# which model wrote the prose behind each verdict on turns whose receipts the
# pruner took away long ago. See `#feedback_by_model`.
#
# WHAT IT STILL CANNOT SHOW is named rather than quietly missing:
#
#   * a turn whose receipts were pruned -- which, by default, is none of them.
#     `Chat::KEEP_TURNS` is nil unless `TA_CHAT_KEEP_TURNS` is set, so every
#     turn a playthrough ever played keeps its prompts, answers, token counts
#     and models. Where a cap IS set, an old turn keeps its `Scene` and loses
#     its receipts, and that is said out loud where it happens rather than left
#     to look like a turn that cost nothing.
#
# WHAT THE PLAYER TYPED IS NO LONGER ONE OF THEM. `Scene#typed` is a column now,
# written on every branch by `Playthrough::Turn#play`, so it survives whatever
# the retention setting is -- see `#typed_on`, whose two fallbacks exist only for
# turns written before that column did.
class Playthrough::Debug
  # One turn of the log, as the records tell it.
  #
  # `branch` is DERIVED, never read back -- see `#branch_for`. `evidence` is
  # the reasoning in the open, so a wrong answer here is visible as a wrong
  # answer rather than as a confident label.
  Turn = Data.define(:scene, :branch, :evidence, :elapsed_minutes, :cost_reading,
                     :typed, :interactions, :cast, :conversations, :feedback) do
    def opening? = branch == :opening
    def judged? = !feedback.nil?

    # WHAT THE TURN COST, from the provider's own numbers. Zero is not the same
    # as unknown: a turn whose conversations were pruned has none left to add up,
    # and an opening arrival was paid for at world-build time by somebody else.
    def input_tokens = conversations.sum(&:input_tokens)
    def output_tokens = conversations.sum(&:output_tokens)
    def recorded? = conversations.any?

    # Which models actually answered this turn. Usually one; more than one means
    # `BaseAgent` rotated past a model that failed, which is worth seeing.
    def models = conversations.flat_map(&:models).uniq
  end

  # ONE CONVERSATION, as far as this turn is concerned.
  #
  # `messages` is only the part exchanged on THIS turn, which is the whole
  # reason the scene is recorded on the message rather than on the chat: a
  # durable conversation with a character runs across many turns and each turn
  # pays for its own two messages.
  Exchange = Data.define(:chat, :messages) do
    def purpose = chat.purpose || "(unfiled)"
    def durable? = chat.purpose == Chat::CHARACTER
    def input_tokens = messages.sum { |message| message.input_tokens.to_i }
    def output_tokens = messages.sum { |message| message.output_tokens.to_i }
    def models = messages.filter_map { |message| message.model&.model_id }.uniq

    def sent = messages.select { |message| message.role.to_s == "user" }
    def answers = messages.select { |message| message.role.to_s == "assistant" }

    # The system instruction lives on the chat, not on the turn -- it is written
    # once and replayed -- so it is read from the conversation rather than from
    # this turn's messages.
    def instructions = chat.messages.find { |message| message.role.to_s == "system" }
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

    # The two rows of one edge must carry the same values -- they are written
    # from one answer and `LocationConnection`'s tables are direction-neutral
    # for exactly that reason -- so a disagreement means one direction is wrong.
    # `Story::Doctor` reports this story-wide as `connection_directions_disagree`;
    # this is the same question asked of the room the player is standing in.
    def directions_disagree?
      return false if out.nil? || back.nil?

      [ out.distance, out.travel_method ] != [ back.distance, back.travel_method ]
    end

    # Minutes, or nil when either value is outside the fixed tables. Nil here is
    # NOT "no value": it is a value the app cannot price, which is
    # `Story::Doctor`'s `unknown_distance` / `unknown_travel_method`.
    def minutes
      return nil if out.nil?

      LocationConnection.travel_minutes(out.distance, out.travel_method)
    end

    def unpriceable? = !out.nil? && minutes.nil?
  end

  # A world mechanic and where it stands on the story's clock.
  Mechanic = Data.define(:mechanic, :owed, :next_at, :events)

  # A place, and who the game believes is standing in it.
  #
  # `cast` is the HOLDOVER rule -- whoever was in the last scene here that
  # recorded anyone -- which is one of the three things
  # `Scene::Generator#characters_present` answers from, and the only one that
  # is about this place rather than about the player. The protagonist and any
  # companion travel with the player and so would appear in every row, which
  # would say nothing.
  Place = Data.define(:location, :cast, :here) do
    def stub? = location.stub?
  end

  # A character, and the last moment the world recorded them anywhere.
  #
  # NOTHING RECORDS WHERE A CHARACTER STANDS -- `characters` has no location
  # column -- so this is the whole of what the game knows about where somebody
  # is, and a character the player has never met is honestly nowhere.
  Person = Data.define(:character, :last_scene) do
    def seen? = !last_scene.nil?
  end

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

  # ------------------------------------------------------------------------
  # WHAT THE RECORDS SAY ABOUT THE PROSE. `Story::Audit` read offline, over the
  # scenes this playthrough actually played -- so the page that shows what the
  # app decided also shows where the narration disagreed with it. Read-only like
  # everything else here: the sweep makes no model call and writes nothing.
  # ------------------------------------------------------------------------
  def audit = @audit ||= Story::Audit.new(story)

  # Contradictions on this playthrough's own turns, newest first, so the most
  # recent disagreement is the one at the top.
  def contradictions
    scene_ids = turns.filter_map { |turn| turn.scene&.id }.to_set

    audit.contradictions.select { |flag| scene_ids.include?(flag.scene&.id) }.reverse
  end

  # EVERY TURN THIS PLAYER REACHED FOR SOMETHING THAT WAS NOT THERE, newest
  # first. Read straight off `Playthrough::Drift` rather than through the audit,
  # because these belong to this playthrough and the audit is story-wide.
  def drifts
    @drifts ||= playthrough.drifts.in_story_order.includes(:scene, :location).to_a.reverse
  end

  def drift_tally = Playthrough::Drift.tally(playthrough.drifts)

  # ------------------------------------------------------------------------
  # WHAT THE PLAYER THOUGHT OF EACH TURN. `Playthrough::Feedback` is the one
  # thing on this page the app did not decide and no model wrote: it is the
  # captain's own judgement, recorded a click at a time while he played, with
  # the turn's provenance frozen onto it so it stays legible after
  # `prune_conversations!` has taken the receipts away.
  #
  # This is where it is read back, because the question it exists to answer is
  # the kind this page is for -- which model do the turns marked good actually
  # come from. Counts only: what the numbers prove is a later task
  # (`ta-narrator-model`, `ta-talk-model`), and a score computed here would be
  # an answer the data has not earned yet.
  # ------------------------------------------------------------------------

  # Every verdict on this playthrough, newest first, so the turn he judged last
  # is at the top. `scene` is preloaded because each row is shown next to the
  # prose it judges.
  def feedback
    @feedback ||= playthrough.feedbacks.includes(:scene).in_story_order.to_a.reverse
  end

  def feedback_tally = playthrough.feedbacks.group(:verdict).count

  # THE CROSS-TAB, and the reason the provenance is frozen: verdict against the
  # model that wrote the prose being judged. Read off the feedback rows
  # themselves -- never off `chats` -- so a turn whose conversations were pruned
  # months ago still counts.
  #
  # A row keyed nil is honest and stays in: those are turns judged after their
  # receipts had already gone, or an opening arrival that was generated when the
  # world was built. Dropping them would quietly shrink the denominator.
  def feedback_by_model
    feedback.group_by(&:prose_model).transform_values do |rows|
      rows.group_by(&:verdict).transform_values(&:size)
    end
  end

  # Every mechanic, with what it still owes and when it fires next. `owed` is
  # normally empty: `Playthrough::Turn#play` catches the world up before it
  # reads the command, so anything here is a night the world has not paid --
  # which happens when the story's clock moved without a turn being played.
  def mechanics
    @mechanics ||= story.world_mechanics.order(:id).map do |mechanic|
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
    @world_events ||= story.world_events.includes(:world_mechanic, :locations).in_story_order.reverse
  end

  # THE MAP, every place the world has named. Stubs included and counted: an
  # unexplored exit is a real record with a name and a teaser, and the ratio of
  # stubs to realized places is the clearest single number about how much of
  # this world has actually been written.
  # THE MAP, every place the world has named, with who is standing in each.
  def places
    @places ||= story.locations.includes(:connected_locations).order(:id).map do |place|
      Place.new(location: place, cast: cast_recorded_at(place), here: place == location)
    end
  end

  def stub_count = places.count(&:stub?)
  def realized_count = places.count { |place| !place.stub? }

  # THE CAST, everyone this world has generated, with where each was last seen.
  def cast
    @cast ||= story.characters.includes(:race).order(:id).map do |character|
      Person.new(character: character, last_scene: last_scene_for(character))
    end
  end

  def unseen_count = cast.count { |person| !person.seen? }

  # WHAT THE WHOLE PLAYTHROUGH HAS COST, over the turns still holding receipts.
  def input_tokens = turns.sum(&:input_tokens)
  def output_tokens = turns.sum(&:output_tokens)
  def recorded_turns = turns.count(&:recorded?)
  def pruned_turns = turns.count { |turn| !turn.recorded? }

  # Every model that has answered anything in this playthrough. More than one is
  # `BaseAgent` having rotated -- past a model that failed, or down to ollama
  # because there was no key.
  def answering_models = turns.flat_map(&:models).uniq

  # THE CONVERSATIONS THAT ARE STILL RUNNING: one per person the player has
  # spoken to, picked up again on every turn rather than started fresh.
  #
  # This is the part of the game that quitting used to lose. It is also the part
  # with a ceiling on it -- `Chat#prune_history!` keeps the last
  # `Chat::HISTORY_EXCHANGES` -- so the count of what is left is worth showing
  # next to the count of `Interaction` rows, which is everything that was ever
  # said.
  def durable_conversations
    @durable_conversations ||= playthrough.chats.durable
                                          .includes(:character, messages: :model).order(:id).to_a
  end

  # Every conversation this story has ever kept, newest first. The five
  # structured fields are the whole reason `Interaction` exists and the player
  # only ever reads them rendered into prose.
  def interactions
    # Qualified: `interactions` comes through `characters`, so a bare
    # `created_at` is ambiguous across the join.
    @interactions ||= story.interactions.includes(:character, :location, :scene)
                           .order(Interaction.arel_table[:created_at].desc).to_a
  end

  private

  # Whoever was in the last scene in this location that recorded anyone. The
  # same read `Scene::Generator#holdovers` makes, and deliberately so: it is
  # what the game will answer with next time somebody walks in here, so a
  # second opinion would be a second answer.
  def cast_recorded_at(place)
    scene = place.scenes.joins(:characters).order(story_timestamp: :desc, id: :desc).first

    scene ? scene.characters.to_a : []
  end

  # The latest scene, in story time, that recorded this character anywhere.
  def last_scene_for(character)
    character.scenes.includes(:location).order(story_timestamp: :desc, id: :desc).first
  end

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
    conversations = conversations_for(scene)

    Turn.new(
      scene: scene,
      branch: branch,
      evidence: evidence_for(scene, previous, branch, elapsed, cost),
      elapsed_minutes: elapsed,
      cost_reading: cost,
      typed: typed_on(scene, conversations),
      interactions: scene.interactions.to_a,
      cast: scene.characters.to_a,
      conversations: conversations,
      feedback: verdicts[scene.id]
    )
  end

  # The verdicts this player recorded, keyed by turn. One query for the whole
  # log; see `Playthrough#feedback_by_scene` for why it is keyed by
  # (playthrough, scene) rather than by scene alone.
  def verdicts = @verdicts ||= playthrough.feedback_by_scene

  # EVERY CONVERSATION THIS TURN PAID FOR, in the order they happened.
  #
  # Grouped from `messages.scene_id`, so a durable conversation contributes only
  # the two messages this turn exchanged and the one-shot ones contribute all
  # of theirs. Ordered by the first message written, which is the order the loop
  # made the calls in: classify, then the branch.
  def conversations_for(scene)
    scene.messages.sort_by(&:id).group_by(&:chat)
         .map { |chat, messages| Exchange.new(chat: chat, messages: messages) }
         .sort_by { |exchange| exchange.messages.first.id }
  end

  # WHAT THE PLAYER TYPED, out of `Scene#typed` -- a column written on every
  # branch by `Playthrough::Turn#play`, so this no longer depends on the audit
  # trail surviving. The two fallbacks are for turns written before that column
  # existed and are what the migration backfills from: `Interaction#user_input`
  # on a talk turn, and the classifier's own prompt while it is still kept.
  def typed_on(scene, conversations)
    return scene.typed if scene.typed.present?

    recorded = scene.interactions.filter_map(&:user_input).first
    return recorded if recorded.present?

    classifier = conversations.find { |exchange| exchange.purpose == "classifier" }
    classifier&.sent&.first&.text.to_s[/## The Player Types\n(.*)/m, 1]&.strip.presence
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
      associations: [ :location, :characters, { interactions: :character },
                      { messages: [ :model, :chat ] } ]
    ).call
  end
end
