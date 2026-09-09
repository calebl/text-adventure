require "test_helper"

class EngineSweepRealizationTest < ActiveSupport::TestCase
  test "a failed first entry resumes through the browser without repaying detail" do
    result = EngineSweep.run([ recovery_script ]).sole

    assert result.passed?, result.report
  end

  test "a realization allowance cannot authorize rewriting an already written room" do
    document = {
      "story" => "The Unfinished Workshop",
      "steps" => [ {
        "type" => "/move Workshop",
        "browser" => { "token" => "wrong-room", "realizes" => "Market",
                       "replies" => [ { "purpose" => "location", "unavailable" => true } ] }
      } ]
    }
    Tempfile.create([ "realization-sweep", ".yml" ]) do |file|
      file.write(document.to_yaml)
      file.flush
      error = assert_raises(EngineSweep::InvalidScript) do
        EngineSweep.run([ EngineSweep::Script.load(file.path) ])
      end
      assert_includes error.message, "realizes must name a stub"
    end
  end

  test "newly generated cast remains protected against later changes to the world layer" do
    result = with_browser_fault do |game, step|
      next unless step.browser.fetch("token") == "revisit"

      game.story.characters.find_by!(fullname: "Sella Reed").increment!(:level)
    end

    assert_includes result.report, "stat_blocks_unmoved"
    assert_includes result.report, "Sella Reed"
  end

  test "a named realization never accepts changes to an existing world character" do
    result = with_browser_fault do |game, step|
      next unless step.browser.fetch("token") == "first-entry"

      game.story.characters.find_by!(fullname: "Cal").update!(location: game.story.locations.find_by!(name: "Workshop"))
    end

    assert_includes result.report, "cast_unmoved"
    assert_includes result.report, "Cal"
  end

  private

  def recovery_script
    EngineSweep::Script.load(Rails.root.join("lib/engine_sweep/scripts/unfinished-realization-resumes-on-entry.yml"))
  end

  def with_browser_fault(&fault)
    original = EngineSweep::BrowserTurn.instance_method(:run)
    EngineSweep::BrowserTurn.define_method(:run) do |step|
      original.bind_call(self, step).tap { fault.call(@mechanics.playthrough, step) }
    end
    EngineSweep.run([ recovery_script ]).sole
  ensure
    EngineSweep::BrowserTurn.define_method(:run, original)
  end
end
