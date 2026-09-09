FactoryBot.define do
  factory :playthrough_command, class: "Playthrough::Command" do
    association :playthrough
    sequence(:request_token) { |number| "submission-#{number}" }
    command { "/look" }
  end
end
