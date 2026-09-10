FactoryBot.define do
  factory :playthrough_npc_action, class: "Playthrough::NpcAction" do
    association :playthrough, :started
    character do
      association :character, story: playthrough.story, location: playthrough.current_location,
                              age: 32, sex: "female"
    end

    initialize_with { new(playthrough, character) }
    skip_create
  end
end
