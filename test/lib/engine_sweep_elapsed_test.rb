require "test_helper"

class EngineSweepElapsedTest < ActiveSupport::TestCase
  test "a browser escape followed by a longer walk uses each actual edge and charges once" do
    script = EngineSweep::Script.load(Rails.root.join("lib/engine_sweep/scripts/fleeing-then-a-longer-journey.yml"))
    result = EngineSweep.run([ script ]).sole

    assert result.passed?, result.report
  end

  test "an incorrect elapsed expectation fails with the measured clock difference" do
    document = <<~YAML
      story: A Turn at the Gate
      steps:
      - type: /move Courtyard
        browser: {token: escape, fail: arrival}
        expect:
          elapsed_minutes: 99
    YAML
    Tempfile.create([ "elapsed-sweep", ".yml" ]) do |file|
      file.write(document)
      file.flush
      result = EngineSweep.run([ EngineSweep::Script.load(file.path) ]).sole
      failure = result.failures.sole.unmet

      assert_equal "elapsed_minutes", failure.key
      assert_equal "99", failure.expected
      assert_equal "6.0", failure.actual
    end
  end
end
