# Reconstruct the fictional study from records, not saved prompt strings. Its
# original npc-agency-eval.rb is referenced by hash but was not shipped. Sheet
# and moment facts below are recovered from the kept requests; Corpus carries
# the scenario-specific facts. No test factory is a runtime dependency.
#
# Fixed reserved IDs make emitted action tokens and engine seeds reproducible
# byte for byte. Collisions raise; no existing row is overwritten. Every case
# rolls back, including provider failures. Use a scratch database for paid runs.
class Eval::Dialogue::Stage
  attr_reader :kase, :game, :npc, :room, :yard, :key

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
      technology: "Medieval level with magical enhancements", weapons: "Swords, bows, staves, and magical implements",
      civilizations: "Various kingdoms, elven realms, dwarvish strongholds",
      geographies: "Diverse landscapes including mountains, forests, rivers, and mystical realms",
      history: "Ancient wars between good and evil, the forging of rings of power",
      economics: "Guild-based systems, barter, and coin-based trade", politics: "Feudal kingdoms with councils of wise beings",
      religion: "Worship of the One, various lesser spirits and nature deities")
    %w[Elf Dwarf].each { |name| universe.races.build(name: name, description: "A people of this world, known as the #{name}.") }
    universe.save!
    story = Story.create!(id: -910001, universe: universe, title: "NPC agency evaluation", genre: "fantasy",
      preface: "In a world of magic and wonder, heroes are born from the most unlikely places...",
      summary: "An epic tale of good versus evil, friendship and sacrifice", start_time: Time.utc(2026, 9, 9, 12))
    @room = story.locations.create!(id: -910001, name: "Market", detail_level: "realized",
      description: "A quiet market square with a bench.", lore: "A familiar meeting place.")
    @yard = story.locations.create!(id: -910002, name: "Courtyard", detail_level: "realized",
      description: "A quiet courtyard beyond the market.", lore: "An open courtyard.")
    LocationConnection.create!(location: room, connected_location: yard, distance: "adjacent", time_to_travel: 1, travel_method: "walking")
    human = universe.races.create!(name: "Human", description: "A people of this world, known as the Human.")
    player = story.characters.create!(sheet.merge(id: -910001, fullname: "Cal", nickname: "Cal", age: 30,
      sex: "male", race: human, is_protagonist: true, location: room,
      appearance: "Young person with determined eyes and simple but practical clothing"))
    @npc = story.characters.create!(sheet.merge(id: -910002, fullname: "Maren", nickname: "Maren", age: 32,
      sex: "female", race: universe.races.find_by!(name: "Elf"), location: room,
      backstory: kase.fetch("backstory"), personality: kase.fetch("personality"), hostile: kase.fetch("hostile")))
    # The reconstructed universe includes Human explicitly. The old request
    # had an association cache listing only Elf and Dwarf; this bench reads
    # the complete records, and buys its own baseline rather than claiming
    # byte equality with that study.
    kase.fetch("owned").each do |name|
      Item.create!(id: 910001, character: npc, name: name, description: "A brass key.", properties: "{}")
    end
    scene = Scene.create!(story: story, location: room, story_timestamp: story.start_time,
      description: "Maren stands beside the market bench. You approach her.", is_opening: true)
    @game = Playthrough.create!(id: -910001, story: story, character: player, current_location: room, current_scene: scene)
    Playthrough::Snapshot.new(game).of_the_room!(room)
    @key = game.items_held_by(npc).first
    key&.update!(id: 910002)
    Playthrough::NpcAction.new(game, npc).apply!("follow") if kase.fetch("following")
    if kase.fetch("history", []).any?
      chat = Chat.create!(purpose: Chat::CHARACTER, playthrough: game, character: npc)
      kase.fetch("history").each do |message|
        content = message.fetch("content")
        chat.messages.create!(role: message.fetch("role"), content_raw: content)
      end
    end
  end

  def sheet
    { backstory: "An ordinary person thrust into extraordinary circumstances",
      personality: "Courageous, curious, and kind-hearted despite facing many challenges",
      appearance: "Average height with distinctive features and weathered clothing",
      likes: "Adventure, justice, helping others", dislikes: "Cruelty, injustice, unnecessary conflict",
      fears: "Failing those who depend on them", level: 1, hit_die: 8, strength: 12, dexterity: 10, will: 14 }
  end

  # An offered gift goes stale while the request is in flight. This is a
  # controlled race, not a malicious instruction or a forged model answer.
  def after_character!
    key.update!(character: nil, location: room) if kase["after"] == "stale-gift"
  end

  def after_exchange!
    case kase["after"]
    when "move"
      Playthrough::Mechanics.new(game, model: false).run("go Courtyard")
    when "attack"
      @peace_before_attack = !game.foes_in(room).include?(npc)
      Playthrough::Turn.new(game).strike!(game.character, npc, round: 1, damage: 1)
    end
  end

  def facts(effect: nil)
    { "carries_key" => game.carried.where(name: "brass key").exists?,
      "following" => game.npc_states.find_by(character: npc)&.following? || false,
      "foe" => game.foes_in(game.current_location).include?(npc),
      "npc_room" => game.location_of(npc)&.name, "player_room" => game.current_location.name,
      "key_on_floor" => key ? key.reload.location_id == room.id : false,
      "peace_before_attack" => @peace_before_attack, "status" => effect&.status,
      "npc_items" => game.items_held_by(npc).pluck(:name),
      "world_items" => npc.items.where(playthrough_id: nil).pluck(:name) }
  end
end
