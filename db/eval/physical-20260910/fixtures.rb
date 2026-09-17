require "factory_bot_rails"
FactoryBot.find_definitions if FactoryBot.factories.count.zero?

module PhysicalFixtures
  AT = Time.utc(2026, 1, 1, 12)

  def self.build(kind)
    universe = FactoryBot.create(:universe, :modern,
      physics: "Ordinary physics, with one magical exception: a healing draught restores wounds when drunk.",
      technology: "Hand tools, paper records and horse-drawn carts.",
      weapons: "Staves and ordinary knives.", religion: "People follow their household traditions.")
    story = FactoryBot.create(:story, universe: universe, title: "Tools at the market",
      summary: "Cal and Maren meet beside the gate to a courtyard.", start_time: AT)
    market = FactoryBot.create(:location, story: story, name: "Market",
      description: "A quiet square has a bench and a gate to the Courtyard.", lore: "Neighbors trade tools here.")
    courtyard = FactoryBot.create(:location, story: story, name: "Courtyard",
      description: "A sheltered yard beyond the market gate.", lore: "A shared courtyard.")
    player = FactoryBot.create(:character, :protagonist, story: story, fullname: "Cal", nickname: "Cal",
      age: 30, sex: "male", level: 10, strength: 12, dexterity: 12,
      appearance: "A traveler in a wool coat.", personality: "Cal chooses his actions during play.", backstory: "Cal lives by the market.")
    refusing = kind == "refuse-apple"
    npc = FactoryBot.create(:character, story: story, location: market, fullname: "Maren", nickname: "Maren",
      age: 32, sex: "female", level: 10, appearance: "A market worker in a blue coat.",
      personality: refusing ? "Maren does not trust Cal and firmly refuses any food he offers." : "Maren is hungry, friendly and glad to receive the apple she requested.",
      backstory: refusing ? "Cal previously gave Maren spoiled food. She decided never to accept food from him again." : "Maren asked Cal to bring a red apple for her lunch.",
      likes: "Honesty and reliable neighbors.", dislikes: "Deception.", fears: "Being harmed by someone she trusts.")
    templates = {}
    add = lambda do |name, use_kind = "ordinary", combustible = false|
      templates[name] = FactoryBot.create(:item, character: player, location: nil,
        name: name, description: "A #{name} in good condition.", use_kind: use_kind, combustible: combustible)
    end
    barrier, key = "open", nil
    case kind
    when "drink-healing-draught" then add.call("healing draught", "healing")
    when "offer-requested-apple", "refuse-apple" then add.call("red apple", "food")
    when "unlock-with-key"
      key = add.call("brass key", "key")
      barrier = "keyed"
    when "pry-jammed-gate"
      add.call("iron lever", "lever")
      barrier = "jammed"
    when "burn-paper"
      add.call("tinderbox", "firestarter")
      add.call("folded note", "ordinary", true)
    when "cannot-burn-stone"
      add.call("tinderbox", "firestarter")
      add.call("smooth stone")
    else raise ArgumentError, kind
    end
    door = FactoryBot.create(:location_connection, location: market, connected_location: courtyard,
      distance: "adjacent", barrier: barrier, key_template: key)
    back = FactoryBot.create(:location_connection, location: courtyard, connected_location: market,
      distance: "adjacent", barrier: barrier, key_template: key)
    scene = Scene.create!(story: story, location: market, characters: [ player, npc ],
      description: "You face Maren beside the courtyard gate.", story_timestamp: AT)
    game = Playthrough.create!(story: story, character: player, current_location: market, current_scene: scene)
    Playthrough::Turn.new(game).harm!(player, 10) if kind == "drink-healing-draught"
    { game: game, npc: npc, door: door, back: back, templates: templates }
  end

  def self.state(fixture)
    game, npc, door, back = fixture.values_at(:game, :npc, :door, :back)
    { hp: game.vitals_for(game.character).hp, location: game.reload.current_location.name,
      carried: game.carried.order(:id).pluck(:name), npc_items: game.items_held_by(npc).order(:id).pluck(:name),
      floor: game.items_lying_in(game.current_location).order(:id).pluck(:name),
      items: game.items.order(:id).map { |item| item.attributes.slice("name", "disposition", "use_kind") },
      door_open: door.open_for?(game), return_open: back.open_for?(game),
      templates: fixture.fetch(:templates).transform_values { |item| item.reload.attributes.slice("disposition", "character_id", "location_id") } }
  end
end
