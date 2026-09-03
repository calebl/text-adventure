# ONE RUN, SCORED. The unit everything else in this module aggregates.
#
# It is a plain value that round-trips through JSON, and that is load-bearing:
# the run databases are big and live under `tmp/`, so a set is scored once and
# the scores are what a comparison reads weeks later. `Eval::Comparison` never
# opens a database.
#
# `judgeable` is the denominator PER CHECK and not the turn count, because
# `Story::Audit#judgeable_for` is the only thing that knows which passages carry
# the records a given check reads -- a check that cannot be judged on a turn
# must not have that turn counted against it. A check the run could not answer
# at all is `available: false`, reported and never scored as zero.
class Eval::RunScore
  # ONE CHECK'S READING ON ONE RUN.
  Reading = Data.define(:code, :flagged, :judgeable, :unjudged, :available) do
    def rate = judgeable.positive? ? flagged.fdiv(judgeable) : 0.0
    def to_h = { code: code.to_s, flagged:, judgeable:, unjudged:, available: }
  end

  # ONE FLAG, FLATTENED FOR A REPORT SOMEBODY READS. The turn, what was typed
  # and the offending passage -- which is the whole of what the captain's
  # accuracy pass needs and is why the evidence is copied out rather than
  # referenced: the database it came from is a temporary file.
  Finding = Data.define(:code, :story, :turn, :typed, :headline, :claim, :where, :evidence) do
    def to_h = { code: code.to_s, story:, turn:, typed:, headline:, claim:, where:, evidence: }
  end

  ATTRIBUTES = %i[story held_out rep turns scenes readings findings richness usage
                  failures drifts branches].freeze

  attr_reader(*ATTRIBUTES)

  def initialize(story:, held_out:, rep:, turns:, scenes:, readings:, findings:, richness:,
                 usage: [], failures: [], drifts: [], branches: {})
    @story = story
    @held_out = held_out
    @rep = rep
    @turns = turns
    @scenes = scenes
    @readings = readings
    @findings = findings
    @richness = richness
    @usage = usage
    @failures = failures
    @drifts = drifts
    @branches = branches
  end

  def held_out? = held_out

  def reading(code) = readings.find { |row| row.code == code }

  def rate(code) = reading(code)&.rate

  def flagged(code) = reading(code)&.flagged.to_i

  def available?(code) = reading(code)&.available || false

  def cost = @cost ||= Eval::Cost.actual(usage)

  def label = "#{WorldSeed.slug(story)} r#{rep}"

  def to_h
    { story:, held_out:, rep:, turns:, scenes:,
      readings: readings.map(&:to_h), findings: findings.map(&:to_h),
      richness: richness.to_h, usage:, failures:, drifts:, branches: }
  end

  # `failures`, `drifts` and `branches` are kept string-keyed on the way back in.
  # They are verbatim slices of the run manifest rather than fields this class
  # defines, and symbolising them would make a reader guess which half of the
  # object they were holding.
  def self.from_h(row)
    data = row.deep_symbolize_keys

    new(story: data[:story], held_out: data[:held_out], rep: data[:rep],
        turns: data[:turns], scenes: data[:scenes],
        readings: data[:readings].map { |r| Reading.new(code: r[:code].to_sym, flagged: r[:flagged],
                                                        judgeable: r[:judgeable], unjudged: r[:unjudged],
                                                        available: r[:available]) },
        findings: data[:findings].map { |f| Finding.new(code: f[:code].to_sym, story: f[:story], turn: f[:turn],
                                                        typed: f[:typed], headline: f[:headline], claim: f[:claim],
                                                        where: f[:where],
                                                        evidence: (f[:evidence] || {}).transform_keys(&:to_s)) },
        richness: Eval::Richness::Summary.new(**data[:richness].slice(*Eval::Richness::Summary.members)),
        usage: Array(data[:usage]).map { |u| u.transform_keys(&:to_sym) },
        failures: Array(row["failures"] || row[:failures]),
        drifts: Array(row["drifts"] || row[:drifts]),
        branches: row["branches"] || row[:branches] || {})
  end
end
