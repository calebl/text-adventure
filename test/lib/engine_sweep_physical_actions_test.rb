require "test_helper"

class EngineSweepPhysicalActionsTest < ActiveSupport::TestCase
  CONSUMPTION = "consumption-survives-interruption-and-revisit".freeze
  PASSAGES = "opening-a-door-is-not-crossing-it".freeze

  test "a player consumes once across interruption, later movement and a revisit" do
    result = EngineSweep.run([ script(CONSUMPTION) ]).sole

    assert result.passed?, result.report
  end

  test "a player opens a real door and can return without opening it for another game" do
    result = EngineSweep.run([ script(PASSAGES) ]).sole

    assert result.passed?, result.report
  end

  test "the consumption walk fails if the physical effect leaves the item available" do
    original = Playthrough::PhysicalAction.instance_method(:spend!)
    Playthrough::PhysicalAction.define_method(:spend!) { |*_args| nil }
    result = EngineSweep.run([ prefix(CONSUMPTION, 4) ]).sole

    assert_not result.passed?
    assert result.failures.any? { |failure| failure.unmet.key == "carrying" }, result.report
  ensure
    Playthrough::PhysicalAction.define_method(:spend!, original)
    Playthrough::PhysicalAction.send(:private, :spend!)
  end

  test "the revisit walk fails if a snapshot restores a spent room item" do
    original = Item::Snapshot.instance_method(:of_the_room!)
    Item::Snapshot.define_method(:of_the_room!) do |location|
      result = original.bind_call(self, location)
      if location&.name == "Workshop"
        playthrough.items.where(disposition: "consumed").includes(:template).each do |item|
          next unless item.template.location_id == location.id

          item.update!(disposition: "intact", location: location)
        end
      end
      result
    end
    result = EngineSweep.run([ prefix(CONSUMPTION, 6) ]).sole

    assert_not result.passed?
    assert result.failures.any? { |failure| failure.unmet.key == "here" }, result.report
  ensure
    Item::Snapshot.define_method(:of_the_room!, original)
  end

  test "the return walk fails if opening only changes the outward passage" do
    original = Playthrough::Passage.method(:open!)
    Playthrough::Passage.define_singleton_method(:open!) do |game, edge, **options|
      result = original.call(game, edge, **options)
      reverse = LocationConnection.find_by(location: edge.connected_location, connected_location: edge.location)
      where(playthrough: game, location_connection: reverse).delete_all
      result
    end
    # The barrier refuses the move before arrival. The walk's exact provider
    # sequence must fail rather than silently skipping its declared arrival.
    error = assert_raises(EngineSweep::ModelCalled) { EngineSweep.run([ prefix(PASSAGES, 8) ]) }

    assert_includes error.message, 'expected ["arrival"] rendering calls, got []'
  ensure
    Playthrough::Passage.define_singleton_method(:open!, original)
  end

  private

  def script(name)
    EngineSweep::Script.load(Rails.root.join("lib/engine_sweep/scripts/#{name}.yml"))
  end

  def prefix(name, length)
    original = script(name)
    EngineSweep::Script.new(path: original.path, story: original.story, steps: original.steps.first(length), why: original.why)
  end
end
