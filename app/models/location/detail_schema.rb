# Realizing a stub: what the player reads on arrival, plus what the place is.
# Lengths are explicit on every field. Without them a strong model answered a
# one-word field with 2,382 characters of prose, and both of these are
# interpolated into every scene generated here.
#
# `description` DESCRIBES THE PLACE, NOT ITS NEIGHBOURS, and that clause is
# load-bearing rather than stylistic. A description is written once and never
# regenerated -- that is the whole persistence model -- so a sentence naming
# what stands across the way becomes permanently wrong the moment the world
# graph moves it. The Lunar Cartographer already has one: Room 3's description
# was generated before `WorldMechanic` existed and puts a clothier's shop
# outside the window. Asking for the place itself is what stops the next one.
class Location::DetailSchema < RubyLLM::Schema
  string :description, description: "What the player sees, hears and smells standing in this place right now. Describe THIS place only -- not what neighbours it, not what is visible out of a window or across the way, because the world around it can move. Second person. One paragraph, 4 to 6 sentences.", max_length: 1200
  string :lore, description: "What this place is, who made it and what happened here. Written for the game engine rather than the player. One paragraph, 3 to 5 sentences.", max_length: 900
end
