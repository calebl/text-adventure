
class Character::BaseSchema < RubyLLM::Schema
  string :fullname, description: "Full name of the character"
  string :nickname, description: "Nickname of the character"
  number :age, description: "Age in years", minimum: 18, maximum: 120
  string :sex, description: "Sex of the character", enum: [ "male", "female", "non-binary" ]
  string :race, description: "Race of the character"
end
