# `Playthrough::SlashMenu`: the words the input box offers after a slash, and
# what each one can be followed by in the room the playthrough stands in.
module EngineVectors::SlashMenu
  SOURCES = [ "app/models/playthrough/slash_menu.rb", "app/models/playthrough/grammar.rb",
              "app/models/playthrough/classifier.rb", "app/models/playthrough/physical_action.rb" ].freeze
  NOTES = "Each case is SlashMenu#to_h for the room named `world` (a world in `worlds`): `verbs` is " \
          "[{word, hint}] in order, and `targets` is each word with the names it completes to, as " \
          "[word, names] pairs so the order is kept.".freeze

  WORLDS = %w[office office_tavern cascade refusal physical empty castless nowhere].freeze

  def self.constants_table
    { "worlds" => EngineVectors::Rooms::WORLDS.slice(*WORLDS).to_a, "hints" => EngineVectors.pairs(Playthrough::SlashMenu::HINTS),
      "physical_hints" => EngineVectors.pairs(Playthrough::SlashMenu::PHYSICAL_HINTS) }
  end

  def self.cases
    WORLDS.map do |world|
      EngineVectors.case_for(world, { "world" => world }, EngineVectors.rolled_back { menu(EngineVectors::Rooms.build!(world)) })
    end
  end

  def self.menu(room)
    menu = Playthrough::SlashMenu.new(room.playthrough, classifier: room.classifier).to_h
    { "verbs" => menu[:verbs].map { |verb| verb.transform_keys(&:to_s) }, "targets" => menu[:targets].to_a }
  end
end
