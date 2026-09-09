require "test_helper"

class EngineSweepNoticesTest < ActiveSupport::TestCase
  SCRIPT = "lib/engine_sweep/scripts/hazard-notices-survive-quiet-arrival.yml".freeze

  test "quiet arrival prose still shows one record-derived notice after redelivery" do
    result = EngineSweep.run([ EngineSweep::Script.load(Rails.root.join(SCRIPT)) ]).sole

    assert result.passed?, result.report
  end

  test "an incorrect count of visible notices fails against the actual rendered entry" do
    document = YAML.safe_load_file(Rails.root.join(SCRIPT))
    document.fetch("steps").first.fetch("expect")["shown"] = []
    Tempfile.create([ "notice-sweep", ".yml" ]) do |file|
      file.write(document.to_yaml)
      file.flush
      result = EngineSweep.run([ EngineSweep::Script.load(file.path) ]).sole
      failure = result.failures.sole.unmet

      assert_equal "shown", failure.key
      assert_equal "nothing", failure.expected
      assert_includes failure.actual, "drop on the way from Market into Courtyard"
    end
  end
end
