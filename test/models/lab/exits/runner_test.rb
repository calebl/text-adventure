require "test_helper"

# ONE DRAW OF A VANTAGE, WITH THE MODEL STOOD IN FOR AND THE WORLD PUT BACK.
#
# `Lab::Exits::Runner`'s header is the design: it is
# `Lab::Realization::Runner` with three methods changed, so what this file has to
# prove is exactly those three and the guarantee they all rest on. Everything
# else is already held by `Lab::Realization::RunnerTest`, and re-asserting it
# here would be two tests of one behaviour.
#
#   `#ad_hoc_case`  the `absent` list reaches the staging and the places really
#                   leave the prompt. THE LOAD-BEARING ONE: without it the pick
#                   under test is never exercised and the lab measures nothing,
#                   silently.
#   `#label`        the staging title says which instrument made it, which only
#                   works because the parent reads a METHOD rather than its own
#                   constant -- a lexical constant would have staged every exits
#                   draw under the words "realization lab".
#   `#shape`        a stored row that reached a board says which lab it came from.
#
# AND A VANTAGE IS NEVER A BUILDING, so it always makes both calls and is always
# asked for its exits. That is the whole reason there is no `inside` band to type.
#
# NEVER A LIVE MODEL. `RealizingAgent` stands in at the `BaseAgent` boundary --
# `test/support`'s, shared with `Lab::Realization::RunnerTest` rather than copied,
# because a second fake would be a second answer to what a realization call
# leaves behind and the two could drift into testing different things.
class Lab::Exits::RunnerTest < ActiveSupport::TestCase
  WORLD = "The Quay House".freeze

  # A PLACE THIS WORLD REALLY HAS. `Eval::Realization::Stage#find_room!` refuses
  # a name it does not, which is the next test but one.
  OFF_THE_BOOKS = "The Bonded Cellar".freeze

  test "a vantage always makes both calls and is always asked for its exits" do
    sample = draw(create(:lab_exits_vantage, world: WORLD))

    assert_equal 2, sample.reading.calls,
                 "a vantage cannot be a building, so #write_exits! always asks"
    assert sample.reading.asked_for_exits?
    assert_not sample.reading.parameters_asked?, "the parameters block is the other lab's subject"
    assert sample.answered?
  end

  # THE ONE THAT MATTERS MOST.
  #
  # ASSERTED ON THE PROMPT'S LINES AND NOT AS A SUBSTRING, which is not fussiness:
  # this world holds `The Bonded Cellar` AND `The Bonded Cellar room 1`, so a
  # substring check passes on the rooms and would have gone on passing with the
  # `absent` list doing nothing at all. The prompt lists one place per line
  # (`Location::Generator#known_location_names`), so a line is what a place is.
  test "a place off the books leaves the prompt the model is given" do
    with_it = offered_in(draw(create(:lab_exits_vantage, world: WORLD)))
    without_it = offered_in(draw(create(:lab_exits_vantage, world: WORLD, absent: OFF_THE_BOOKS)))

    assert_includes with_it, OFF_THE_BOOKS,
                    "with nothing off the books the prompt offers it as somewhere to reuse"
    assert_not_includes without_it, OFF_THE_BOOKS,
                        "and that is the whole mechanism: no reuse to offer, so a reason to invent"
  end

  # AND WHAT TAKING A PLACE OFF THE BOOKS DOES NOT DO, written down because the
  # captain will meet it the first time he tries it on a building. Removing a
  # place removes THAT ROW. A world file that also declares rooms of it keeps
  # them, so their names stay on the prompt's reuse list -- they are ordinary
  # locations that happen to be named after their parent, and nothing infers a
  # tree from a name.
  #
  # SO THE LIST IS A LIST OF PLACES AND NOT A SUBTREE, and a vantage that wants
  # the rooms gone names the rooms. `Lab::Exits::Vantage`'s header says so where
  # he types it.
  test "taking a place off the books leaves the rooms a world file declared under it" do
    offered = offered_in(draw(create(:lab_exits_vantage, world: WORLD, absent: OFF_THE_BOOKS)))

    assert_not_includes offered, OFF_THE_BOOKS
    assert_includes offered, "#{OFF_THE_BOOKS} room 1",
                    "a room of it is its own location, and removing the parent does not remove it"
  end

  test "the places off the books are gone from the world the call was made in" do
    sample = draw(create(:lab_exits_vantage, world: WORLD, absent: OFF_THE_BOOKS))

    assert_not_includes sample.reading.places.map { |place| place["name"] }, OFF_THE_BOOKS
  end

  test "several places come off the books, one per line" do
    sample = draw(create(:lab_exits_vantage, :with_places_off_the_books, world: WORLD))
    on_the_books = sample.reading.places.map { |place| place["name"] }

    assert_not_includes on_the_books, "The Custom House"
    assert_not_includes on_the_books, "The Bonded Cellar"
  end

  # A PERSON'S MISTAKE GETS A SENTENCE AND NOT A STACK TRACE -- and this is the
  # commonest mistake on this lab, because the name has to match a place in a
  # world file he is not looking at.
  test "a place the world does not have is refused with the name in it" do
    vantage = create(:lab_exits_vantage, world: WORLD, absent: "The Drowned Compact")

    error = assert_raises(Eval::Realization::Stage::Unstageable) { draw(vantage) }

    assert_includes error.message, "The Drowned Compact"
  end

  test "a way back the world does not have is refused the same way" do
    vantage = create(:lab_exits_vantage, world: WORLD, reached_from: "The Drowned Compact")

    assert_raises(Eval::Realization::Stage::Unstageable) { draw(vantage) }
  end

  # THE SEAM. Without `#label` as a method on the parent, Ruby would resolve the
  # constant lexically and every exits draw would be staged under the other lab's
  # word -- so this asserts the override took, from both sides.
  test "the staging title says this lab made it and never reaches the prompt" do
    sample = draw(create(:lab_exits_vantage, world: WORLD))
    detail = sample.row["prompts"]["detail"]

    assert_not_includes detail, Lab::Exits::Runner::LABEL,
                        "the narrator is told the story's title, so the staging label must not be in it"
    assert_not_includes detail, Lab::Realization::Runner::LABEL
    assert_includes detail, WORLD, "and the world's real title is"
  end

  test "the stored row is labelled with the vantage and this labs own shape" do
    vantage = create(:lab_exits_vantage, world: WORLD)
    sample = draw(vantage)

    assert_equal "lab-vantage-#{vantage.id}", sample.row["id"]
    assert_equal Lab::Exits::Runner::SHAPE, sample.row["shape"]
    assert_not_equal Lab::Realization::Runner::SHAPE, sample.row["shape"],
                     "a row that reached a board must not masquerade as the other lab's draw"
  end

  test "the row is the benchs own reading, complete enough to rescore offline" do
    row = draw(create(:lab_exits_vantage, world: WORLD)).row

    assert_equal WORLD, row["story"]
    assert_equal %w[detail exits], row["answers"].keys
    assert_equal %w[detail exits], row["prompts"].keys
    assert row["after"].key?("new_places"), "the field every reach figure stands on"
    assert_operator row["input_tokens"].to_i, :>, 0
  end

  test "the prompt carries the typed name and teaser and nothing the lab wrote" do
    vantage = create(:lab_exits_vantage, world: WORLD, name: "Harbour Steps",
                                         teaser: "Wet stone down to the tide line.")
    detail = draw(vantage).row["prompts"]["detail"]

    assert_includes detail, "Harbour Steps"
    assert_includes detail, "Wet stone down to the tide line."
  end

  test "a vantage naming the way back gets an edge in both directions" do
    sample = draw(create(:lab_exits_vantage, :reached_from_the_quay, world: WORLD))

    assert_equal "The Quay", sample.reading.reached_from
    assert_equal [ "The Quay" ], sample.reading.reachable
  end

  test "a vantage with no way back is an opening room and is drawn all the same" do
    sample = draw(create(:lab_exits_vantage, world: WORLD))

    assert_equal "", sample.reading.reached_from
    assert_empty sample.reading.reachable
  end

  test "a declared danger reaches the stub" do
    sample = draw(create(:lab_exits_vantage, :dangerous, world: WORLD))

    assert_equal "dangerous", sample.reading.facts["danger"]
  end

  # THE GUARANTEE THE WHOLE INSTRUMENT RESTS ON, and it has to be asserted here
  # as well as on the parent: this subclass DESTROYS ROOMS in the staged copy, so
  # a rollback that stopped working would eat the captain's worlds rather than
  # merely add to them.
  test "a draw leaves nothing behind but its sample, even having destroyed rooms" do
    vantage = create(:lab_exits_vantage, :with_places_off_the_books, :reached_from_the_quay, world: WORLD)
    before = [ Story.count, Location.count, Character.count, Item.count, LocationConnection.count ]

    sample = draw(vantage)

    assert_equal before, [ Story.count, Location.count, Character.count, Item.count, LocationConnection.count ]
    assert sample.persisted?, "and the sample is the one thing that does survive"
    assert_equal vantage, sample.vantage
  end

  test "the sample lands on the vantages own draws" do
    vantage = create(:lab_exits_vantage, world: WORLD)
    sample = draw(vantage)

    assert_equal [ sample ], vantage.reload.samples.to_a
    assert_kind_of Lab::Exits::Sample, sample
  end

  test "a call that failed is recorded as a sample rather than raised" do
    sample = draw(create(:lab_exits_vantage, world: WORLD), answer: BaseAgent::RefusalError.new("no"))

    assert sample.failed?
    assert_not sample.answered?
    assert_nil sample.verdict
  end

  test "the runner names the vantage as itself as well as as a kind" do
    vantage = create(:lab_exits_vantage, world: WORLD)
    runner = Lab::Exits::Runner.new(vantage)

    assert_equal vantage, runner.vantage
    assert_equal vantage, runner.kind, "the parent's word for the same object"
  end

  private

  # THE PLACES THE EXITS PROMPT ACTUALLY OFFERED, one per line, read off the
  # prompt as SENT. Not off the records: what this lab is about is what the model
  # was told, and the two are only the same while nothing has gone wrong.
  def offered_in(sample)
    sample.row["prompts"]["exits"].to_s.lines.map(&:strip)
          .map { |line| line.sub(/ \(already written.*\)\z/, "") }
  end

  def draw(vantage, answer: nil)
    stub = lambda do |*args, **options|
      RealizingAgent.new(answer, purpose: options[:purpose], instructions: args.first)
    end

    BaseAgent.stub(:new, stub) do
      Lab::Exits::Runner.new(vantage, arm: "fake/model").draw!
    end
  end
end
