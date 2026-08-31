# Arriving somewhere: the prose the player reads on the way in, plus the one
# line the rest of the game remembers it by.
#
# Both fields fill columns on `scenes`, and both are bounded. The description
# is deliberately shorter than `Location::DetailSchema#description` (1,200):
# the room's own description is already in the prompt and already in front of
# the player, so an arrival that runs as long is describing the room a second
# time rather than describing walking into it.
#
# The summary is not a spare field. Nothing has ever written `scenes.summary`,
# and long playthroughs will have to be summarised to stay inside the context
# window (ROADMAP, "Persistence and history"). Writing it here costs ~30 output
# tokens on a call that has the whole moment in front of it; a later pass over
# old scenes would be a fresh round trip with less context than this one has.
class Scene::Schema < RubyLLM::Schema
  string :description,
         description: "What the player experiences as they arrive here, right now. Second person, present tense. One paragraph, 3 to 5 sentences.",
         max_length: 900
  string :summary,
         description: "What happened in this moment, for the game engine rather than the player. Third person. One sentence.",
         max_length: 200
end
