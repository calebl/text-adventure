# `Playthrough::Ledger#recall`: what one character has seen happen in one
# game, oldest first, inside both of the ledger's bounds.
module EngineVectors::Ledger
  SOURCES = [ "app/models/playthrough/ledger.rb", "app/models/playthrough/blow.rb", "app/models/playthrough/toll.rb",
              "app/models/playthrough/volition/record.rb", "app/models/playthrough/vitals.rb" ].freeze
  NOTES = "Each case is one game's rows (`records`, every row the database holds; see " \
          "lib/engine_vectors/records.rb) and the output is Ledger.new(playthrough, character).recall(location:) " \
          "for every character in the story, in id order, with location null and then each room in id " \
          "order: [{character, location, recall}]. A volition, a blow and a toll are ordered by their " \
          "created_at in whole seconds and then their id. `games` differ in how much happened: a quiet one, " \
          "one inside both bounds, and one past `rows` events and past `budget` characters.".freeze

  # [name, story id, how many rounds of acts, blows and tolls]
  GAMES = [ [ "quiet", 9_201, 0 ], [ "short", 9_202, 2 ], [ "long", 9_203, 7 ], [ "wordy", 9_204, 12 ] ].freeze

  def self.constants_table = { "rows" => Playthrough::Ledger::ROWS, "budget" => Playthrough::Ledger::BUDGET }

  def self.cases
    GAMES.map do |name, story_id, rounds|
      EngineVectors::Records.frozen do
        game = build!(story_id, rounds, wordy: name == "wordy")
        input = { "playthrough" => game.id, "records" => EngineVectors::Records.dump }
        EngineVectors.case_for(name, input, recall(game))
      end
    end
  end

  def self.recall(game)
    rooms = [ nil ] + game.story.locations.order(:id).to_a
    game.story.characters.order(:id).flat_map do |character|
      rooms.map do |room|
        { "character" => character.id, "location" => room&.id,
          "recall" => Playthrough::Ledger.new(game, character).recall(location: room) }
      end
    end
  end

  STATS = { strength: 12, dexterity: 11, will: 10, hit_die: 10, level: 3 }.freeze

  # Two rooms joined by a doorway that tolls, the player and two others. Each
  # round the clerk acts, the player and the clerk trade a blow, and the place
  # takes a toll from somebody -- in the hall, on the doorway, or in the yard.
  # Times step by a minute a row, but a blow shares its round's minute with the
  # act before it, so the id breaks the tie.
  def self.build!(story_id, rounds, wordy:)
    story = EngineVectors::World.story!(story_id)
    base = story_id * 100
    long = wordy ? " of the Long Southern Arcade Beneath the Old Customs Tower" : ""
    hall = EngineVectors::World.location!(story, id: base + 1, name: "The Hall#{long}", detail_level: :realized)
    yard = EngineVectors::World.location!(story, id: base + 2, name: "The Yard#{long}", detail_level: :realized)
    door = LocationConnection.create!(id: base + 1, location: hall, connected_location: yard, distance: "adjacent",
                                      travel_method: Location::Interior::WALKING, hazard: "drop", hazard_die: 6)
    LocationConnection.create!(id: base + 2, location: yard, connected_location: hall, distance: "adjacent",
                               travel_method: Location::Interior::WALKING)
    name = ->(first) { wordy ? "#{first} Aurelian Castellane-Whitlock" : first }
    player = EngineVectors::Room.person!(story, { "id" => base + 3, "fullname" => name.call("Iri Calder") },
                                         is_protagonist: true, location: hall, **STATS)
    clerk = EngineVectors::Room.person!(story, { "id" => base + 4, "fullname" => name.call("Odile Vance"), "nickname" => "Odile" },
                                        location: hall, **STATS)
    EngineVectors::Room.person!(story, { "id" => base + 5, "fullname" => name.call("Perrin Lasco") }, location: yard, **STATS)
    game = Playthrough.create!(id: story_id, story: story, character: player, current_location: hall,
                               token: EngineVectors::Walked::TOKEN)

    at = ->(minute) { EngineVectors::World::START + minute.minutes }
    rounds.times do |round|
      minute = round * 3
      room = round.even? ? hall : yard
      Playthrough::Volition::Record.create!(playthrough: game, character: clerk, location: room, round: round + 1,
                                            chosen: Playthrough::Volition::WAIT, status: round.zero? ? "none" : "applied",
                                            serves: Playthrough::Volition::SERVES[round % 5],
                                            fact: "#{clerk.fullname} stayed in #{room.name} and changed nothing.",
                                            created_at: at.call(minute))
      attacker, target = round.even? ? [ player, clerk ] : [ clerk, player ]
      Playthrough::Blow.create!(playthrough: game, attacker: attacker, target: target, location: room, round: round + 1,
                                sequence: round, damage: round % 4, hp_after: [ 22 - round * 2, 0 ].max,
                                story_timestamp: at.call(minute), created_at: at.call(minute))
      toll = { playthrough: game, character: round % 3 == 2 ? clerk : player, damage: 1 + round % 3,
               hp_after: [ 20 - round, 0 ].max, saved: round % 4 == 3, sequence: -(round + 1),
               story_timestamp: at.call(minute + 1), created_at: at.call(minute + 1) }
      case round % 3
      when 0 then Playthrough::Toll.create!(**toll, location: hall, hazard: "flooded")
      when 1 then Playthrough::Toll.create!(**toll, location: hall, location_connection: door, hazard: "drop")
      else Playthrough::Toll.create!(**toll, location: yard, hazard: "unlit")
      end
    end
    game.reload
  end
end
