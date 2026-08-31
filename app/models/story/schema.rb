# The opening of a text adventure, plus the name of the room it opens in.
#
# The room is here rather than in a call of its own on purpose. The preface
# already describes the place the player is standing; asking a second model call
# to name "the room the preface above describes -- do not invent a different
# one" spends 2,276 input tokens and a round trip to produce 39 tokens that the
# call which wrote the preface could have produced for free. One call cannot
# disagree with itself.
class Story::Schema < RubyLLM::Schema
  string :title, description: "The title of the story. 2 to 5 words, no subtitle.", max_length: 80
  string :genre, description: "The genre of the story, e.g. 'gothic horror', 'space western'. 1 to 4 words.", max_length: 60
  string :preface, description: "The opening text shown to the player before they take their first action. Second person, addressed as 'you'. One or two paragraphs, 5 to 9 sentences.", max_length: 1800
  string :summary, description: "A summary of the situation the story opens on, written for the game engine rather than the player. One paragraph, 3 to 5 sentences.", max_length: 900
  string :opening_location_name, description: "The name of the place the preface opens in, as a player would refer to it. 1 to 4 words, no article.", max_length: 60
  string :opening_location_teaser, description: "A one-line glimpse of that place, the kind a narrator gives before you walk in. Exactly one sentence.", max_length: 160
end
