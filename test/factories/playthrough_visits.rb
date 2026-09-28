FactoryBot.define do
  # A ROOM ONE GAME HAS STOOD IN. The room is in the playthrough's own story,
  # because a visit to another world's room is one the model refuses.
  factory :playthrough_visit, class: "Playthrough::Visit" do
    association :playthrough
    location { association :location, story: playthrough.story }
  end
end
