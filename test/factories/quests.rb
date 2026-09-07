FactoryBot.define do
  # A WORLD'S OWN ARC. The main arc by default -- no parent -- because that is
  # what a story has one of and what almost every test means. A side quest asks
  # for one by naming its `parent_quest`.
  #
  # NO DICE ANYWHERE, which is `test/factories/location_connections.rb`'s rule:
  # every value here is fixed, so a test that reads one is reading what it wrote
  # rather than what a die gave it.
  factory :quest do
    association :story
    sequence(:title) { |n| "The Long Way Down #{n}" }
    premise { "Somebody was taken below, and getting them back is the whole of it." }
    status { "open" }
    contributes { true }
    origin { "seeded" }

    # THE ARC AS `Quest::Generator` WOULD HAVE LEFT IT: written at world
    # creation, with nothing bound, which is the state the doctor treats
    # differently (`unbound_quest_steps`).
    trait :generated do
      origin { "generated" }
    end

    # AN AUTHORED TRAGEDY -- a seed file saying on purpose that this world does
    # not let you finish. `Playthrough::Arc` evaluates nothing for one.
    trait :doomed do
      status { "doomed" }
    end

    # THE ORDINARY SHAPE A TEST WANTS: one beat to reach and one ending to reach
    # it into, so reaching the beat concludes the game.
    trait :with_an_ending do
      after(:create) do |quest|
        create(:quest_outcome, quest: quest, name: "rescued", is_default: true)
      end
    end
  end

  # ONE BEAT. `time_passed` by default, because it is the one trigger that needs
  # no row in the world at all -- so a factory-made step is complete on its own
  # and a test that wants a target says which.
  factory :quest_step, class: "Quest::Step" do
    association :quest
    sequence(:position) { |n| n }
    summary { "Find where they are keeping him." }
    trigger_kind { "time_passed" }
    minutes { 40 }

    trait :reach_location do
      trigger_kind { "reach_location" }
      minutes { nil }
      target_name { "Blackfang Warren" }
    end

    trait :speak_to do
      trigger_kind { "speak_to" }
      minutes { nil }
      target_name { "Prince Aurel Durn" }
    end

    trait :hold_item do
      trigger_kind { "hold_item" }
      minutes { nil }
      target_name { "the cell key" }
    end
  end

  # ONE ENDING. Not the default unless a test says so: `default: true` is the
  # world saying which sentence it was built toward, and a factory that assumed
  # it would make every second outcome a second default.
  factory :quest_outcome, class: "Quest::Outcome" do
    association :quest
    sequence(:name) { |n| "ending-#{n}" }
    summary { "The prince is carried back through the iron gate alive." }
    is_default { false }

    trait :default do
      is_default { true }
    end
  end
end
