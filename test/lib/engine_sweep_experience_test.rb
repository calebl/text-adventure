require "test_helper"

class EngineSweepExperienceTest < ActiveSupport::TestCase
  test "the player walk reaches injuries and an older promise through the real character prompt" do
    result = EngineSweep.run([ experience_script ]).sole

    assert result.passed?, result.report
  end

  test "malformed prompt expectations cannot silently pass" do
    document = { "story" => "A Turn at the Gate", "steps" => [ {
      "type" => "/talk Maren", "browser" => { "token" => "bad", "replies" => [ {
        "purpose" => "character", "content" => {}, "prompt_includes" => "a string instead of a list"
      } ] }
    } ] }
    Tempfile.create([ "experience-sweep", ".yml" ]) do |file|
      file.write(document.to_yaml)
      file.flush

      assert_raises(EngineSweep::InvalidScript) { EngineSweep::Script.load(file.path) }
    end
  end

  private

  def experience_script
    EngineSweep::Script.load(Rails.root.join("lib/engine_sweep/scripts/npc-experience-survives-small-talk.yml"))
  end
end
