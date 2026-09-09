# Offline review probe. Reads the checkout in cwd; all database/log/cache artifacts stay in /tmp.
require 'securerandom'
require 'digest'
require 'json'
require 'open3'
tracked = %w[app/models/playthrough/turn.rb app/models/playthrough/command.rb app/jobs/narration_job.rb]
snapshot = lambda do
  { head: Open3.capture2('git', 'rev-parse', 'HEAD').first.strip,
    files: tracked.to_h { |file| [file, Digest::SHA256.file(file).hexdigest] },
    dirty: Open3.capture2('git', 'status', '--porcelain', '--', *tracked).first.lines.map(&:strip) }
end
before_source = snapshot.call
ENV['RAILS_ENV'] = 'test'
ENV['DATABASE_URL'] = "sqlite3:/tmp/gate6-observer-drain-#{SecureRandom.hex(8)}.sqlite3"
ENV['DISABLE_BOOTSNAP'] = '1'
ENV['TA_CHAT_KEEP_TURNS'] = ''
require File.join(Dir.pwd, 'config/application')
Rails.application.config.logger = Logger.new(File::NULL)
Rails.application.initialize!
require File.join(Dir.pwd, 'test/support/fake_agent')
require 'minitest/mock'
# Force the classes under review to load before the trials, then record that boundary.
[Playthrough::Turn, Playthrough::Command, NarrationJob]
loaded_source = snapshot.call
ActiveRecord::Schema.verbose = false
load File.join(Dir.pwd, 'db/schema.rb')
FactoryBot.find_definitions if FactoryBot.factories.count.zero?
include FactoryBot::Syntax::Methods

class ProbeObserverError < StandardError; end
class ProbeEngineError < StandardError; end

checks = []
results = []
[:none, :start, :finish, :engine, :error_observer].each do |fault|
  story = create(:story)
  character = create(:character, story: story, is_protagonist: true, level: 10)
  game = create(:playthrough, :started, story: story, character: character)
  opening = create(:scene, story: story, location: game.current_location)
  game.update!(current_scene: opening)
  create(:item, :lying, location: game.current_location, name: 'red coin')
  Playthrough::Snapshot.new(game).of_the_room!(game.current_location)
  engine_fault = [:engine, :error_observer].include?(fault)
  lines = [engine_fault ? 'take red coin' : '/take red coin', '/drop red coin']
  rows = lines.each_with_index.map { |line, i| Playthrough::Command.accept!(game, line, "command-#{i}") }
  events = []
  error_seen = []
  result = nil
  escaped = nil
  scene_count = Scene.count
  callbacks = {
    on_start: lambda { |line|
      events << ['start', line]
      raise ProbeObserverError, 'start observer unavailable' if fault == :start && events.count { |e| e.first == 'start' } == 1
    },
    on_finish: lambda { |outcome|
      events << ['finish', outcome&.typed]
      raise ProbeObserverError, 'finish observer unavailable' if fault == :finish && events.count { |e| e.first == 'finish' } == 1
    },
    on_error: lambda { |error|
      error_seen << error.class.name
      events << ['error', error.class.name]
      raise ProbeObserverError, 'error observer unavailable' if fault == :error_observer
    }
  }
  agent = engine_fault ? FakeAgent.new(ProbeEngineError.new('classifier failed before an engine action')) :
                         FakeAgent.new('You pick up the red coin.', 'You put down the red coin.')
  begin
    result = BaseAgent.stub(:new, agent) do
      Playthrough::Turn.new(game).play(lines.last, request_token: rows.last.request_token, **callbacks)
    end
  rescue => error
    escaped = error.class.name
  end
  game.reload
  measured = {
    fault: fault, escaped: escaped, error_observed: error_seen,
    statuses: game.commands.order(:id).pluck(:status),
    actions: game.scene_chain.drop(1).map(&:resolved_action),
    scene_delta: Scene.count - scene_count,
    carried: game.carried.map(&:name),
    floor: game.items_lying_in(game.current_location).map(&:name),
    returned: result&.typed, events: events
  }
  if engine_fault
    passed = escaped == 'ProbeEngineError' && error_seen == ['ProbeEngineError'] &&
             measured[:statuses] == %w[failed pending] && measured[:scene_delta] == 0
  else
    passed = escaped.nil? && error_seen.empty? && measured[:statuses] == %w[completed completed] &&
             measured[:actions] == %w[take drop] && measured[:scene_delta] == 2 &&
             measured[:carried].empty? && measured[:floor] == ['red coin'] && result == rows.last.reload.result_scene
  end
  checks << { name: "#{fault}: observer isolation or real failure", passed: passed }
  results << measured

  next unless !engine_fault && measured[:statuses] == %w[completed completed]

  replay_events = []
  count_before_replays = Scene.count
  BaseAgent.stub(:new, ->(*) { raise 'A duplicate must not ask any agent' }) do
    latest = Playthrough::Turn.new(game).play(lines.last, request_token: rows.last.request_token,
      on_start: ->(line) { replay_events << ['start', line] },
      on_finish: ->(outcome) { replay_events << ['finish', outcome&.typed] })
    earlier = Playthrough::Turn.new(game).play(lines.first, request_token: rows.first.request_token,
      on_start: ->(line) { replay_events << ['stale_start', line] },
      on_finish: ->(outcome) { replay_events << ['stale_finish', outcome&.typed] },
      on_error: ->(error) { replay_events << ['stale_error', error.class.name] })
    checks << { name: "#{fault}: latest replay and overtaken suppression", passed:
      replay_events == [['finish', 'drop red coin']] && Scene.count == count_before_replays &&
      latest == rows.last.reload.result_scene && earlier == rows.first.reload.result_scene }
  end
  results << { fault: "#{fault}_replay", events: replay_events, scene_delta: Scene.count - count_before_replays }
end

after_source = snapshot.call
output = {
  source_before: before_source, source_loaded: loaded_source, source_after: after_source,
  stable_sources: before_source == loaded_source && loaded_source == after_source,
  database: ENV.fetch('DATABASE_URL'), checks: checks, results: results
}
puts JSON.pretty_generate(output)
exit(checks.all? { |check| check[:passed] } && output[:stable_sources] ? 0 : 1)
