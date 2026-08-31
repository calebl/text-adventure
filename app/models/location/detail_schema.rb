# Realizing a stub: what the player reads on arrival, plus what the place is.
# Lengths are explicit on every field. Without them a strong model answered a
# one-word field with 2,382 characters of prose, and both of these are
# interpolated into every scene generated here.
class Location::DetailSchema < RubyLLM::Schema
  string :description, description: "What the player sees, hears and smells standing in this place right now. Second person. One paragraph, 4 to 6 sentences.", max_length: 1200
  string :lore, description: "What this place is, who made it and what happened here. Written for the game engine rather than the player. One paragraph, 3 to 5 sentences.", max_length: 900
end
