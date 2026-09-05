# THE SAME CORPUS WITH NO MODEL AT ALL, WHICH IS WHAT A CLASSIFIER CALL IS
# BOUGHT AGAINST.
#
# `Playthrough::Mechanics` has a fixed grammar for `model: false` -- a verb
# table, `LEADING_WORDS` stripped off the front of a name, an exact match then
# an unambiguous prefix then an unambiguous fragment read both ways round, and
# an ambiguity rule that refuses. Its own header says why each of those exists:
# a real line was refused. So the honest question about the classifier is not
# "how accurate is it" but "how much more does it get right than the free thing
# underneath it", and this is the number that answers it.
#
# FIVE OUTCOMES, TOLD APART BECAUSE THEY ARE DIFFERENT FACTS about what the free
# floor can do:
#
#   resolved   the grammar produced the answer the label wants.
#   refused    the grammar refused, and the label says the line earns a refusal.
#              A right refusal for possibly the wrong reason -- see below.
#   wrong      the grammar produced an answer, and it is not one the label
#              accepts. The dangerous outcome: a fixed grammar that resolves the
#              wrong record does it silently.
#   over_refused  the grammar refused a line the label says should have played.
#              What the classifier is bought for, mostly.
#   unparsed   no verb it knows and no exit by that name, so nothing at all --
#              `Playthrough::Mechanics#unknown`, which prints the whole grammar.
#              Counted apart from `over_refused` because the player is told
#              something different.
#
# WHAT THIS CANNOT SAY, stated rather than left to be found. The grammar's
# refusals are STRINGS it composes itself, not `Playthrough::Refusal` objects
# with a `kind` -- the ambiguity refusal, the "there is no X called Y" refusal
# and the whole-grammar refusal all come back as prose. So the offline floor can
# report WHETHER a line was refused and never WHICH KIND, and refusal-kind
# agreement is a model-only figure. It also has no `also_named`: nothing in a
# fixed grammar produces one, which is why `one-act-per-line.yml` reaches the
# two-name refusal by the ambiguity rule instead and says so.
#
# FREE, OFFLINE AND DETERMINISTIC. `#parse` makes no model call and writes
# nothing -- it reads the closed sets and returns a `Reading` -- so this runs in
# `bin/rails test` beside the corpus validator and needs no key.
#
# IT REACHES `#parse` DIRECTLY, and that is a deliberate choice about where the
# seam goes. `Playthrough::Mechanics#run` would ACT on the line -- move a row,
# take a thing -- and a floor that mutated the position it was measuring would
# be measuring itself. The alternative was a new public reader on the engine for
# an instrument's benefit; the instrument reaches for the private one instead,
# because the engine should not grow a method to be measured.
class Eval::Classifier::Offline
  OUTCOMES = %i[resolved refused wrong over_refused unparsed].freeze

  Reading = Data.define(:line, :outcome, :got) do
    def id = line.id
    def shape = line.shape
    def right? = outcome == :resolved || outcome == :refused

    def to_h = { id: id, shape: shape, typed: line.typed, outcome: outcome,
                 expected: line.answers.map(&:to_s), got: got }
  end

  attr_reader :corpus

  def initialize(corpus: Eval::Classifier.corpus)
    @corpus = corpus
  end

  # Returns the readings. Staged in one rolled-back transaction, exactly as the
  # live bench is, and with `EngineSweep.without_a_model` in front of it so a
  # model call from anywhere raises rather than reaching a provider -- the same
  # guard, for the same reason: a floor that quietly made a call would be
  # measuring the model.
  def run
    EngineSweep.without_a_model do
      Eval::Classifier::Stage.open(corpus.positions) do |stages|
        corpus.lines.map { |line| read(line, stages.fetch(line.position)) }
      end
    end
  end

  def summary(readings = run) = Summary.new(readings: readings)

  private

  def read(line, standing)
    mechanics = Playthrough::Mechanics.new(standing.playthrough, model: false)
    reading = mechanics.send(:parse, line.typed)

    if reading.intent
      answer = Eval::Classifier::Corpus::Answer.new(
        intent: reading.intent.action,
        target: Playthrough::Classifier.label_for(reading.intent.subject),
        also_named: Playthrough::Classifier.label_for(reading.intent.also_named)
      )
      outcome = line.accepts?(answer) ? :resolved : :wrong
      return Reading.new(line: line, outcome: outcome, got: answer.to_s)
    end

    return Reading.new(line: line, outcome: :unparsed, got: nil) if reading.refusal.blank?

    outcome = line.refused? ? :refused : :over_refused
    Reading.new(line: line, outcome: outcome, got: reading.refusal.to_s)
  end

  # THE FLOOR AS A NUMBER, printed beside the model's by `Eval::Classifier::Report`.
  Summary = Data.define(:readings) do
    def size = readings.size
    def count(outcome) = readings.count { |reading| reading.outcome == outcome }
    def rate(outcome) = size.zero? ? 0.0 : count(outcome).fdiv(size)

    # WHAT THE FREE FLOOR GETS RIGHT: an answer the label accepts, or a refusal
    # on a line the label says earns one. `#refused` is generous to the grammar
    # and deliberately so -- it does not check WHICH refusal, because the
    # grammar has no kinds (see the header). The board says so under the figure.
    def right = count(:resolved) + count(:refused)
    def accuracy = size.zero? ? 0.0 : right.fdiv(size)

    def by_shape
      readings.group_by(&:shape).transform_values do |rows|
        { size: rows.size, right: rows.count(&:right?),
          rate: rows.empty? ? 0.0 : rows.count(&:right?).fdiv(rows.size) }
      end
    end

    def to_h
      { size:, accuracy: accuracy.round(4),
        outcomes: Eval::Classifier::Offline::OUTCOMES.to_h { |outcome| [ outcome, count(outcome) ] },
        by_shape: by_shape, readings: readings.map(&:to_h) }
    end
  end
end
