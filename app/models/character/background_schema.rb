# Lengths are explicit on every field. The whole character sheet is
# interpolated into each interaction prompt by Character#interaction_instructions,
# so an unbounded field costs context on every single turn of dialogue.
class Character::BackgroundSchema < RubyLLM::Schema
  string :personality, description: "The character's temperament and how they treat others. 2 to 3 sentences.", max_length: 400
  string :appearance, description: "What the character looks like. 2 to 3 sentences.", max_length: 400
  string :likes, description: "What the character enjoys. A comma separated list of 3 to 5 items.", max_length: 200
  string :dislikes, description: "What the character cannot stand. A comma separated list of 3 to 5 items.", max_length: 200
  string :fears, description: "What the character is afraid of. A comma separated list of 2 to 4 items.", max_length: 200
  string :backstory, description: "The character's life before the story, their motivations and their goals. One paragraph, 4 to 6 sentences.", max_length: 1200
end
