FactoryBot.define do
  factory :location do
    association :story
    sequence(:name) { |n| "Location #{n}" }
    # The default is a realized location: a place that has been written out and
    # can be walked into. Use the :stub trait for one that has only been named.
    detail_level { "realized" }
    teaser { "A door stands open onto somewhere you have not been" }
    description { "A mysterious place filled with wonder and potential adventure" }
    lore { "Ancient tales speak of this place and the events that shaped its history" }
    last_protagonist_visit { nil }
    parent_location { nil }
    # Places stay put unless a world says otherwise -- see WorldMechanic.
    mobile { false }
    # And a place is safe unless a world says otherwise -- the column's own
    # default, and what every room already written is. `danger` decides which
    # pool the people BORN here are drawn from (`Character::Registry#slots`), so
    # defaulting it to anything else would put monsters in rooms nobody asked
    # for.
    danger { Location::SAFE }

    # AND A PLACE HAS SOMEBODY IN IT, WHICH IS THE ONE DEFAULT HERE THAT IS NOT
    # THE COLUMN'S. The column is nullable and nil is a real state -- *nobody
    # picked a word for this room* -- and the engine ROLLS a label for one
    # (`Location::Population.label_for`). A factory that left it nil would
    # therefore roll a die: half the rooms it built would come out with nobody
    # in them, and every test that reads a slot, a cast or an allowance off a
    # factory location would be a lottery on that row's id. That is the flake
    # `test/factories/location_connections.rb` carries the full diagnosis of,
    # and this is the same rule applied one table over.
    #
    # `a crowd` AND NOT THE MIDDLE WORD, because the middle word is a die too:
    # `a person or two` draws 1 or 1 or 2 and a test asserting on the second
    # slot would be green two runs in three. `a crowd` is the one label whose
    # whole band is at least two people, so a test that names two of them is
    # stable whatever the row's id came out as. Ask for a variation by trait,
    # and pin an EXACT count by stubbing `Location::Population.count_for` --
    # nothing here may roll one.
    population { "a crowd" }

    # Named by a neighbour and nothing more -- no description, no lore. This is
    # what an unexplored exit looks like until the player walks through it.
    trait :stub do
      detail_level { "stub" }
      description { nil }
      lore { nil }
    end

    trait :realized do
      detail_level { "realized" }
    end

    # A ROOM THAT DRAWS ITS PEOPLE FROM THE WORLD'S BESTIARY. Half the faces of
    # `Location::DANGER_DIE`, which is what `Location::DANGERS` says
    # "dangerous" is; `:deadly` is the one a seed file may say and the engine
    # never rolls.
    trait :dangerous do
      danger { "dangerous" }
    end

    trait :deadly do
      danger { "deadly" }
    end

    # A ROOM THE PICK SAID IS EMPTY: `nobody` is a word somebody CHOSE, so the
    # engine asks for no people and rolls no slots.
    trait :unpeopled do
      population { "nobody" }
    end

    # AND A ROOM NOBODY PICKED FOR AT ALL, which is what the opening room, every
    # room of a laid-out interior, every seeded room whose file leaves the key
    # out and every row older than the column are. The engine rolls the label
    # itself, so a test using this trait must not assert on a count.
    trait :population_unset do
      population { nil }
    end

    # A ROOM THAT COSTS YOU HIT POINTS FOR WALKING INTO IT. `hazard` is nullable
    # and NIL IS THE DEFAULT for the reason the column is nullable: almost no
    # room in any world does anything to anybody, and a factory that gave every
    # location a hazard would make every move in every test cost a die.
    #
    # The two traits are the two `when:` values in `Location::HAZARDS`, because
    # they reach two different branches of `Playthrough::Hazards`.
    trait :flooded do
      hazard { "flooded" }
      hazard_die { 4 }
    end

    trait :airless do
      hazard { "airless" }
      hazard_die { 4 }
    end

    trait :indoor do
      name { "Ancient Hall" }
      description { "A grand indoor space with high ceilings and echoing footsteps" }
      lore { "Built by craftsmen long ago, this hall has witnessed many important events" }
    end

    trait :outdoor do
      name { "Misty Mountains" }
      description { "Towering peaks shrouded in mist and ancient mystery" }
      lore { "These mountains have stood since the world was young, hiding secrets in their depths" }
    end

    trait :visited do
      last_protagonist_visit { 1.day.ago }
    end

    # A place the world moves at night. What travels is the graph around it: a
    # mobile location's edges out to places that are NOT mobile get repointed.
    trait :mobile do
      mobile { true }
    end

    trait :with_parent do
      parent_location { association :location, strategy: :build }
    end

    # A PLACE WITH AN INSIDE: an extent and no position, which is what the
    # outermost place of an interior carries (`Location::Box`). Fixed numbers,
    # never rolled -- a factory that threw dice for a box would land an overlap
    # on whoever ran the suite next.
    trait :with_a_footprint do
      width { 12 }
      depth { 8 }
    end

    # A ROOM PLACED IN A PARENT'S PLANE: all five columns and a parent that has
    # a footprint of its own, which is the only whole way to have a position.
    # It is the west half of `:with_a_footprint`'s 12 x 8, so a second placed
    # room at x = 7 is beside it and not on top of it.
    trait :placed do
      parent_location { association :location, :with_a_footprint, story: instance.story }
      x { 0 }
      y { 0 }
      z { 0 }
      width { 7 }
      depth { 8 }
    end

    # Specific location examples
    trait :rivendell do
      name { "Rivendell" }
      description { "A peaceful elven sanctuary hidden in the mountains, with waterfalls and beautiful architecture" }
      lore { "The Last Homely House East of the Sea, refuge for weary travelers and home to Elrond" }
    end

    trait :shire do
      name { "The Shire" }
      description { "A peaceful land of rolling green hills where hobbits live in comfortable holes" }
      lore { "Home to the halflings, a place of peace and plenty far from the troubles of the world" }
    end

    trait :museum do
      name { "Metropolitan Museum" }
      description { "A grand museum with marble halls filled with priceless artifacts" }
      lore { "One of the city's most prestigious cultural institutions" }
    end

    trait :artifact_room do
      name { "Ancient Artifacts Room" }
      description { "A secured room displaying the museum's most valuable historical pieces" }
      lore { "Where the missing artifact was last seen before its mysterious disappearance" }
    end
  end
end
