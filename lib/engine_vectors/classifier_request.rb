# `Playthrough::Classifier::State` and `Playthrough::Classifier::Request`: the
# whole System One request one typed line would send, words and all.
module EngineVectors::ClassifierRequest
  SOURCES = [ "app/models/playthrough/classifier/state.rb", "app/models/playthrough/classifier/request.rb",
              "config/engine/playthrough/classifier/request.yml", "app/models/playthrough/classifier.rb" ].freeze
  NOTES = "Each case stands in the room named `world` (a world in `worlds`) and builds the request for " \
          "`typed`: `state` is State#to_h and `questions` is Request#to_h, every instruction and criterion " \
          "as it is sent, keys in the order they are sent. The `scored` world is the position " \
          "test/fixtures/files/scored_classifier_request.json was sent for, and its case reproduces that " \
          "file's state and questions byte for byte, but for the one clause `examine` gained after that arm " \
          "was scored (`examine_edit`: the fixture's text, then today's); the export stops if anything " \
          "else differs. The words come from " \
          "config/engine/playthrough/classifier/request.yml; `nothing` is the option every target and " \
          "also_named question ends with.".freeze

  FIXTURE = "test/fixtures/files/scored_classifier_request.json".freeze
  SCORED_LINE = "ask Rowe and Perrin what happened at four o'clock".freeze
  WORLDS = %w[scored office cascade cascade_bare cascade_anvil refusal physical empty castless nowhere].freeze
  LINES = [ "take the ward stamp", "", "  look around  " ].freeze

  def self.constants_table
    { "worlds" => EngineVectors::Rooms::WORLDS.slice(*WORLDS).to_a, "nothing" => Playthrough::IntentSchema::NOTHING,
      "examine_edit" => EXAMINE_EDIT }
  end

  def self.cases
    typed = [ [ "scored", SCORED_LINE ] ] + WORLDS.product(LINES)
    typed.map do |world, line|
      input = { "world" => world, "typed" => line }
      output = EngineVectors.rolled_back { request(EngineVectors::Rooms.build!(world).classifier, line) }
      check!(output) if input == { "world" => "scored", "typed" => SCORED_LINE }
      EngineVectors.case_for("#{world} #{line.inspect}", input, output)
    end
  end

  def self.request(classifier, typed)
    state = Playthrough::Classifier::State.new(classifier, typed)
    { "state" => state.to_h, "questions" => Playthrough::Classifier::Request.new(state).to_h }
  end

  # THE ONE DIFFERENCE THAT IS ALLOWED, the same one
  # `Playthrough::Classifier::RequestTest` names: `examine` gained a clause
  # after that arm was scored, with its own baseline either side.
  EXAMINE_EDIT = [ "without moving or taking it.", "without moving or taking it, or looking around the place in general." ].freeze

  def self.check!(output)
    stored = JSON.parse(Rails.root.join(FIXTURE).read)
    criteria = stored.dig("questions", "intent", "criteria")
    criteria["examine"] = criteria.fetch("examine").sub(*EXAMINE_EDIT)
    return if JSON.generate(stored.slice("state", "questions")) == JSON.generate(output)

    raise "the scored position no longer reproduces #{FIXTURE}"
  end
end
