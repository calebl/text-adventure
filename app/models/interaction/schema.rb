# One character's reaction to what the player said or did. InteractionAgent
# interpolates all five fields into the narrator prompt by string key, so the
# names here are a hard contract with InteractionAgent#narrator_instructions.
#
# Lengths are explicit on every field, and they matter more here than anywhere
# else in the app: this is the only schema that runs once per turn of dialogue,
# so an unbounded field has no ceiling on what a conversation costs. It is also
# the schema that used to have no bounds at all -- the same omission that once
# had a strong model answer "Race of the character" with 2,382 characters.
class Interaction::Schema < RubyLLM::Schema
  string :pre_thought, description: "What you thought immediately in response to the user's action. One sentence.", max_length: 200
  string :pre_feeling, description: "What you felt immediately in response to the user's action. Two or three words, comma separated.", max_length: 60
  string :action, description: "What you did in response to the user's action. One or two sentences.", max_length: 300
  string :post_feeling, description: "What you felt after you took the action. Two or three words, comma separated.", max_length: 60
  string :post_thought, description: "What you thought after you took the action. One sentence.", max_length: 200
end
