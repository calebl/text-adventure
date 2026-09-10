# Study fixtures reconstructed from arrival-after.json. Fixed reserved IDs keep
# engine picks stable; transactions roll back on failure as well as success.
# Openings stage generated-world records, including the population roll, without
# buying world generation. The protagonist is never omitted to force cast_list's
# unreachable empty-array fallback: an empty opening means no OTHER people.
class Eval::Arrival::Stage
  attr_reader :kase, :story, :room, :origin, :player, :resident, :game, :generator

  def self.open(kase)
    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      stage = new(kase)
      stage.build!
      result = yield stage
      raise ActiveRecord::Rollback
    end
    result
  end

  def initialize(kase) = @kase = kase

  def build!
    universe = Universe.new(physics: "Standard physics with magical exceptions allowing for spells and enchantments",
      technology: "Medieval level with magical enhancements", weapons: "Swords and bows",
      civilizations: "Harbour towns", geographies: "A flooded coast", history: "An old harbour",
      economics: "Trade", politics: "Councils", religion: "Local traditions")
    universe.races.build(name: "Human", description: "People of the harbour.")
    universe.races.build(name: "Elf", description: "Elves of the harbour.")
    universe.save!
    @story = Story.create!(id: -920001, universe: universe, title: "The Drowned Ledger", genre: "mystery",
      preface: "An account is missing.", summary: "You are tracing a missing ship's account through the flooded counting house.",
      start_time: Time.utc(2026, 9, 9, 12))
    @room = story.locations.create!(id: -920002, name: kase.fetch("name", "Counting House"), detail_level: "realized",
      description: "Maren Vosk waits beside a brass key on the desk. Water laps at the lowest stair.",
      lore: "This counting house kept the harbour's manifests.")
    @player = person(920001, "Iri Calder", "Iri", protagonist: true)
    if kase["opening"]
      count = Location::Population.count_for(room)
      count.times { |index| person(920002 + index, index.zero? ? "Maren Vosk" : "Clerk #{index}", "Clerk#{index}") }
      room.update!(description: "Water laps at the lowest stair beside a desk.") if count.zero?
      @generator = Scene::Generator.new(room, opening: true)
      return
    end
    @origin = story.locations.create!(id: -920001, name: "Market", detail_level: "realized",
      description: "A quiet market.", lore: "The harbour market.")
    @resident = person(920002, "Maren Vosk", "Maren")
    edge = LocationConnection.create!(location: origin, connected_location: room,
      distance: "adjacent", travel_method: "walking", time_to_travel: 1)
    unless kase["state"] == "no_exits"
      LocationConnection.create!(location: room, connected_location: origin,
        distance: "adjacent", travel_method: "walking", time_to_travel: 1)
    end
    if kase["state"] == "returning"
      Scene.create!(story: story, location: room, story_timestamp: story.start_time,
        description: "You stand beside the desk.", summary: "Iri visits the counting house.")
    end
    previous = Scene.create!(story: story, location: origin, story_timestamp: story.start_time + 2.hours,
      description: "You leave the market for the counting house.", summary: "You leave the market for the counting house.")
    @game = Playthrough.create!(id: -920001, story: story, character: player, current_location: origin, current_scene: previous)
    Item.create!(name: "brass key", description: "A brass key.", location: room, properties: "{}")
    Playthrough::Snapshot.new(game).of_the_room!(room)
    prepare_state!(edge)
    @generator = Scene::Generator.new(room, previous_scene: previous, playthrough: game)
  end

  def person(id, fullname, nickname, protagonist: false)
    story.characters.create!(id: id, fullname: fullname, nickname: nickname, age: 30, sex: "female",
      race: story.universe.races.find_by!(name: protagonist ? "Human" : "Elf"), location: protagonist ? nil : room, is_protagonist: protagonist,
      backstory: "A harbour resident.", personality: "Observant", appearance: "Practical clothes",
      likes: "Order", dislikes: "Waste", fears: "Flooding", level: 3, hit_die: 8,
      strength: 12, dexterity: 10, will: 14)
  end

  def prepare_state!(edge)
    case kase["state"]
    when "dead"
      game.vitals.find_by!(character: resident).update!(hp_current: 0, provoked_at: story.start_time)
    when "wounded"
      game.vitals.find_by!(character: resident).update!(hp_current: 3)
    when "carried", "inventory"
      game.items.find_by!(name: "brass key").update!(location: nil, character: nil)
      if kase["state"] == "inventory"
        Item.create!(playthrough: game, location: room, name: "blue ledger", description: "A blue ledger.", properties: "{}")
      end
    when "crossing", "toll"
      game.vitals.find_by!(character: player).update!(hp_current: 15)
      edge.update!(hazard: "undertow", hazard_die: 4) if kase["state"] == "toll"
      room.update!(hazard: "flooded", hazard_die: 4) if kase["state"] == "crossing"
      game.tolls.create!(character: player, location: room,
        location_connection: kase["state"] == "toll" ? edge : nil,
        hazard: kase["state"] == "toll" ? "undertow" : "flooded", damage: 3, hp_after: 15, saved: false,
        story_timestamp: generator_time, sequence: -1)
    end
  end

  def generator_time = story.start_time + 2.hours + 1.minute

  def request
    at = generator.story_timestamp
    { "system" => generator.system_prompt,
      "user" => generator.arrival_prompt(room.last_protagonist_visit.present?, room.time_since_last_visit(at), generator.characters_present),
      "schema" => JSON.parse(JSON.generate(Scene::Schema.new.to_json_schema)), "history" => [] }
  end

  def facts
    context = game && Scene::ArrivalContext.new(game, location: room)
    floor = context ? context.floor.map(&:name) : []
    { "room" => room.name, "moved" => !kase["opening"], "protagonist" => [ player.fullname, player.nickname ],
      "places" => story.locations.pluck(:name).index_with(&:itself), "exits" => room.exits.pluck(:name),
      "present" => (generator.characters_present - [ player ]).map(&:fullname),
      "floor" => floor, "carried" => context ? context.carried.map(&:name) : [],
      "elsewhere" => floor.map { |name| { "name" => name, "whereabouts" => room.name, "here" => true } },
      "current" => context&.facts, "required" => kase.fetch("facts"), "returning" => kase["state"] == "returning" }
  end
end
