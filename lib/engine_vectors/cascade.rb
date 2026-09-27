# `Playthrough::Classifier::Cascade`: a System One answer set composed into an
# intent, or a line escalated to the model call. The answers are recorded ones
# handed over at the agent seam; no case makes a call.
module EngineVectors::Cascade
  SOURCES = [ "app/models/playthrough/classifier/cascade.rb", "app/models/playthrough/classifier/state.rb",
              "app/models/playthrough/classifier/request.rb", "app/agents/SystemOneAgent.rb",
              "app/models/playthrough/classifier.rb" ].freeze
  NOTES = "Each case stands in the room named `world` (a world in `worlds`) and reads `typed` through " \
          "Cascade#read with an agent that answers `answers`. A `request` case records what would be " \
          "sent: `state` is State#to_h, and `questions` is each question id with its type and, for a " \
          "choice, its options -- the record keys and `nothing` -- in order; the instructions and " \
          "criteria wording are config/engine/playthrough/classifier/request.yml, read by " \
          "Playthrough::Classifier::Request. A `compose` case's `answers` is written short: a string " \
          "is a Choice with probability 1.0, a number a Noul, and every question not named is answered " \
          "`nothing` or 0.0; an `answers` object that carries its own \"answers\" key is the provider's " \
          "whole body, and {\"unavailable\": message} is a provider that failed. `escalate: false` " \
          "reads the answers with the escalation rule switched off, which is how the presence gate is " \
          "reached on its own. The output is {path, target_present, named_more_than_one, intent}, " \
          "`intent` null when the line goes on to the model call.".freeze

  # Hands back recorded answers the way `SystemOneAgent#ask_questions` does,
  # through the real `SystemOneAgent::Answers` and its verification.
  class Recorded
    def initialize(reply) = @reply = reply

    def ask_questions(state:, questions:)
      raise SystemOneAgent::Unavailable, @reply["unavailable"] if @reply.key?("unavailable")

      SystemOneAgent::Answers.new(body(questions), questions)
    end

    private

    def body(questions)
      return @reply if @reply.key?("answers")

      answers = questions.to_h do |id, question|
        value = @reply.fetch(id) { question["type"] == "noul" ? 0.0 : Playthrough::IntentSchema::NOTHING }
        [ id, value.is_a?(Numeric) ? { "type" => "noul", "noul" => value } :
                { "type" => "choice", "choice" => value, "probabilities" => { value => 1.0 }, "confidence" => 1.0 } ]
      end
      { "answers" => answers }
    end
  end

  CLEAR = { "named_more_than_one" => 0.02, "target_present" => 0.95 }.freeze
  NOTHING = Playthrough::IntentSchema::NOTHING

  # `test/models/playthrough/classifier/cascade_test.rb`, case for case.
  TESTED = [
    [ "cascade", "take the ward stamp", { "intent" => "take", "target_take" => "available_item_2" } ],
    [ "cascade", "take the ward stamp", { "intent" => "take", "target_take" => "available_item_1", "target_move" => "way_1",
                                          "target_talk" => "person_2", "target_examine" => "player_item_1" } ],
    [ "cascade", "wonder about the weather", { "intent" => "other", "target_take" => "available_item_1" } ],
    [ "cascade_bare", "put down the daybook", { "intent" => "drop" } ],
    [ "cascade", "go down to the cellar", { "intent" => "move", "target_move" => NOTHING } ],
    [ "cascade", "take the press and the stamp", { "intent" => "take", "target_take" => "available_item_1",
                                                   "also_named" => "available_item_2" } ],
    [ "cascade", "take the press and ask Perrin about it", { "intent" => "take", "target_take" => "available_item_1",
                                                             "also_named" => "person_1" } ],
    [ "cascade", "take the ward stamp", { "intent" => "take", "target_take" => "available_item_1",
                                          "also_named" => "available_item_1" } ],
    [ "cascade", "ask my landlord for another week", { "intent" => "talk", "target_talk" => "person_1", "target_present" => 0.05 } ],
    [ "cascade", "take the ward stamp", { "intent" => "take", "target_take" => "available_item_1", "target_present" => 0.15 } ],
    [ "cascade", "take the press and the stamp", { "intent" => "take", "target_take" => "available_item_1",
                                                   "also_named" => "available_item_2", "target_present" => 0.02 }, false ],
    [ "cascade", "take the press and the stamp", { "intent" => "take", "target_take" => "available_item_1",
                                                   "also_named" => "available_item_2", "named_more_than_one" => 0.5 } ],
    [ "cascade", "take the press and the stamp", { "intent" => "take", "target_take" => "available_item_1",
                                                   "also_named" => "available_item_2", "named_more_than_one" => 0.49 } ],
    [ "cascade", "ask the landlord and the clerk about it", { "intent" => "talk", "named_more_than_one" => 0.91,
                                                              "target_present" => 0.03 } ],
    [ "cascade", "take the press and whatever else is going", { "intent" => "take", "target_take" => "available_item_1",
                                                                "also_named" => NOTHING, "named_more_than_one" => 0.91 } ],
    [ "cascade", "take the press and ask Perrin about it", { "intent" => "take", "target_take" => "available_item_1",
                                                             "also_named" => "person_1", "named_more_than_one" => 0.77 } ],
    [ "cascade", "take the crowbar and the ledger", { "intent" => "take", "target_take" => NOTHING, "named_more_than_one" => 0.88 } ],
    [ "cascade", "take the press and the stamp", { "intent" => "take", "target_take" => "available_item_1",
                                                   "also_named" => "available_item_2", "named_more_than_one" => 0.31 } ],
    [ "cascade_anvil", "take the anvil", { "intent" => "take", "target_take" => "available_item_3" } ],
    [ "cascade", "drink the daybook", { "intent" => "use", "target_use" => "attempt_1" } ],
    [ "cascade", "take the ward stamp", { "unavailable" => "timed out" } ],
    [ "cascade", "take the ward stamp", { "answers" => { "intent" => { "type" => "choice", "choice" => "take" } } } ],
    [ "cascade", "take the ward stamp", { "intent" => "take", "target_take" => "way_1" } ],
    [ "cascade", "ask Rowe about the hour", { "intent" => "talk", "target_talk" => "person_2" } ],
    [ "cascade", "take the ward stamp", { "intent" => "take", "target_take" => "available_item_2", "named_more_than_one" => 0.02,
                                          "target_present" => 0.91 } ],
    [ "cascade", "take the ward stamp", { "intent" => "take", "target_take" => "available_item_2", "named_more_than_one" => 0.87,
                                          "target_present" => 0.91 } ]
  ].freeze

  WORLDS = %w[cascade cascade_bare cascade_anvil physical empty].freeze
  READINGS = [ [ 0.02, 0.95 ], [ 0.49, 0.15 ], [ 0.5, 0.95 ], [ 0.02, 0.1499 ] ].freeze

  def self.constants_table
    { "worlds" => EngineVectors::Rooms::WORLDS.slice(*WORLDS).to_a,
      "presence_threshold" => Playthrough::Classifier::Cascade::PRESENCE_THRESHOLD,
      "two_name_threshold" => Playthrough::Classifier::Cascade::TWO_NAME_THRESHOLD, "nothing" => NOTHING }
  end

  def self.cases
    requests + tested + swept
  end

  def self.requests
    (TESTED.map { |world, typed, _| [ world, typed ] }.uniq + (WORLDS - %w[cascade]).map { |world| [ world, "a line" ] }).map do |world, typed|
      EngineVectors.case_for("request #{world} #{typed.inspect}", { "world" => world, "typed" => typed },
                             EngineVectors.rolled_back { request(EngineVectors::Rooms.build!(world).classifier, typed) })
    end
  end

  def self.request(classifier, typed)
    state = Playthrough::Classifier::State.new(classifier, typed)
    questions = Playthrough::Classifier::Request.new(state).to_h.transform_values do |question|
      { "type" => question["type"], "options" => question["criteria"]&.keys }.compact
    end
    { "state" => state.to_h, "questions" => questions }
  end

  def self.tested
    TESTED.each_with_index.map do |(world, typed, answers, escalate), n|
      input = { "world" => world, "typed" => typed, "answers" => (answers.key?("unavailable") || answers.key?("answers") ? answers : CLEAR.merge(answers)) }
      input["escalate"] = false if escalate == false
      EngineVectors.case_for("tested #{n}", input, EngineVectors.rolled_back { compose(EngineVectors::Rooms.build!(world).classifier, input) })
    end
  end

  # Every intent against every key its own question offers and `nothing`,
  # with no second name, the first key and the last; then the first target at
  # each side of both thresholds.
  def self.swept
    WORLDS.flat_map do |world|
      EngineVectors.rolled_back do
        classifier = EngineVectors::Rooms.build!(world).classifier
        state = Playthrough::Classifier::State.new(classifier, "a line")
        keys = state.all_keys
        Playthrough::IntentSchema::INTENTS.flat_map do |intent|
          id = Playthrough::Classifier::Request.target_id(intent)
          own = state.keys_for(intent)
          targets = own.empty? ? [ nil ] : own + [ NOTHING ]
          alsos = ([ NOTHING ] + keys.first(1) + keys.last(1)).uniq
          readings = targets.product(alsos, READINGS.first(1)) + targets.first(1).product(alsos.first(2), READINGS.drop(1))
          readings.map do |target, also, (two_name, presence)|
            answers = { "intent" => intent, "also_named" => also, "named_more_than_one" => two_name, "target_present" => presence }
            answers[id] = target if target
            answers.delete("also_named") if keys.empty?
            input = { "world" => world, "typed" => "a line", "answers" => answers }
            EngineVectors.case_for("swept #{world} #{answers.values.join(" ")}", input, compose(classifier, input))
          end
        end
      end
    end
  end

  def self.compose(classifier, input)
    cascade = Playthrough::Classifier::Cascade.new(classifier, agent: Recorded.new(input["answers"]))
    cascade.define_singleton_method(:escalate?) { |**| false } if input["escalate"] == false
    intent = cascade.read(input["typed"])
    { "path" => cascade.path, "target_present" => cascade.target_present, "named_more_than_one" => cascade.named_more_than_one,
      "intent" => EngineVectors::Room.intent(intent) }
  end
end
