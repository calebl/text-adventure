FactoryBot.define do
  factory :playthrough_npc_state, class: "Playthrough::NpcState" do
    association :playthrough
    character { association :character, story: playthrough.story, age: 32, sex: "female" }
    location { character.location }
    following { false }
    ceasefire { false }
    peace_after_blow_id { 0 }
  end
end
