require "test_helper"

class Playthrough::TurnRecoveryTest < ActiveSupport::TestCase
  setup do
    story = create(:story)
    character = create(:character, story: story, is_protagonist: true, level: 10)
    @game = create(:playthrough, :started, story: story, character: character)
    @opening = create(:scene, story: @game.story, location: @game.current_location)
    @game.update!(current_scene: @opening)
  end

  test "a failed pickup renderer still records the turn and the enemy response once" do
    item = lying_here(@game, @game.current_location, name: "red coin")
    enemy = create(:character, story: @game.story, location: @game.current_location, hostile: true)
    before = @game.story_now
    failure = FakeAgent.new(RuntimeError.new("provider unavailable"))
    scene = BaseAgent.stub(:new, failure) do
      Playthrough::Turn.new(@game).play("/take red coin", request_token: "pickup")
    end

    assert_includes @game.reload.carried, item
    assert_equal @opening, scene.previous_scene
    assert_predicate scene, :engine_authored?
    assert_equal "take", scene.resolved_action
    assert_instance_of RuntimeError, scene.rendering_error
    assert_equal "provider unavailable", scene.rendering_error.message
    assert_operator @game.story_now, :>, before
    assert_equal 1, @game.blows.where(attacker: enemy).count
    assert_equal "completed", @game.commands.find_by!(request_token: "pickup").status

    no_calls = ->(*) { flunk "a redelivery must not ask a model" }
    assert_no_difference [ -> { Scene.count }, -> { @game.blows.count } ] do
      repeated = BaseAgent.stub(:new, no_calls) do
        Playthrough::Turn.new(@game).play("/take red coin", request_token: "pickup")
      end
      assert_equal scene, repeated
    end
  end

  # TWO LINES ACCEPTED WHILE A TURN RAN, AND THE JOBS RACE. `config/queue.yml`
  # runs three worker threads and flock is not FIFO, so the move's job can reach
  # the lock first. If it played its own line first the party would be on the
  # quay before the coin was picked up, and the pickup would then resolve
  # nothing -- both submissions reporting success over a lost act.
  test "a later job that reaches the lock first still plays the earlier line first" do
    item = lying_here(@game, @game.current_location, name: "red coin")
    destination = create(:location, story: @game.story, name: "Quay")
    create(:location_connection, location: @game.current_location, connected_location: destination,
                                 distance: "adjacent")
    Playthrough::Command.accept!(@game, "/take red coin", "pickup")
    started = []
    agent = FakeAgent.new("You close your hand around the red coin.",
                          { "description" => "The quay opens out ahead of you.", "summary" => "They reach the quay." })

    outcome = BaseAgent.stub(:new, agent) do
      Playthrough::Turn.new(@game).play("/move Quay", request_token: "crossing",
                                        on_start: ->(line) { started << line })
    end

    assert_equal [ "/take red coin", "/move Quay" ], started
    assert_includes @game.reload.carried, item, "the earlier line resolved in the room it was typed in"
    assert_equal destination, @game.current_location
    assert_equal destination, outcome.location, "and the caller is handed its own submission's turn"
    assert_equal [ "take", "move" ], @game.scene_chain.drop(1).map(&:resolved_action)
    assert_equal %w[completed completed], @game.commands.order(:id).pluck(:status)
  end

  test "the overtaken job finds its own line already played and takes no second turn" do
    lying_here(@game, @game.current_location, name: "red coin")
    Playthrough::Command.accept!(@game, "/take red coin", "pickup")
    agent = FakeAgent.new("You close your hand around the red coin.")
    played = BaseAgent.stub(:new, agent) do
      Playthrough::Turn.new(@game).play("/take red coin", request_token: "pickup")
    end

    assert_no_difference [ -> { Scene.count }, -> { @game.blows.count } ] do
      repeated = BaseAgent.stub(:new, ->(*) { flunk "a redelivery must not ask a model" }) do
        Playthrough::Turn.new(@game).play("/take red coin", request_token: "pickup")
      end
      assert_equal played, repeated
    end
  end

  test "an arrival renderer failure completes its charged crossing and a redelivery cannot charge twice" do
    destination = create(:location, story: @game.story, name: "Quay")
    create(:location_connection, location: @game.current_location, connected_location: destination,
                                 distance: "adjacent", hazard: "drop", hazard_die: 4)
    failure = FakeAgent.new(RuntimeError.new("provider unavailable"))
    scene = BaseAgent.stub(:new, failure) do
      Playthrough::Turn.new(@game).play("/move Quay", request_token: "crossing")
    end

    assert_equal destination, @game.reload.current_location
    assert_equal scene, @game.current_scene
    assert_predicate scene, :engine_authored?
    assert_instance_of RuntimeError, scene.rendering_error
    assert_equal 1, @game.tolls.count
    assert_equal scene.id, @game.tolls.first.scene_id
    assert_includes scene.description, destination.name

    assert_no_difference [ -> { Scene.count }, -> { @game.tolls.count } ] do
      BaseAgent.stub(:new, ->(*) { flunk "a completed crossing cannot call a model" }) do
        assert_equal scene, Playthrough::Turn.new(@game).play("/move Quay", request_token: "crossing")
      end
    end
  end

  test "a blank pickup rendering also finishes the committed action" do
    item = lying_here(@game, @game.current_location, name: "red coin")
    scene = BaseAgent.stub(:new, FakeAgent.new("")) do
      Playthrough::Turn.new(@game).play("/take red coin")
    end

    assert_includes @game.reload.carried, item
    assert_predicate scene, :engine_authored?
    assert_instance_of BaseAgent::UnusableResponseError, scene.rendering_error
    assert_equal "take red coin", scene.typed
    assert_equal @opening, scene.previous_scene
  end

  test "an item fallback leaves environmental facts untold when its prose never included them" do
    lying_here(@game, @game.current_location, name: "red coin")
    toll = create(:playthrough_toll, playthrough: @game)
    BaseAgent.stub(:new, FakeAgent.new(RuntimeError.new("provider unavailable"))) do
      Playthrough::Turn.new(@game).play("/take red coin")
    end

    assert_nil toll.reload.scene_id
  end

  test "a partial stream without a committed action cannot leave a scene behind on failure" do
    agent = FakeAgent.new("A sentence that never finished.")
    assert_raises(RuntimeError) do
      BaseAgent.stub(:new, agent) do
        Scene::Narrator.new(@game).narrate("look") { raise "broadcast failed" }
      end
    end
    assert_equal @opening, @game.reload.current_scene
  end

  test "failed attribution cannot skip the world's response to a persisted pickup" do
    lying_here(@game, @game.current_location, name: "red coin")
    enemy = create(:character, story: @game.story, location: @game.current_location, hostile: true)
    agent = FakeAgent.new("You pick up the coin.")
    agent.define_singleton_method(:attribute_to!) { |_scene| raise "audit database unavailable" }

    scene = BaseAgent.stub(:new, agent) { Playthrough::Turn.new(@game).play("/take red coin") }

    assert_equal "take", scene.resolved_action
    assert_equal 1, @game.blows.where(attacker: enemy).count
    assert_equal scene, @game.reload.current_scene
  end

  test "failed arrival streaming cannot skip the enemy response after the player moved" do
    enemy = create(:character, story: @game.story, location: @game.current_location, hostile: true)
    destination = create(:location, story: @game.story, name: "Quay")
    create(:location_connection, location: @game.current_location, connected_location: destination, distance: "adjacent")
    agent = FakeAgent.new({ "description" => "You reach the quay.", "summary" => "Arrived at the quay." })
    BaseAgent.stub(:new, agent) do
      Playthrough::Turn.new(@game).play("/move Quay", request_token: "arrive") { raise "broadcast unavailable" }
    end

    assert_equal destination, @game.reload.current_location
    assert_equal 1, @game.blows.where(attacker: enemy).count
    assert_predicate @game.commands.find_by!(request_token: "arrive"), :completed?
  end

  test "a crisis pickup completes its state and preserves the app notice on redelivery" do
    lying_here(@game, @game.current_location, name: "red coin")
    scene = BaseAgent.stub(:new, FakeAgent.new(BaseAgent::CrisisResponseError)) do
      Playthrough::Turn.new(@game).play("/take red coin", request_token: "pickup")
    end
    assert_predicate scene, :engine_authored?
    assert scene.safety_notice
    turn = Playthrough::Turn.new(@game)
    turn.play("/take red coin", request_token: "pickup")
    assert turn.safety_notice
  end
end
