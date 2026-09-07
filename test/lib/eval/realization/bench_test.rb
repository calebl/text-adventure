require "test_helper"

# THE REALIZATION, WITH THE MODEL STOOD IN FOR.
#
# The bench's job is to put `Location::Generator`'s OWN prompts in front of a
# model and keep what came back beside the facts it was asked against, and every
# part of that is testable without paying for a call:
#
#   * the prompts are the generator's, so a case's world really does reach the
#     room builder -- the allowance, the places that already exist, the ones
#     marked written, and the cast slots the engine rolled;
#   * both calls are made, in the app's own conversation, and the answers are
#     read back off the `messages` rows rather than out of this bench;
#   * what the registries ADMITTED is read off the records, which is the half no
#     reading of the answer could give;
#   * A CASE LEAVES NOTHING BEHIND. Each one is staged inside a transaction that
#     is rolled back, so the case after it gets the world the seed file has.
#
# NEVER A LIVE MODEL. A `FakeAgent` stands in at the `BaseAgent` boundary,
# exactly as it does in `Eval::Prompt::BenchTest`, so this runs in CI for
# nothing.
class Eval::Realization::BenchTest < ActiveSupport::TestCase
  CORPUS = <<~YML
    cases:
    - id: a-hallway
      story: The Unrecorded Hour
      room: The Long Hallway
      reached_from: Ward Office 12
      expects_new_ground: true
      shape: written-neighbour
      why: both of this world's other rooms are already written
    - id: b-closet
      story: The Unrecorded Hour
      room: The Supply Closet
      reached_from: Ward Office 12
      unwritten:
      - The Long Hallway
      expects_new_ground: false
      shape: dead-end
      why: a closet off one office, where one exit is the whole answer
  YML

  def setup
    @corpus = Eval::Realization::Corpus.load(written(CORPUS))
  end

  test "a pass realizes every case and keeps both answers with the facts beside them" do
    pass = bench.passes.sole

    assert_equal 2, pass.rows.size
    assert_equal 2, pass.scanned
    assert_equal 0, pass.failures

    hallway = row(pass, "a-hallway")
    assert_equal 2, hallway["calls"], "a realization is two calls and not one more"
    assert_equal "The Long Hallway", hallway.dig("facts", "room")
    assert_equal Endless::DETAIL, hallway.dig("answers", "detail")
    assert_equal Endless::EXITS, hallway.dig("answers", "exits")
  end

  # THE PROMPTS ARE THE APP'S. Not a fixture, not a copy: the case's world
  # reaches the room builder through `Location::Generator`'s own instruction
  # blocks, which are the three things this bench exists to measure.
  test "the room builder is handed the prompts the app would have built" do
    agents = nil
    bench { |built| agents = built }

    prompts = agents.flat_map(&:prompts)
    detail = prompts.find { |prompt| prompt.include?("## The Place") }
    assert_includes detail, "name: The Long Hallway"
    assert_includes detail, "## Who Is Here"
    assert_includes detail, "## What Is Lying Here"
    assert_includes detail, "Who they are is already decided"
    assert_includes detail, "The Unrecorded Hour", "the world's own title, not the staging label"

    exits = prompts.find { |prompt| prompt.include?("Now list the ways out") }
    assert_includes exits, "## Where This Room Already Leads"
    assert_includes exits, "- Ward Office 12"
    assert_includes exits, "The Supply Closet (already written -- do not open a new way into it)"
    assert_includes agents.filter_map(&:instructions).join("\n"), "You build the rooms of a text adventure"
  end

  # THE FACTS ARE THE ONES THE PROMPT WAS BUILT FROM, which is what makes the
  # offline scoring mean anything: a checker reading a different list from the
  # one the model was shown would be scoring a prompt nobody sent.
  test "the stored facts are the allowances and the lists the prompt carried" do
    hallway = row(bench.passes.sole, "a-hallway")
    facts = hallway["facts"]

    assert_equal 3, facts["exit_allowance"], "one of the room's four is spent on the way back"
    assert_equal [ "Ward Office 12" ], facts["reachable"]
    assert_equal "Ward Office 12", facts["reached_from"],
                 "the scorer's dead-end gate needs the way back by name, not merely a reachable list"
    assert_equal facts["people_allowance"], facts["slots"].size
    assert_includes facts["taken_names"], "Halkett Rowe"

    closet = facts["places"].find { |place| place["name"] == "The Supply Closet" }
    assert closet["realized"], "the closet is written in the seed file"
    assert_not closet["connected"], "and the hallway cannot reach it, which is what makes naming it a defect"
  end

  # AND WHAT THE REGISTRIES MADE OF THE ANSWER, off the records. The half a
  # reading of the JSON could not give.
  test "what the registries admitted is read off the records" do
    hallway = row(bench.passes.sole, "a-hallway")

    assert_equal [ "the disciplinary index" ], hallway.dig("after", "items")
    assert_equal [ "Vessa Kirn" ], hallway.dig("after", "people")
    assert_includes hallway.dig("after", "exits"), "The Stair Head",
                    "the one exit that named somewhere new"
    assert_includes hallway.dig("after", "new_places"), "The Stair Head"
    assert_not_includes hallway.dig("after", "exits"), "The Supply Closet",
                        "an exit into a written room is refused by Location::Generator#connect_exit!"
  end

  # A CASE'S OWN COPY OF THE WORLD. Without it the second case would be realized
  # into a world the first one had already written a room into.
  test "a case leaves nothing behind for the case after it" do
    pass = bench.passes.sole

    assert_includes row(pass, "a-hallway").dig("after", "new_places"), "The Stair Head"
    closet = row(pass, "b-closet")
    assert_not_includes closet["facts"]["places"].map { |place| place["name"] }, "The Stair Head"
    assert_equal [ "Ward Office 12", "The Long Hallway" ],
                 closet["facts"]["places"].map { |place| place["name"] }
  end

  # --- a room inside a laid-out place ---------------------------------------
  #
  # THE ONE CASE SHAPE THAT MEASURES ONE CALL ON PURPOSE. An interior room's
  # ways out were decided by `Location::Interior` before the room existed as
  # anything but a box, so `Location::Generator#write_exits!` asks a model for
  # none of them -- and what the detail prompt carries instead is the room's own
  # floor plan (`Location::Plan`).

  INTERIOR = <<~YML
    cases:
    - id: c-back-room
      story: The Quay House
      room: The Custom House room 3
      reached_from: The Custom House room 2
      expects_new_ground: false
      shape: interior-room
      why: a room of the one laid-out building in the repository
  YML

  test "a room inside a laid-out place is realized on one call and told its own floor plan" do
    agents = nil
    result = bench(corpus: interior) { |built| agents = built }
    row = result.passes.sole.rows.sole

    assert_equal 1, row["calls"], "the exits call is not made for a room whose doors are the engine's"
    assert_nil row.dig("answers", "exits")
    # Two prompts and not one: the bench warms each arm with a realization of
    # its own before the pass, and the warm-up is the same case.
    prompt = agents.flat_map(&:prompts).last
    assert_includes prompt, "## Where This Room Is"
    assert_includes prompt, "This room is 7 by 6 paces"
  end

  # THE PLAN IS STORED BESIDE THE ANSWER, because the world is rolled back when
  # the pass ends and a checker that wanted to ask the records would have
  # nothing left to ask (`Eval::Realization::Scorer`'s geometry checks).
  test "the floor plan the prompt stated is stored with the facts" do
    plan = bench(corpus: interior).passes.sole.rows.sole.dig("facts", "plan")

    assert_equal "The Custom House", plan["place"]
    assert_equal [ 7, 6, 0 ], [ plan["width"], plan["depth"], plan["storey"] ]
    # THE PLACE'S FOOTPRINT TOO, because `Location::Plan#storey_sentence` states
    # it -- and a checker that only had the room's box would flag prose for
    # repeating it (`Eval::Realization::Scorer#judge_size_the_records_do_not_hold`).
    assert_equal [ 14, 10 ], [ plan["place_width"], plan["place_depth"] ]
    assert_equal [ { "wall" => "north", "to" => "The Custom House room 2" },
                   { "wall" => "west", "to" => "The Custom House room 4" } ], plan["doors"]
  end

  # AND ITS DOORS ARE NOT WOUND BACK. Every other stub's edges arrived with its
  # realization and the case declares which; these arrived with the layout, so
  # dropping one would stage a room the engine never laid out.
  test "an interior room keeps every door the layout gave it" do
    plan = bench(corpus: interior).passes.sole.rows.sole.dig("facts", "plan")

    assert_equal 2, plan["doors"].size, "both doors, not only the one the case was reached from"
  end

  test "the world outside the run is untouched" do
    before = [ Story.count, Location.count, Item.count, Character.count, LocationConnection.count ]
    bench
    assert_equal before, [ Story.count, Location.count, Item.count, Character.count, LocationConnection.count ]
  end

  # A FAILED CALL IS A FAILED CASE AND NOT A FAILED RUN, and it carries no
  # latency: how long it took to fail is a fact about the failure.
  test "a refusal is a failure with a class beside it" do
    pass = bench(BaseAgent::RefusalError.new("I can't help with that")).passes.sole

    assert_equal 2, pass.failures
    assert_equal 2, pass.figures["refusals"]
    assert_equal 0, pass.scanned
    assert_nil row(pass, "a-hallway")["seconds"]
  end

  # WHAT A STORED ANSWER CANNOT SHOW: a required field that never arrived, and
  # one that arrived at its cap. Both are read off the provider's own JSON
  # against the schema's own `required` and `maxLength` -- INCLUDING the fields
  # inside a person, which is what a room loses its whole cast over.
  test "a missing field inside a person is reported, and so is one cut off at its cap" do
    clean = bench.passes.sole
    assert_empty row(clean, "a-hallway")["missing_fields"]
    assert_empty row(clean, "a-hallway")["cap_hits"]

    cut = Endless.stub_detail(Endless::DETAIL.deep_merge(
      "people" => [ Endless::DETAIL["people"].first.merge(
        "fears" => "", "appearance" => "x" * Character::Registry::PERSON_LIMITS[:appearance]
      ) ]
    )) { bench }

    assert_equal [ "detail.people[0].fears" ], row(cut.passes.sole, "a-hallway")["missing_fields"]
    assert_equal [ "detail.people[0].appearance" ], row(cut.passes.sole, "a-hallway")["cap_hits"]
  end

  # THE PINNING FAILING IS THE ONE THING A STORED SET MUST NOT BE SILENT ABOUT.
  # `Result.rotated?` is asked about a ROW, so a row that does not carry its arm
  # cannot be judged and the counter reads zero on exactly the run it exists to
  # catch. Both directions are pinned: a set whose rows were answered by the arm
  # counts none, and one answered by anything else counts them.
  test "a reading answered by another model is counted as a rotation in the stored set" do
    pass = bench(answered_by: "someone/else").passes.sole

    assert_equal "fake/model", row(pass, "a-hallway")["arm"], "the row says which arm it belongs to"
    assert_equal 1, row(pass, "a-hallway")["rep"]
    assert_equal "someone/else", row(pass, "a-hallway")["answered_by"]
    assert_equal pass.rows.size, pass.figures["rotations"],
                 "every row was answered by a model this arm was not pinned to"
  end

  test "a reading answered by its own arm is not a rotation" do
    pass = bench.passes.sole

    assert_equal "fake/model", row(pass, "a-hallway")["answered_by"]
    assert_equal 0, pass.figures["rotations"]
  end

  test "the digests describe what was measured" do
    result = bench

    assert_equal Eval::Realization.digest(@corpus), result.corpus_digest
    assert result.prompt_stable, "the same case sent the same scrubbed prompts in every repetition"
    assert_equal @corpus.by_shape.keys.sort, result.prompt_shapes.keys.sort,
                 "one designated prompt per shape"
  end

  private

  def row(pass, id) = pass.rows.find { |row| row["id"] == id }

  def interior = Eval::Realization::Corpus.load(written(INTERIOR))

  # A FAKE THAT LEAVES THE RECORDS A REAL CALL WOULD LEAVE, which is what makes
  # this a test of the bench and not of the fake: `Eval::Realization::Bench`
  # reads both answers, what they were told and what they cost off the `chats`
  # and `messages` rows the generator wrote, exactly as
  # `Playthrough::Feedback` does. A double that wrote none would leave every one
  # of those figures nil and prove nothing about them.
  def bench(answer = nil, answered_by: "fake/model", corpus: nil, &block)
    agents = []
    block&.call(agents)

    stub = lambda do |*args, **options|
      Endless.new(answer, purpose: options[:purpose], instructions: args.first,
                  answered_by: answered_by).tap { |agent| agents << agent }
    end

    BaseAgent.stub(:new, stub) do
      Eval::Realization::Bench.new(corpus: corpus || @corpus, arms: [ "fake/model" ], reps: 1, io: nil).run
    end
  end

  # `FakeAgent` answers from a queue, and this bench makes two calls a case, so
  # a queue would have to be as long as the corpus and in the right order. This
  # answers by SCHEMA -- which is how the generator itself tells its two calls
  # apart -- and writes the conversation down.
  class Endless < FakeAgent
    DETAIL = {
      "description" => "Doors close one after another down the length of it, and the light is out at the far end.",
      "lore" => "The ward's own corridor, walked by everybody and recorded by nobody.",
      "items" => [ { "name" => "the disciplinary index", "description" => "A thin card file, out of its drawer.",
                     "readable" => true, "inscription" => "LASCO, P. -- SEE WARD OFFICE 12" } ],
      "people" => [ { "fullname" => "Vessa Kirn", "nickname" => "Kirn",
                      "appearance" => "Stooped over an armful of folders she has not put down.",
                      "personality" => "Talks to a stranger the way she talks to a form.",
                      "backstory" => "Vessa Kirn was sent up from filing an hour ago and nobody has told her why.",
                      "likes" => "carbon paper, quiet", "dislikes" => "the seventh bell",
                      "fears" => "being asked what she saw" } ]
    }.freeze

    EXITS = {
      "exits" => [
        { "name" => "The Stair Head", "teaser" => "The stair down, and the shoes you can hear on it.",
          "distance" => "adjacent", "travel_method" => "walking" },
        { "name" => "The Supply Closet", "teaser" => "No inventory number and no lock.",
          "distance" => "adjacent", "travel_method" => "walking" }
      ]
    }.freeze

    # The detail answer, so a test can stand a truncated or incomplete one in its
    # place for the length of a run.
    def self.stub_detail(answer)
      was = @detail
      @detail = answer
      yield
    ensure
      @detail = was
    end

    def self.detail = @detail || DETAIL

    attr_reader :purpose

    def initialize(answer = nil, purpose: nil, instructions: nil, answered_by: "fake/model")
      super()
      @answer = answer
      @purpose = purpose
      @instructions = instructions
      @answered_by = answered_by
      @written = []
    end

    def ask(prompt, verify: nil, &block)
      @prompts << prompt
      raise @answer if @answer.is_a?(Exception)

      content = @schemas.last == Location::ExitsSchema ? EXITS : self.class.detail
      write!(prompt, content)
      verify&.call(content)
      Response.new(content)
    end

    def recorded_chat = @chat

    def current_model = { provider: :fake, model: "fake/model" }

    private

    # THE REGISTRY ROW IS ASSOCIATED RATHER THAN THE ID ASSIGNED, which is the
    # rule `test/factories/chats.rb` states: assigning `model_id` as a string
    # makes RubyLLM resolve it through the provider, which needs an API key, and
    # this test has none and wants none.
    def write!(prompt, content)
      @chat ||= Chat.create!(purpose: purpose, model: registry).tap do |chat|
        chat.messages.create!(role: "system", content: @instructions, model: registry) if @instructions
      end
      @written << @chat.messages.create!(role: "user", content: prompt, model: registry)
      @written << @chat.messages.create!(role: "assistant", model: registry, content: content.to_json,
                                         content_raw: content, input_tokens: 900, output_tokens: 250)
    end

    # THE MODEL ROW THE MESSAGES ARE WRITTEN AGAINST, which is where the bench
    # reads `answered_by` from. A run where the pinning failed writes a row
    # naming the model that really answered, so a test of the rotation guard has
    # to be able to stand one up.
    def registry
      @registry ||= Model.find_by(model_id: @answered_by) ||
                    FactoryBot.create(:model, model_id: @answered_by, name: @answered_by,
                                              provider: "openrouter")
    end
  end

  def written(body)
    file = Tempfile.new([ "realization_corpus", ".yml" ])
    file.write(body)
    file.close
    file.path
  end
end
