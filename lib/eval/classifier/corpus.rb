# THE LABELLED LINES, AND THE THING THAT STOPS A LABEL BEING A CLAIM.
#
# `test/fixtures/files/classifier_corpus.yml` is typed lines with the answer
# written beside each one by hand. A hand-written label is only worth what its
# verification is worth, so the verification is mechanical and it runs in
# `bin/rails test`: `#validate!` stages every position the corpus names and
# checks each label against the closed sets that position actually offers.
#
# WHAT IT CATCHES, which is everything a careless label can be:
#
#   * a `target` that is not in the set the action reads against -- "take the
#     apron" labelled in a room the apron is not lying in. The commonest way to
#     write a wrong label, and the reason a corpus without this check would
#     quietly measure the corpus.
#   * a `target` on an intent that resolves no record (`other`).
#   * an `also_named` equal to the `target`, which `Playthrough::Classifier#also_record`
#     collapses to nil by design -- so a label asserting it would assert a thing
#     the app will never answer.
#   * a stated `refusal:` that does not follow from the stated intent, target and
#     `also_named`. This is the one that matters most: the refusal kinds are
#     DERIVABLE from the other three through the same predicates
#     `Playthrough::Classifier::Intent` uses, so storing them is redundant --
#     and the redundancy is exactly the point. Two independent readings of one
#     line have to agree, and disagreement is a failing test rather than a
#     number nobody checked.
#
# WHAT IT CANNOT CATCH is whether the label is the right reading of the English,
# and nothing can: that is the hand-verification, and each line carries a `why`
# stating it. Lines whose English genuinely admits two readings carry
# `also_accept`, and the board reports how many there are -- a bench that marked
# a defensible answer wrong would measure its own labelling.
class Eval::Classifier::Corpus
  class Invalid < StandardError; end

  # A rebuildable starting state: a seeded world, a room in it, and the typed
  # lines that get from the world's opening room to the state the label was
  # written against. Walked offline; see `Eval::Classifier::Stage`.
  # `cast` is the ONE thing a position may state that no typed line can reach:
  # a mapping of a character's fullname to the room the records are to put them
  # in, written through `Character#move_to!`. It is here because the shape the
  # whole refusal ruling hangs on -- one line naming TWO PEOPLE -- is unreachable
  # otherwise: no seeded world has two people in one room, which is the gap
  # `lib/engine_sweep/scripts/one-act-per-line.yml` states and leaves to unit
  # tests. `#move_to!` is the app's own explicit writer and a `WorldMechanic`
  # moves people with it on the story's clock, so a position that uses it is a
  # position a world can really be in -- unlike one built by writing columns.
  # A player still cannot write a whereabouts, and nothing here lets them.
  Position = Data.define(:id, :story, :room, :cast, :setup, :why) do
    def initialize(cast: {}, setup: [], why: nil, **rest) = super
  end

  # ONE WHOLE ANSWER TO ONE LINE: an intent, the record it resolved and the one
  # further record the line also named. Both a label and a classifier's reply
  # are one of these, which is what lets them be compared at all -- the corpus
  # holds NAMES and the engine holds records, so the comparison has to happen
  # over names.
  #
  # THE PAIR IS A SET AND NOT AN ORDER. Nothing in the app says which of two
  # explicitly named things is `target` and which is `also_named`: both are
  # resolved through the same closed set by the same matcher and NEITHER is
  # acted on, because the line is refused. So an answer that swapped them
  # answered the same line the same way, and scoring the order would be scoring
  # the labeller.
  Answer = Data.define(:intent, :target, :also_named) do
    def initialize(target: nil, also_named: nil, **rest) = super

    def named = [ target, also_named ].compact.map { |name| name.to_s.downcase }.sort

    def same_as?(other) = intent == other.intent && named == other.named

    def refusal
      Eval::Classifier::Corpus.implied_refusal(intent: intent, target: target, also_named: also_named)
    end

    def to_s = "#{intent} -> #{target || Eval::Classifier::NONE}#{" (and #{also_named})" if also_named}"
  end

  # ONE LABELLED LINE.
  #
  # `intent` and `target` are the answer; `target` is nil when the line names
  # nothing on the lists, which is the `nothing` the enum answers with.
  # `also_named` is the ONE further name out of the same closed set the line
  # also held, nil on a line that named one thing -- the commonest case by a
  # long way. `refusal` is the kind the ruling of 2026-09-04 earns the line, or
  # `:none`; it is redundant with the other three on purpose (see the header).
  # `also_accept` is the answers a bench counts as correct beside the labelled
  # one, for a line whose English really is ambiguous. Each entry is a whole
  # answer -- intent, target and `also_named` -- rather than a target alone,
  # because a line that admits two readings usually admits two REFUSALS with
  # them, and an entry that left `also_named` to be inferred would be the bench
  # guessing at the label.
  # `shape` is what the line is IN the corpus for, and the board groups by it.
  Line = Data.define(:id, :position, :typed, :intent, :target, :also_named, :refusal, :shape, :why, :also_accept) do
    def initialize(target: nil, also_named: nil, refusal: :none, shape: nil, why: nil, also_accept: [], **rest) = super

    def refused? = refusal != :none
    def arguable? = also_accept.any?

    # EVERY ANSWER THIS LINE ACCEPTS, the label first. A pair rather than an
    # `Intent`, because a corpus holds names and the bench holds records.
    #
    # EVERY ANSWER THIS LINE ACCEPTS, the label first.
    def answers
      [ Eval::Classifier::Corpus::Answer.new(intent: intent, target: target, also_named: also_named),
        *also_accept.map { |other| Eval::Classifier::Corpus::Answer.new(**other) } ]
    end

    def accepts?(answer) = answers.any? { |wanted| wanted.same_as?(answer) }

    # THE REFUSALS THIS LINE ACCEPTS. A line that admits two readings admits
    # whatever each of them earns, and `#refused?` above is the LABEL's -- which
    # is what the corpus states and what the validator checks.
    def refusals = answers.map(&:refusal).uniq
  end

  # THE REFUSAL A LABEL IMPLIES, derived through the same three predicates the
  # engine decides with, in the same order -- `Playthrough::Classifier::Intent#refused?`.
  # Written out over names rather than by building an `Intent` because a corpus
  # line holds names and has no records to build one from, and a second copy of
  # the ORDER is the thing worth keeping honest here.
  def self.implied_refusal(intent:, target:, also_named:)
    return :named_more_than_one if !also_named.nil? && !target.nil?
    return :unresolved if Playthrough::Drift::ACTIONS.include?(intent.to_s) && target.nil?

    :none
  end

  def self.load(path = Eval::Classifier::CORPUS)
    document = YAML.safe_load(File.read(path))
    raise Invalid, "#{path}: expected a mapping with `positions` and `lines`" unless document.is_a?(Hash)

    positions = Array(document["positions"]).map { |row| position(row, path) }
    lines = Array(document["lines"]).map { |row| line(row, path) }
    new(path: path, positions: positions, lines: lines)
  end

  def self.position(row, path)
    missing = %w[id story room] - row.keys
    raise Invalid, "#{path}: position #{row.inspect} is missing #{missing.join(", ")}" if missing.any?

    Position.new(id: row["id"], story: row["story"], room: row["room"],
                 cast: (row["cast"] || {}).to_h { |name, room| [ name.to_s, room ] },
                 setup: Array(row["setup"]), why: row["why"])
  end

  def self.line(row, path)
    missing = %w[id position typed intent] - row.keys
    raise Invalid, "#{path}: line #{row.inspect} is missing #{missing.join(", ")}" if missing.any?

    intent = row["intent"].to_sym
    unless Eval::Classifier::INTENTS.include?(intent)
      raise Invalid, "#{path}: line #{row["id"]} has intent #{intent.inspect}, " \
                     "which is not one of #{Eval::Classifier::INTENTS.inspect}"
    end

    refusal = (row["refusal"] || "none").to_sym
    unless Eval::Classifier::REFUSALS.include?(refusal)
      raise Invalid, "#{path}: line #{row["id"]} has refusal #{refusal.inspect}, " \
                     "which is not one of #{Eval::Classifier::REFUSALS.inspect}"
    end

    Line.new(id: row["id"], position: row["position"], typed: row["typed"], intent: intent,
             target: row["target"], also_named: row["also_named"], refusal: refusal,
             shape: row["shape"], why: row["why"],
             also_accept: Array(row["also_accept"]).map { |other|
               { intent: other["intent"].to_sym, target: other["target"], also_named: other["also_named"] }
             })
  end

  attr_reader :path, :positions, :lines

  def initialize(path:, positions:, lines:)
    @path = path
    @positions = positions
    @lines = lines
  end

  def size = lines.size

  def position(id) = positions.find { |row| row.id == id }

  def by_shape = lines.group_by(&:shape)

  # THE LINES THAT ANSWER ONE QUESTION, and only the positions they need. Used
  # by `Eval::Classifier::Omission` to run a targeted probe for a few cents
  # rather than the whole corpus -- and by anybody debugging one shape.
  def subset(&block)
    kept = lines.select(&block)
    needed = kept.map(&:position).uniq

    self.class.new(path: path, positions: positions.select { |row| needed.include?(row.id) }, lines: kept)
  end

  # THE LINES WHOSE LABEL CARRIES A SECOND NAME -- the `also_named` positives,
  # which is what PR 102's finding F4 is about.
  def two_noun_lines = subset { |line| !line.also_named.nil? }

  def for_position(id) = lines.select { |line| line.position == id }

  # THE VERIFICATION, run offline in the test suite. Returns the complaints
  # rather than raising them, so one failing test can print all of them at once
  # -- a corpus this size is edited in batches and a validator that stops at the
  # first problem is a validator somebody runs three hundred times.
  def problems
    found = []
    found.concat(structural_problems)
    return found if found.any?

    Eval::Classifier::Stage.open(positions) do |stages|
      lines.each { |line| found.concat(problems_for(line, stages[line.position])) }
    end
    found
  end

  def validate!
    found = problems
    raise Invalid, "#{path}:\n  #{found.join("\n  ")}" if found.any?

    true
  end

  private

  # The checks that need no records: duplicate ids, a position nobody defined,
  # a line stating a refusal its own label does not imply.
  def structural_problems
    found = []

    lines.map(&:id).tally.select { |_id, count| count > 1 }.each_key do |id|
      found << "line id #{id.inspect} is used more than once"
    end
    positions.map(&:id).tally.select { |_id, count| count > 1 }.each_key do |id|
      found << "position id #{id.inspect} is used more than once"
    end

    lines.each do |line|
      found << "#{line.id}: no position called #{line.position.inspect}" if position(line.position).nil?

      implied = self.class.implied_refusal(intent: line.intent, target: line.target, also_named: line.also_named)
      if implied != line.refusal
        found << "#{line.id}: labelled refusal #{line.refusal.inspect} but intent/target/also_named imply " \
                 "#{implied.inspect} -- the two readings of this line disagree"
      end

      if line.also_named && line.target && line.also_named.casecmp?(line.target)
        found << "#{line.id}: also_named is the same name as target, which #{"Playthrough::Classifier#also_record"} " \
                 "collapses to nil -- a label the app can never answer"
      end
    end

    found
  end

  # The checks that need the room: every name in a label has to be in the closed
  # set the action reads against.
  def problems_for(line, standing)
    return [ "#{line.id}: position #{line.position.inspect} could not be staged" ] if standing.nil?

    line.answers.flat_map do |answer|
      name_problems(line, standing, answer.intent, answer.target, "target") +
        name_problems(line, standing, answer.intent, answer.also_named, "also_named")
    end
  end

  def name_problems(line, standing, intent, name, field)
    return [] if name.nil?

    offered = standing.offered_for(intent).flat_map { |record| names_of(record) }
    if offered.empty?
      return [ "#{line.id}: #{field} #{name.inspect} on a #{intent} -- that intent resolves no record, " \
               "so the label can only ever be nothing" ]
    end
    return [] if offered.any? { |offer| offer.to_s.casecmp?(name.to_s) }

    [ "#{line.id}: #{field} #{name.inspect} is not in the closed set a #{intent} reads against at " \
      "#{standing.position.id} -- that set is [#{offered.join(", ")}]" ]
  end

  def names_of(record)
    return [ record.fullname, record.nickname ].compact_blank if record.respond_to?(:fullname)

    [ record.name ].compact_blank
  end
end
