# Runner-only allowlist. The first request must match the inspected fixture
# bytes. The second must come from this same InteractionAgent, the just-returned
# answer and the actual NpcAction receipt. Checks precede budget reservation.
module PhysicalDialoguePayload
  MAX_CALLS = 72
  class Refused < Exception; end

  class << self
    attr_accessor :gate

    def install!
      BaseAgent.prepend(BeforeBudget) unless BaseAgent.ancestors.include?(BeforeBudget)
      InteractionAgent.prepend(ExchangeBinding) unless InteractionAgent.ancestors.include?(ExchangeBinding)
      Playthrough::NpcAction.prepend(Effects) unless Playthrough::NpcAction.ancestors.include?(Effects)
    end
  end

  class Gate
    attr_reader :sent, :exchange, :first_answer, :effect

    def initialize(samples:, allowed:, attempted: [])
      @cases = Eval::Dialogue.cases.index_by { |row| row.fetch('id') }
      @requests = samples.fetch('samples').to_h { |row| [ row.fetch('id'), row.fetch('actual_first_request') ] }
      complete = (1..4).flat_map { |rep| @cases.keys.map { |id| [ id, rep ] } }
      raise Refused, 'Manifest does not cover exactly the fixed corpus' unless @requests.keys.sort == @cases.keys.sort
      raise Refused, 'Invalid or duplicate allowed reading' unless allowed.uniq == allowed && (allowed - complete).empty?
      raise Refused, 'An unfinished charged reading cannot be repurchased automatically' if (allowed & attempted).any?
      raise Refused, 'Too many calls allowed' if complete.size * 2 > MAX_CALLS
      @allowed, @sent = allowed, []
    end

    def start!(id, rep)
      @current = [ id, rep ]
      raise Refused, 'Reading is not allowed or was already attempted' unless @allowed.include?(@current) && sent.none? { |key| key.first(2) == @current }
      @phase, @exchange, @first_answer, @effect, @narrator_request = :ready, nil, nil, nil, nil
    end

    def bind!(candidate, line)
      raise Refused, 'No fresh permitted exchange' unless @phase == :ready && !exchange
      game = candidate.playthrough
      unless game && game.id == -910001 && game.story_id == -910001 && candidate.character.id == -910002 &&
             game.character_id == -910001 && Playthrough.count == 1 && Story.count == 1 &&
             game.story.title == 'NPC agency evaluation' && line == @cases.fetch(@current.first).fetch('line')
        raise Refused, 'Exchange is not the fixed isolated fictional fixture'
      end
      @exchange = candidate
      @character_agent, @narrator_agent = candidate.character_agent, candidate.narrator_agent
      @npc_actions = candidate.send(:npc_actions)
    end

    def before!(agent, prompt)
      raise Refused, 'No bound fixture exchange' unless exchange
      actual = Eval::Dialogue::Version.request(agent, prompt)
      if agent.equal?(@character_agent) && @phase == :ready
        raise Refused, 'NPC request differs from inspected fixture' unless actual == @requests.fetch(@current.first)
        @phase, pass = :character_sent, 1
      elsif agent.equal?(@narrator_agent) && @phase == :narrator_built
        raise Refused, 'Narrator request differs from the verified exchange builder' unless actual == @narrator_request
        @phase, pass = :narrator_sent, 2
      else
        raise Refused, 'Unexpected agent, pass, or repeated call'
      end
      key = @current + [ pass ]
      raise Refused, 'Call already attempted or cap reached' if sent.include?(key) || sent.size >= MAX_CALLS
      sent << key
    end

    def received!(agent, response)
      if agent.equal?(@character_agent) && @phase == :character_sent
        @first_answer = JSON.parse(JSON.generate(response.content))
        @phase = :answered
      elsif agent.equal?(@narrator_agent) && @phase == :narrator_sent
        @phase = :finished
      else
        raise Refused, 'Response came from an unexpected pass'
      end
    end

    def effect!(actions, choice, result)
      return unless exchange && actions.equal?(@npc_actions)
      raise Refused, 'Effect does not belong to the received character answer' unless @phase == :answered && choice == first_answer.fetch('engine_action', 'none')
      @effect = result
      @effect_fields = JSON.parse(JSON.generate(result.to_h))
    end

    def check_builder!(candidate, line, response, receipt)
      unless candidate.equal?(exchange) && @phase == :answered &&
             line == @cases.fetch(@current.first).fetch('line') && JSON.parse(JSON.generate(response)) == first_answer &&
             receipt.equal?(effect) && effect && JSON.parse(JSON.generate(receipt.to_h)) == @effect_fields
        raise Refused, 'Narrator builder must use this fixture answer and actual engine receipt'
      end
    end

    def built!(prompt)
      @narrator_request = Eval::Dialogue::Version.request(@narrator_agent, prompt)
      raise Refused, 'Narrator must have no unrelated history or system data' unless @narrator_request.fetch('history').empty? && @narrator_request['schema'].nil? && @narrator_request['system'].blank?
      @phase = :narrator_built
    end
  end

  module BeforeBudget
    def ask(prompt, **options, &block)
      guard = PhysicalDialoguePayload.gate or raise Refused, 'No payload allowlist installed'
      guard.before!(self, prompt)
      response = super
      guard.received!(self, response)
      response
    end
  end

  module ExchangeBinding
    def ask(line, &block)
      guard = PhysicalDialoguePayload.gate or raise Refused, 'No payload allowlist installed'
      guard.bind!(self, line)
      super
    end

    def narrator_prompt(line, response, effect: nil)
      guard = PhysicalDialoguePayload.gate or raise Refused, 'No payload allowlist installed'
      guard.check_builder!(self, line, response, effect)
      prompt = super
      guard.built!(prompt)
      prompt
    end
  end

  module Effects
    def apply!(choice)
      result = super
      PhysicalDialoguePayload.gate&.effect!(self, choice, result)
      result
    end
  end
end
