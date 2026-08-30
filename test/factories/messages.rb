FactoryBot.define do
  factory :message do
    association :chat
    role { "user" }
    content { "What lies beyond the gate?" }
    model_id { "minimax/minimax-m3" }

    trait :assistant do
      role { "assistant" }
      content { "A road, and then the sea." }
      input_tokens { 42 }
      output_tokens { 17 }
    end

    trait :system do
      role { "system" }
      content { "You are the narrator." }
    end
  end
end
