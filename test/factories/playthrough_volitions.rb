FactoryBot.define do
  # WHAT ONE PERSON DECIDED TO DO ON ONE TURN OF ONE GAME. Every column is a
  # fact the engine decided, so a factory-made row is for a test that wants the
  # RECORD rather than the turn that produced one -- a test about somebody
  # walking out builds it through `Playthrough::Volition`, which is the only
  # thing in the app that writes here.
  #
  # `scene` is nil, which is what makes a row UNTOLD: no paragraph has carried
  # it yet, and `Playthrough::Moment` states exactly those. `:told` is the
  # other half. The default is an APPLIED walk, because that is the row the
  # narrator reader and the sweep both care about; `:waited` and `:rejected`
  # are the two that moved nothing.
  #
  # NOTHING HERE IS ROLLED. `chosen` names no id, so the default row is the one
  # token that needs no other record to exist.
  factory :playthrough_volition, class: "Playthrough::Volition::Record" do
    association :playthrough
    character { association :character, story: playthrough.story, age: 41, sex: "female" }
    location { playthrough.current_location || association(:location, story: playthrough.story) }
    chosen { "stop_following" }
    status { "applied" }
    serves { "conscious" }
    fact { "#{character.fullname} stopped accompanying the player and remains in #{location.name}." }
    round { 1 }

    trait :waited do
      chosen { Playthrough::Volition::WAIT }
      status { "none" }
      serves { "none" }
      fact { "#{character.fullname} stayed in #{location.name} and changed nothing." }
    end

    trait :rejected do
      status { "rejected" }
      serves { "none" }
      fact { "#{character.fullname} was going to act and could not: the act is no longer available. Nothing moved." }
    end

    trait :told do
      scene { association :scene, story: playthrough.story, location: location }
    end
  end
end
