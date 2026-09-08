FactoryBot.define do
  # One draw of one kind. See Lab::Realization::Sample.
  #
  # THE ROW IS THE WHOLE POINT AND IT IS WRITTEN OUT BY HAND. A sample's row is
  # `Eval::Realization::Bench::Reading#to_h` -- what the two calls said and what
  # the world held around them -- so a factory that invented one would let a test
  # assert against a shape the bench does not produce. What these traits write is
  # the SUBSET the lab reads: the picks, the exits and the two gates their
  # denominators stand on (`facts["parameters_asked"]` and the presence of an
  # `answers["exits"]` key). Everything else on a real row is left out, and
  # `Eval::Realization::Scorer::Reading` reads an absent key exactly as it reads
  # one on a set stored before that key existed -- which is the behaviour the
  # gates were built for.
  #
  # NO VERDICT BY DEFAULT: an unjudged sample is the ordinary state of a sample
  # the moment it is drawn.
  factory :lab_realization_sample, class: "Lab::Realization::Sample" do
    association :kind, factory: :lab_realization_kind
    row { { "id" => "lab-kind-1", "shape" => "lab", "calls" => 2 } }

    # A ROOM'S DRAW: an exits call was made and answered, so the two per-exit
    # picks are judgeable and the five parameter picks are not.
    trait :a_room do
      row do
        { "id" => "lab-kind-1", "shape" => "lab", "calls" => 2,
          # THE ALLOWANCES ARE ON THE ROW because two checks read a count against
          # them, and a fixture missing them reads as a room with room for
          # nothing -- which would flag `exit_over_the_allowance` for a reason
          # that has nothing to do with what the fixture is for.
          "facts" => { "room" => "The Fishmonger's Warehouse", "parameters_asked" => false,
                       "people_allowance" => 1, "item_allowance" => 2, "exit_allowance" => 4,
                       "expects_new_ground" => false },
          "answers" => {
            "detail" => { "description" => "Black water stands a foot deep.", "lore" => "It flooded once." },
            "exits" => { "exits" => [
              { "name" => "The Chandler's Lane", "inside" => Location::Parameters::NO_INSIDE,
                "population" => "a person or two" }
            ] }
          },
          "after" => { "name" => "The Fishmonger's Warehouse", "rooms" => [] } }
      end
    end

    # AND A BUILDING'S: the parameters block was offered and answered, and there
    # was no exits call at all -- which is a laid-out place's ways out being its
    # rooms' (`Location::Generator#write_exits!` returns early).
    trait :a_building do
      row do
        { "id" => "lab-kind-1", "shape" => "lab", "calls" => 1,
          "facts" => { "room" => "The Fishmonger's Warehouse", "parameters_asked" => true },
          "answers" => { "detail" => {
            "description" => "Black water stands a foot deep.", "lore" => "It flooded once.",
            "parameters" => { "storeys_above" => "ground floor only", "storeys_below" => "a cellar",
                              "danger" => "uneasy", "gradient" => "worse the deeper you go",
                              "hazard" => "flooded" }
          } },
          "after" => { "name" => "The Fishmonger's Warehouse",
                       "rooms" => [ { "storey" => 0, "danger" => "uneasy", "hazard" => "flooded",
                                      "hazard_die" => 6, "width" => 4, "depth" => 4, "doors" => 1 },
                                    { "storey" => -1, "danger" => "dangerous", "hazard" => nil,
                                      "hazard_die" => nil, "width" => 4, "depth" => 4, "doors" => 1 } ] } }
      end
    end

    # AND A BUILDING WHOSE ROOMS SAY WHERE THEY ARE -- the shape
    # `Eval::Realization::Stage::Standing#rooms_laid_out` writes since slice 2,
    # and the one `Lab::Realization::Plan` can draw. Six rooms: four tiling a
    # four-by-four ground floor, two in a cellar, with the doors and the stair
    # the layout actually opened rather than every wall the boxes share -- which
    # is the whole reason the adjacency is stored and not derived.
    #
    # THE GROUND FLOOR IS A SERPENTINE, which is what `Location::Interior`
    # actually opens: 0 -> 1 -> 3 -> 2 around the four cells, so the two rooms on
    # the diagonal are joined by neither a door nor a wall.
    #
    # THE NUMBERS TILE EXACTLY, because `Location::Interior`'s rooms do: the
    # union of these boxes is the footprint, which is what the plan reads as its
    # plane. A fixture whose rooms overlapped would draw a building the layout
    # cannot build.
    trait :a_building_with_a_plan do
      row do
        { "id" => "lab-kind-1", "shape" => "lab", "calls" => 1,
          "facts" => { "room" => "The Fishmonger's Warehouse", "parameters_asked" => true },
          "answers" => { "detail" => {
            "description" => "Black water stands a foot deep.", "lore" => "It flooded once.",
            "parameters" => { "storeys_above" => "ground floor only", "storeys_below" => "a cellar",
                              "danger" => "uneasy", "gradient" => "worse the deeper you go",
                              "hazard" => "flooded" }
          } },
          "after" => { "name" => "The Fishmonger's Warehouse",
                       "rooms" => [
                         { "index" => 0, "name" => "The Loading Floor", "storey" => 0,
                           "x" => 0, "y" => 0, "width" => 2, "depth" => 2,
                           "danger" => "safe", "hazard" => nil, "hazard_die" => nil,
                           "doors" => 1, "doors_to" => [ 1 ], "stairs_to" => [] },
                         { "index" => 1, "name" => "The Salt Store", "storey" => 0,
                           "x" => 2, "y" => 0, "width" => 2, "depth" => 2,
                           "danger" => "dangerous", "hazard" => nil, "hazard_die" => nil,
                           "doors" => 3, "doors_to" => [ 0, 3 ], "stairs_to" => [ 4 ] },
                         { "index" => 2, "name" => "The Counting Room", "storey" => 0,
                           "x" => 0, "y" => 2, "width" => 2, "depth" => 2,
                           "danger" => "safe", "hazard" => nil, "hazard_die" => nil,
                           "doors" => 1, "doors_to" => [ 3 ], "stairs_to" => [] },
                         { "index" => 3, "name" => "The Wet Dock", "storey" => 0,
                           "x" => 2, "y" => 2, "width" => 2, "depth" => 2,
                           "danger" => "uneasy", "hazard" => "flooded", "hazard_die" => 6,
                           "doors" => 2, "doors_to" => [ 1, 2 ], "stairs_to" => [] },
                         { "index" => 4, "name" => "The Cellar Stair", "storey" => -1,
                           "x" => 0, "y" => 0, "width" => 4, "depth" => 2,
                           "danger" => "safe", "hazard" => nil, "hazard_die" => nil,
                           "doors" => 2, "doors_to" => [ 5 ], "stairs_to" => [ 1 ] },
                         { "index" => 5, "name" => "The Bilge", "storey" => -1,
                           "x" => 0, "y" => 2, "width" => 4, "depth" => 2,
                           "danger" => "dangerous", "hazard" => "flooded", "hazard_die" => 4,
                           "doors" => 1, "doors_to" => [ 4 ], "stairs_to" => [] }
                       ] } }
      end
    end

    # A BUILDING THAT PICKED NOTHING, so every pick fell to its quietest default
    # -- `parameters_declined`, and the state the hit rate has to read as the
    # default rather than as unjudgeable, because the default is what the place
    # became.
    trait :a_building_that_picked_nothing do
      row do
        { "id" => "lab-kind-1", "shape" => "lab", "calls" => 1,
          "facts" => { "room" => "The Fishmonger's Warehouse", "parameters_asked" => true },
          "answers" => { "detail" => { "description" => "Dry boards.", "lore" => "Nothing much." } },
          "after" => { "name" => "The Fishmonger's Warehouse", "rooms" => [] } }
      end
    end

    trait :failed do
      row do
        { "id" => "lab-kind-1", "shape" => "lab", "calls" => 0,
          "error" => "BaseAgent::RefusalError: the model would not write it" }
      end
    end

    trait :good do
      verdict { "good" }
    end

    trait :bad do
      verdict { "bad" }
      aspects { "prose, exits" }
      note { "the ways out all restated places the world already had" }
    end
  end
end
