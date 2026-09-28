require "test_helper"

class EngineSweepExperienceTest < ActiveSupport::TestCase
  test "the player walk reaches injuries and an older promise through the real character prompt" do
    result = EngineSweep.run([ experience_script ]).sole

    assert result.passed?, result.report
  end

  # A DEFECT PLANTED IN THE RUBY REFERENCE LOOP, and the walk on that loop
  # catches it. The sweep walks the Rust engine, where this prompt is built in
  # Rust, so these two walk the Ruby loop by name (`engine: :ruby`).
  test "the walk fails when the character's own condition is omitted" do
    original = Playthrough::Moment.instance_method(:personal_facts)
    Playthrough::Moment.define_method(:personal_facts) do |character|
      original.bind_call(self, character).reject { |text| text.start_with?("Your own condition:") }
    end

    error = assert_raises(EngineSweep::ModelCalled) { EngineSweep.run([ experience_script ], engine: :ruby) }
    assert_includes error.message, "prompt omitted"
    assert_includes error.message, "Your own condition: hurt"
  ensure
    Playthrough::Moment.define_method(:personal_facts, original)
  end

  test "the walk fails when old recollections never reach the character" do
    original = Playthrough::Moment.instance_method(:recollections)
    Playthrough::Moment.define_method(:recollections) { |*_, **_| [] }

    error = assert_raises(EngineSweep::ModelCalled) { EngineSweep.run([ experience_script ], engine: :ruby) }
    assert_includes error.message, "I promise to lend Cal my brass key"
  ensure
    Playthrough::Moment.define_method(:recollections, original)
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
