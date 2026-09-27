# THE ROOMS THE LINE-READING PORTIONS STAND IN, each an `EngineVectors::Room`
# world. They are the rooms the model tests of the grammar, the refusals and
# the System One composition build, plus the shapes those tests reach by
# adding one record, and a few that no test had: a room with nothing in it, a
# story nobody plays, a game standing nowhere, and a room full of physical
# attempts.
module EngineVectors::Rooms
  def self.world(story_id, here: "Ward Office 12", protagonist: "Odile Vance", exits: [], cast: [], lying: [], carried: [])
    count = 0
    next_id = -> { story_id * 100 + (count += 1) }
    {
      "story_id" => story_id,
      "protagonist" => protagonist && { "id" => next_id.call, "fullname" => protagonist },
      "here" => here && { "id" => next_id.call, "name" => here },
      "exits" => exits.map { |exit| { "id" => next_id.call }.merge(exit.is_a?(String) ? { "name" => exit } : exit) },
      "cast" => cast.map { |fullname, nickname| { "id" => next_id.call, "fullname" => fullname, "nickname" => nickname } },
      "lying" => lying.map { |item| { "id" => next_id.call }.merge(item.is_a?(String) ? { "name" => item } : item) },
      "carried" => carried.map { |item| { "id" => next_id.call }.merge(item.is_a?(String) ? { "name" => item } : item) }
    }
  end

  OFFICE = { exits: [ "The Supply Closet" ], cast: [ [ "Halkett Rowe", "Rowe" ] ], lying: [ "ward stamp" ],
             carried: [ "Ward Office 12 daybook" ] }.freeze

  # `test/models/playthrough/cascade_test.rb`'s room.
  CASCADE = { protagonist: "Iri Calder", exits: [ "The Supply Closet" ],
              cast: [ [ "Perrin Lasco", "Perrin" ], [ "Halkett Rowe", nil ] ],
              lying: [ "filing press", "ward stamp" ],
              carried: [ { "name" => "Ward Office 12 daybook", "use_kind" => "food" } ] }.freeze

  # `test/models/playthrough/refusal_test.rb`'s room: an immovable press, and
  # a thing whose own name carries its article.
  REFUSAL = { protagonist: "Halkett Rowe", exits: [ "The Supply Closet" ], cast: [ [ "Perrin Lasco", nil ] ],
              lying: [ "Perrin's private index", "copy-room apron", { "name" => "filing press", "bulk" => "immovable" },
                       { "name" => "a bolted filing press", "bulk" => "immovable" } ],
              carried: [ "Ward Office 12 daybook" ] }.freeze

  # Every kind of physical attempt a room can offer without a key template.
  PHYSICAL = { exits: [ "The Supply Closet", { "name" => "The Coal Hatch", "barrier" => "jammed" } ],
               cast: [ [ "Halkett Rowe", "Rowe" ], [ "Perrin Lasco", "Perrin" ] ],
               lying: [ { "name" => "oily rag", "combustible" => true }, { "name" => "iron anvil", "bulk" => "immovable" } ],
               carried: [ { "name" => "tinderbox", "use_kind" => "firestarter" }, { "name" => "heel of bread", "use_kind" => "food" },
                          { "name" => "flask of gin", "use_kind" => "drink" }, { "name" => "crowbar", "use_kind" => "lever" },
                          { "name" => "old letter", "combustible" => true } ] }.freeze

  # The position `test/fixtures/files/scored_classifier_request.json` was sent
  # for: the design of record's own stored System One request.
  SCORED = { protagonist: "Iri Calder", exits: [ "The Supply Closet", "The Long Hallway" ],
             cast: [ [ "Perrin Lasco", "Perrin" ], [ "Halkett Rowe", "Sub-Inspector Rowe" ] ],
             lying: [ "filing press", "ward stamp" ], carried: [ "Ward Office 12 daybook" ] }.freeze

  WORLDS = {
    "office" => world(8_001, **OFFICE),
    "office_register" => world(8_002, **OFFICE, lying: [ "ward stamp", "ward register" ]),
    "office_apron" => world(8_003, **OFFICE, lying: [ "ward stamp", "copy-room apron" ]),
    "office_tavern" => world(8_004, **OFFICE, exits: [ "The Supply Closet", "The Bell and Anchor" ]),
    "office_supply_room" => world(8_005, **OFFICE, exits: [ "The Supply Closet", "The Supply Room" ]),
    "office_hat" => world(8_006, **OFFICE, lying: [ "ward stamp", "flat hat" ]),
    "cascade" => world(8_007, **CASCADE),
    "cascade_bare" => world(8_008, **CASCADE, carried: []),
    "cascade_anvil" => world(8_009, **CASCADE, lying: [ "filing press", "ward stamp",
                                                        { "name" => "ward anvil", "bulk" => "immovable" } ]),
    "refusal" => world(8_010, **REFUSAL),
    "physical" => world(8_011, **PHYSICAL),
    "empty" => world(8_012),
    "castless" => world(8_013, protagonist: nil, **OFFICE),
    "nowhere" => world(8_014, here: nil, exits: [], cast: [], lying: [], carried: [ "Ward Office 12 daybook" ]),
    "scored" => world(8_015, **SCORED)
  }.freeze

  def self.build!(name) = EngineVectors::Room.build!(WORLDS.fetch(name))
end
