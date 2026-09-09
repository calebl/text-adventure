FactoryBot.define do
  factory :scene_arrival_context, class: "Scene::ArrivalContext" do
    association :playthrough, :started
    location { association :location, story: playthrough.story }

    initialize_with { new(playthrough, location: location) }
    skip_create
  end
end
