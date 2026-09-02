FactoryBot.define do
  # RubyLLM's model registry, introduced by the v1.7 acts_as migration. Chats
  # and messages now point at a row here instead of carrying a model string.
  factory :model do
    # The registry is unique on (provider, model_id), and both chats and
    # messages associate one. Reuse the existing row rather than colliding.
    initialize_with { Model.find_or_initialize_by(model_id: model_id, provider: provider) }

    # The app's default hosted model, `BaseAgent::REMOTE_MODEL_IDS.first`.
    model_id { "mistralai/mistral-medium-3.1" }
    provider { "openrouter" }
    name { "Mistral Medium 3.1" }
    family { "mistral" }
    context_window { 128_000 }
    max_output_tokens { 32_000 }
    capabilities { [ "structured_output" ] }
    modalities { { "input" => [ "text" ], "output" => [ "text" ] } }
    pricing { { "text_tokens" => { "standard" => { "input_per_million" => 0.3, "output_per_million" => 1.2 } } } }

    trait :ollama do
      model_id { "gemma3:12b" }
      provider { "ollama" }
      name { "Gemma 3 12B" }
      family { "gemma3" }
    end
  end
end
