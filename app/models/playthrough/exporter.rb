# ONE PLAYTHROUGH AS A JSON FILE, keyed by names rather than database ids.
#
# WHY IT EXISTS. A GitHub issue about a played-in world needs the turns, the
# commands, the rooms as they stood, and the model exchanges that wrote them --
# not a pointer into somebody's development.sqlite3. `WorldSeed::Exporter` is
# the world's own dump and deliberately leaves progress behind; this is the
# other half: one player's way through a story, with enough of the world beside
# it that the file can be read alone.
#
# READ ONLY. Nothing here asks a model, writes a row, or advances a clock -- the
# same rule `Playthrough::Debug` is under, for the same reason: looking at a
# game must not move it. The file is a photograph.
#
# NAMES, NOT IDS. Every cross-reference is a written name (`Location#name`,
# `Character#fullname`, `Item#name`) or a turn key built from story time, place
# and typed line. Journal receipts that stored `{ "record" => "...", "id" => N }`
# are re-resolved to names on the way out, so a future reader never has to
# open the database that produced the file.
#
# WHAT IT CARRIES:
#
#   * the story's title, genre, preface and summary -- enough to know which
#     world this was without re-exporting the seed
#   * every location of the story (stubs included), with parent, footprint /
#     box, prose and the exits between them by name
#   * every character, with world whereabouts and this game's `NpcState`
#   * world-layer items and this playthrough's copies, each saying where they
#     lie or who holds them
#   * the turn log (`Playthrough#scene_chain`), with branch and evidence from
#     `Playthrough::Debug` so the file says what the debug page would
#   * every submitted command and its journal / refusal
#   * drifts, overreaches, feedback, tolls, beats
#   * every chat this playthrough still holds, prompts and answers included --
#     the receipts that explain why a room came out the way it did
#
# WHAT IT IS NOT. It is not a seed file and it will not load back into a
# database. For a restoreable miniature primary DB of this playthrough's story,
# see `Playthrough::SqlitePackage` / `rake game:dump_playthrough`.
class Playthrough::Exporter
  FORMAT = 1
  DIRECTORY = Rails.root.join("tmp/playthrough-exports")

  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
    @warnings = []
  end

  def story = playthrough.story

  # Writes the JSON file and returns its path. Defaults under
  # `tmp/playthrough-exports/`, named from the story and the protagonist so two
  # playthroughs of the same world do not silently overwrite each other when
  # the character differs.
  def write!(path: nil)
    path = Pathname.new(path || default_path)
    path.dirname.mkpath
    path.write(JSON.pretty_generate(document))
    path
  end

  def warnings = @warnings.uniq

  # The whole playthrough as a plain Hash. Keys in the order a reader meeting
  # the file for the first time wants them.
  def document
    debug = Playthrough::Debug.new(playthrough)
    turns = debug.turns
    turn_keys = turns.map { |turn| turn_key(turn.scene) }

    {
      "format" => FORMAT,
      "exported_at" => Time.current.utc.iso8601,
      "story" => story_document,
      "playthrough" => playthrough_document,
      "locations" => locations_document,
      "connections" => connections_document,
      "characters" => characters_document,
      "items" => {
        "world" => world_items_document,
        "in_this_game" => playthrough_items_document
      },
      "turns" => turns_document(turns, turn_keys),
      "commands" => commands_document(turn_keys),
      "drifts" => drifts_document(turn_keys),
      "overreaches" => overreaches_document(turn_keys),
      "feedback" => feedback_document(turn_keys),
      "tolls" => tolls_document(turn_keys),
      "beats" => beats_document,
      "conversations" => conversations_document(turn_keys)
    }.tap { warn_about_gaps!(turns) }
  end

  private

  def default_path
    story_slug = WorldSeed.slug(story.title)
    who = playthrough.character&.fullname.presence || "unstarted"
    DIRECTORY.join("#{story_slug}--#{WorldSeed.slug(who)}.json")
  end

  def story_document
    {
      "title" => story.title,
      "genre" => story.genre,
      "start_time" => iso(story.start_time),
      "summary" => story.summary,
      "preface" => story.preface
    }.compact
  end

  def playthrough_document
    location = playthrough.current_location
    {
      "protagonist" => playthrough.character&.fullname,
      "current_location" => location&.name,
      "containing_place" => location&.parent_location&.name,
      "story_now" => iso(playthrough.story_now),
      "story_clock" => iso(story.clock)
    }.compact
  end

  def locations_document
    story.locations.includes(:parent_location).order(:id).map do |location|
      document = {
        "name" => location.name,
        "detail_level" => location.detail_level,
        "teaser" => location.teaser
      }
      document["parent"] = location.parent_location.name if location.parent_location
      document["place"] = true if location.place?
      document["laid_out"] = true if location.laid_out?
      document["danger"] = location.danger unless location.danger == Location::SAFE
      document["population"] = location.population if location.population.present?
      if location.hazard.present?
        document["hazard"] = location.hazard
        document["hazard_die"] = location.hazard_die
      end
      Location::Box::COLUMNS.each do |column|
        document[column.to_s] = location[column] unless location[column].nil?
      end
      if location.realized?
        document["description"] = location.description
        document["lore"] = location.lore
      end
      document["last_protagonist_visit"] = iso(location.last_protagonist_visit) if location.last_protagonist_visit
      document["placeholder_name"] = true if location.parent_location &&
        Location::Interior.placeholder_name?(location.parent_location, location.name)
      document.compact
    end
  end

  def connections_document
    seen = {}
    rows = []

    LocationConnection
      .where(location_id: story.locations.select(:id))
      .includes(:location, :connected_location)
      .order(:id)
      .each do |edge|
        a = edge.location.name
        b = edge.connected_location.name
        key = [ a, b ].sort
        next if seen[key]

        seen[key] = true
        rows << {
          "between" => key,
          "distance" => edge.distance,
          "travel_method" => edge.travel_method,
          "time_to_travel" => edge.time_to_travel,
          "barrier" => edge.barrier,
          "hazard" => edge.hazard,
          "hazard_die" => edge.hazard_die
        }.compact
      end

    rows
  end

  def characters_document
    npc_by_character = playthrough.npc_states.includes(:location, :character).index_by(&:character_id)

    story.characters.includes(:race, :location).order(:id).map do |character|
      document = {
        "fullname" => character.fullname,
        "nickname" => character.nickname,
        "race" => character.race&.name,
        "is_protagonist" => character.is_protagonist? || nil,
        "is_companion" => character.is_companion? || nil,
        "hostile" => character.hostile? || nil,
        "deliberately_absent" => character.deliberately_absent? || nil,
        "world_location" => character.location&.name
      }
      state = npc_by_character[character.id]
      if state
        document["in_this_game"] = {
          "location" => state.location&.name,
          "following" => state.following? || nil,
          "ceasefire" => state.ceasefire? || nil
        }.compact
      end
      document.compact
    end
  end

  def world_items_document
    Item.in_story(story).templates.includes(:location, :character).order(:id).map do |item|
      item_document(item)
    end
  end

  def playthrough_items_document
    playthrough.items.includes(:location, :character, :template).order(:id).map do |item|
      item_document(item).merge("template" => item.template&.name).compact
    end
  end

  def item_document(item)
    {
      "name" => item.name,
      "description" => item.description,
      "location" => item.location&.name,
      "held_by" => item.character&.fullname,
      "use_kind" => item.use_kind,
      "readable" => item.readable? || nil,
      "inscription" => item.inscription,
      "combustible" => item.combustible? || nil,
      "disposition" => item.disposition,
      "bulk" => item.bulk
    }.compact
  end

  def turns_document(turns, _turn_keys)
    turns.map do |turn|
      scene = turn.scene
      {
        "key" => turn_key(scene),
        "branch" => turn.branch.to_s,
        "typed" => turn.typed.presence,
        "location" => scene.location&.name,
        "containing_place" => scene.location&.parent_location&.name,
        "story_timestamp" => iso(scene.story_timestamp),
        "resolved_action" => scene.resolved_action,
        "resolved_by" => scene.resolved_by,
        "acted_on" => acted_on_name(scene),
        "is_opening" => scene.is_opening? || nil,
        "engine_fallback" => scene.engine_fallback? || nil,
        "description" => scene.description,
        "summary" => scene.summary,
        "engine_fact" => scene.engine_fact,
        "evidence" => turn.evidence,
        "elapsed_minutes" => turn.elapsed_minutes,
        "cost_reading" => turn.cost_reading,
        "cast" => turn.cast.map(&:fullname),
        "feedback" => turn.feedback && {
          "verdict" => turn.feedback.verdict,
          "note" => turn.feedback.note,
          "prose_model" => turn.feedback.prose_model,
          "prose_purpose" => turn.feedback.prose_purpose
        }.compact,
        "input_tokens" => turn.input_tokens,
        "output_tokens" => turn.output_tokens,
        "models" => turn.models
      }.compact
    end
  end

  def commands_document(_turn_keys)
    playthrough.commands.order(:id).map do |command|
      {
        "command" => command.command,
        "status" => command.status,
        "error_kind" => command.error_kind,
        "refusal" => command.refusal.presence,
        "result_turn" => turn_keys_by_scene_id[command.result_scene_id],
        "journal" => name_keyed_journal(command.journal)
      }.compact
    end
  end

  def drifts_document(_turn_keys)
    playthrough.drifts.in_story_order.includes(:scene, :location).map do |drift|
      {
        "turn" => turn_keys_by_scene_id[drift.scene_id],
        "location" => drift.location&.name,
        "action" => drift.action,
        "command" => drift.command,
        "offered" => drift.offered,
        "story_timestamp" => iso(drift.story_timestamp)
      }.compact
    end
  end

  def overreaches_document(_turn_keys)
    playthrough.overreaches.in_story_order.includes(:scene, :location).map do |row|
      {
        "turn" => turn_keys_by_scene_id[row.scene_id],
        "location" => row.location&.name,
        "action" => row.action,
        "command" => row.command,
        "acted" => row.acted,
        "unacted" => row.unacted,
        "story_timestamp" => iso(row.story_timestamp)
      }.compact
    end
  end

  def feedback_document(_turn_keys)
    playthrough.feedbacks.in_story_order.includes(:scene).map do |row|
      {
        "turn" => turn_keys_by_scene_id[row.scene_id],
        "verdict" => row.verdict,
        "note" => row.note,
        "prose_model" => row.prose_model,
        "prose_models" => row.prose_models,
        "prose_purpose" => row.prose_purpose,
        "answering_models" => row.answering_models,
        "input_tokens" => row.input_tokens,
        "output_tokens" => row.output_tokens
      }.compact
    end
  end

  def tolls_document(_turn_keys)
    playthrough.tolls.order(:sequence, :id).includes(:character, :location, :scene).map do |toll|
      {
        "turn" => turn_keys_by_scene_id[toll.scene_id],
        "character" => toll.character.fullname,
        "location" => toll.location.name,
        "hazard" => toll.hazard,
        "damage" => toll.damage,
        "hp_after" => toll.hp_after,
        "saved" => toll.saved? || nil,
        "story_timestamp" => iso(toll.story_timestamp)
      }.compact
    end
  end

  def beats_document
    playthrough.beats.includes(quest_step: :quest).in_story_order.map do |beat|
      step = beat.quest_step
      {
        "quest" => step.quest.title,
        "step" => step.position,
        "summary" => step.summary,
        "trigger_kind" => step.trigger_kind,
        "target_name" => step.target_name,
        "reached_at" => iso(beat.reached_at)
      }.compact
    end
  end

  def conversations_document(_turn_keys)
    playthrough.chats.includes(:character, messages: :model).order(:id).map do |chat|
      {
        "purpose" => chat.purpose,
        "character" => chat.character&.fullname,
        "messages" => chat.messages.order(:id).map do |message|
          {
            "role" => message.role.to_s,
            "turn" => turn_keys_by_scene_id[message.scene_id],
            "model" => message.model&.model_id,
            "input_tokens" => message.input_tokens,
            "output_tokens" => message.output_tokens,
            "content" => message.content,
            "content_raw" => message.content_raw
          }.compact
        end
      }.compact
    end
  end

  def turn_key(scene)
    [
      iso(scene.story_timestamp) || "no-time",
      scene.location&.name || "nowhere",
      scene.typed.presence || (scene.is_opening? ? "(opening)" : "(untimed)")
    ].join(" | ")
  end

  def turn_keys_by_scene_id
    @turn_keys_by_scene_id ||= playthrough.scene_chain.to_h { |scene| [ scene.id, turn_key(scene) ] }
  end

  def acted_on_name(scene)
    target = scene.acted_on
    return nil if target.nil?

    case target
    when Location then target.name
    when Character then target.fullname
    when Item then target.name
    else target.class.name
    end
  end

  def iso(time)
    time&.utc&.iso8601(6)
  end

  def name_keyed_journal(journal)
    return nil if journal.blank?

    deep_name_key(journal)
  end

  def deep_name_key(value)
    case value
    when Array
      value.map { |entry| deep_name_key(entry) }
    when Hash
      if value.key?("record") && value.key?("id")
        named_record(value)
      else
        value.to_h { |key, entry| [ key, deep_name_key(entry) ] }
      end
    else
      value
    end
  end

  def named_record(encoded)
    type = encoded.fetch("record")
    id = encoded.fetch("id")
    row = type.constantize.find_by(id: id)

    named = { "record" => type }
    if row.nil?
      named["missing"] = true
      named["id"] = id
      @warnings << "journal named #{type} ##{id}, which is gone from the database"
      return named
    end

    case row
    when Location
      named["name"] = row.name
      named["parent"] = row.parent_location&.name
    when Character
      named["name"] = row.fullname
    when Item
      named["name"] = row.name
      named["held_by"] = row.character&.fullname
      named["location"] = row.location&.name
    when Scene
      named["turn"] = turn_keys_by_scene_id[row.id] || turn_key(row)
      named["tolls"] = encoded["tolls"] if encoded.key?("tolls")
      named["safety"] = encoded["safety"] if encoded.key?("safety")
      named["setup"] = encoded["setup"] if encoded.key?("setup")
    when LocationConnection
      named["between"] = [ row.location.name, row.connected_location.name ]
      named["distance"] = row.distance
      named["travel_method"] = row.travel_method
    when Playthrough::Blow
      named["attacker"] = row.attacker&.fullname
      named["target"] = row.target&.fullname
      named["round"] = row.round
    when Playthrough::Toll
      named["character"] = row.character.fullname
      named["location"] = row.location.name
      named["hazard"] = row.hazard
      named["damage"] = row.damage
    when Playthrough::Ending
      named["outcome"] = row.quest_outcome&.name
    when Quest::Outcome
      named["name"] = row.name
    else
      named["id"] = id
      @warnings << "journal record #{type} has no name mapping; id left in place"
    end

    named.compact
  end

  def warn_about_gaps!(turns)
    pruned = turns.count { |turn| !turn.recorded? }
    if pruned.positive?
      @warnings << "#{pruned} turn(s) have no chat receipts left " \
                   "(TA_CHAT_KEEP_TURNS pruned them); their prompts are not in this file"
    end

    if playthrough.chats.where(purpose: "location").none? &&
       story.locations.realized.where.not(parent_location_id: nil).exists?
      @warnings << "interior rooms were realized but this playthrough holds no purpose=location chats; " \
                   "those receipts may live on a chat without playthrough_id"
    end
  end
end
