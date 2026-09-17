FactoryBot.define do
  factory :playthrough_physical_action, class: "Playthrough::PhysicalAction" do
    association :playthrough
    initialize_with { new(playthrough) }
    skip_create
  end
end
