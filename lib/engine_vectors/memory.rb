# `Playthrough::Memory`: which of a character's earlier exchanges with the
# player come back into a prompt, and in what words.
module EngineVectors::Memory
  SOURCES = [ "app/models/playthrough/memory.rb", "app/models/playthrough/moment.rb", "app/models/playthrough.rb" ].freeze
  NOTES = "One game's rows (`records`, every row the database holds; see lib/engine_vectors/records.rb): a " \
          "chain of scenes ending at the playthrough's current scene, one scene of another game's that is " \
          "not in the chain, and interactions of two people across both. The first case carries the rows; " \
          "every later one names it in `records_of` instead. Each case asks one `character` " \
          "with `query` (a string or null) and `replayed`: `recall` is the interaction ids " \
          "Memory#recall(query:, replayed:) ranks, in its order, with each one's #resolution and " \
          "#recollection; `conclusions` and `recollections` are Moment#conclusions and #recollections " \
          "for the same arguments. Ranking reads natural logarithms, so a port must rank with the same " \
          "double-precision arithmetic.".freeze

  STORY = 9_301
  QUERIES = [ nil, "the brass ledger key", "what did Rowe say about the fire", "zzz" ].freeze
  REPLAYED = [ 0, 2, 9 ].freeze

  def self.constants_table
    { "stop_words" => Playthrough::Memory::STOP_WORDS, "conclusions" => Playthrough::Moment::CONCLUSIONS,
      "conclusions_budget" => Playthrough::Moment::CONCLUSIONS_BUDGET, "memories_budget" => Playthrough::Moment::MEMORIES_BUDGET }
  end

  def self.cases
    EngineVectors::Records.frozen do
      game, people = build!
      records = EngineVectors::Records.dump
      people.flat_map do |person|
        QUERIES.product(REPLAYED).map do |query, replayed|
          input = { "playthrough" => game.id, "character" => person.id, "query" => query, "replayed" => replayed, "records" => records }
          EngineVectors.case_for("#{person.fullname} #{query.inspect} #{replayed}", input, read(game, person, query, replayed))
        end
      end
    end.then { |cases| share_records(cases) }
  end

  # The rows are the same for every case, so every case after the first
  # names the first instead of repeating them.
  def self.share_records(cases)
    first = cases.first["name"]
    cases.each_with_index.map do |one, index|
      index.zero? ? one : one.merge("input" => one["input"].except("records").merge("records_of" => first))
    end
  end

  def self.read(game, person, query, replayed)
    memory = Playthrough::Memory.new(game, person)
    moment = Playthrough::Moment.new(game)
    {
      "recall" => memory.recall(query: query, replayed: replayed).map do |row|
        { "id" => row.id, "resolution" => memory.resolution(row), "recollection" => memory.recollection(row) }
      end,
      "conclusions" => moment.conclusions(person, replayed: replayed, query: query),
      "recollections" => moment.recollections(person, replayed: replayed, query: query)
    }
  end

  # [speaker, typed, answered, resolved or nil, status or nil, fact or nil]
  EXCHANGES = [
    [ :rowe, "Where were you when the fire started?", "I was at the ledger desk, counting.", nil, nil, nil ],
    [ :rowe, "Give me the brass ledger key.", "Rowe hands over the brass ledger key.", "I gave the key up; it is not worth the trouble.",
      "applied", "Halkett Rowe gave the brass ledger key to Iri Calder." ],
    [ :perrin, "Did Rowe start the fire?", "Perrin shrugs.", "I will not accuse Rowe of anything yet.", "none", nil ],
    [ :rowe, "Where were you when the fire started?", "I was at the ledger desk, counting.", nil, nil, nil ],
    [ :rowe, "", "Rowe says nothing and keeps counting.", "Silence is safest while the inspector is here.", "rejected", nil ],
    [ :rowe, "Tell me about the fire in the counting room, every detail of it, from the first smoke to the last bucket " \
             "of water and who carried it up the stairs.", "Rowe tells the long story of the fire, the smoke and the " \
             "buckets, and of the clerk who carried the last of them up four flights with her sleeves alight and " \
             "never once put it down.", "The inspector wants the whole story; I told it all.", "applied",
      "Halkett Rowe described the fire." ],
    [ :perrin, "What does the key open?", "The strongbox under the stair.", nil, nil, nil ],
    [ :rowe, "Is the strongbox yours?", "It was my father's, and it is mine now.", "Admit the box; deny the key.", nil, nil ],
    [ :rowe, "What was in it?", "Rowe will not say.", "Say nothing about the deeds.", "applied", nil ]
  ].freeze

  def self.build!
    story = EngineVectors::World.story!(STORY)
    base = STORY * 100
    room = EngineVectors::World.location!(story, id: base + 1, name: "The Counting Room", detail_level: :realized)
    player = EngineVectors::Room.person!(story, { "id" => base + 2, "fullname" => "Iri Calder" }, is_protagonist: true, location: room)
    people = {
      rowe: EngineVectors::Room.person!(story, { "id" => base + 3, "fullname" => "Halkett Rowe", "nickname" => "Rowe" }, location: room),
      perrin: EngineVectors::Room.person!(story, { "id" => base + 4, "fullname" => "Perrin Lasco" }, location: room)
    }
    scene = ->(id, previous) { Scene.create!(id: id, story: story, location: room, previous_scene: previous, description: "A turn.",
                                             story_timestamp: EngineVectors::World::START) }
    stranger = scene.call(base + 90, nil)
    chain = EXCHANGES.size.times.reduce([]) { |scenes, n| scenes << scene.call(base + 10 + n, scenes.last) }
    game = Playthrough.create!(id: STORY, story: story, character: player, current_location: room, current_scene: chain.last,
                               token: EngineVectors::Walked::TOKEN)
    Item.create!(id: base + 5, playthrough: game, character: people[:rowe], name: "strongbox deed", description: "A thing.")

    exchange = ->(id, speaker, scene_row, typed, answered, resolved, status, fact) do
      Interaction.create!(id: id, character: people.fetch(speaker), scene: scene_row, location: room, user_input: typed,
                          action: answered, inner_resolution: resolved, action_status: status, action_fact: fact,
                          pre_thought: "A thought.", pre_feeling: "Wary.", post_thought: "Another.", post_feeling: "Tired.")
    end
    exchange.call(base + 50, :rowe, stranger, "Who are you?", "A clerk.", nil, nil, nil)
    EXCHANGES.each_with_index { |row, n| exchange.call(base + 60 + n, row.first, chain[n], *row.drop(1)) }
    [ game.reload, people.values ]
  end
end
