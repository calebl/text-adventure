FactoryBot.define do
  # One draw of one vantage. See Lab::Exits::Sample.
  #
  # THE ROW IS THE WHOLE POINT AND IT IS WRITTEN OUT BY HAND, for
  # `lab_realization_samples`' reason: a sample's row is
  # `Eval::Realization::Bench::Reading#to_h`, so a factory that invented one would
  # let a test assert against a shape the bench does not produce. What these
  # traits write is the SUBSET this lab reads -- the exits answer, and
  # `after["new_places"]`, which is the gate every reach figure stands on.
  #
  # `after["new_places"]` IS THE ONE FIELD THAT MATTERS MOST HERE, because it is
  # what tells a discarded pick from one the engine could use. It is the RECORD of
  # what the world gained (`Eval::Realization::Bench#after`), so a fixture that
  # left it out reads as an answer whose every name restated a place the world
  # already had -- which is a real state and is what `:every_pick_discarded` is.
  #
  # NO VERDICT BY DEFAULT: an unjudged draw is the ordinary state of a draw the
  # moment it is bought.
  factory :lab_exits_sample, class: "Lab::Exits::Sample" do
    association :vantage, factory: :lab_exits_vantage
    row { { "id" => "lab-vantage-1", "shape" => "exits", "calls" => 2 } }

    # ONE BUILDING AND ONE STRETCH OF OPEN GROUND, both newly opened. The
    # ordinary good answer: a band given to the place that reads like a building
    # and none to the one that does not, and the engine could use both.
    trait :one_building_and_open_ground do
      row do
        { "id" => "lab-vantage-1", "shape" => "exits", "calls" => 2,
          "facts" => { "room" => "Harbour Steps", "parameters_asked" => false,
                       "people_allowance" => 1, "item_allowance" => 2, "exit_allowance" => 4,
                       "expects_new_ground" => true, "places" => [], "reachable" => [] },
          "answers" => {
            "detail" => { "description" => "Weed slicks the lowest step.", "lore" => "The tide takes it twice a day." },
            "exits" => { "exits" => [
              { "name" => "The Salt Chandlery", "teaser" => "A low door under a swinging sign.",
                "distance" => "a short walk", "travel_method" => "walking",
                "inside" => "a few rooms", "population" => "a person or two" },
              { "name" => "Tide Flats", "teaser" => "Mud running out to the channel.",
                "distance" => "a short walk", "travel_method" => "walking",
                "inside" => Location::Parameters::NO_INSIDE, "population" => "nobody" }
            ] }
          },
          "after" => { "name" => "Harbour Steps", "rooms" => [],
                       "new_places" => [ "The Salt Chandlery", "Tide Flats" ] } }
      end
    end

    # EVERY BAND THROWN AWAY, which is the state four bought draws of a real
    # vantage were in and the finding this lab was designed around
    # (`data/ta-exits-lab-scout/report.md` section 2.2). Both names restate places
    # the world already held, so `new_places` is empty and
    # `Location::Generator#connect_exit!` passed neither band to `create_stub!`.
    trait :every_pick_discarded do
      row do
        { "id" => "lab-vantage-1", "shape" => "exits", "calls" => 2,
          "facts" => { "room" => "Harbour Steps", "parameters_asked" => false,
                       "people_allowance" => 1, "item_allowance" => 2, "exit_allowance" => 4,
                       "expects_new_ground" => true,
                       "places" => [ { "name" => "The Custom House", "realized" => true, "connected" => false },
                                     { "name" => "The Bonded Cellar", "realized" => false, "connected" => false } ],
                       "reachable" => [] },
          "answers" => {
            "detail" => { "description" => "Weed slicks the lowest step.", "lore" => "It floods." },
            "exits" => { "exits" => [
              { "name" => "The Custom House", "teaser" => "The door you came out of.",
                "distance" => "adjacent", "travel_method" => "walking",
                "inside" => "a warren of rooms", "population" => "a crowd" },
              { "name" => "The Bonded Cellar", "teaser" => "Lamplight under the shutters.",
                "distance" => "a short walk", "travel_method" => "walking",
                "inside" => "one room", "population" => "a person or two" }
            ] }
          },
          # THE ENGINE OPENED NOTHING, which is what makes both bands discarded.
          "after" => { "name" => "Harbour Steps", "rooms" => [], "new_places" => [] } }
      end
    end

    # NO BAND AT ALL ON EITHER PLACE -- `inside_declined`, a decision NOT MADE
    # rather than a decision to have none. Measured at nought on the shipping
    # model's current prompt and at 41 of 42 on a previous wording, so it is a
    # state one word away rather than a hypothetical.
    trait :no_band_picked do
      row do
        { "id" => "lab-vantage-1", "shape" => "exits", "calls" => 2,
          "facts" => { "room" => "Harbour Steps", "parameters_asked" => false,
                       "people_allowance" => 1, "item_allowance" => 2, "exit_allowance" => 4,
                       "expects_new_ground" => true, "places" => [], "reachable" => [] },
          "answers" => {
            "detail" => { "description" => "Weed slicks the lowest step.", "lore" => "It floods." },
            "exits" => { "exits" => [
              { "name" => "Tide Flats", "teaser" => "Mud running out to the channel.",
                "distance" => "a short walk", "travel_method" => "walking", "population" => "nobody" }
            ] }
          },
          "after" => { "name" => "Harbour Steps", "rooms" => [], "new_places" => [ "Tide Flats" ] } }
      end
    end

    # A NAME WITHOUT ITS ARTICLE, opened under the name the model gave. The shape
    # `Location::Generator#find_location` was widened to resolve, kept here so a
    # test can prove the lab keys a place the same way the engine does -- one
    # judgement for `The Salt Chandlery` and `Salt Chandlery` alike.
    trait :named_without_the_article do
      row do
        { "id" => "lab-vantage-1", "shape" => "exits", "calls" => 2,
          "facts" => { "room" => "Harbour Steps", "parameters_asked" => false,
                       "people_allowance" => 1, "item_allowance" => 2, "exit_allowance" => 4,
                       "expects_new_ground" => true, "places" => [], "reachable" => [] },
          "answers" => {
            "detail" => { "description" => "Weed slicks the lowest step.", "lore" => "It floods." },
            "exits" => { "exits" => [
              { "name" => "Salt Chandlery", "teaser" => "A low door under a swinging sign.",
                "distance" => "a short walk", "travel_method" => "walking",
                "inside" => "a few rooms", "population" => "a person or two" }
            ] }
          },
          "after" => { "name" => "Harbour Steps", "rooms" => [], "new_places" => [ "Salt Chandlery" ] } }
      end
    end

    # AN ANSWER THAT NAMED NOTHING. `min_items: 1` on the schema means an empty
    # array is a call that came back with no answer to the question, and a
    # quantifier scored over nothing would read `none of them` as satisfied by a
    # failure -- so `#answered?` is false and it is out of every denominator.
    trait :named_nothing do
      row do
        { "id" => "lab-vantage-1", "shape" => "exits", "calls" => 2,
          "facts" => { "room" => "Harbour Steps", "parameters_asked" => false },
          "answers" => { "detail" => { "description" => "Steps." }, "exits" => { "exits" => [] } },
          "after" => { "name" => "Harbour Steps", "rooms" => [], "new_places" => [] } }
      end
    end

    # AND NO EXITS CALL AT ALL, which a vantage should never produce -- it is what
    # a room already at its exit cap gets. Kept so the denominator's gate has both
    # of its states under test.
    trait :never_asked do
      row do
        { "id" => "lab-vantage-1", "shape" => "exits", "calls" => 1,
          "facts" => { "room" => "Harbour Steps", "parameters_asked" => false },
          "answers" => { "detail" => { "description" => "Steps." } },
          "after" => { "name" => "Harbour Steps", "rooms" => [], "new_places" => [] } }
      end
    end

    trait :failed do
      row do
        { "id" => "lab-vantage-1", "shape" => "exits", "calls" => 0,
          "error" => "BaseAgent::RefusalError: the model would not write it" }
      end
    end

    trait :good do
      verdict { "good" }
    end

    trait :bad do
      verdict { "bad" }
      aspects { "too_many_ways_out, invented_a_way_out" }
      note { "a dead end given three doors" }
    end
  end
end
