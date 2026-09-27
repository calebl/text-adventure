FactoryBot.define do
  factory :relay_receipt do
    association :player
    route { "chat_completions" }
    model { BaseAgent::REMOTE_MODEL_IDS.first }
    status { "open" }
    reserved_usd { BigDecimal("0.01") }

    trait :settled do
      status { "closed" }
      cost_usd { BigDecimal("0.01") }
      cost_source { "usage" }
    end
  end
end
