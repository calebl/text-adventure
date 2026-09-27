require "test_helper"
require_relative "../support/per_step_engine"

# THE COMMITTED DUMPS ARE WHAT THE RUBY ENGINE PLAYS TODAY. Every sweep script
# is played again and compared byte for byte, so an engine change that moves
# any record a script could assert fails here until `bin/rails engine:parity`
# is run and the diff is committed with it. See docs/engine-parity.md.
class EngineParityTest < ActiveSupport::TestCase
  DIRECTORY = Rails.root.join(EngineSweep::Parity::DIRECTORY)

  test "the committed dumps match what the engine plays now" do
    stale = EngineSweep::Parity.files.reject { |name, body| DIRECTORY.join(name).exist? && DIRECTORY.join(name).read == body }

    assert_empty stale.keys, "run `bin/rails engine:parity` and commit the diff; see docs/engine-parity.md"
  end

  test "every file in the directory is a script's dump" do
    expected = EngineSweep.scripts.map { |script| "#{script.name}.json" }.sort

    assert_equal expected, DIRECTORY.children.map { |path| path.basename.to_s }.sort
  end

  test "a dump holds the expectation keys in their order and no others" do
    dump = JSON.parse(DIRECTORY.join("a-thing-can-be-thrown.json").read).dig("steps", 0, "dump")

    assert_equal EngineSweep::Dump::KEYS, dump.keys
    assert_equal EngineSweep::Expectation::KEYS - %w[exits_include exits_exclude], dump.keys
  end

  test "the first divergence names the step and the key" do
    script = EngineSweep::Script.load(EngineSweep::DIRECTORY.join("a-thing-can-be-thrown.yml"))
    golden = EngineSweep::Parity.golden(script)
    moved = golden.deep_dup
    moved[1]["hp"] = -1

    assert_nil EngineSweep::Parity.first_divergence(script, golden, golden)
    divergence = EngineSweep::Parity.first_divergence(script, golden, moved)

    assert_includes divergence, script.steps[1].label
    assert_includes divergence, "hp:"
    assert_includes EngineSweep::Parity.first_divergence(script, golden, golden.first(1)), "has no dump"
  end

  # A subprocess engine that answers with the goldens agrees with them, and is
  # never handed a provider key.
  test "a command engine plays through a subprocess without the provider keys" do
    script = EngineSweep::Script.load(EngineSweep::DIRECTORY.join("a-thing-can-be-thrown.yml"))
    echo = <<~RUBY.squish
      require "json";
      abort "a key reached the engine" if ENV.key?("OPENROUTER_API_KEY") || ENV.key?("TYPESAFE_API_KEY");
      JSON.parse(File.read(#{DIRECTORY.join("#{script.name}.json").to_s.inspect}))["steps"].each { |row| puts row["dump"].to_json }
    RUBY
    engine = EngineSweep::Parity::Command.new("ruby -e #{Shellwords.escape(echo)}")

    ENV["OPENROUTER_API_KEY"], saved = "not-a-key", ENV["OPENROUTER_API_KEY"]
    assert_empty EngineSweep::Parity.diff(engine, scripts: [ script ])
  ensure
    ENV["OPENROUTER_API_KEY"] = saved
  end
end

# THE SHARED-DATABASE CONTRACT, with a per-step engine that is the Ruby engine
# played one step at a time (test/support/per_step_engine.rb). Not transactional:
# the runner's scratch database is a connection of its own, and it has to commit
# for the engine to read it; the suite's database is only read, to copy it.
class EngineParitySharedDatabaseTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  # THE SHARED-DATABASE CONTRACT, with a per-step engine that is the Ruby
  # engine played one step at a time: every script, re-seeds and browser steps
  # included, agrees with the goldens when the runner owns the database.
  test "a per-step engine on a shared database agrees with every golden" do
    engine = EngineSweep::Parity::Command.new("per-step", shared_database: true, launch: PerStepEngine.method(:launch))

    assert_empty EngineSweep::Parity.diff(engine)
  end

  # And once as a real subprocess, on a script with a re-seed in it, so the
  # command line and the environment are the ones the contract names.
  test "a per-step engine runs as a subprocess, one call per typed step, without the provider keys" do
    script = EngineSweep::Script.load(EngineSweep::DIRECTORY.join("reseed-a-played-world.yml"))
    calls = []
    launch = lambda do |environment, *arguments|
      calls << [ environment.slice("ENGINE_STEP", *EngineSweep::Parity::WITHHELD), arguments.drop(3) ]
      Open3.capture2(environment, *arguments)
    end
    engine = EngineSweep::Parity::Command.new("bin/rails runner test/support/per_step_engine.rb",
                                              shared_database: true, launch: launch)

    ENV["OPENROUTER_API_KEY"], saved = "not-a-key", ENV["OPENROUTER_API_KEY"]
    assert_empty EngineSweep::Parity.diff(engine, scripts: [ script ])
    typed = script.steps.reject(&:reseed?)
    assert_equal typed.map { |step| step.index.to_s }, calls.map { |environment, _| environment["ENGINE_STEP"] }
    assert calls.all? { |environment, _| EngineSweep::Parity::WITHHELD.all? { |key| environment.key?(key) && environment[key].nil? } }
    assert_equal typed.map { |step| [ "--database", "--player", step.player, script.path.to_s ] },
                 calls.map { |_, arguments| arguments.values_at(0, 2, 3, 4) }
  ensure
    ENV["OPENROUTER_API_KEY"] = saved
  end

  test "a per-step engine that fails fails the step, and the scratch database is gone afterwards" do
    script = EngineSweep::Script.load(EngineSweep::DIRECTORY.join("a-thing-can-be-thrown.yml"))
    files = []
    launch = lambda do |_environment, *arguments|
      files << arguments[arguments.index("--database") + 1]
      [ "", PerStepEngine::Status.new(3) ]
    end
    engine = EngineSweep::Parity::Command.new("broken", shared_database: true, launch: launch)

    error = assert_raises(EngineSweep::InvalidScript) { engine.play(script) }
    assert_includes error.message, script.steps.first.label
    assert_equal 1, files.size
    refute File.exist?(files.first)
    refute_equal File.expand_path(ActiveRecord::Base.connection_db_config.database), File.expand_path(files.first)
  end
end
