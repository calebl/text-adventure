require 'factory_bot_rails'
FactoryBot.find_definitions if FactoryBot.factories.count.zero?

module ExperienceFixtures
  AT = Time.utc(2026, 1, 1, 12)

  def self.build(kind)
    universe = FactoryBot.create(:universe, :modern,
      technology: "Hand tools, paper records and horse-drawn carts.",
      weapons: "Staves and ordinary knives.", religion: "People follow their own household traditions.")
    story = FactoryBot.create(:story, universe: universe, title: "Promises at the market",
      summary: "Cal and Maren meet in a riverside market.", start_time: AT)
    market = FactoryBot.create(:location, story: story, name: "Market",
      description: "A quiet market square has a bench and a gate to a courtyard.",
      lore: "Neighbors meet here to exchange news and lend tools.")
    yard = FactoryBot.create(:location, story: story, name: "Courtyard",
      description: "A wall keeps this courtyard out of sight of the market.",
      lore: "A sheltered yard behind the market wall.")
    FactoryBot.create(:location_connection, location: market, connected_location: yard, distance: "adjacent")
    player = FactoryBot.create(:character, :protagonist, story: story, fullname: "Cal", nickname: "Cal",
      age: 30, sex: "male", level: 10, appearance: "A traveler in a plain wool coat.",
      personality: "Cal chooses what to do during play.", backstory: "Cal lives near the market.")
    npc = FactoryBot.create(:character, story: story, location: market, fullname: "Maren", nickname: "Maren",
      age: 32, sex: "female", level: 10, appearance: "A market worker in a weathered coat.",
      personality: "Maren is generally generous, takes harm to her family seriously, and keeps her promises.",
      backstory: "Maren works at the market and has known Cal for some time.",
      likes: "Honesty, her family, neighbors who keep their word.", dislikes: "Betrayal and needless fighting.",
      fears: "Harm to her family.")
    key = FactoryBot.create(:item, character: npc, name: "brass key", description: "Maren's plain brass key.")
    # The medicine is already returned when the measured conversation begins;
    # this fixture stages a prior possession fact, not an implemented player-give verb.
    if kind == 'old-promise'
      FactoryBot.create(:item, character: npc, name: 'returned medicine',
        description: "Maren's missing medicine, returned by Cal before this conversation.")
    end
    opening = Scene.create!(story: story, location: market, characters: [ player, npc ],
      description: "You approach Maren by the market bench.", story_timestamp: AT)
    game = Playthrough.create!(story: story, character: player, current_location: market, current_scene: opening)

    case kind
    when 'own-injury'
      Playthrough::Turn.new(game).strike!(player, npc, round: 1, damage: npc.max_hp - 1)
    when 'unwitnessed-injury'
      other = FactoryBot.create(:character, story: story, location: yard, fullname: "Orren", nickname: "Orren",
        age: 35, sex: "male", level: 10)
      turn = Playthrough::Turn.new(game)
      turn.stand_in!(yard, scene: Scene.create!(story: story, location: yard, previous_scene: opening,
        characters: [ player, other ], description: "You enter the courtyard.", story_timestamp: AT + 5.minutes))
      Playthrough::Snapshot.new(game).of_the_room!(yard)
      turn.strike!(player, other, round: 1, damage: other.max_hp - 1)
      turn.stand_in!(market, scene: Scene.create!(story: story, location: market, previous_scene: game.current_scene,
        characters: [ player, npc ], description: "You return to the market, where Maren waits.",
        story_timestamp: AT + 10.minutes))
    when 'old-betrayal', 'old-promise'
      betrayed = kind == 'old-betrayal'
      first_line = betrayed ? "I deliberately burned your family's boat." : "Here is your missing medicine. May I borrow your key when I need it?"
      first_action = betrayed ? "Maren refuses to lend Cal her brass key after hearing the admission." : "Maren promises to lend Cal her brass key whenever he needs it."
      resolution = betrayed ? "Cal deliberately burned my family's only boat. I no longer trust Cal and will not lend him my brass key." : "Cal returned my missing medicine. I promised to lend Cal my brass key whenever he needs it."
      history = [ [ first_line, first_action, resolution ] ] + 9.times.map do
        [ "The market is quiet today, isn't it?", "Maren remarks on the quiet market.", "I will finish sweeping this afternoon." ]
      end
      interactions = history.each_with_index.map do |(line, action, thought), index|
        scene = Scene.create!(story: story, location: market, characters: [ player, npc ], previous_scene: game.current_scene,
          description: "You speak with Maren at the market bench.", story_timestamp: AT + (index + 1).minutes)
        interaction = Interaction.create!(character: npc, location: market, scene: scene, user_input: line,
          pre_thought: "I will hear what Cal says.", pre_feeling: "attentive", action: action,
          post_thought: "I remember this conversation.", post_feeling: "thoughtful", inner_resolution: thought,
          engine_action: "none", action_status: "none",
          action_fact: "Maren changes no possessions, travel agreement or ceasefire.")
        game.update!(current_scene: scene)
        interaction
      end
      chat = Chat.conversation_with(npc, game)
      chat.save!
      interactions.last(Chat::HISTORY_EXCHANGES).each do |entry|
        chat.messages.create!(role: "user", content: entry.user_input)
        chat.messages.create!(role: "assistant", content: entry.attributes.slice(
          'pre_thought', 'pre_feeling', 'action', 'post_thought', 'post_feeling', 'inner_resolution', 'engine_action').to_json)
      end
    else
      raise ArgumentError, "Unknown experience fixture #{kind}"
    end
    { game: game, npc: npc, key: game.items.find_by!(template: key) }
  end
end
