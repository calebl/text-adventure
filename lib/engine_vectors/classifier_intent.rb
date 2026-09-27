# `Playthrough::Classifier#build_intent`: a model's three answers (intent,
# target, also_named) and a throw's aim, resolved against the room's closed
# sets -- and the refusal the engine gives the intent that comes of it.
module EngineVectors::ClassifierIntent
  SOURCES = [ "app/models/playthrough/classifier.rb", "app/models/playthrough/intent_schema.rb",
              "app/models/playthrough/refusal.rb", "app/models/playthrough/physical_action.rb",
              "app/models/item.rb" ].freeze
  NOTES = "Each case stands in the room named `world` (a world in `worlds`) and calls " \
          "#build_intent(intent, target, exits_here, characters_here, items_here, items_carried, " \
          "also_named, thrown_at) with the four sets the room offers. `intent` is the intent as " \
          "lib/engine_vectors/room.rb writes one (records as ids, `physical` as the attempt's token); " \
          "`refused` is Intent#refused?; `refusal` is Refusal.for(intent, typed: `typed`, " \
          "offered: #offered_for(intent's action)) as {kind, text}, or null; the refusal portion " \
          "carries the rest of a refusal's readings.".freeze

  WORLDS = %w[office office_tavern cascade refusal physical empty castless nowhere].freeze
  TYPED = "the line".freeze

  def self.constants_table
    { "worlds" => EngineVectors::Rooms::WORLDS.slice(*WORLDS).to_a, "intents" => Playthrough::IntentSchema::INTENTS,
      "nothing" => Playthrough::IntentSchema::NOTHING }
  end

  def self.cases
    WORLDS.flat_map do |world|
      EngineVectors.rolled_back do
        room = EngineVectors::Rooms.build!(world)
        classifier = room.classifier
        sets = [ classifier.exits_here, classifier.characters_here, classifier.items_here, classifier.items_carried ]
        offered = (Playthrough::IntentSchema::INTENTS + %w[other]).to_h { |action| [ action.to_sym, classifier.offered_for(action) ] }
        answers(classifier).map do |intent, target, also, thrown_at|
          input = { "world" => world, "intent" => intent, "target" => target, "also_named" => also, "thrown_at" => thrown_at }
          EngineVectors.case_for("#{world} #{[ intent, target, also, thrown_at ].inspect}", input, build(classifier, sets, offered, input))
        end
      end
    end
  end

  # Every intent the table has, one it does not, and one in the wrong case;
  # against every name its own set answers to, a name from each other set,
  # the first name in capitals, `nothing`, a blank and a name nothing answers
  # to; then a second name from its own set and from another, and a throw's
  # aim at every person and way out and at a thing, which is no aim.
  def self.answers(classifier)
    sets = [ classifier.exits_here.map(&:name), classifier.characters_here.flat_map { |person| [ person.fullname, person.nickname ] },
             classifier.items_here.map(&:name), classifier.items_carried.map(&:name) ].map(&:compact_blank)
    labels = sets.flatten.uniq
    nothing = Playthrough::IntentSchema::NOTHING
    tokens = classifier.physical_actions.map(&:token)

    (Playthrough::IntentSchema::INTENTS + %w[steal Take]).flat_map do |intent|
      own = classifier.offered_for(intent).flat_map { |record| record.respond_to?(:fullname) ? [ record.fullname, record.nickname ] : [ record.try(:name) ] }.compact_blank
      others = sets.filter_map { |set| (set - own).first }
      targets = (own + others + labels.first(1).map(&:upcase) + [ nothing, "", "the moon" ]).uniq
      alsos = [ nil, nothing ] + own.first(2) + others.first(1)
      case intent
      when "throw" then targets.product([ nil, nothing, "the moon" ] + sets[0] + sets[1] + sets[2].first(1)).map { |target, aim| [ intent, target, nil, aim ] }
      when "use" then (tokens + [ nothing, "use:consume:0:0:0:0" ]).product([ nil ] + tokens.first(2) + labels.first(2)).map { |target, also| [ intent, target, also, nil ] }
      else targets.product(alsos.uniq).map { |target, also| [ intent, target, also, nil ] }
      end
    end.uniq
  end

  def self.build(classifier, sets, offered, input)
    intent = classifier.send(:build_intent, input["intent"], input["target"], *sets, input["also_named"], input["thrown_at"])
    refusal = Playthrough::Refusal.for(intent, typed: TYPED, offered: offered.fetch(intent.action))
    { "intent" => EngineVectors::Room.intent(intent), "refused" => intent.refused?, "refusal" => refusal && { "kind" => refusal.kind.to_s, "text" => refusal.text } }
  end
end
