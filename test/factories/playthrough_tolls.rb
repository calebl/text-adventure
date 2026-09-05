FactoryBot.define do
  # WHAT ONE HAZARD TOOK OFF ONE BODY IN ONE GAME. Every column is a fact the
  # engine decided, so a factory-made row is for a test that wants the RECORD
  # rather than the walk that produced one -- a test about a hazard being paid
  # builds it through `Playthrough::Hazards`, which is the only thing in the app
  # that writes here.
  #
  # `scene` is nil, which is what makes a row UNTOLD: no paragraph has carried
  # it yet, and `Playthrough::Moment` states exactly those. `:told` is the other
  # half. `location_connection` is nil, which is what makes it a ROOM's hazard;
  # `:on_a_doorway` is the other half.
  factory :playthrough_toll, class: "Playthrough::Toll" do
    association :playthrough
    character { playthrough.character || association(:character, story: playthrough.story) }
    location { playthrough.current_location || association(:location, story: playthrough.story) }
    hazard { "flooded" }
    saved { false }
    damage { 3 }
    hp_after { 5 }
    # `add_attribute` because `sequence` is FactoryBot's own DSL word and the
    # column is `Roll`'s. It counts DOWN -- see `Playthrough::Toll.next_sequence`
    # for why the tolls have the negative half of the space to themselves.
    add_attribute(:sequence) { -1 }
    story_timestamp { playthrough.story_now }

    trait :saved do
      saved { true }
      damage { 0 }
    end

    trait :killing do
      hp_after { 0 }
    end

    trait :told do
      scene { association :scene, story: playthrough.story, location: location }
    end

    trait :on_a_doorway do
      hazard { "drop" }
      location_connection do
        association :location_connection,
                    location: association(:location, story: playthrough.story),
                    connected_location: location
      end
    end
  end
end
