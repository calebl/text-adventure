FactoryBot.define do
  # What he says about one place a vantage names. See Lab::Exits::Judgement.
  #
  # NO DICE, and no name that varies: the whole point of this row is that its
  # identity is a place, so a sequenced name would make every test that pairs a
  # judgement with a drawn place a lottery. `The Salt Chandlery` is the place both
  # sample traits open, which is what lets the two factories meet.
  #
  # `name_key` IS NEVER SET HERE. `Lab::Exits::Judgement` derives it from the name
  # in a `before_validation`, and a factory that set it could set one the model
  # would never derive -- which is the one way to write a row the page cannot find.
  #
  # AND NEITHER HALF IS SET BY DEFAULT. A bare judgement row is a legal and
  # ordinary state: `#unmet?` is false, `#expectation?` is false, and it is out of
  # every denominator. The traits are the two halves, separately, because the
  # header's whole argument is that they must not be scored by one reader.
  factory :lab_exits_judgement, class: "Lab::Exits::Judgement" do
    association :vantage, factory: :lab_exits_vantage
    name { "The Salt Chandlery" }

    # THE EXPECTATION HALF, typed in advance. The band the
    # `:one_building_and_open_ground` sample actually gave that place, so a test
    # asserting a hit does not have to restate it.
    trait :expecting_a_few_rooms do
      expects_inside { "a few rooms" }
    end

    trait :expecting_no_inside do
      expects_inside { Location::Parameters::NO_INSIDE }
    end

    trait :expecting_nobody do
      expects_population { "nobody" }
    end

    # A NAME WITHOUT ITS ARTICLE, so a test can prove the key is what identity
    # means: this and the default name are one row and one figure.
    trait :without_the_article do
      name { "Salt Chandlery" }
    end

    # A PLACE NO DRAW WILL EVER NAME, for the rule that makes the captain's Call
    # 4c honest: an expectation nothing answered is out of the denominator and not
    # a miss.
    trait :for_a_place_no_draw_names do
      name { "The Bell Tower" }
      expects_inside { "a warren of rooms" }
    end

    # THE JUDGEMENT HALF, written after a draw.
    trait :good do
      verdict { "good" }
    end

    trait :bad do
      verdict { "bad" }
      aspects { "inside_wrong, band_wrong" }
      note { "a chandlery is a shop, not a warren" }
    end
  end
end
