class Story::Schema < RubyLLM::Schema
  string :title, description: "The title of the story. 2 to 5 words, no subtitle.", max_length: 80
  string :genre, description: "The genre of the story, e.g. 'gothic horror', 'space western'. 1 to 4 words.", max_length: 60
  string :preface, description: "The opening text shown to the player before they take their first action. Second person, addressed as 'you'. One or two paragraphs, 5 to 9 sentences.", max_length: 1800
  string :summary, description: "A summary of the situation the story opens on, written for the game engine rather than the player. One paragraph, 3 to 5 sentences.", max_length: 900
end
