# The ways out of a location. Each exit becomes a stub Location plus a
# LocationConnection, so the entries have to be individually addressable rather
# than a paragraph of prose -- the player has to be able to walk into one.
class Location::ExitsSchema < RubyLLM::Schema
  array :exits,
        description: "The places a player can reach directly from here.",
        min_items: 2,
        max_items: 4 do
    object do
      string :name, description: "The name of the place this exit leads to, as a player would refer to it. 1 to 4 words, no article.", max_length: 60
      string :teaser, description: "A one-line glimpse of what lies that way, enough to make the player choose it. Exactly one sentence.", max_length: 160
      string :distance, description: "How far it is, with a unit. A few words.", max_length: 60
      string :time_to_travel, description: "How long the journey takes, with a unit. A few words.", max_length: 60
      string :travel_method, description: "How the player gets there, e.g. 'walking', 'climbing a rope ladder'. 1 to 5 words.", max_length: 60
    end
  end
end
