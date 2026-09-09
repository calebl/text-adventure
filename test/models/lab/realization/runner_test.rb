require "test_helper"

# ONE DRAW, WITH THE MODEL STOOD IN FOR AND THE WORLD PUT BACK.
#
# The runner's whole job is to reach `Location::Generator`'s OWN two calls from a
# name and a teaser somebody typed, and then leave nothing behind. Both halves
# are testable without paying for anything:
#
#   * the prompt is the generator's -- the kind's name and teaser are in it, the
#     world around them is read off the staged records, and NOTHING in the lab
#     writes a sentence a model reads;
#   * which SCHEMA is sent follows from the `inside` band, because the band makes
#     `Location#place?` true and `#detail_schema` reads that;
#   * the stored row is the bench's own reading, so the lab and
#     `rake eval:realization` cannot disagree about a call they both watched;
#   * A DRAW LEAVES NOTHING BUT ITS SAMPLE. The world is a rolled-back copy, so a
#     lab pointed at the captain's own universes never writes a room into one.
#     A regression there would be an instrument that quietly ate a database.
#
# NEVER A LIVE MODEL. `RealizingAgent` stands in at the `BaseAgent` boundary, the
# way `Eval::Realization::BenchTest` and `Eval::Prompt::BenchTest` both do. It
# lives in `test/support` rather than here because `Lab::Exits::RunnerTest`
# answers the same conversation and a second fake would be a second answer to
# what a realization call leaves behind.
class Lab::Realization::RunnerTest < ActiveSupport::TestCase
  # THE WORLD EVERY CASE HERE IS DRAWN IN. The sweep's own, which is the smallest
  # of the five and the only one in the repository with a building already in it.
  WORLD = "The Quay House".freeze

  test "the prompt the sample sent is the generators own, carrying the typed name and teaser" do
    kind = create(:lab_realization_kind, world: WORLD, name: "The Fishmonger's Warehouse",
                                         teaser: "A flooded warehouse, its doors swollen shut.")
    sample = draw(kind)

    detail = sample.row["prompts"]["detail"]

    assert_includes detail, "The Fishmonger's Warehouse"
    assert_includes detail, "A flooded warehouse, its doors swollen shut."
    assert_includes detail, "The Quay", "the world around the room is in the prompt too"
    assert_not_includes detail, Lab::Realization::Runner::LABEL,
                        "the staging title must not reach the prompt -- the narrator is told the title"
  end

  test "a kind with a band is sent the place schema and a kind without one is not" do
    building = draw(create(:lab_realization_kind, :a_building, world: WORLD))
    room = draw(create(:lab_realization_kind, world: WORLD))

    assert building.reading.parameters_asked?
    assert_equal "a cellar", building.picks_for(Lab::Realization.pick("storeys_below")).sole
    assert_equal 1, building.reading.calls, "a laid-out place makes no exits call at all"

    assert_not room.reading.parameters_asked?
    assert_equal 2, room.reading.calls
    assert room.reading.asked_for_exits?
  end

  # THE BAND IS A PARAMETER AND THE FOOTPRINT IS THE ENGINE'S. The model never
  # writes a number: `Location::Parameters#footprint` rolls two sides inside the
  # band the label names, on `Roll::FOOTPRINT`'s own axis.
  test "the engine rolls a footprint inside the bands own paces" do
    sample = draw(create(:lab_realization_kind, :a_building, world: WORLD))

    assert sample.reading.rooms.any?, "a place with a footprint gets an inside laid out"
    assert(sample.reading.rooms.all? { |room| room["width"].to_i.positive? })
  end

  test "a declared danger reaches the stub and a declared population reaches the prompt" do
    dangerous = draw(create(:lab_realization_kind, :dangerous, world: WORLD))

    assert_equal "dangerous", dangerous.reading.facts["danger"]
    assert_operator dangerous.reading.facts["danger_share"].to_i, :>, 0

    # THE COUNT IS NOT ASSERTED AND MUST NOT BE. The word rides on the stub and
    # `Location::Population.count_for` throws inside its band, seeded on the
    # room's NAME -- so the number is a die and pinning it here would pin the
    # die. What the lab is responsible for is that the WORD got through, which is
    # the band the count came out of.
    crowded = draw(create(:lab_realization_kind, :crowded, world: WORLD))

    assert_includes Location::Population::BANDS.fetch("a crowd"), crowded.reading.people_allowance,
                    "the word rides on the stub and Character::Registry rolls the count inside its band"
  end

  test "a kind naming the way back gets an edge, in both directions" do
    kind = create(:lab_realization_kind, world: WORLD, reached_from: "The Quay")
    sample = draw(kind)

    assert_equal "The Quay", sample.reading.reached_from
    assert_equal [ "The Quay" ], sample.reading.reachable
  end

  test "a kind with no way back is an opening room and is drawn all the same" do
    sample = draw(create(:lab_realization_kind, world: WORLD))

    assert_equal "", sample.reading.reached_from
    assert_empty sample.reading.reachable
    assert sample.reading.scored?
  end

  # A PERSON'S MISTAKE GETS A SENTENCE AND NOT A STACK TRACE.
  test "a way back the world does not have is refused with the name in it" do
    kind = create(:lab_realization_kind, world: WORLD, reached_from: "The Drowned Compact")

    error = assert_raises(Eval::Realization::Stage::Unstageable) { draw(kind) }

    assert_includes error.message, "The Drowned Compact"
  end

  test "a world with no file is refused by the stage" do
    kind = build(:lab_realization_kind, world: "The Salt Assizes")
    kind.save!(validate: false)
    kind.update_column(:world, "The World With No File")

    assert_raises(Eval::Realization::Stage::Unstageable) { draw(kind) }
  end

  # THE GUARANTEE THE WHOLE INSTRUMENT RESTS ON.
  test "a draw leaves nothing behind but its sample" do
    kind = create(:lab_realization_kind, world: WORLD, reached_from: "The Quay")
    before = [ Story.count, Location.count, Character.count, Item.count, LocationConnection.count ]

    sample = draw(kind)

    assert_equal before, [ Story.count, Location.count, Character.count, Item.count, LocationConnection.count ]
    assert sample.persisted?, "and the sample is the one thing that does survive"
    assert_equal kind, sample.kind
  end

  test "the row is the benchs own reading, complete enough to rescore offline" do
    sample = draw(create(:lab_realization_kind, world: WORLD))
    row = sample.row

    assert_equal "lab-kind-#{sample.kind_id}", row["id"]
    assert_equal Lab::Realization::Runner::SHAPE, row["shape"]
    assert_equal WORLD, row["story"]
    assert_equal %w[detail exits], row["answers"].keys
    assert_equal %w[detail exits], row["prompts"].keys
    assert row["facts"].key?("parameters_asked"), "the gate both parameter checks stand on"
    assert row["after"].key?("new_places"), "and what the registries made of the answer"
    assert_equal "fake/model", row["answered_by"]
    assert_operator row["input_tokens"].to_i, :>, 0
  end

  # A FAILED CALL IS STILL A SAMPLE, which is what stops a provider dropping one
  # call in a hundred from costing the whole look -- and a refusal is the one
  # failure that is about the prompt.
  test "a call that failed is recorded as a sample rather than raised" do
    sample = draw(create(:lab_realization_kind, world: WORLD), answer: BaseAgent::RefusalError.new("no"))

    assert sample.failed?
    assert sample.reading.refused?
    assert_nil sample.verdict
  end

  private

  def draw(kind, answer: nil)
    stub = lambda do |*args, **options|
      RealizingAgent.new(answer, purpose: options[:purpose], instructions: args.first)
    end

    BaseAgent.stub(:new, stub) do
      Lab::Realization::Runner.new(kind, arm: "fake/model").draw!
    end
  end
end
