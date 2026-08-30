class Character::BaseSchema < RubyLLM::Schema
  string :fullname, description: "Full name of the character. 2 to 4 words.", max_length: 60
  string :nickname, description: "A short nickname the character is known by. 1 or 2 words.", max_length: 30
  number :age, description: "Age in years", minimum: 18, maximum: 120
  string :sex, description: "Sex of the character", enum: [ "male", "female", "non-binary" ]
end
