# The whole character sheet, in one call.
#
# This was two calls: four identity fields, then six background fields. The
# split did not earn its round trip. The first pass produced 21 output tokens
# against a 2,497-token prompt, and two of its four fields -- `age` and `sex` --
# were already rolled by the generator and stated in that same prompt, so the
# model was being asked to decide something it had just been told. They are
# gone from here; the roll decides them now.
#
# Lengths are explicit on every field. The whole sheet is interpolated into
# Character#interaction_instructions, so an unbounded field is a context cost
# paid on every single turn of dialogue.
class Character::Schema < RubyLLM::Schema
  string :fullname, description: "Full name of the character. 2 to 4 words.", max_length: 60
  string :nickname, description: "A short nickname the character is known by. 1 or 2 words.", max_length: 30
  string :personality, description: "The character's temperament and how they treat others. 2 to 3 sentences.", max_length: 400
  string :appearance, description: "What the character looks like. 2 to 3 sentences.", max_length: 400
  string :likes, description: "What the character enjoys. A comma separated list of 3 to 5 items.", max_length: 200
  string :dislikes, description: "What the character cannot stand. A comma separated list of 3 to 5 items.", max_length: 200
  string :fears, description: "What the character is afraid of. A comma separated list of 2 to 4 items.", max_length: 200
  string :backstory, description: "The character's life before the story, their motivations and their goals. One paragraph, 4 to 6 sentences.", max_length: 1200
end
