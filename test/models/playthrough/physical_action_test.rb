require "test_helper"

class Playthrough::PhysicalActionTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @player = create(:character, :protagonist, story: @story, level: 10, strength: 12)
    @game = create(:playthrough, :started, story: @story, character: @player)
    @opening = create(:scene, story: @story, location: @game.current_location)
    @game.update!(current_scene: @opening)
    @actions = Playthrough::PhysicalAction.new(@game)
  end

  test "drinking heals once and leaves a spent copy which cannot respawn" do
    potion = carried("healing draught", use_kind: "healing")
    Playthrough::Turn.new(@game).harm!(@player, 10)
    before = @game.condition.hp
    scene = play("/drink healing draught", token: "dose")

    assert_equal before + Item::HEALING_POINTS, @game.condition.hp
    assert_equal "consumed", potion.reload.disposition
    assert_not_includes @game.carried, potion
    assert_equal "use", scene.resolved_action
    assert_equal potion, scene.acted_on
    assert_equal "intact", potion.template.reload.disposition
    Item::Snapshot.new(@game).of_the_room!(@game.current_location)
    assert_equal 1, @game.items.where(template: potion.template).count

    BaseAgent.stub(:new, ->(*) { flunk "completed redelivery must make no model call" }) do
      assert_equal scene, Playthrough::Turn.new(@game.reload).play("/drink healing draught", request_token: "dose")
    end
    assert_equal before + Item::HEALING_POINTS, @game.condition.hp
  end

  test "consumption never raises health past its maximum and ordinary food does not heal" do
    potion = carried("draught", use_kind: "healing")
    apple = carried("apple", use_kind: "food")
    max = @game.condition.hp
    @actions.apply!(@actions.choices.find { |choice| choice.item == potion })
    assert_equal max, @game.condition.hp
    Playthrough::Turn.new(@game).harm!(@player, 5)
    @actions.apply!(@actions.choices.find { |choice| choice.kind == "consume" && choice.item == apple })
    assert_equal max - 5, @game.condition.hp
  end

  test "burning requires an actual combustible target and a carried firestarter" do
    paper = carried("note", combustible: true)
    stone = carried("stone")
    assert_empty @actions.choices.select { |choice| choice.kind == "burn" }
    lighter = carried("tinderbox", use_kind: "firestarter")
    choice = @actions.choices.find { |row| row.kind == "burn" }
    assert_equal paper, choice.item
    assert_equal lighter, choice.tool
    assert_equal "applied", @actions.apply!(choice).status
    assert_equal "burned", paper.reload.disposition
    assert_includes @game.carried, lighter
    assert_includes @game.carried, stone
    assert_equal "rejected", @actions.apply!(choice).status
    assert_equal "intact", paper.template.reload.disposition
  end

  test "a stale or foreign physical choice writes nothing" do
    apple = carried("apple", use_kind: "food")
    choice = @actions.choices.find { |row| row.kind == "consume" }
    other = create(:playthrough, story: @story, character: @player)
    assert_equal "rejected", Playthrough::PhysicalAction.new(other).apply!(choice).status
    apple.update!(location: @game.current_location)
    assert_equal "rejected", @actions.apply!(choice).status
    assert_equal "intact", apple.reload.disposition
  end

  test "the matching key opens both directions without moving the player or changing another game" do
    key = carried("brass key", use_kind: "key")
    wrong = carried("iron key", use_kind: "key")
    door, back = doorway("keyed", key: key.template)
    other = create(:playthrough, story: @story, character: @player, current_location: @game.current_location)
    here = @game.current_location
    choices = @actions.choices.select { |choice| choice.kind == "unlock" }
    assert_equal [ key ], choices.map(&:tool)
    assert_not_includes choices.map(&:tool), wrong

    scene = play("/unlock Courtyard with brass key")
    assert_equal "use", scene.resolved_action
    assert_equal here, @game.reload.current_location
    assert door.open_for?(@game)
    assert back.open_for?(@game)
    assert_not door.open_for?(other)
    assert_equal "keyed", door.reload.barrier
    assert_includes @game.carried, key
  end

  test "closed passages reject movement and throwing without spending a turn" do
    door, = doorway("jammed")
    carried("stone")
    BaseAgent.stub(:new, ->(*) { flunk "closed passage needs no model" }) do
      [ "/go Courtyard", "/throw stone at Courtyard" ].each do |line|
        result = Playthrough::Turn.new(@game).play(line)
        assert_instance_of Playthrough::Refusal, result
        assert_match(/jammed/, result.text)
      end
    end
    assert_equal @opening, @game.reload.current_scene
    assert_not door.open_for?(@game)
  end

  test "prying uses the ability kernel and a failed roll leaves the gate closed" do
    lever = carried("lever", use_kind: "lever")
    door, = doorway("jammed")
    choice = @actions.choices.find { |row| row.kind == "pry" }
    @player.update!(strength: 3)
    failure = @player.check(:strength, rng: Random.new(1))
    assert_not failure.passed?
    Playthrough::Turn.stub(:new, Struct.new(:answer) { def check(*) = answer }.new(failure)) do
      assert_equal "failed", @actions.apply!(choice).status
    end
    assert_not door.open_for?(@game)
    assert_includes @game.carried, lever
  end

  test "an interrupted consumed item finishes before the next action and is not consumed twice" do
    potion = carried("draught", use_kind: "healing")
    coin = carried("coin")
    Playthrough::Turn.new(@game).harm!(@player, 15)
    before = @game.condition.hp
    original = Playthrough::Command::Journal.method(:commit)
    interrupt = lambda do |key, &work|
      value = original.call(key, &work)
      raise Interrupt if key == "physical_effect"
      value
    end
    assert_raises(Interrupt) do
      Playthrough::Command::Journal.stub(:commit, interrupt) do
        Playthrough::Turn.new(@game).play("/drink draught", request_token: "dose")
      end
    end
    assert_equal "consumed", potion.reload.disposition
    assert_equal before + Item::HEALING_POINTS, @game.condition.hp
    started = []
    BaseAgent.stub(:new, FakeAgent.new("You finish your drink.", "You set the coin down.")) do
      Playthrough::Turn.new(@game.reload).play("/drop coin", request_token: "later", on_start: ->(line) { started << line })
    end
    assert_equal [ "/drink draught", "/drop coin" ], started
    assert_equal before + Item::HEALING_POINTS, @game.condition.hp
    assert_equal @game.current_location, coin.reload.location
    assert_equal %w[completed completed], @game.commands.order(:id).pluck(:status)
  end

  test "an NPC can accept only the item actually offered by this player" do
    npc = create(:character, story: @story, location: @game.current_location)
    apple = carried("apple", use_kind: "food")
    coin = carried("coin")
    offered = Playthrough::NpcAction.new(@game, npc, offered_item: apple)
    assert offered.choices.key?("accept:#{apple.id}")
    assert_not offered.choices.key?("accept:#{coin.id}")
    assert_equal "none", offered.apply!("none").status
    assert_includes @game.carried, apple
    assert_equal "applied", offered.apply!("accept:#{apple.id}").status
    assert_includes @game.items_held_by(npc), apple
    assert_not_includes @game.carried, apple
    assert_equal "rejected", offered.apply!("accept:#{apple.id}").status
    assert_equal "rejected", offered.apply!("accept:#{coin.id}").status
  end

  test "plain language dispatches the classifier's closed physical choice through the same writer" do
    potion = carried("draught", use_kind: "healing")
    choice = @actions.choices.find { |row| row.kind == "consume" }
    agent = FakeAgent.new({ "intent" => "use", "target" => choice.token, "also_named" => "nothing" }, "You drink the draught.")
    scene = BaseAgent.stub(:new, agent) { Playthrough::Turn.new(@game).play("I drink the draught.", request_token: "plain") }
    assert_equal "consumed", potion.reload.disposition
    assert_equal "model", scene.resolved_by
    assert_equal "use", scene.resolved_action
    assert_equal 2, agent.prompts.length
  end

  test "a model cannot use an invented token or hide a second act behind a physical choice" do
    apple = carried("apple", use_kind: "food")
    coin = carried("coin")
    choice = @actions.choices.find { |row| row.kind == "consume" }
    [ [ "use:consume:99999999", "nothing" ], [ choice.token, coin.name ] ].each_with_index do |(token, extra), index|
      agent = FakeAgent.new({ "intent" => "use", "target" => token, "also_named" => extra })
      result = BaseAgent.stub(:new, agent) do
        Playthrough::Turn.new(@game).play("Eat the apple and drop the coin.", request_token: "invalid-#{index}")
      end
      assert_instance_of Playthrough::Refusal, result
      assert_equal "intact", apple.reload.disposition
      assert_includes @game.carried, coin
      assert_equal @opening, @game.reload.current_scene
    end
  end

  test "an offered item is transferred before the real interaction narrator and saved with its receipt" do
    npc = create(:character, story: @story, location: @game.current_location, fullname: "Maren", nickname: "Maren")
    apple = carried("apple", use_kind: "food")
    reaction = { "pre_thought" => "Cal brought what I requested.", "pre_feeling" => "glad", "action" => "Maren accepts the apple.",
      "post_thought" => "I have my lunch.", "post_feeling" => "content", "inner_resolution" => "I will thank Cal.", "engine_action" => "accept:#{apple.id}" }
    agent = FakeAgent.new(reaction, "Maren accepts the apple from you.")
    scene = BaseAgent.stub(:new, agent) do
      Playthrough::Turn.new(@game).play("/offer apple to Maren", request_token: "offer")
    end
    assert_includes @game.items_held_by(npc), apple
    assert_not_includes @game.carried, apple
    row = scene.interactions.sole
    assert_equal "applied", row.action_status
    assert_equal "accept:#{apple.id}", row.engine_action
    assert_equal "use", scene.resolved_action
    assert_includes agent.prompts.last, row.action_fact
    assert_equal "intact", apple.template.reload.disposition
  end

  test "failed consumption persistence rolls back the healing and its receipt" do
    potion = carried("draught", use_kind: "healing")
    choice = @actions.choices.find { |row| row.kind == "consume" }
    Playthrough::Turn.new(@game).harm!(@player, 10)
    before = @game.condition.hp
    command = Playthrough::Command.accept!(@game, "/drink draught", "failed-save")
    assert_raises(ActiveRecord::StatementInvalid) do
      command.execute! do
        Playthrough::Command::Journal.commit("physical_effect") do
          @actions.apply!(choice)
          raise ActiveRecord::StatementInvalid, "interrupted persistence"
        end
      end
    end
    assert_equal before, @game.condition.hp
    assert_equal "intact", potion.reload.disposition
    assert_not command.reload.journal.fetch("steps").key?("physical_effect")
  end

  private

  def carried(name, **attributes)
    template = create(:item, character: nil, location: @game.current_location, name: name, **attributes)
    Item::Snapshot.new(@game).of_the_room!(@game.current_location)
    copy = @game.items.find_by!(template: template)
    copy.update!(character: nil, location: nil, **Location::Placement.unplaced)
    copy
  end

  def doorway(barrier, key: nil)
    target = create(:location, story: @story, name: "Courtyard")
    [ create(:location_connection, location: @game.current_location, connected_location: target, barrier: barrier, key_template: key),
      create(:location_connection, location: target, connected_location: @game.current_location, barrier: barrier, key_template: key) ]
  end

  def play(line, token: "physical")
    BaseAgent.stub(:new, FakeAgent.new("You finish the action.")) do
      Playthrough::Turn.new(@game).play(line, request_token: token)
    end
  end
end
