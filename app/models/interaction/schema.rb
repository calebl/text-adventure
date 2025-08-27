class Interaction::Schema < RubyLLM::Schema
  string :pre_thought, description: "What you thought immediately in response to the user's action"
  string :pre_feeling, description: "what you felt immediately in response to the user's action"
  string :action, description: "What you did in response to the user's action?"
  string :action_type, description: "The type of action you took. This could be a physical action, a verbal action, or a mental action.", enum: [ "physical", "verbal", "mental" ]
  string :post_feeling, description: "What you felt after you took the action"
  string :post_thought, description: "What you thought after you took the action"
end
