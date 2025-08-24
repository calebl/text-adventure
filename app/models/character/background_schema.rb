class Character::BackgroundSchema < RubyLLM::Schema
  string :personality, description: "Personality of the character"
  string :appearance, description: "Appearance of the character"
  string :likes, description: "Likes of the character"
  string :dislikes, description: "Dislikes of the character"
  string :fears, description: "Fears of the character"
  string :backstory, description: "Backstory of the character"
end
