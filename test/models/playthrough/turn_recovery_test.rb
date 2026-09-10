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

  # THE DRAIN'S TWO ANSWERS TO A FAILED PREDECESSOR. A line that failed at the
  # classifier wrote nothing a later line owes a finish to, so the later line
  # plays alone and the failure is left where the page can offer it. A line that
  # failed AFTER taking something is finished first, because the closed sets the
  # next line resolves against already include what it took.
  test "a failure before any effect is stepped past and a failure after one is finished first" do
    coin = lying_here(@game, @game.current_location, name: "red coin")
    started = []
    BaseAgent.stub(:new, FakeAgent.new(RuntimeError.new("classifier unavailable"))) do
      assert_raises(RuntimeError) do
        Playthrough::Turn.new(@game).play("open the ledger", request_token: "unread")
      end
    end
    unread = @game.commands.find_by!(request_token: "unread")
    assert_equal "failed", unread.status
    assert_predicate unread, :recoverable?
    assert_not_predicate unread, :blocks_later?

    BaseAgent.stub(:new, FakeAgent.new("You take the red coin.")) do
      Playthrough::Turn.new(@game.reload).play("/take red coin", request_token: "pickup",
                                               on_start: ->(line) { started << line })
    end
    assert_equal [ "/take red coin" ], started, "an unread line is not replayed by the next one"
    assert_equal "failed", unread.reload.status
    assert_predicate unread, :overtaken?
    assert_includes @game.reload.carried, coin

    original = Playthrough::Command::Journal.method(:commit)
    failing = lambda do |key, &work|
      value = original.call(key, &work)
      raise ActiveRecord::StatementInvalid, "database unavailable" if key == "narrated"
      value
    end
    BaseAgent.stub(:new, FakeAgent.new("You put the red coin down.")) do
      assert_raises(ActiveRecord::StatementInvalid) do
        Playthrough::Command::Journal.stub(:commit, failing) do
          Playthrough::Turn.new(@game.reload).play("/drop red coin", request_token: "putdown")
        end
      end
    end
    putdown = @game.commands.find_by!(request_token: "putdown")
    assert_equal "failed", putdown.status
    assert_predicate putdown, :blocks_later?
    assert_equal putdown, Playthrough::Command.resume_target(@game)

    started.clear
    BaseAgent.stub(:new, FakeAgent.new("You take the red coin.")) do
      Playthrough::Turn.new(@game.reload).play("/take red coin", request_token: "again",
                                               on_start: ->(line) { started << line })
    end
    assert_equal [ "/drop red coin", "/take red coin" ], started, "a dropped coin is finished before it is taken again"
    assert_equal %w[failed completed completed completed], @game.commands.order(:id).pluck(:status)
    assert_equal %w[take drop take], @game.reload.scene_chain.drop(1).map(&:resolved_action)
    assert_includes @game.carried, coin
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
  %w[take narrated scene_facts told_tolls riposte room_hazard arc fight_closed].each do |checkpoint|
    test "interruption after #{checkpoint} finishes one pickup and one enemy reply" do
      coin = lying_here(@game, @game.current_location, name: "red coin")
      enemy = create(:character, story: @game.story, location: @game.current_location, hostile: true)
      agent = FakeAgent.new("You take the red coin.")
      original = Playthrough::Command::Journal.method(:commit)
      interrupt = lambda do |key, &work|
        value = original.call(key, &work)
        raise Interrupt, "worker stopped" if key == checkpoint
        value
      end
      BaseAgent.stub(:new, agent) do
        assert_raises(Interrupt) do
          Playthrough::Command::Journal.stub(:commit, interrupt) do
            Playthrough::Turn.new(@game).play("/take red coin", request_token: "interrupted")
          end
        end
        Playthrough::Turn.new(@game.reload).play("/take red coin", request_token: "interrupted")
      end
      assert_includes @game.reload.carried, coin
      assert_equal 1, @game.blows.where(attacker: enemy).count
      assert_equal [ "take" ], @game.scene_chain.drop(1).map(&:resolved_action)
      assert_predicate @game.commands.find_by!(request_token: "interrupted"), :completed?
      assert_nil Thread.current[:turn_journal]
    end
  end

  test "a failed receipt rolls back the item effect and can finish after repair" do
    coin = lying_here(@game, @game.current_location, name: "red coin")
    original = Playthrough::Command::Journal.instance_method(:save)
    failure = lambda do |journal, key, value|
      raise ActiveRecord::StatementInvalid, "receipt unavailable" if key == "take"
      original.bind_call(journal, key, value)
    end
    Playthrough::Command::Journal.define_method(:save) { |key, value| failure.call(self, key, value) }
    assert_raises(ActiveRecord::StatementInvalid) do
      Playthrough::Turn.new(@game).play("/take red coin", request_token: "write-failed")
    end
    assert_equal @game.current_location, coin.reload.location
    Playthrough::Command::Journal.define_method(:save, original)
    BaseAgent.stub(:new, FakeAgent.new("You take the red coin.")) do
      Playthrough::Turn.new(@game.reload).play("/take red coin", request_token: "write-failed")
    end
    assert_includes @game.reload.carried, coin
  ensure
    Playthrough::Command::Journal.define_method(:save, original)
  end
  %w[arrival_cost arrival moved riposte].each do |checkpoint|
    test "interruption after #{checkpoint} charges one crossing and reaches its destination" do
      origin = @game.current_location
      destination = create(:location, story: @game.story, name: "Quay")
      create(:location_connection, location: origin, connected_location: destination,
                                   distance: "adjacent", hazard: "drop", hazard_die: 4)
      enemy = create(:character, story: @game.story, location: origin, hostile: true)
      answer = { "description" => "You reach the quay.", "summary" => "You arrived." }
      agent = FakeAgent.new(answer)
      original = Playthrough::Command::Journal.method(:commit)
      stop = lambda do |key, &work|
        result = original.call(key, &work)
        raise Interrupt if key == checkpoint
        result
      end
      BaseAgent.stub(:new, agent) do
        assert_raises(Interrupt) do
          Playthrough::Command::Journal.stub(:commit, stop) do
            Playthrough::Turn.new(@game).play("/move Quay", request_token: "crossing")
          end
        end
        Playthrough::Turn.new(@game.reload).play("/move Quay", request_token: "crossing")
      end
      assert_equal destination, @game.reload.current_location
      assert_equal 1, @game.tolls.count
      assert_equal 1, @game.blows.where(attacker: enemy).count
      assert_equal 1, @game.scene_chain.count { |scene| scene.resolved_action == "move" }
      assert_predicate @game.commands.find_by!(request_token: "crossing"), :completed?
    end
  end

  test "a resumed conversation reuses its decision and preserves the applied gift receipt" do
    keeper = create(:character, story: @game.story, location: @game.current_location,
                                fullname: "Keeper", nickname: "Keeper")
    template = create(:item, character: keeper, name: "brass key")
    Playthrough::Snapshot.new(@game).of_the_room!(@game.current_location)
    key = @game.items.find_by!(template: template)
    reaction = { "pre_thought" => "They need my help.", "pre_feeling" => "concerned",
                 "action" => "I give them my key.", "post_feeling" => "hopeful",
                 "post_thought" => "They can open it now.", "inner_resolution" => "I will wait here.",
                 "engine_action" => "give:#{key.id}" }
    agent = FakeAgent.new(reaction, "Keeper gives you the brass key.")
    original = Playthrough::Command::Journal.method(:commit)
    stop = lambda do |name, &work|
      value = original.call(name, &work)
      raise Interrupt if name == "character_effect"
      value
    end
    BaseAgent.stub(:new, agent) do
      assert_raises(Interrupt) do
        Playthrough::Command::Journal.stub(:commit, stop) do
          Playthrough::Turn.new(@game).play("/talk Keeper", request_token: "gift")
        end
      end
      assert_includes @game.reload.carried, key
      scene = Playthrough::Turn.new(@game.reload).play("/talk Keeper", request_token: "gift")
      interaction = scene.interactions.sole
      assert_equal "applied", interaction.action_status
      assert_equal "give:#{key.id}", interaction.engine_action
      assert_equal "I give them my key.", interaction.action
    end
    assert_equal 2, agent.prompts.size, "one decision and one rendering, despite the restart"
    assert_equal keeper, template.reload.character
  end
  test "a setup notice survives interruption and completed redelivery without provider details" do
    lying_here(@game, @game.current_location, name: "red coin")
    original = Playthrough::Command::Journal.method(:commit)
    stop = lambda do |name, &work|
      value = original.call(name, &work)
      raise Interrupt if name == "narrated"
      value
    end
    BaseAgent.stub(:new, FakeAgent.new(BaseAgent::NoModelConfiguredError.new("private provider detail"))) do
      assert_raises(Interrupt) do
        Playthrough::Command::Journal.stub(:commit, stop) do
          Playthrough::Turn.new(@game).play("/take red coin", request_token: "no-model")
        end
      end
    end
    2.times do
      BaseAgent.stub(:new, ->(*) { flunk "the saved scene needs no model" }) do
        scene = Playthrough::Turn.new(@game.reload).play("/take red coin", request_token: "no-model")
        assert_equal Playthrough::SetupNotice::COMPLETED, Playthrough::SetupNotice.for(scene.rendering_error)
      end
    end
    assert_not_includes @game.commands.sole.journal.to_json, "private provider detail"
  end
end
