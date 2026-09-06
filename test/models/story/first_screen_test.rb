require "test_helper"

# THE SEQUENCE `rake game:new` RUNS, driven with the model stubbed.
#
# The task itself is a paid path and nothing in CI may run it, which is exactly
# why the order it works in was extracted into `Story::FirstScreen`: the order
# is the load-bearing part -- the protagonist and the opening room's cast have
# to exist before `Scene::Generator.opening` reads them -- and an order that
# only exists inside a rake task body is an order nothing can hold.
class Story::FirstScreenTest < ActiveSupport::TestCase
  PROTAGONIST = {
    "fullname" => "Coraith Vell", "nickname" => "Vell",
    "personality" => "Patient with a ledger and short with everybody who is not one.",
    "appearance" => "Salt-stiff coat, ink to the second knuckle.",
    "likes" => "A tide that runs to the table, quiet, strong tea",
    "dislikes" => "A witness who has been coached, bells",
    "fears" => "Signing something she cannot later prove",
    "backstory" => "Coraith Vell was raised inland and sent to the coast to close a court nobody wanted closed."
  }.freeze

  # The person the realization itself names, as `Location::DetailSchema`'s
  # `people` array answers with them -- no race, age or sex, because those are
  # `Character::Registry#slots`' and never a model's.
  IN_THE_ROOM = {
    "fullname" => "Neb Halloran", "nickname" => "Neb",
    "appearance" => "Wet to the knee and not moving from the post.",
    "personality" => "Talks to keep from thinking and stops the moment you listen.",
    "backstory" => "Neb Halloran was chained to the tide post on a warrant nobody has produced.",
    "likes" => "Slack water, being believed",
    "dislikes" => "The turn of the tide, being asked twice",
    "fears" => "That the warrant is real"
  }.freeze

  DETAIL = {
    "description" => "The court stands on the causeway with the water an hour out.",
    "lore" => "Two hundred years of assizes have been held here between tides."
  }.freeze

  PEOPLED = DETAIL.merge("people" => [ IN_THE_ROOM ]).freeze
  EMPTY_ROOM = DETAIL.merge("people" => []).freeze

  EXITS = {
    "exits" => [
      { "name" => "The Tide Post", "teaser" => "A post at the waterline.",
        "distance" => "adjacent", "travel_method" => "walking" }
    ]
  }.freeze

  ARRIVAL = {
    "description" => "You come up the causeway with the court already sitting.",
    "summary" => "The player arrives at the Causeway Court."
  }.freeze

  def setup
    @story = create(:story)
    @opening = create(:location, :stub, story: @story, name: "The Causeway Court")
  end

  # The whole sequence, with every call the four steps make queued in order:
  # the protagonist's sheet, the room's detail, the room's exits, the arrival.
  def build(*responses, reporter: nil)
    agent = FakeAgent.new(*responses)
    screen = BaseAgent.stub(:new, agent) do
      Story::FirstScreen.new(@story, reporter: reporter).build!
    end

    [ screen, agent ]
  end

  def ordinary_build(reporter: nil)
    build(PROTAGONIST, PEOPLED, EXITS, ARRIVAL, reporter: reporter)
  end

  # ------------------------------------------------------------------------
  # THE THREE THINGS, AND THE ORDER.
  # ------------------------------------------------------------------------

  test "writes exactly one protagonist and marks them" do
    screen, = ordinary_build

    protagonists = @story.characters.protagonists.to_a
    assert_equal 1, protagonists.size
    assert_equal "Coraith Vell", protagonists.first.fullname
    assert_equal protagonists.first, screen.protagonist
    assert screen.protagonist.is_protagonist?
    assert_equal screen.protagonist, @story.reload.protagonist
  end

  # The party is derived from where the playthrough is, so a protagonist has no
  # whereabouts -- which is what all three checked-in worlds do by hand.
  test "leaves the protagonist nowhere, because the party is derived" do
    screen, = ordinary_build

    assert_nil screen.protagonist.location
    assert screen.protagonist.nowhere?
  end

  test "realizes the opening room and puts the realization's people in it" do
    screen, = ordinary_build

    assert_equal @opening, screen.location
    assert screen.location.reload.realized?
    assert_equal [ "Neb Halloran" ], screen.cast.map(&:fullname)
  end

  # THE POINT OF THE ORDER. The arrival is narrated last, so the Scene it
  # writes carries both the player and the person standing in the room -- which
  # is what the arrival prompt's `## Who Is Here` block is built from.
  test "the opening arrival's cast carries the protagonist and the room" do
    screen, = ordinary_build

    assert screen.scene.is_opening?
    names = screen.scene.characters.map(&:fullname)
    assert_includes names, "Coraith Vell"
    assert_includes names, "Neb Halloran"
  end

  test "names the protagonist to the arrival prompt as the one arriving" do
    _screen, agent = ordinary_build

    assert_includes agent.prompts.last, "Coraith Vell (Vell)"
    assert_includes agent.prompts.last, "the player, the one arriving"
  end

  # ------------------------------------------------------------------------
  # THE BODY. Call C1, applied to a generated world.
  # ------------------------------------------------------------------------

  test "gives the protagonist the house's body rather than a generated one" do
    screen, = ordinary_build

    assert_equal Character::StatBlock::PROTAGONIST_LEVEL, screen.protagonist.level
    assert_equal Character::StatBlock::PROTAGONIST_HIT_DIE, screen.protagonist.hit_die
    assert_equal 18, screen.protagonist.max_hp
    assert screen.protagonist.abilities?
  end

  # Everybody else keeps the ordinary roll: the house rule is the player's.
  test "gives the room's own people the ordinary rolled body" do
    screen, = ordinary_build

    person = screen.cast.first
    assert_equal Character::StatBlock::STARTING_LEVEL, person.level
    assert_includes Character::HIT_DICE, person.hit_die
    assert person.abilities?
  end

  # ------------------------------------------------------------------------
  # AN OPENING ROOM WITH NOBODY IN IT IS A LEGITIMATE WORLD.
  #
  # The captain's ruling of 2026-09-05: *"the opening room should not guarantee
  # at least one person. The protagonist can start by themselves."* So the
  # opening realization is asked exactly what every other room is asked, and an
  # empty answer is taken and reported rather than filled in.
  # ------------------------------------------------------------------------

  test "asks the opening room for a cast on the ordinary terms" do
    _screen, agent = ordinary_build

    detail_prompt = agent.prompts[1]
    assert_includes detail_prompt, "NOBODY is the right answer for most rooms"
    assert_not_includes detail_prompt, "AT LEAST"
  end

  test "takes an empty opening room rather than writing somebody into it" do
    screen, agent = build(PROTAGONIST, EMPTY_ROOM, EXITS, ARRIVAL)

    assert_empty screen.cast
    assert_equal 1, @story.characters.count, "only the protagonist should have been written"
    assert_equal 4, agent.prompts.size, "an empty opening room must not buy a fifth model call"
  end

  # The player is still on the arrival's cast when they are the only one on it:
  # that is the half of `Scene::Generator#characters_present` this task fixed.
  test "narrates an empty opening room with the protagonist as its whole cast" do
    screen, = build(PROTAGONIST, EMPTY_ROOM, EXITS, ARRIVAL)

    assert_equal [ "Coraith Vell" ], screen.scene.characters.map(&:fullname)
  end

  # ------------------------------------------------------------------------
  # WHAT THE DOCTOR SAYS ABOUT WHAT THIS BUILT.
  # ------------------------------------------------------------------------

  test "leaves a story the doctor finds no protagonist or cast fault in" do
    ordinary_build

    codes = Story::Doctor.new(@story.reload).findings.map(&:code)
    assert_not_includes codes, :no_protagonist
    assert_not_includes codes, :several_protagonists
    assert_not_includes codes, :character_nowhere
    assert_not_includes codes, :character_without_race
    assert_not_includes codes, :character_without_a_stat_block
  end

  # AND AN EMPTY OPENING ROOM IS NOT A FINDING EITHER, on the ruling above. The
  # doctor has no level below `warning`, so reporting a world working as
  # written is how a person learns to stop reading warnings -- the same rule
  # `#characters_nowhere` is under about `deliberately_absent`.
  test "says nothing about a story that opens with nobody in the room" do
    build(PROTAGONIST, EMPTY_ROOM, EXITS, ARRIVAL)

    doctor = Story::Doctor.new(@story.reload)
    assert doctor.playable?, doctor.findings.map(&:message).join("; ")
    assert_empty doctor.findings.map(&:code).grep(/opening_room/)
  end

  # ------------------------------------------------------------------------
  # WHAT THE TASK PRINTS WHILE IT WORKS.
  # ------------------------------------------------------------------------

  test "reports each step it takes to the reporter it was given" do
    labels = []
    reporter = ->(label, &work) { labels << label; work.call }

    ordinary_build(reporter: reporter)

    assert_equal [ "Generating the protagonist", "Generating opening location", "Narrating the opening arrival" ], labels
  end

  test "runs silently with no reporter at all" do
    screen, = build(PROTAGONIST, PEOPLED, EXITS, ARRIVAL)

    assert screen.scene.present?
  end
end
