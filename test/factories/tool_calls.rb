FactoryBot.define do
  factory :tool_call do
    association :message, factory: [ :message, :assistant ]
    sequence(:tool_call_id) { |n| "call_#{n}" }
    name { "get_scene_details" }
    arguments { { "scene_id" => 1 } }
  end
end
