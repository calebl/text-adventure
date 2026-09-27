# `Playthrough::Volition::State` and `Playthrough::Volition::SystemOne#request`:
# the typed volition request a room's people would be sent, words and all.
module EngineVectors::VolitionRequest
  SOURCES = [ "app/models/playthrough/volition/system_one.rb", "app/models/playthrough/volition/state.rb",
              "app/models/playthrough/volition.rb", "app/models/playthrough/ledger.rb" ].freeze
  NOTES = "Each case builds SystemOne.new(playthrough, characters, location:, line:).request from `records` " \
          "(every row the database holds; see lib/engine_vectors/records.rb): `characters` are ids in the " \
          "order handed in, `location` an id and `line` the typed line or null. The output is the request " \
          "{state, questions} as it is sent, keys in order. The `fixture` case is the room " \
          "test/fixtures/files/volition_system_one_request.json was written for, and reproduces that file " \
          "exactly (the export stops if it does not). The others are sweep script moments (`script`, " \
          "after step `step`) asking about everybody in the player's room but the player, in id order, " \
          "and a room asked about nobody.".freeze

  FIXTURE = "test/fixtures/files/volition_system_one_request.json".freeze

  # The clerk `Playthrough::Volition::SystemOneTest` stages, with the desires
  # its factory gives her.
  CLERK = {
    "conscious_desire" => "To be paid what they are owed before the week is out",
    "unconscious_desire" => "To be asked their opinion by somebody who waits for the answer",
    "recognized_need" => "To keep their word, because it is the only thing they have never broken",
    "unrecognized_need" => "To walk into the one room they have been going around for years",
    "desire_pursuit" => "obtain", "need_pursuit" => "reach"
  }.freeze

  STOPS = [
    [ "a-fight-the-player-wins", [ 3, 24 ] ],
    [ "somebody-walks-out-on-their-own", [ 0 ] ],
    [ "a-one-way-hazard-on-a-door", [ 7, 8 ] ],
    [ "the-salt-assizes-to-an-ending", [ 1, 2 ] ],
    [ "the-unrecorded-hour-two-bodies", [ 6 ] ]
  ].freeze

  def self.constants_table
    { "serves" => Playthrough::Volition::SERVES, "pressure_threshold" => Playthrough::Volition::SystemOne::PRESSURE_THRESHOLD }
  end

  def self.cases
    [ fixture ] + walked
  end

  def self.fixture
    EngineVectors::Records.frozen do
      story = EngineVectors::World.story!(9_101)
      room = EngineVectors::World.location!(story, id: 910_101, name: "The Counting Room")
      next_door = EngineVectors::World.location!(story, id: 910_102, name: "The Stairwell")
      [ [ room, next_door, 910_101 ], [ next_door, room, 910_102 ] ].each do |from, to, id|
        LocationConnection.create!(id: id, location: from, connected_location: to, distance: "adjacent",
                                   travel_method: Location::Interior::WALKING)
      end
      player = EngineVectors::Room.person!(story, { "id" => 910_103, "fullname" => "Hero Protagonist", "nickname" => "Hero" },
                                           is_protagonist: true)
      game = Playthrough.create!(id: 9_101, story: story, character: player, current_location: room, token: EngineVectors::Walked::TOKEN)
      clerk = EngineVectors::Room.person!(story, { "id" => 910_104, "fullname" => "Odile Vance", "nickname" => "Odile" },
                                          location: room, **CLERK)
      Item.create!(id: 910_105, playthrough: game, location: room, name: "a brass ledger key", description: "A thing.")
      Playthrough::Volition.new(game, clerk, location: room).apply!(Playthrough::Volition::WAIT)

      input = { "characters" => [ clerk.id ], "location" => room.id, "line" => "read the docket", "records" => EngineVectors::Records.dump }
      output = request(game.reload, input)
      unless "#{JSON.pretty_generate(output)}\n" == Rails.root.join(FIXTURE).read
        raise "the staged room no longer reproduces #{FIXTURE}"
      end
      EngineVectors.case_for("fixture", input, output)
    end
  end

  def self.walked
    STOPS.flat_map do |script, stops|
      EngineVectors::Walked.each_stop(script, stops) do |game, index, step|
        location = game.current_location
        cast = (game.cast_in(location) - [ game.character ].compact).sort_by(&:id)
        records = EngineVectors::Records.dump
        asked = [ [ cast, step.typed ] ]
        asked << [ [], nil ] if [ script, index ] == [ STOPS.first.first, STOPS.first.last.first ]
        asked.map do |characters, line|
          input = { "script" => script, "step" => index, "characters" => characters.map(&:id), "location" => location.id,
                    "line" => line, "records" => records }
          EngineVectors.case_for("#{script} #{index}#{" nobody" if characters.empty?}", input, request(game, input))
        end
      end
    end.flatten
  end

  def self.request(game, input)
    characters = input["characters"].map { |id| Character.find(id) }
    Playthrough::Volition::SystemOne.new(game, characters, location: Location.find(input["location"]), line: input["line"])
                                    .request.deep_stringify_keys
  end
end
