require "test_helper"

# Exercise Mechanics' own dispatch with the real physical writer. Browser
# physical tests cannot detect a resolved choice falling through to a no-op
# here, and every offline path forbids even constructing a model agent.
class Playthrough::MechanicsPhysicalTest < ActiveSupport::TestCase
  setup do
    @story = create(:story)
    @player = create(:character, :protagonist, story: @story, level: 10, strength: 3)
    @room = create(:location, story: @story, name: "Workshop")
    @game = create(:playthrough, story: @story, character: @player, current_location: @room)
    @opening = create(:scene, story: @story, location: @room)
    @game.update!(current_scene: @opening)
    @mechanics = Playthrough::Mechanics.new(@game, model: false)
  end

  test "consumption heals once and preserves the spent copy on a later snapshot" do
    dose = carried("healing draught", use_kind: "healing")
    Playthrough::Turn.new(@game).harm!(@player, 12)
    before = @game.condition.hp

    report = play("/drink healing draught")
    assert report.changed?
    assert_not report.refused?
    assert_equal before + Item::HEALING_POINTS, report.state.condition.hp
    assert_equal "consumed", dose.reload.disposition
    assert_empty @game.carried
    assert_equal "intact", dose.template.reload.disposition

    again = play("/drink healing draught")
    assert again.refused?
    assert_not again.changed?
    assert_equal before + Item::HEALING_POINTS, @game.condition.hp
    assert_equal 1, @game.items.where(template: dose.template).count
    assert_equal @opening, @game.reload.current_scene
  end

  test "burning destroys only the combustible copy and keeps the tool" do
    paper = lying_here(@game, @room, name: "folded note", combustible: true)
    tool = carried("tinderbox", use_kind: "firestarter")

    report = play("/burn folded note with tinderbox")
    assert report.changed?
    assert_equal "burned", paper.reload.disposition
    assert_empty @game.items_lying_in(@room)
    assert_equal [ tool ], @game.carried.to_a
    assert_equal "intact", paper.template.reload.disposition
    assert_equal @opening, @game.reload.current_scene
  end

  test "unlocking opens both directions for this game and permits a separate round trip" do
    key = carried("brass key", use_kind: "key")
    door, back = doorway("keyed", key: key.template)
    other = create(:playthrough, story: @story, character: @player, current_location: @room)

    assert play("/move Courtyard").refused?
    opened = play("/unlock Courtyard with brass key")
    assert opened.changed?
    assert_not opened.refused?
    assert_equal @room, @game.reload.current_location
    assert door.open_for?(@game)
    assert back.open_for?(@game)
    assert_not door.open_for?(other)
    assert_equal "keyed", door.reload.barrier
    assert_includes @game.carried, key

    assert play("/move Courtyard").changed?
    assert_equal door.connected_location, @game.reload.current_location
    assert play("/move Workshop").changed?
    assert_equal @room, @game.reload.current_location
  end

  test "closed movement and throws spend no turn but a failed force pays the room's hazard" do
    door, = doorway("jammed")
    stone = carried("stone")
    @room.update!(hazard: "airless", hazard_die: 4)
    before = @game.condition.hp

    [ "/move Courtyard", "/throw stone at Courtyard" ].each do |command|
      report = play(command)
      assert report.refused?
      assert_match "jammed", report.refusal
      assert_not report.changed?
      assert_equal @room, @game.reload.current_location
      assert_equal before, @game.condition.hp
      assert_empty @game.tolls
      assert_empty @game.blows
      assert_includes @game.carried, stone
    end

    # Strength 3 less the force penalty of 4 fails for every possible die.
    report = play("/force Courtyard")
    assert_not report.refused?
    assert_not report.changed?
    assert_match "The way remains closed", report.note.join(" ")
    assert_not door.open_for?(@game)
    assert_equal 1, @game.tolls.count
    assert_operator @game.condition.hp, :<, before
    assert_equal @opening, @game.reload.current_scene
  end

  test "an offer leaves custody unchanged and follows the same world response as talk" do
    recipient = create(:character, story: @story, location: @room, fullname: "Maren")
    apple = carried("apple", use_kind: "food")
    @room.update!(hazard: "airless", hazard_die: 4)

    report = play("/offer apple to Maren")
    assert_match "talking is prose", report.refusal
    assert_not report.changed?
    assert_includes @game.carried, apple
    assert_empty @game.items_held_by(recipient)
    assert_equal 1, @game.tolls.count
    assert_equal @opening, @game.reload.current_scene
  end

  test "a failed physical attempt prints its outcome even when the world has no response" do
    door, = doorway("jammed")

    report = play("/force Courtyard")
    assert_not report.changed?
    assert_not report.refused?
    assert_match "The way remains closed", report.to_s
    assert_not door.open_for?(@game)
  end

  test "the classifier's physical choice uses the writer with no narration call" do
    apple = carried("apple", use_kind: "food")
    choice = Playthrough::PhysicalAction.new(@game).choices.find { |row| row.kind == "consume" }
    agent = FakeAgent.new({ "intent" => "use", "target" => choice.token, "also_named" => "nothing" })

    report = BaseAgent.stub(:new, agent) { Playthrough::Mechanics.new(@game).run("I eat the apple.") }
    assert report.changed?
    assert_equal "consumed", apple.reload.disposition
    assert_equal "model", report.resolved_by
    assert_equal 1, agent.prompts.length
    assert_equal @opening, @game.reload.current_scene
  end

  test "an unavailable slashed physical attempt is refused without consulting the classifier" do
    BaseAgent.stub(:new, ->(*) { flunk "unavailable slash use must not call a model" }) do
      report = Playthrough::Mechanics.new(@game).run("/drink missing draught")
      assert report.refused?
      assert_equal "grammar", report.resolved_by
      assert_not report.changed?
    end
    assert_equal @opening, @game.reload.current_scene
  end

  private

  def play(command)
    BaseAgent.stub(:new, ->(*) { flunk "offline mechanics must not call a model" }) { @mechanics.run(command) }
  end

  def carried(name, **attributes)
    item = lying_here(@game, @room, name: name, **attributes)
    Playthrough::Turn.new(@game).carry!(item)
    item
  end

  def doorway(barrier, key: nil)
    destination = create(:location, story: @story, name: "Courtyard")
    [ [ @room, destination ], [ destination, @room ] ].map do |from, to|
      create(:location_connection, location: from, connected_location: to, barrier: barrier, key_template: key)
    end
  end
end
