require "test_helper"

# THE REAL EXTENSION, when it is built (`bin/rails engine:build`); skipped
# otherwise, so the default suite needs no Rust toolchain. CI's Rust job builds
# it and runs this file beside `bin/rails engine:rust_gates`.
class RustEngineExtensionTest < ActiveSupport::TestCase
  # The engine reads what Ruby committed, on scratch copies of this database,
  # so nothing here may sit inside the suite's transaction.
  self.use_transactional_tests = false

  setup do
    skip "the Rust engine's extension is not built (bin/rails engine:build)" if Playthrough::RustEngine.extension.nil?
  end

  test "it opens this schema" do
    database = File.expand_path(ApplicationRecord.connection_db_config.database, Rails.root)
    answer = JSON.parse(RenderedStep.play(database, 0, "/look", nil))

    assert_equal "no_such_playthrough", answer.dig("error", "kind"), answer.inspect
    assert_operator ActiveRecord::Base.connection_pool.migration_context.current_version.to_s, :>=, RenderedStep::SCHEMA_VERSION
  end

  test "every failure is an answer, never an exception or a panic" do
    missing = JSON.parse(RenderedStep.submit("/nonexistent/game.sqlite3", 1, "/look", "t", "{}"))
    assert_equal "database", missing.dig("error", "kind")

    garbled = JSON.parse(RenderedStep.submit("/nonexistent/game.sqlite3", 1, "/look", "t", "not json"))
    assert_equal "panicked", garbled.dig("error", "kind")

    assert_equal "database", JSON.parse(RenderedStep.play("/nonexistent/game.sqlite3", 1, "/look", nil)).dig("error", "kind")
  end

  test "a script walked on the Rust engine passes every gate" do
    script = EngineSweep.scripts.find { |candidate| candidate.name == "a-thing-can-be-thrown" }

    assert_equal [ [] ], EngineSweep::RustGates.check([ script ]).map(&:problems)
  end

  test "a newer schema that changes a table the engine writes is refused in the engine's words" do
    script = EngineSweep.scripts.find { |candidate| candidate.name == "a-thing-can-be-thrown" }
    before = Playthrough::RustEngine.failures.fetch("schema_changed", 0)
    finished = []

    Dir.mktmpdir do |directory|
      file = File.join(directory, "newer.sqlite3")
      EngineSweep::Parity.copy_database!(file)
      engine = EngineSweep::Parity::InProcess.new(:rust)
      error = assert_raises(Playthrough::RustEngine::EngineError) do
        engine.on_file(file) do
          walk = EngineSweep::Walk.new(script)
          walk.prepare!
          ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('99990101000000')")
          # A trigger on a table the engine writes, which it would not know fires.
          ActiveRecord::Base.connection.execute(<<~SQL)
            CREATE TRIGGER a_newer_rule AFTER INSERT ON playthrough_commands BEGIN SELECT 1; END
          SQL
          game = walk.game_of(script.steps.first.player)
          Playthrough::RustEngine.replaying([]) do
            Playthrough::Session.new(game).play("/look", request_token: "newer-schema", on_finish: ->(ending) { finished << ending })
          end
        end
      end

      assert_equal "schema_changed", error.kind
    end
    assert_match "a_newer_rule", finished.sole.error
    assert_equal before + 1, Playthrough::RustEngine.failures["schema_changed"]
  end
end
