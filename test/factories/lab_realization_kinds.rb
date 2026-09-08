FactoryBot.define do
  # A kind of place typed in the realization lab. See Lab::Realization::Kind.
  #
  # NO DICE, in either half. `test/factories/location_connections.rb` carries the
  # full diagnosis of the 1-in-35 flake that made that a rule, and a kind is the
  # exact shape it warns about: every field here is read by a test that asserts
  # on the picks it allows or the staging it produces, so a random default would
  # land the failure on whoever runs the suite next.
  #
  # THE WORLD IS ONE WITH A FILE. `Eval::Realization::STORIES` is validated
  # against, and `The Quay House` is the sweep's own world -- the smallest of the
  # five and the only one with a building already in it.
  #
  # NO EXPECTATION BY DEFAULT, because *don't care* is the ordinary answer and a
  # kind that declared one would give every test that reads a hit rate a figure
  # it did not ask for. The `:expecting` traits are for the ones that want one.
  factory :lab_realization_kind, class: "Lab::Realization::Kind" do
    world { "The Quay House" }
    sequence(:name) { |n| "The Fishmonger's Warehouse #{n}" }
    teaser { "A flooded warehouse on the river, its doors swollen shut." }

    # A BUILDING: the band is what makes `Location#place?` true once the engine
    # has rolled a footprint inside it, which is what sends the detail call
    # `Location::PlaceSchema` and its five parameter picks.
    trait :a_building do
      inside { "a few rooms" }
    end

    trait :dangerous do
      danger { "dangerous" }
    end

    trait :crowded do
      population { "a crowd" }
    end

    # ONE EXPECTATION ON A PICK ONLY A BUILDING IS ASKED, and one on a pick only
    # a room is asked -- the two halves of `Kind#answerable?`.
    trait :expecting_a_cellar do
      expects_storeys_below { "a cellar, two levels down, deep" }
    end

    trait :expecting_no_insides do
      expects_inside { Location::Parameters::NO_INSIDE }
    end
  end
end
