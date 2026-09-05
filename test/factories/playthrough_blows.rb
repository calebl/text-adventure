FactoryBot.define do
  # ONE BLOW LANDED IN ONE GAME. Every column is a fact the engine decided, so a
  # factory-made row is for a test that wants the RECORD rather than the fight
  # that produced it -- a test about a fight builds one through
  # `Playthrough::Turn#strike!`, which is the only writer in the app.
  #
  # `scene` is nil, which is what makes a row an OPEN blow: the fight it belongs
  # to has not been closed. `:closed` is the other half.
  factory :playthrough_blow, class: "Playthrough::Blow" do
    association :playthrough
    location { playthrough.current_location || association(:location, story: playthrough.story) }
    attacker { association :character, story: playthrough.story }
    target { playthrough.character || association(:character, story: playthrough.story) }
    damage { 3 }
    hp_after { 5 }
    round { 1 }
    # `add_attribute` because `sequence` is FactoryBot's own DSL word and the
    # column is `Roll`'s -- which roll of this game the blow was. The column
    # keeps the dice vocabulary; the factory says so out loud.
    add_attribute(:sequence) { 4 }
    story_timestamp { playthrough.story_now }

    trait :killing do
      hp_after { 0 }
    end

    trait :closed do
      scene { association :scene, story: playthrough.story, location: location }
    end
  end
end
