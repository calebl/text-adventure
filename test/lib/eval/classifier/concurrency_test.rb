require "test_helper"

# THE LINES OF A PASS RUNNING AT THE SAME TIME, AND THE THREE THINGS THAT MAKE
# THAT A MEASUREMENT RATHER THAN A RACE.
#
# Every test here is offline and free: `FakeAgent` stands in at the `BaseAgent`
# boundary, exactly as it does in `Eval::Classifier::BenchTest`. What is being
# checked is the harness -- the order the readings come back in, the rollback,
# and the deadlock that the shape this replaced produced on the first try.
class Eval::Classifier::ConcurrencyTest < ActiveSupport::TestCase
  CORPUS = <<~YML
    positions:
    - id: office
      story: The Unrecorded Hour
      room: Ward Office 12
    - id: closet
      story: The Unrecorded Hour
      room: The Supply Closet
    lines:
    - id: a-take
      position: office
      typed: take the ward stamp
      intent: take
      target: ward stamp
      shape: take
      why: the only thing on this floor
    - id: a-reach
      position: office
      typed: take the tide-slate
      intent: take
      refusal: unresolved
      shape: unresolved-take
      why: another world's item
    - id: an-other
      position: office
      typed: wait
      intent: other
      shape: other
      why: reaches for no record and must not be refused
    - id: a-single
      position: closet
      typed: take the index
      intent: take
      target: Perrin's private index
      shape: take
      why: one of two things on this floor
  YML

  def setup
    @corpus = Eval::Classifier::Corpus.load(written(CORPUS))
  end

  # THE BUG THIS PREVENTS PRODUCES PLAUSIBLE NUMBERS AND NO ERROR. Readings
  # appended as they arrive land in completion order, so every one of them is
  # scored against another line's label and the accuracy is meaningless in a way
  # nothing in the output would show.
  test "a concurrent pass answers in corpus order and reads the same as a serial one" do
    serial = bench(concurrency: 1).passes.sole
    concurrent = bench(concurrency: 4).passes.sole

    assert_equal @corpus.lines.map(&:id), serial.readings.map(&:id)
    assert_equal @corpus.lines.map(&:id), concurrent.readings.map(&:id),
                 "written back by index, so the corpus order survives whatever order they finished in"
    assert_equal serial.readings.size, concurrent.readings.size
    assert_equal serial.readings.map(&:right?), concurrent.readings.map(&:right?)
    assert_in_delta 1.0, serial.accuracy, 0.001, "otherwise the two could agree by both failing"
    assert_in_delta serial.accuracy, concurrent.accuracy
    assert_equal 0, concurrent.failures, concurrent.failed.map(&:error).inspect
  end

  # THE ROLLBACK IS THE WHOLE REASON A BENCH IS SAFE AGAINST A HALF-PLAYED
  # DATABASE, and `Eval::Concurrency.rolled_back` is a different mechanism from
  # the transaction it replaced -- so it is asserted again here rather than
  # assumed to have carried over.
  test "a concurrent pass leaves the row counts exactly as it found them" do
    before = counts

    bench(concurrency: 4)

    assert_equal before, counts
  end

  # THE DEADLOCK, AS A REGRESSION TEST. Nesting the workers inside
  # `ActiveRecord::Base.transaction` hangs for ever on the first statement any
  # worker makes: `within_new_transaction` holds the connection lock for the
  # whole duration of its block. This is timeout-guarded because the failure
  # mode is a hang and not an assertion -- an unguarded version of this test
  # would wedge CI rather than fail it.
  test "four workers complete inside Stage.open instead of deadlocking on the connection lock" do
    finished = Thread.new do
      Eval::Classifier::Stage.open(@corpus.positions) do |stages|
        Eval::Concurrency.fan((1..8).to_a, threads: 4) do |number|
          # A real query on the shared pinned connection, which is what the
          # workers of a pass are really doing between round trips.
          stages.fetch("office").playthrough.story.locations.count + number
        end
      end
    end

    assert finished.join(30), "the workers deadlocked on the connection lock -- see Eval::Concurrency's header"
    assert_equal 8, finished.value.size
  end

  test "a local arm runs one call at a time whatever the concurrency asks for" do
    bench = Eval::Classifier::Bench.new(corpus: @corpus, arms: [ "ollama:qwen3:4b" ], reps: 1, io: nil,
                                        concurrency: 8)

    assert_equal 1, bench.concurrency_for(Eval::Classifier::Arm.parse("ollama:qwen3:4b")),
                 "one CPU-only daemon has nothing to overlap; concurrency would report queueing as model speed"
    assert_equal 8, bench.concurrency_for(Eval::Classifier::Arm.parse("mistralai/mistral-medium-3.1"))
  end

  # `Arm#pinned` REWRITES A SINGLETON METHOD ON `BaseAgent`, which is
  # process-global. Two benches at once in one process answer as each other's
  # model and the `rotations` guard cannot see it, because it reads the same
  # corrupted `BaseAgent`.
  test "a second bench in this process is refused rather than measured" do
    Eval::Classifier::Bench.exclusive("some other arm") do
      error = assert_raises(Eval::Classifier::Bench::ConcurrentArms) { bench(concurrency: 1) }

      assert_match(/some other arm/, error.message)
      assert_match(/one arm per process/, error.message)
    end
  end

  test "the claim is released even when the run raised" do
    assert_raises(RuntimeError) do
      Eval::Classifier::Bench.exclusive("an arm") { raise "the pass blew up" }
    end

    Eval::Classifier::Bench.exclusive("the next arm") { assert true }
  end

  # THE NUMBER IS RECORDED BECAUSE IT MOVES THE LATENCY COLUMNS AND NOTHING
  # ELSE, and a set written before it existed reads as serial.
  test "the concurrency is recorded on the result and survives a round trip" do
    Dir.mktmpdir do |directory|
      bench(concurrency: 4).write!(directory, name: "unit")

      assert_equal 4, Eval::Classifier::Result.load(directory).concurrency
    end
  end

  test "a set written before concurrency existed reads as serial" do
    Dir.mktmpdir do |directory|
      bench(concurrency: 4).write!(directory, name: "unit")
      file = File.join(directory, Eval::Classifier::RESULTS)
      document = JSON.parse(File.read(file))
      document.delete("concurrency")
      File.write(file, JSON.pretty_generate(document))

      assert_equal Eval::Classifier::Result::SERIAL, Eval::Classifier::Result.load(directory).concurrency
    end
  end

  private

  def counts
    { stories: Story.count, playthroughs: Playthrough.count, items: Item.count,
      chats: Chat.count, scenes: Scene.count }
  end

  def bench(concurrency:)
    agent = ByLine.new(@corpus)
    BaseAgent.stub(:new, ->(**_options) { agent }) do
      Eval::Classifier::Bench.new(corpus: @corpus, arms: [ "fake/model" ], reps: 1, io: nil,
                                  concurrency: concurrency).run
    end
  end

  # Every line answered exactly as its label says, found by what was typed --
  # never by a queue, because a queue is precisely the mis-attribution these
  # tests are about.
  class ByLine < FakeAgent
    def initialize(corpus)
      super
      @corpus = corpus
    end

    def ask(prompt, verify: nil)
      typed = prompt[/## The Player Types\n(.*)\n/m, 1].to_s.strip
      line = @corpus.lines.find { |row| row.typed.strip == typed }
      raise "no corpus line typed #{typed.inspect}" if line.nil?

      Response.new({ "intent" => line.intent.to_s,
                     "target" => line.target || Playthrough::IntentSchema::NOTHING,
                     "also_named" => line.also_named || Playthrough::IntentSchema::NOTHING })
    end

    def current_model = { provider: :fake, model: "fake/model" }
  end

  def written(body)
    file = Tempfile.new([ "concurrency_corpus", ".yml" ])
    file.write(body)
    file.flush
    file.path
  end
end
