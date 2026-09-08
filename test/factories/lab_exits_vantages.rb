FactoryBot.define do
  # A place typed in the exits lab for the model to name the ways out of. See
  # Lab::Exits::Vantage.
  #
  # NO DICE, in any of it. `test/factories/location_connections.rb` carries the
  # full diagnosis of the 1-in-35 flake that made that a rule, and a vantage is
  # the exact shape it warns about: every field here is read by a test that
  # asserts on the expectation it declares or the staging it produces, so a random
  # default would land the failure on whoever runs the suite next.
  #
  # THE WORLD IS ONE WITH A FILE -- `Eval::Realization::STORIES` is validated
  # against, and `The Quay House` is the sweep's own world and the smallest of the
  # five.
  #
  # NOTHING IS OFF THE BOOKS BY DEFAULT, and that is the honest default rather
  # than the useful one: it is the state a vantage is typed in, and it is the
  # state whose measurement is worthless (`Lab::Exits`'s header). The
  # `:with_places_off_the_books` trait is for the tests that want the surgery.
  #
  # AND NO EXPECTATION BY DEFAULT, because *don't care* is the ordinary answer and
  # a vantage that declared one would give every test that reads a rate a figure
  # it did not ask for.
  factory :lab_exits_vantage, class: "Lab::Exits::Vantage" do
    world { "The Quay House" }
    sequence(:name) { |n| "Harbour Steps #{n}" }
    teaser { "Wet stone steps down to the tide line, the harbour wall running off both ways." }

    # NEWLINE-SEPARATED, WHICH IS THE COLUMN'S CONTRACT: these are place names and
    # one of the corpus's worlds holds `Grenn's Boarding House, Room 3`, so a
    # comma-joined list would split one place into two the world does not have.
    trait :with_places_off_the_books do
      absent { "The Custom House\nThe Bonded Cellar" }
    end

    trait :reached_from_the_quay do
      reached_from { "The Quay" }
    end

    trait :dangerous do
      danger { "dangerous" }
    end

    # THE TWO SHAPES `Lab::Exits::Alignment` REFUSES A SET FOR NOT HOLDING BOTH
    # OF, which is the captain's Call 5 and the reason both traits exist.
    trait :expecting_no_insides do
      expects_inside_quantifier { "none of them" }
    end

    trait :expecting_a_building do
      expects_inside_quantifier { "at least one" }
    end

    trait :expecting_every_one do
      expects_inside_quantifier { "every one" }
    end

    trait :expecting_an_empty_neighbourhood do
      expects_population { "nobody" }
    end
  end
end
