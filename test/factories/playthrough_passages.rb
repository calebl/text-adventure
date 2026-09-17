FactoryBot.define do
  factory :playthrough_passage, class: "Playthrough::Passage" do
    association :playthrough
    location_connection do
      association(:location_connection, location: playthrough.current_location,
                                        connected_location: association(:location, story: playthrough.story))
    end
    means { "force" }
    opened_at { Time.utc(2026, 1, 1, 12) }
  end
end
