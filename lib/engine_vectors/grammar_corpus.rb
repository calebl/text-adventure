# `Playthrough::Grammar` over every line of the labelled classifier corpus --
# the input `rake eval:classifier_offline` reads -- in the room the line was
# labelled against.
#
# EACH POSITION IS STAGED FROM ITS SEED FILE, AS THE BENCH STAGES IT, and then
# written down as an `EngineVectors::Room` world with explicit ids: the room a
# port reads is the world in `worlds`, not a seed file. The line is read in
# both rooms and the two readings must say the same thing, name for name, or
# the export stops -- so a position the room description cannot carry (a
# locked door, somebody dead in this game) is found here and not in a port.
module EngineVectors::GrammarCorpus
  SOURCES = [ "app/models/playthrough/grammar.rb", "app/models/playthrough/refusal.rb",
              "app/models/playthrough/classifier.rb", "config/engine/playthrough/grammar.yml",
              "lib/eval/classifier/corpus.rb", "lib/eval/classifier/stage.rb", "lib/eval/classifier/offline.rb" ].freeze
  NOTES = "Each case is one corpus line (`id`) typed in the room named `world`: the line's position, " \
          "staged from its seed file and written down in `worlds`. `reading_first` and `parse` are the two readings, as the " \
          "grammar portion writes them. `refusal` is the sentence the player is refused with offline, as " \
          "rake eval:classifier_offline reaches it through #parse: Refusal.for(intent, typed:, offered: " \
          "#offered_for(action)).text when the intent is refused, else the grammar's own refusal, else " \
          "null.".freeze

  FIRST_STORY = 9_000

  # The worlds and the cases come out of one staging, which is the slow part:
  # a seed load per position.
  def self.contents
    worlds, cases = EngineSweep.without_a_model { stage }
    [ { "worlds" => worlds.to_a }, cases ]
  end

  def self.stage
    corpus = Eval::Classifier.corpus
    worlds = {}
    # The staged rooms are read and rolled back before the rebuilt ones exist.
    rows = Eval::Classifier::Stage.open(corpus.positions) do |stages|
      corpus.positions.each_with_index { |position, index| worlds[position.id] = world(stages.fetch(position.id), FIRST_STORY + index) }
      corpus.lines.map { |line| [ line, said(stages.fetch(line.position).classifier, line.typed) ] }
    end
    cases = rows.group_by { |line, _| line.position }.flat_map do |position, lines|
      EngineVectors.rolled_back do
        room = EngineVectors::Room.build!(worlds.fetch(position))
        lines.map do |line, staged|
          output = read(room.classifier, line.typed)
          rebuilt = said(room.classifier, line.typed)
          raise "#{line.id}: the rebuilt room reads #{line.typed.inspect} as #{rebuilt}, the staged one as #{staged}" unless rebuilt == staged

          EngineVectors.case_for(line.id.to_s, { "id" => line.id, "world" => position, "typed" => line.typed }, output)
        end
      end
    end
    # In the corpus's own order, though each room is built once.
    order = corpus.lines.each_with_index.to_h { |line, index| [ line.id.to_s, index ] }
    [ worlds, cases.sort_by { |one| order.fetch(one["name"]) } ]
  end

  def self.read(classifier, typed)
    grammar = Playthrough::Grammar.new(classifier.playthrough, classifier: classifier)
    parsed = grammar.parse(typed)
    { "reading_first" => EngineVectors::Room.reading(grammar.reading_first(typed)),
      "parse" => EngineVectors::Room.reading(parsed), "refusal" => refusal(classifier, parsed, typed) }
  end

  def self.refusal(classifier, reading, typed)
    if reading.intent&.refused?
      return Playthrough::Refusal.for(reading.intent, typed: typed, offered: classifier.offered_for(reading.intent.action)).text
    end

    reading.refusal
  end

  # What a reading says in words, which is the same in both rooms whatever the
  # ids: how it was understood, which records it named, and what it refused.
  def self.said(classifier, typed)
    grammar = Playthrough::Grammar.new(classifier.playthrough, classifier: classifier)
    [ grammar.reading_first(typed), grammar.parse(typed) ].map do |reading|
      next nil if reading.nil?

      intent = reading.intent
      named = intent && [ intent.subject, intent.at, intent.also_named ].map { |record| Playthrough::Classifier.label_for(record) }
      [ reading.understood, reading.refusal, reading.note, reading.wound, reading.attempt, reading.resolved_by,
        intent&.action, named, intent&.physical&.name ]
    end + [ refusal(classifier, grammar.parse(typed), typed) ]
  end

  # THE STAGED ROOM AS A ROOM DESCRIPTION. Only what the closed sets read is
  # carried; a position that needs more raises rather than being written down
  # as a different room.
  def self.world(standing, story_id)
    playthrough = standing.playthrough
    count = 0
    next_id = -> { story_id * 100 + (count += 1) }
    here = playthrough.current_location
    edges = LocationConnection.where(location: here).index_by(&:connected_location_id)
    exits = standing.exits.map do |exit|
      edge = edges.fetch(exit.id)
      raise "#{standing.position.id}: a #{edge.barrier} doorway is not a room description" unless %w[open jammed].include?(edge.barrier)

      { "id" => next_id.call, "name" => exit.name }.merge(edge.barrier == "open" ? {} : { "barrier" => edge.barrier })
    end
    {
      "story_id" => story_id,
      "protagonist" => playthrough.character && { "id" => next_id.call, "fullname" => playthrough.character.fullname },
      "here" => { "id" => next_id.call, "name" => here.name },
      "exits" => exits,
      "cast" => standing.cast.map { |person| { "id" => next_id.call, "fullname" => person.fullname, "nickname" => person.nickname } },
      "lying" => standing.here.map { |item| item(item, next_id.call) },
      "carried" => standing.carried.map { |item| item(item, next_id.call) }
    }
  end

  def self.item(item, id)
    written = { "id" => id, "name" => item.name, "bulk" => item.bulk, "use_kind" => item.use_kind, "combustible" => item.combustible }
    defaults = Item.new
    written.reject { |key, value| EngineVectors::Room::ITEM_KEYS.include?(key) && value == defaults[key] }
  end
end
