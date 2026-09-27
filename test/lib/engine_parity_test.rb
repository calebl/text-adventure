require "test_helper"

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
