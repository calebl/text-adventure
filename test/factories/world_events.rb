FactoryBot.define do
  # SOMETHING THE WORLD DID TO ITSELF. A mechanic's row by default, which is the
  # only kind that existed before the arc and still the only kind a world with
  # no quests can have -- so every existing test reads exactly as it did.
  factory :world_event do
    association :world_mechanic
    story { world_mechanic.story }
    source { WorldEvent::WORLD_MECHANIC }
    occurred_at { story.start_time + 1.hour }
    summary { "Mournwell Lane now opens onto The Celestial Spire instead of Sovereign's Circle." }

    trait :with_locations do
      after(:create) do |event|
        event.locations = create_list(:location, 2, story: event.story)
      end
    end

    # A FAILED ARC, which is the other writer of this stream. It carries no
    # mechanic and it DOES carry a playthrough, because a failure is one game's
    # and the world's own events are everybody's -- see `WorldEvent`'s header.
    # A ROW ABOUT THE FUTURE -- the captain's Call 8. A world file writes one
    # (`schedule:`) and so does a quest outcome's ramification; both are the
    # same shape here, which is the whole point of one stream. `after_minutes`
    # is fixed rather than rolled, like every other number in these files.
    trait :scheduled do
      world_mechanic { nil }
      source { WorldEvent::SEEDED }
      story { association :story }
      occurred_at { story.start_time }
      scheduled_for { story.start_time + 1.hour }
      summary { "The tide comes over the quay and the low door goes under water." }
    end

    # AND ONE THE ENGINE HAS ALREADY REACHED THE HOUR OF. `fired_at` is at or
    # after `scheduled_for` -- the clock only moves when somebody plays, so the
    # gap is real and the column keeps it.
    trait :fired do
      scheduled
      fired_at { story.start_time + 70.minutes }
    end

    trait :a_failed_quest do
      world_mechanic { nil }
      source { WorldEvent::QUEST }
      story { association :story }
      playthrough { association :playthrough, story: story }
      summary { "The Long Way Down was left unfinished: it stopped at find where they are keeping him." }
    end
  end
end
