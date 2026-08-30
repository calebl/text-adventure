# The societal half of a universe. See Universe::PhysicalSchema for why this is
# a separate call.
class Universe::SocietalSchema < RubyLLM::Schema
  # Races are a structured list rather than prose: characters are assigned a
  # race from it, so the individual entries have to be addressable.
  array :races,
        description: "The peoples and species that inhabit this world.",
        min_items: 3,
        max_items: 6 do
    object do
      string :name, description: "The name of this people, as they are known in this world. 1 to 3 words.", max_length: 40
      string :description, description: "What sets this people apart -- appearance, temperament, standing in the world. 2 to 3 sentences.", max_length: 500
    end
  end

  string :civilizations, description: "The major civilizations, factions and settlements. One paragraph, 3 to 5 sentences.", max_length: 900
  string :history, description: "The defining historical events that shaped the present. One paragraph, 3 to 5 sentences.", max_length: 900
  string :economics, description: "How wealth, trade and scarcity work here. One paragraph, 3 to 5 sentences.", max_length: 900
  string :politics, description: "Who holds power, and the tensions between them. One paragraph, 3 to 5 sentences.", max_length: 900
  string :religion, description: "The beliefs, deities and rituals of this world. One paragraph, 3 to 5 sentences.", max_length: 900
end
