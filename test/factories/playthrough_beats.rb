FactoryBot.define do
  # ONE BEAT OF THE ARC, REACHED, IN ONE GAME. Written by `Playthrough::Arc` in
  # the app and by this only for a test that wants the ROW rather than the walk
  # that produced one.
  factory :playthrough_beat, class: "Playthrough::Beat" do
    association :playthrough
    quest_step { association :quest_step, quest: association(:quest, story: playthrough.story) }
    reached_at { playthrough.story_now }
  end

  # AND WHICH ENDING ONE GAME GOT.
  factory :playthrough_ending, class: "Playthrough::Ending" do
    association :playthrough
    quest_outcome { association :quest_outcome, quest: association(:quest, story: playthrough.story) }
    reached_at { playthrough.story_now }
  end
end
