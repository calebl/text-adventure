# Runner-only fixture/request boundary. The original physical corpus, fixture
# builder and full Turn evaluator are reused unchanged. Narrator text may depend
# on a fresh NPC answer or engine roll, but only the actual frozen builders for
# this synthetic game may supply it. Checks precede shared budget reservation.
require "json"
require "digest"
require Rails.root.join("db/eval/physical-20260910/fixtures")
require Rails.root.join("db/eval/adversarial-20260909/eval-budget-streaming-v2")

module PhysicalConfirmation
  ROOT = Rails.root.join("db/eval/physical-classifier-revised-20260910/physical-confirmation")
  ORIGINAL = Rails.root.join("db/eval/physical-20260910")
  HELPER = Rails.root.join("db/eval/adversarial-20260909/eval-budget-streaming-v2.rb")
  DATABASE = "/tmp/ta-physical-classifier-revised-20260910-live.sqlite3"
  LABEL = "classifier-revised-20260910"
  # The purchased baseline began after the seed world's IDs. Reserve those
  # numeric slots without copying any world/player rows, so closed tokens and
  # deterministic dice remain matched to that baseline.
  SEQUENCE_OFFSETS = { "universes" => 3, "stories" => 3, "locations" => 13,
    "characters" => 9, "items" => 7, "location_connections" => 20, "scenes" => 3 }.freeze
  class Halt < ReviewEvalBudget::Halt; end

  class << self
    attr_accessor :gate

    def json(value) = JSON.parse(JSON.generate(value))

    def request(agent, prompt)
      json(purpose: agent.purpose, prompt: prompt, instructions: agent.instructions,
        schema: agent.schema&.new&.to_json_schema,
        history: agent.chat.messages.order(:id).map { |message| { role: message.role, content: message.text } })
    end

    def source
      names = Dir.glob("{app,config/initializers,test/factories}/**/*.rb", base: Rails.root).sort +
        %w[Gemfile.lock db/schema.rb db/eval/physical-20260910/evaluate.rb
           db/eval/physical-20260910/fixtures.rb db/eval/physical-20260910/cases.json
           db/eval/adversarial-20260909/eval-budget-streaming-v2.rb]
      names += Dir.glob("*.rb", base: ROOT).map { |name| ROOT.join(name).relative_path_from(Rails.root).to_s }
      names.sort.to_h { |name| [ name, Digest::SHA256.file(Rails.root.join(name)).hexdigest ] }
    end

    def install!
      PhysicalFixtures.singleton_class.prepend(Fixtures)
      BaseAgent.prepend(Agent)
      Scene::Narrator.prepend(Narrator)
      InteractionAgent.prepend(Exchange)
      Playthrough::NpcAction.prepend(Effect)
    end

    def empty_database!
      ReviewEvalBudget.assert_isolated_database!
      unless [ Universe, Story, Location, LocationConnection, Scene, Playthrough, Character, Item, Chat, Message ].all? { |model| model.count.zero? }
        raise Halt, "Use a fresh schema with only the offline model registry; no player saves"
      end
      ActiveRecord::Migration.check_all_pending!
      connection = ActiveRecord::Base.connection
      SEQUENCE_OFFSETS.each do |table, offset|
        connection.execute("DELETE FROM sqlite_sequence WHERE name = #{connection.quote(table)}")
        connection.execute("INSERT INTO sqlite_sequence(name, seq) VALUES (#{connection.quote(table)}, #{offset})")
      end
    end
  end

  class Gate
    attr_reader :current, :sent, :fixture, :requests, :first_answer, :effect

    def initialize(rows, capture: false)
      @rows, @capture, @sent, @requests, @index = rows, capture, [], [], -1
      ids = JSON.parse(ORIGINAL.join("cases.json").read).map { |row| row.fetch("id") }
      expected = (1..4).flat_map { |rep| ids.map { |id| [ id, rep ] } }
      raise Halt, "Need exactly seven unchanged cases and four complete runs" unless rows.map { |row| row.values_at("case", "rep") } == expected
      @cap = rows.sum { |row| row.fetch("calls").length }
      raise Halt, "Unexpected corpus call cap" unless @cap == 60
    end

    def start!(kind)
      @index += 1
      @current = @rows.fetch(@index) { raise Halt, "Extra fixture" }
      raise Halt, "Fixture order changed" unless current.fetch("case") == kind
      @call_index, @fixture, @built, @first_answer, @effect, @exchange = 0, nil, {}, nil, nil, nil
    end

    def built_fixture!(value)
      @fixture = value
      actual = PhysicalConfirmation.json(PhysicalFixtures.state(value))
      raise Halt, "Changed synthetic starting state" unless actual == current.fetch("before")
      expected_games = @index + 1
      unless Story.count == expected_games && Playthrough.count == expected_games &&
             Character.count == expected_games * 2 && fixture.fetch(:game).story.title == "Tools at the market"
        raise Halt, "Database contains records outside the fixed fixtures"
      end
    end

    def game!(game, line)
      unless fixture && game == fixture.fetch(:game) && line == current.fetch("line")
        raise Halt, "Request builder is outside the fixed fictional turn"
      end
    end

    def built!(agent, prompt) = @built[agent.object_id] = PhysicalConfirmation.request(agent, prompt)

    def bind_exchange!(exchange, line)
      game!(exchange.playthrough, line)
      raise Halt, "Unexpected NPC or second exchange" unless exchange.character == fixture.fetch(:npc) && @exchange.nil?
      @exchange = exchange
    end

    def effect!(actions, choice, result)
      unless @exchange && actions.equal?(@exchange.send(:npc_actions)) &&
             choice == first_answer&.fetch("engine_action", "none")
        raise Halt, "NPC effect did not come from this fixture's received answer"
      end
      @effect, @effect_fields = result, PhysicalConfirmation.json(result.to_h)
    end

    def narrator_exchange!(exchange, line, answer, receipt)
      game!(exchange.playthrough, line)
      unless exchange.equal?(@exchange) && PhysicalConfirmation.json(answer) == first_answer &&
             receipt.equal?(effect) && effect && PhysicalConfirmation.json(effect.to_h) == @effect_fields
        raise Halt, "NPC narrator did not use the received answer and actual engine receipt"
      end
    end

    def before!(agent, prompt)
      raise Halt, "No fixture or call cap exceeded" unless fixture && sent.length < @cap
      reference = current.fetch("calls").fetch(@call_index) { raise Halt, "Extra fixture request" }
      actual = PhysicalConfirmation.request(agent, prompt)
      raise Halt, "Unexpected request purpose" unless actual.fetch("purpose") == reference.fetch("purpose")
      expected = reference.slice("purpose", "prompt", "instructions", "schema", "history")
      expected["instructions"] = Playthrough::Classifier::INSTRUCTIONS if actual.fetch("purpose") == "classifier"
      checked = @capture ? actual.except("history") : actual
      if %w[classifier character].include?(agent.purpose) || @capture
        raise Halt, "Request differs from inspected fixture: #{agent.purpose}" unless checked == expected
      else
        raise Halt, "Narrator request bypassed the actual fixture builder" unless actual == @built.delete(agent.object_id)
        %w[instructions schema history].each do |key|
          raise Halt, "Unexpected narrator #{key}" unless actual.fetch(key) == expected.fetch(key)
        end
      end
      sent << [ current.fetch("case"), current.fetch("rep"), @call_index ]
      requests << actual
      @call_index += 1
      actual
    end

    def received!(agent, response)
      @first_answer = PhysicalConfirmation.json(response.content) if agent.purpose == "character"
    end
  end

  module Fixtures
    def build(kind)
      PhysicalConfirmation.gate.start!(kind)
      super.tap { |fixture| PhysicalConfirmation.gate.built_fixture!(fixture) }
    end
  end

  module Agent
    def ask(prompt, **options, &block)
      request = PhysicalConfirmation.gate.before!(self, prompt)
      response = super
      PhysicalConfirmation.gate.received!(self, response)
      ReviewEvalBudget.calls.last&.merge!(history: request.fetch("history"))
      response
    end
  end

  module Narrator
    def prompt_for(line, *args)
      PhysicalConfirmation.gate.game!(playthrough, line)
      super.tap { |prompt| PhysicalConfirmation.gate.built!(agent, prompt) }
    end
  end

  module Exchange
    def ask(line, &block)
      PhysicalConfirmation.gate.bind_exchange!(self, line)
      super
    end

    def narrator_prompt(line, answer, effect: nil)
      PhysicalConfirmation.gate.narrator_exchange!(self, line, answer, effect)
      super.tap { |prompt| PhysicalConfirmation.gate.built!(narrator_agent, prompt) }
    end
  end

  module Effect
    def apply!(choice)
      super.tap { |result| PhysicalConfirmation.gate.effect!(self, choice, result) }
    end
  end
end
