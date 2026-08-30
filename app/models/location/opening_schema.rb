# The place the story opens in. Only enough to create the stub -- the
# description and lore follow from Location::DetailSchema on the same
# conversation, so the model is not asked for twenty fields at once.
class Location::OpeningSchema < RubyLLM::Schema
  string :name, description: "The name of the place the story opens in, as a player would refer to it. 1 to 4 words, no article.", max_length: 60
  string :teaser, description: "A one-line glimpse of the place, the kind a narrator gives before you walk in. Exactly one sentence.", max_length: 160
end
