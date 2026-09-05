require "test_helper"

# THE TURN, WITH THE MODEL STOOD IN FOR.
#
# The bench's job is to put the app's OWN prompt in front of a model and keep
# what came back beside the facts it was written against, and every part of that
# is testable without paying for a call:
#
#   * the prompt is `Playthrough::Moment`'s and `Playthrough::Turn`'s, not this
#     class's -- so a case's facts really do reach the narrator;
#   * the branch is chosen by `Playthrough::Turn#play` off the case's declared
#     action, so a `take` takes and a `move` reaches the arrival pass;
#   * the facts stored beside the passage are the ones the checks read;
#   * A CASE LEAVES NOTHING BEHIND. Each one runs inside a savepoint that is
#     rolled back, so the case after it stands in the same room with the same
#     things on the same floor.
#
# NEVER A LIVE MODEL. `FakeAgent` stands in at the `BaseAgent` boundary, exactly
# as it does in `Eval::Classifier::BenchTest`, so this runs in CI for nothing.
class Eval::Prompt::BenchTest < ActiveSupport::TestCase
  CORPUS = <<~YML
    positions:
    - id: office
      story: The Unrecorded Hour
      room: Ward Office 12
    cases:
    - id: a-take
      position: office
      typed: pick up the ward stamp
      act: take
      target: ward stamp
      shape: take
      why: the only thing on this floor
    - id: a-drop
      position: office
      typed: put the daybook down
      act: drop
      target: Ward Office 12 daybook
      shape: drop
      why: the only thing in these hands
    - id: a-move
      position: office
      typed: go to the supply closet
      act: move
      target: The Supply Closet
      shape: move
      why: the one realized door
    - id: an-other
      position: office
      typed: wait
      act: other
      shape: other
      why: reaches for no record
  YML

  def setup
    @corpus = Eval::Prompt::Corpus.load(written(CORPUS))
  end

  test "a pass plays every case and keeps the passage with the facts beside it" do
    result = bench

    pass = result.passes.sole
    assert_equal 4, pass.rows.size
    assert_equal 4, pass.scanned
    assert_equal 0, pass.failures

    take = row(pass, "a-take")
    assert_equal "narration", take["pass"]
    assert_equal 1, take["calls"], "a case is one model call and not one more"
    assert_equal "Ward Office 12", take.dig("facts", "room")
    assert_includes take.dig("facts", "carried"), "ward stamp"
    assert_equal "ward stamp", take.dig("facts", "item")
  end

  # THE PROMPT IS THE APP'S. Not a fixture, not a copy: the case's facts reach
  # the narrator through `Playthrough::Moment`, and the sentence about what
  # already happened is `Playthrough::Turn#taken_fact`.
  test "the narrator is handed the moment the app would have built" do
    agents = nil
    bench { |built| agents = built }

    prompts = agents.flat_map(&:prompts)
    take = prompts.find { |prompt| prompt.include?("pick up the ward stamp") }
    assert_includes take, "The player is in Ward Office 12"
    assert_includes take, "Ways out of here: The Supply Closet, The Long Hallway"
    assert_includes take, "Also here: Halkett Rowe"
    assert_includes take, "has picked up the ward stamp and is now carrying it",
                    "the fact the app writes, not one this bench composes"
    assert_includes agents.filter_map(&:instructions).join("\n"),
                    "You are the narrator of a text adventure"
  end

  # A `move` REACHES THE OTHER PROSE PASS, which is schema'd and has its own
  # instructions -- so the bench measures two prompt versions and has to record
  # which one answered.
  test "a move reaches the arrival pass and not the narrator" do
    pass = bench.passes.sole
    moved = row(pass, "a-move")

    assert_equal "arrival", moved["pass"]
    assert_equal "The Supply Closet", moved.dig("facts", "room")
    assert moved.dig("facts", "moved"), "the case moved, so unrecorded_departure must not be judged on it"
  end

  # ITS OWN COPY OF THE WORLD PER CASE. Without it the second case would stand in the room the first
  # one left it in, holding what the first one picked up.
  test "a case leaves nothing behind for the case after it" do
    pass = bench.passes.sole

    # The take put the stamp in the party's hands...
    assert_includes row(pass, "a-take").dig("facts", "carried"), "ward stamp"
    # ...and the drop, played next, still found the daybook there and the stamp
    # on the floor, which is only true if the take was rolled back.
    assert_includes row(pass, "a-drop").dig("facts", "floor"), "ward stamp"
    assert_includes row(pass, "a-drop").dig("facts", "floor"), "Ward Office 12 daybook"
    # ...and the move, played after both, walked out of the room the position
    # names rather than the one the move before it would have left.
    assert_equal "Ward Office 12", row(pass, "a-move").dig("facts", "from")
  end

  test "the world outside the run is untouched" do
    before = [ Story.count, Item.count, Scene.count, Playthrough.count ]
    bench
    assert_equal before, [ Story.count, Item.count, Scene.count, Playthrough.count ]
  end

  # A FAILED CALL IS A FAILED CASE AND NOT A FAILED RUN, and it carries no
  # latency: how long it took to fail is a fact about the failure.
  test "a refusal is a failure with a class beside it" do
    result = bench(BaseAgent::RefusalError.new("I can't help with that"))
    pass = result.passes.sole

    assert_equal 4, pass.failures
    assert_equal 4, pass.figures["refusals"]
    assert_equal 0, pass.scanned, "a refusal is not a passage"
    assert_nil row(pass, "a-take")["seconds"]
  end

  # WHAT A STORED PASSAGE CANNOT SHOW: a required field that never arrived, and
  # a field that arrived at its cap. Only a schema'd pass has either, so this is
  # the arrival's figure -- read off the provider's own JSON against the
  # schema's own `required` and `maxLength`.
  test "a schema'd pass reports its omitted fields and its cap hits, and a clean answer reports neither" do
    pass = bench.passes.sole
    moved = row(pass, "a-move")

    assert_empty moved["missing_fields"], "both fields arrived, so neither is missing"
    assert_empty moved["cap_hits"]
    assert_equal 0, pass.figures["omitted_fields"]

    cut = bench_with_arrival("description" => "x" * Scene::Schema.new.to_json_schema
                                                    .deep_stringify_keys.dig("schema", "properties", "description", "maxLength"))
    assert_equal [ "summary" ], row(cut.passes.sole, "a-move")["missing_fields"]
    assert_equal [ "description" ], row(cut.passes.sole, "a-move")["cap_hits"]
  end

  test "the digests describe what was measured" do
    result = bench

    assert_equal Eval::Prompt.digest(@corpus), result.corpus_digest
    assert result.prompt_stable, "the same case sent the same prompt in every repetition"
    assert_equal @corpus.by_shape.keys.sort, result.prompt_shapes.keys.sort,
                 "one designated prompt per shape"
  end

  private

  def row(pass, id) = pass.rows.find { |row| row["id"] == id }

  # The same run with the arrival answering something the schema asked it not
  # to: one field at its cap and the other absent.
  def bench_with_arrival(answer)
    Endless.stub_const(answer) { bench }
  end

  # A FAKE THAT LEAVES THE RECORDS A REAL CALL WOULD LEAVE, which is what makes
  # this a test of the bench and not of the fake: `Eval::Prompt::Bench` reads
  # which pass answered, what it was told and what it cost off the `chats` and
  # `messages` rows the turn wrote, exactly as `Playthrough::Feedback` does. A
  # double that wrote none would leave every one of those figures nil and prove
  # nothing about them.
  def bench(answer = nil, &block)
    agents = []
    block&.call(agents)

    stub = lambda do |*args, **options|
      Endless.new(answer, purpose: options[:purpose], playthrough: options[:playthrough],
                  instructions: args.first).tap { |agent| agents << agent }
    end

    BaseAgent.stub(:new, stub) do
      Eval::Prompt::Bench.new(corpus: @corpus, arms: [ "fake/model" ], reps: 1, io: nil).run
    end
  end

  # `FakeAgent` answers from a queue, and this bench makes one call a case, so a
  # queue would have to be as long as the corpus and in the right order -- the
  # mis-attribution `Eval::Classifier::BenchTest` avoids the same way. This
  # answers the same thing every time, keyed only on whether the caller asked
  # for a schema, and writes the conversation down.
  class Endless < FakeAgent
    ARRIVAL = { "description" => "The door swings shut behind you and the closet closes in.",
                "summary" => "The player steps into the supply closet." }.freeze

    # The arrival's answer, so a test can stand a truncated or incomplete one in
    # its place for the length of a run.
    def self.stub_const(answer)
      was = @arrival
      @arrival = answer
      yield
    ensure
      @arrival = was
    end

    def self.arrival = @arrival || ARRIVAL
    NARRATION = "You do the thing, and the room is exactly as it was.".freeze

    attr_reader :purpose

    def initialize(answer = nil, purpose: nil, playthrough: nil, instructions: nil)
      super()
      @answer = answer
      @purpose = purpose
      @playthrough = playthrough
      @instructions = instructions
      @written = []
    end

    def ask(prompt, verify: nil, &block)
      @prompts << prompt
      raise @answer if @answer.is_a?(Exception)

      content = @schemas.any? ? self.class.arrival : NARRATION
      write!(prompt, content)
      block&.call(Chunk.new(content)) if content.is_a?(String)
      verify&.call(content)
      Response.new(content)
    end

    def recorded_chat = @chat

    # The same contract `BaseAgent#attribute_to!` keeps: the messages this agent
    # wrote get stamped with the turn, and the system instruction does not.
    def attribute_to!(scene) = @written.each { |message| message.update!(scene: scene) }

    def current_model = { provider: :fake, model: "fake/model" }

    private

    # THE REGISTRY ROW IS ASSOCIATED RATHER THAN THE ID ASSIGNED, which is the
    # rule `test/factories/chats.rb` states: assigning `model_id` as a string
    # makes RubyLLM resolve it through the provider, which needs an API key, and
    # this test has none and wants none.
    def write!(prompt, content)
      @chat ||= Chat.create!(purpose: purpose, playthrough: @playthrough, model: registry).tap do |chat|
        chat.messages.create!(role: "system", content: @instructions, model: registry) if @instructions
      end
      @written << @chat.messages.create!(role: "user", content: prompt, model: registry)
      @written << @chat.messages.create!(role: "assistant", model: registry,
                                         content: content.is_a?(String) ? content : content.to_json,
                                         content_raw: content.is_a?(Hash) ? content : nil,
                                         input_tokens: 100, output_tokens: 20)
    end

    def registry
      @registry ||= Model.find_by(model_id: "fake/model") ||
                    FactoryBot.create(:model, model_id: "fake/model", name: "fake", provider: "openrouter")
    end
  end

  def written(body)
    file = Tempfile.new([ "prompt_corpus", ".yml" ])
    file.write(body)
    file.close
    file.path
  end
end
