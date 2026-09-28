# A PLAYTHROUGH STANDING IN ONE ROOM, built from a plain description with
# explicit ids: the closed sets `Playthrough::Classifier` reads (the ways out,
# who is here, what is lying here, what the party carries) and nothing else.
# The line-reading portions all stand in one of these.
#
# A world is a Hash:
#
#   story_id     the story's id; the universe shares it
#   protagonist  { id, fullname } or null for a story nobody plays
#   here         { id, name } or null for a playthrough standing nowhere
#   exits        [{ id, name, barrier? }]; a doorway from `here`, barrier
#                "open" unless it says "jammed"; the doorway's own row
#                carries the exit's id too, which a physical attempt's token
#                names
#   cast         [{ id, fullname, nickname }] standing in `here`
#   lying        [{ id, name, bulk?, use_kind?, combustible? }] on this
#                game's floor of `here`
#   carried      the same shape, in this game's hands
#
# The playthrough is `story_id` too. A key left out takes the column's default.
module EngineVectors::Room
  Built = Data.define(:playthrough, :records) do
    def classifier = Playthrough::Classifier.new(playthrough)
    def grammar = Playthrough::Grammar.new(playthrough, classifier: classifier)

    # A record by its explicit id: a Location, a Character or an Item.
    def [](id) = records.fetch(id)
  end

  ITEM_KEYS = %w[bulk use_kind combustible].freeze

  def self.build!(world)
    story = EngineVectors::World.story!(world["story_id"])
    records = {}
    here = world["here"] && EngineVectors::World.location!(story, id: world["here"]["id"], name: world["here"]["name"],
                                                                  detail_level: :realized)
    records[here.id] = here if here

    Array(world["exits"]).each do |exit|
      room = EngineVectors::World.location!(story, id: exit["id"], name: exit["name"])
      records[room.id] = room
      next unless here

      LocationConnection.create!(id: exit["id"], location: here, connected_location: room, distance: "adjacent",
                                 travel_method: Location::Interior::WALKING, barrier: exit["barrier"] || "open")
    end

    protagonist = world["protagonist"] && person!(story, world["protagonist"], is_protagonist: true)
    records[protagonist.id] = protagonist if protagonist
    Array(world["cast"]).each { |person| records[person["id"]] = person!(story, person, location: here) }

    playthrough = Playthrough.create!(id: world["story_id"], story: story, character: protagonist, current_location: here)
    Array(world["lying"]).each { |item| records[item["id"]] = item!(playthrough, item, location: here) }
    Array(world["carried"]).each { |item| records[item["id"]] = item!(playthrough, item) }

    Built.new(playthrough: playthrough.reload, records: records)
  end

  def self.person!(story, person, **attributes)
    Character.create!(id: person["id"], story: story, race: story.universe.races.first,
                      fullname: person["fullname"], nickname: person["nickname"], age: 30, sex: Character.sexes.keys.first,
                      personality: "Steady.", appearance: "Plain.", likes: "Quiet.", dislikes: "Noise.",
                      fears: "Fire.", backstory: "A life.", **attributes)
  end

  def self.item!(playthrough, item, location: nil)
    Item.create!(id: item["id"], playthrough: playthrough, location: location, name: item["name"],
                 description: "A thing.", **item.slice(*ITEM_KEYS).symbolize_keys)
  end

  # HOW A LINE WAS READ, as plain data. A record is its explicit id; nil fields
  # are left out, so a key's absence and a null mean the same thing.
  def self.intent(intent)
    return nil if intent.nil?

    {
      "action" => intent.action.to_s,
      "destination" => intent.destination&.id, "speaker" => intent.speaker&.id, "item" => intent.item&.id,
      "at" => intent.at&.id, "also_named" => intent.also_named&.id, "unknown_action" => intent.unknown_action,
      "physical" => intent.physical&.token
    }.compact
  end

  # `note` is the grammar's whole help text on every reading that carries one,
  # and a case says "help" rather than repeating it: the lines are in the
  # portion's `help` constant.
  def self.reading(reading)
    return nil if reading.nil?

    {
      "intent" => intent(reading.intent), "refusal" => reading.refusal,
      "note" => (reading.note == Playthrough::Grammar::HELP ? "help" : reading.note),
      "understood" => reading.understood, "wound" => reading.wound&.then { |kind, n| [ kind.to_s, n ] },
      "attempt" => reading.attempt&.then { |ability, n| [ ability.to_s, n ] }, "resolved_by" => reading.resolved_by
    }.compact
  end

  def self.refusal(refusal)
    return nil if refusal.nil?

    { "kind" => refusal.kind.to_s, "fact" => refusal.fact, "offer" => refusal.offer, "reason" => refusal.reason,
      "text" => refusal.text, "game_over" => refusal.game_over? }.compact
  end
end
