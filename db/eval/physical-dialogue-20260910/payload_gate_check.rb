# Offline behavioral checks of the runner guard: no provider and no budget use.
require_relative '../../../test/test_helper'
require_relative 'payload_gate'

module DialogueGateFakeReplies
  class << self
    attr_accessor :answers, :calls
  end
  def ask(_prompt, verify: nil, **_options)
    DialogueGateFakeReplies.calls += 1
    answer = DialogueGateFakeReplies.answers.shift
    raise 'No offline answer left' if answer.nil?
    verify&.call(answer)
    Eval::Dialogue::Bench::Response.new(content: answer)
  end
end
BaseAgent.prepend(DialogueGateFakeReplies)
PhysicalDialoguePayload.install!

class DialoguePayloadGateCheck < ActiveSupport::TestCase
  setup do
    @previous_key = RubyLLM.config.openrouter_api_key
    RubyLLM.config.openrouter_api_key = 'offline-gate-check'
    @samples = JSON.parse(File.read(File.join(__dir__, 'request-samples.json')))
    @before = Eval::Dialogue::Result.load(Rails.root.join('db/eval/dialogue-2026-09-10'))
    DialogueGateFakeReplies.calls = 0
  end

  teardown do
    RubyLLM.config.openrouter_api_key = @previous_key
    PhysicalDialoguePayload.gate = nil
  end

  def kase = Eval::Dialogue.cases.first

  def open_exchange
    guard = PhysicalDialoguePayload::Gate.new(samples: @samples, allowed: [ [ kase.fetch('id'), 1 ] ])
    PhysicalDialoguePayload.gate = guard
    guard.start!(kase.fetch('id'), 1)
    Eval::Classifier::Arm.parse(Eval::Dialogue.model).pinned do
      Eval::Dialogue::Stage.open(kase) do |stage|
        exchange = InteractionAgent.new(stage.npc, playthrough: stage.game)
        guard.bind!(exchange, kase.fetch('line'))
        yield guard, exchange, stage
      end
    end
  end

  test 'all inspected fixtures run both real exchange passes with stored replies' do
    rows = @before.rows.select { |row| row.fetch('rep') == 1 }
    guard = PhysicalDialoguePayload::Gate.new(samples: @samples, allowed: rows.map { |row| row.values_at('id', 'rep') })
    PhysicalDialoguePayload.gate = guard
    Eval::Classifier::Arm.parse(Eval::Dialogue.model).pinned do
      rows.each do |row|
        guard.start!(row.fetch('id'), row.fetch('rep'))
        DialogueGateFakeReplies.answers = row.fetch('calls').map { |call| call.fetch('raw_answer', call['answer']) }
        current = Eval::Dialogue.cases.find { |entry| entry.fetch('id') == row.fetch('id') }
        result = Eval::Dialogue::Bench.new.read(current, rep: 1)
        assert_nil result['error'], current.fetch('id')
        assert_equal row.fetch('facts'), result.fetch('facts')
      end
    end
    assert_equal 18, DialogueGateFakeReplies.calls
    assert_equal 18, guard.sent.size
  end

  test 'changed user or system bytes and extra history are blocked before provider' do
    %w[user system history].each do |change|
      open_exchange do |_guard, exchange, _stage|
        agent = exchange.character_agent
        prompt = exchange.character_prompt(kase.fetch('line'))
        prompt += ' unrelated private text' if change == 'user'
        agent.with_instructions('unrelated private text') if change == 'system'
        agent.chat.messages.create!(role: 'user', content_raw: 'unrelated private text') if change == 'history'
        assert_raises(PhysicalDialoguePayload::Refused) { agent.ask(prompt) }
        assert_equal 0, DialogueGateFakeReplies.calls
      end
    end
  end

  test 'changed schema is blocked before provider' do
    open_exchange do |_guard, exchange, _stage|
      exchange.character_agent.with_schema(RubyLLM::Schema.create do
        string :unapproved, description: 'Unrelated field'
      end)
      assert_raises(PhysicalDialoguePayload::Refused) { exchange.character_agent.ask(exchange.character_prompt(kase.fetch('line'))) }
      assert_equal 0, DialogueGateFakeReplies.calls
    end
  end

  test 'narrator cannot run before the fixture answer or with a substituted answer or receipt' do
    open_exchange do |guard, exchange, _stage|
      assert_raises(PhysicalDialoguePayload::Refused) { exchange.narrator_agent.ask('Unapproved prose request') }
      row = @before.rows.find { |entry| entry.values_at('id', 'rep') == [ kase.fetch('id'), 1 ] }
      DialogueGateFakeReplies.answers = [ row.fetch('calls').first.fetch('raw_answer') ]
      answer = exchange.character_agent.ask(exchange.character_prompt(kase.fetch('line'))).content
      effect = exchange.send(:npc_actions).apply!(answer.fetch('engine_action'))
      changed = answer.merge('action' => 'Unrelated private text')
      assert_raises(PhysicalDialoguePayload::Refused) { exchange.narrator_prompt(kase.fetch('line'), changed, effect: effect) }
      substituted = Playthrough::NpcAction::Result.new(action: effect.action, status: effect.status, fact: 'Unrelated receipt')
      assert_raises(PhysicalDialoguePayload::Refused) { exchange.narrator_prompt(kase.fetch('line'), answer, effect: substituted) }
      prompt = exchange.narrator_prompt(kase.fetch('line'), answer, effect: effect)
      assert_raises(PhysicalDialoguePayload::Refused) { exchange.narrator_agent.ask(prompt + 'Unapproved appended text') }
      assert_equal 1, DialogueGateFakeReplies.calls
      assert_equal answer, guard.first_answer
    end
  end

  test 'an existing unrelated game or wrong fixture line cannot bind' do
    open_exchange do |guard, exchange, stage|
      other = Playthrough.create!(story: stage.game.story, character: stage.game.character, current_location: stage.room)
      assert other.persisted?
      guard.start!(kase.fetch('id'), 1)
      assert_raises(PhysicalDialoguePayload::Refused) { guard.bind!(exchange, kase.fetch('line')) }
      other.destroy!
      assert_raises(PhysicalDialoguePayload::Refused) { guard.bind!(exchange, 'Read an unrelated player log') }
      assert_equal 0, DialogueGateFakeReplies.calls
    end
  end

  test 'unknown repetitions duplicates and already charged unfinished readings are refused' do
    pair = [ kase.fetch('id'), 1 ]
    [ [ [ kase.fetch('id'), 5 ] ], [ pair, pair ], [ [ 'unknown', 1 ] ] ].each do |allowed|
      assert_raises(PhysicalDialoguePayload::Refused) { PhysicalDialoguePayload::Gate.new(samples: @samples, allowed: allowed) }
    end
    assert_raises(PhysicalDialoguePayload::Refused) { PhysicalDialoguePayload::Gate.new(samples: @samples, allowed: [ pair ], attempted: [ pair ]) }
  end
end
