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

  test "physical choice tokens score their item and recipient rather than only their subject" do
    corpus = Eval::Classifier.corpus.subset { |line| line.id == "use-offer-daybook-perrin" }
    bench = Eval::Classifier::Bench.new(corpus: corpus, arms: [ "fake/model" ], reps: 1, io: nil)
    arm = Eval::Classifier::Arm.parse("fake/model")

    Eval::Classifier::Stage.open(corpus.positions) do |stages|
      standing = stages.fetch(corpus.lines.sole.position)
      readings = %w[Perrin Halkett].map do |recipient|
        choice = standing.offered_for(:use).find { |offer| offer.recipient.fullname.start_with?(recipient) }
        agent = FakeAgent.new({ "intent" => "use", "target" => choice.token, "also_named" => "nothing" })
        BaseAgent.stub(:new, agent) { bench.send(:read, corpus.lines.sole, standing, arm, 1) }
      end

      assert_predicate readings.first, :right?, readings.first.error
      assert_equal corpus.lines.sole.target, readings.first.answer.target
      assert_predicate readings.last, :closed_set_miss?, "the same item offered to the wrong person is a wrong target"
      assert_equal "Offer Ward Office 12 daybook to Halkett Rowe; they may refuse", readings.last.answer.target
      assert_not_includes readings.first.answer.target, "use:"
    end
  end

  # THE POPULATION SHAPE C CLAIMS TO MOVE, counted the way `Playthrough::Drift`
  # counts it: a closed-set action (`move`, `talk`, `take`, `drop`, `attack`,
  # `use`) that resolved to no record at all -- whether the model named
  # something this room does not have (out of set AND, since the intent was
  # still right, a closed-set miss too) or correctly saw nothing there
  # (out of set, and no miss). The two counters overlap on the first shape and
  # diverge on the second, which is the whole reason they are two counters.
  test "an out-of-set answer is counted separately from a closed-set miss, and a resolved line is neither" do
    pass = bench(perfect).passes.sole

    resolved = pass.readings.find { |row| row.id == "a-take" }
    assert_predicate resolved, :right?
    assert_not resolved.out_of_set?, "a resolved take named something this room actually has"

    genuinely_absent = pass.readings.find { |row| row.id == "a-reach" }
    assert_predicate genuinely_absent, :right?, "the label expects nothing, and the model correctly answered nothing"
    assert genuinely_absent.out_of_set?, "a take that resolved to no record is the drift population regardless of why"
    assert_not genuinely_absent.closed_set_miss?, "the branch AND the record were both right, so this is not a miss"

    cross_room_name = bench(perfect.merge("a-take" => { "intent" => "take", "target" => "Perrin's private index" }))
                        .passes.sole.readings.find { |row| row.id == "a-take" }
    assert cross_room_name.closed_set_miss?, "the right branch, naming a record another room's floor holds"
    assert cross_room_name.out_of_set?, "and this room's own set has nothing that name resolves to either"

    assert_equal 1, pass.out_of_set
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

  # --- speed, on the captain's instruction of 2026-09-04 ------------------

  test "every answered reading is timed and a failed one is deliberately not" do
    pass = bench(perfect.merge("a-reach" => RuntimeError.new("the provider hung up"))).passes.sole

    assert_equal 4, pass.latencies.size, "a latency per reading that answered"
    assert pass.latencies.all? { |seconds| seconds >= 0 }, "CLOCK_MONOTONIC never goes backwards"
    assert_nil pass.readings.find { |row| row.id == "a-reach" }.seconds,
               "how long a call took to FAIL is a fact about the failure, not about how fast the model answers"
    assert_operator pass.latency_median, :>=, 0
  end

  # THE WORST TURN IN TWENTY, nearest-rank, so the figure is one of the observed
  # values and a reader can go and find it in the rows.
  test "the p95 is the nearest observed value and not an interpolation" do
    pass = Eval::Classifier::Bench::Pass.new(arm: "m", rep: 1, readings: timed([ 1, 2, 3, 4, 100 ]))

    assert_equal 3, pass.latency_median
    assert_equal 100, pass.latency_p95, "five readings: the 95th percentile is the slowest of them"
    assert_equal 0.0, Eval::Classifier::Bench::Pass.new(arm: "m", rep: 1, readings: []).latency_p95
  end

  # A SLOW ARM AND A FLAKY ARM READ DIFFERENTLY, which is why the failures are
  # grouped by what raised rather than counted.
  test "failures are grouped by error class, because a count cannot say why" do
    answers = perfect.merge("a-reach" => RuntimeError.new("hung up"),
                            "an-other" => BaseAgent::SchemaIgnoredError.new("answered prose"))
    pass = bench(answers).passes.sole

    assert_equal 2, pass.failures
    assert_equal({ "RuntimeError" => 1, "BaseAgent::SchemaIgnoredError" => 1 }, pass.failures_by_class)
  end

  test "the board prints speed and flakiness together, and says what the latency covers" do
    result = bench(perfect.merge("a-reach" => RuntimeError.new("hung up")))
    out = StringIO.new
    Eval::Classifier::Report.new(result, io: out).print

    printed = out.string
    assert_match(/latency_median/, printed)
    assert_match(/latency_p95/, printed)
    assert_match(/answered\s+4 of 5/, printed)
    assert_match(/FAILED CALLS\s+1/, printed)
    assert_match(/RuntimeError\s+1/, printed)
  end

  # A CASCADE RUN IS PRICED OVER THE CALLS IT ACTUALLY MADE. A line the cascade
  # composed never reached the arm, so pricing every reading as an arm call
  # reported about five times the real bill -- and a spend figure nobody can
  # budget the next run from is worse than none.
  test "a cascade run prices the calls that reached the arm and says what it left out" do
    live = bench(perfect)
    pass = live.passes.sole
    composed = pass.readings.first(3).map { |reading| reading.with(resolved_by: "typed_model") }
    escalated = pass.readings.drop(3).map { |reading| reading.with(resolved_by: "typed_model_escalated") }
    result = Eval::Classifier::Result.new(
      corpus_size: live.corpus_size, arms: live.arms, reps: 1, cascade: true, warmups: live.warmups,
      passes: [ Eval::Classifier::Bench::Pass.new(arm: live.arms.sole, rep: 1, readings: composed + escalated) ]
    )
    out = StringIO.new
    Eval::Classifier::Report.new(result, io: out).print

    assert_match(/cost\s+\$[\d.]+ over 2 calls -- the 3 the cascade composed never reached it/, out.string)
    assert_match(/answered\s+5 of 5/, out.string, "every line still answered -- by one reader or the other")
  end

  test "a run with the reader pinned off prices every reading, as it always has" do
    out = StringIO.new
    Eval::Classifier::Report.new(bench(perfect), io: out).print

    assert_match(/cost\s+\$[\d.]+ over 5 calls\n/, out.string)
  end

  test "a local arm is labelled and its cost is stated as nothing" do
    agent = ByLine.new(perfect, @corpus)
    result = BaseAgent.stub(:new, ->(**_options) { agent }) do
      Eval::Classifier::Bench.new(corpus: @corpus, arms: [ "ollama:qwen3:4b" ], reps: 1, io: nil).run
    end
    out = StringIO.new
    Eval::Classifier::Report.new(result, io: out).print

    assert_equal [ "ollama:qwen3:4b" ], result.arms
    assert_equal [ "ollama:qwen3:4b" ], result.local_arms
    assert_match(/\[LOCAL\]/, out.string)
    assert_match(/cost\s+nothing -- a local model/, out.string)
  end

  test "the persisted rows carry what a board prints and survive a round trip" do
    Dir.mktmpdir do |directory|
      bench(perfect).write!(directory, name: "unit")
      reloaded = Eval::Classifier::Result.load(directory)

      assert_equal "unit", reloaded.name
      assert_equal 5, reloaded.corpus_size
      assert_equal [ 1.0 ], reloaded.values(:strict_accuracy)
      assert_equal 1, reloaded.values(:latency_median).size, "a stored pass carries its speed"
      assert_equal [ 0 ], reloaded.values(:failures)
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

  # THE GUARD MUST FIRE ON A ROTATION AND ON NOTHING ELSE, and the second half
  # is the one that was wrong: an arm's LABEL carries its provider and its
  # `+nothink`, `BaseAgent#current_model` reports the bare model, and compared as
  # strings every local reading read as a rotation. The first real local pass
  # printed "29 ROTATED -- THE PINNING FAILED" over 29 perfectly pinned calls.
  test "the rotation guard compares models and not labels, so a local arm is not slandered" do
    line = @corpus.lines.first
    answer = Eval::Classifier::Corpus::Answer.new(intent: line.intent, target: line.target)
    reading = ->(arm, answered_by) do
      Eval::Classifier::Bench::Reading.new(line: line, arm: arm, rep: 1, answered_by: answered_by,
                                           raw: nil, seconds: 1.0, error: nil, answer: answer)
    end

    assert_not_predicate reading.("ollama:qwen3:4b+nothink", "qwen3:4b"), :rotated?
    assert_not_predicate reading.("ollama:qwen3:8b", "qwen3:8b"), :rotated?
    assert_not_predicate reading.("minimax/minimax-m3", "minimax/minimax-m3"), :rotated?

    assert_predicate reading.("ollama:qwen3:4b+nothink", "qwen3:8b"), :rotated?
    assert_predicate reading.("mistralai/mistral-medium-3.1", "minimax/minimax-m3"), :rotated?
    assert_not_predicate reading.("minimax/minimax-m3", nil), :rotated?,
                         "a failed call answered by nobody has not rotated"
  end

  private

  # Readings with nothing but a latency on them, for the percentile arithmetic.
  def timed(seconds)
    line = @corpus.lines.first
    seconds.map do |value|
      Eval::Classifier::Bench::Reading.new(
        line: line, arm: "m", rep: 1, answered_by: "m", raw: nil, seconds: value, error: nil,
        answer: Eval::Classifier::Corpus::Answer.new(intent: line.intent, target: line.target)
      )
    end
  end

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
