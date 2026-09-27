FactoryBot.define do
  factory :playthrough_turn_event, class: "Playthrough::TurnEvent" do
    association :command, factory: :playthrough_command
    sequence(:sequence) { |number| number }
    kind { "prose" }
    data { { "turn" => "1", "text" => "The door gives." } }
  end
end
