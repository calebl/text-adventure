FactoryBot.define do
  # One verdict on one turn, with the turn's provenance frozen onto it. See
  # Playthrough::Feedback.
  #
  # The provenance columns are left NIL by default rather than filled in with a
  # plausible model name: they are a snapshot taken from real `chats` rows by
  # `.record`, and a factory that invents one would let a test assert that
  # freezing works against a value the factory wrote. Tests that care build the
  # conversations and go through `.record`; the `:frozen` trait is for the ones
  # that only need a row that looks recorded.
  factory :playthrough_feedback, class: "Playthrough::Feedback" do
    association :playthrough
    scene { association :scene, story: playthrough.story }
    verdict { "good" }

    trait :with_note do
      note { "the room read as somewhere, not as a list of nouns" }
    end

    trait :weak do
      verdict { "weak" }
    end

    trait :bad do
      verdict { "bad" }
    end

    trait :frozen do
      prose_model { "mistralai/mistral-medium-3.1" }
      prose_purpose { "narration" }
      prose_models { "mistralai/mistral-medium-3.1" }
      answering_models { "mistralai/mistral-medium-3.1" }
      input_tokens { 1_204 }
      output_tokens { 188 }
    end
  end
end
