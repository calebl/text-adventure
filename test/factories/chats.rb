FactoryBot.define do
  factory :chat do
    # Associating the registry row directly keeps the factory offline. Assigning
    # `model_id` as a string instead makes RubyLLM resolve it through the
    # provider, which needs an API key -- see ChatTest.
    association :model
  end
end
