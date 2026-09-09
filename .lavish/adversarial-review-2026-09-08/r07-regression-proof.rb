require "test_helper"

# Restore just the two R07 mistakes inside this test process. Production
# source and the recovery fallback remain intact; the new tests must reject
# the old battlefield-as-current-scene and previous-scene-as-origin behavior.
Playthrough::Fight.prepend(Module.new do
  def close!
    battlefield = room
    original = Scene.method(:create!)
    Scene.stub(:create!, ->(attributes) {
      original.call(attributes.merge(location: battlefield, characters: playthrough.cast_in(battlefield)))
    }) { super }
  end
end)
Scene::Generator.prepend(Module.new do
  def journey_minutes
    edge = LocationConnection.find_by(location: previous_scene.location, connected_location: location)
    return LocationConnection::DISTANCES.fetch("adjacent") if edge.nil?

    LocationConnection.travel_minutes(edge.distance, edge.travel_method) || LocationConnection::DISTANCES.fetch("adjacent")
  end
end)

require Rails.root.join("test/models/playthrough/fleeing_journey_test")
require Rails.root.join("test/lib/engine_sweep_elapsed_test")
