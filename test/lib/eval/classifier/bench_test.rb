require "test_helper"

# THE SCORING, WITH THE MODEL STOOD IN FOR.
#
# The bench's job is to compare a classifier answer with a hand-written label,
# and the interesting part is not the call -- it is what counts as right. Every
# rule below was a decision:
#
#   * a wrong INTENT and a wrong RECORD are different failures, and the closed-set
#     miss (right branch, wrong record) is counted on its own because it is the
#     one the closed enum was built to prevent;
#   * a two-name answer matches whichever way round it comes back, because
#     nothing in the app decides which of the two is `target`;
#   * a line whose English admits two readings is scored against both, and the
#     headline rate is taken over the lines that do not;
#   * `also_named` is a DETECTOR and has two ways to be wrong.
#
# NEVER A LIVE MODEL. `FakeAgent` stands in at the `BaseAgent` boundary, exactly
# as it does in `Playthrough::ClassifierTest`, so this runs in CI for nothing.
class Eval::Classifier::BenchTest < ActiveSupport::TestCase
  # Four lines against the seeded office, which between them cover a resolving
  # take, a reach that must find nothing, an `other` that must not be refused,
  # and a two-name line that must be.
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
      why: one of two things on this floor, so a second name COULD have resolved and must not
    - id: a-pair
      position: closet
      typed: take the index and the apron
      intent: take
      target: Perrin's private index
      also_named: copy-room apron
      refusal: named_more_than_one
      shape: two-names-one-set
      why: two things on one floor
  YML

  def setup
    @corpus = Eval::Classifier::Corpus.load(written(CORPUS))
  end

  test "a bench pass scores every line and reports the whole answer" do
    result = bench(perfect)

    pass = result.passes.sole
    assert_equal 5, pass.scored.size
    assert_in_delta 1.0, pass.accuracy
    assert_in_delta 1.0, pass.strict_accuracy
    assert_in_delta 1.0, pass.refusal_agreement
    assert_equal 0, pass.closed_set_misses
    assert_equal 0, pass.rotations
  end

  test "a wrong record on the right branch is a closed-set miss and not a wrong branch" do
    pass = bench(perfect.merge("a-take" => { "intent" => "take", "target" => "Ward Office 12 daybook" })).passes.sole
    reading = pass.readings.find { |row| row.id == "a-take" }

    assert reading.intent_right?, "the branch was right"
    assert_not reading.right?
    assert reading.closed_set_miss?
    assert_equal 1, pass.closed_set_misses
    assert_in_delta 0.8, pass.accuracy
    assert_in_delta 1.0, pass.intent_accuracy, 0.001, "every branch was still right"
  end

  test "a wrong branch is not counted as a closed-set miss" do
    pass = bench(perfect.merge("an-other" => { "intent" => "move", "target" => "The Long Hallway" })).passes.sole
    reading = pass.readings.find { |row| row.id == "an-other" }

    assert_not reading.intent_right?
    assert_not reading.closed_set_miss?, "a wrong branch is a different failure from a wrong record"
    assert_in_delta 0.8, pass.intent_accuracy
  end

  # THE RULING OF 2026-09-04, as a number. A reach the model resolves anyway is
  # a line the engine will play that should have been refused, and the reverse
  # is a refusal the player reads for no reason.
  test "refusal agreement follows the answer and not the label" do
    pass = bench(perfect.merge("a-reach" => { "intent" => "take", "target" => "ward stamp" })).passes.sole
    reading = pass.readings.find { |row| row.id == "a-reach" }

    assert_equal :none, reading.refusal, "a resolved take is a line the engine plays"
    assert_not reading.refusal_right?, "the label says this line earns :unresolved"
    assert_in_delta 0.8, pass.refusal_agreement
  end

  test "a two-name answer is right whichever way round the pair comes back" do
    swapped = perfect.merge("a-pair" => { "intent" => "take", "target" => "copy-room apron",
                                          "also_named" => "Perrin's private index" })
    reading = bench(swapped).passes.sole.readings.find { |row| row.id == "a-pair" }

    assert reading.right?
    assert_equal :named_more_than_one, reading.refusal
    assert reading.also_true_positive?
  end

  test "a second name on a line that named one thing is an also_named false positive" do
    invented = perfect.merge("a-single" => { "intent" => "take", "target" => "Perrin's private index",
                                             "also_named" => "copy-room apron" })
    reading = bench(invented).passes.sole.readings.find { |row| row.id == "a-single" }

    assert reading.also_false_positive?
    assert_not reading.right?, "an invented second name refuses a line that should have played"
  end

  test "a missing second name on a line that named two is an also_named false negative" do
    halved = perfect.merge("a-pair" => { "intent" => "take", "target" => "Perrin's private index" })
    reading = bench(halved).passes.sole.readings.find { |row| row.id == "a-pair" }

    assert reading.also_false_negative?
    assert_not reading.also_true_positive?
    assert_equal :none, reading.refusal, "half a line played is exactly what the ruling was made to stop"
  end

  test "a failed call is recorded as a failure and the pass keeps going" do
    answers = perfect.merge("a-reach" => RuntimeError.new("the provider hung up"))
    pass = bench(answers).passes.sole

    assert_equal 1, pass.failures
    assert_equal 4, pass.scored.size, "one dropped call must not cost the other four lines"
    assert_in_delta 1.0, pass.accuracy, 0.001
  end

  test "the persisted rows carry what a board prints and survive a round trip" do
    Dir.mktmpdir do |directory|
      bench(perfect).write!(directory, name: "unit")
      reloaded = Eval::Classifier::Result.load(directory)

      assert_equal "unit", reloaded.name
      assert_equal 5, reloaded.corpus_size
      assert_equal [ 1.0 ], reloaded.values(:strict_accuracy)
      assert_equal 5, reloaded.rows.size
      assert reloaded.rows.all? { |row| row["right"] }
    end
  end

  test "the board prints without a live model and names the lines that missed" do
    result = bench(perfect.merge("a-take" => { "intent" => "take", "target" => "Ward Office 12 daybook" }))
    out = StringIO.new
    Eval::Classifier::Report.new(result, io: out).print

    printed = out.string
    assert_match(/THE CLASSIFIER BENCH -- 5 labelled lines/, printed)
    assert_match(/CLOSED-SET MISS/, printed)
    assert_match(/a-take/, printed)
    assert_match(/CONFUSION/, printed)
    assert_match(/also_named/, printed)
  end

  private

  # Every line answered exactly as its label says.
  def perfect
    @corpus.lines.to_h do |line|
      [ line.id, { "intent" => line.intent.to_s, "target" => line.target || Playthrough::IntentSchema::NOTHING,
                   "also_named" => line.also_named || Playthrough::IntentSchema::NOTHING } ]
    end
  end

  # THE FAKE ANSWERS BY LINE AND NOT IN ORDER, because a queue would silently
  # mis-attribute every answer the moment a line was added above it.
  def bench(answers)
    agent = ByLine.new(answers, @corpus)
    BaseAgent.stub(:new, ->(**_options) { agent }) do
      Eval::Classifier::Bench.new(corpus: @corpus, arms: [ "fake/model" ], reps: 1, io: nil).run
    end
  end

  class ByLine < FakeAgent
    def initialize(answers, corpus)
      super
      @answers = answers
      @corpus = corpus
    end

    def ask(prompt, verify: nil)
      typed = prompt[/## The Player Types\n(.*)\n/m, 1].to_s.strip
      line = @corpus.lines.find { |row| row.typed.strip == typed }
      raise "no corpus line typed #{typed.inspect}" if line.nil?

      answer = @answers.fetch(line.id)
      raise answer if answer.is_a?(Exception)

      Response.new(answer)
    end

    def current_model = { provider: :fake, model: "fake/model" }
  end

  def written(body)
    file = Tempfile.new([ "bench_corpus", ".yml" ])
    file.write(body)
    file.close
    file.path
  end
end
