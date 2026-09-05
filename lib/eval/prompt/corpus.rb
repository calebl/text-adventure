# THE CASES, AND THE THING THAT STOPS A CASE BEING A CLAIM.
#
# `test/fixtures/files/prompt_corpus.yml` is single-turn cases: a position in a
# seeded world, a typed line, and the action the engine resolved it to. Every
# fact the narrator will be told comes out of the records that position really
# holds -- the room and its description, the ways out, who is standing there,
# what is lying on the floor, what is in the party's hands -- so the moment the
# prompt carries is one a player could really be standing in.
#
# WHY THE FACTS ARE NOT WRITTEN IN THE FILE. A case that declared its own room
# description and its own floor would be measuring prompts the app does not
# build: `Playthrough::Moment` is the one builder of what a prose pass is told,
# and a corpus that hand-wrote its input would drift away from it the first time
# a fact was added there. So a case names a POSITION and the position is staged
# offline through the app's own loader and mechanics (`Eval::Classifier::Stage`,
# shared rather than copied), and what the case adds is the one turn.
#
# WHAT THE VALIDATOR CATCHES, and it runs in `bin/rails test`:
#
#   * A `target` that is not in the closed set the action reads against -- "take
#     the apron" in a room the apron is not lying in. The commonest way to write
#     a case that measures nothing, because the engine would have refused the
#     line rather than narrating it.
#   * A `take` or `drop` or `move` with no target at all, which is a refusal and
#     not a turn (`Playthrough::Classifier::Intent#refused?`), so no prose would
#     ever be asked for.
#   * An `examine` of a readable thing with NO INSCRIPTION ON RECORD, which
#     would make `Item::Inscriber` write one -- a second model call, on the
#     first repetition only, so the run's own figures would disagree with
#     themselves.
#   * A `move` to a room that is still a stub, which would call
#     `Location::Generator` -- two more calls, and arrival prose about a room
#     the run had just invented.
#   * A world this bench does not play (`Eval::Prompt::STORIES`), and a `talk`
#     (`Eval::Prompt::UNSUPPORTED_ACTS`). Both have reasons and both are stated
#     there.
#
# WHAT IT CANNOT CATCH is whether the case is worth measuring -- whether this
# turn, in this room, with these things in reach, puts the narrator anywhere
# near the failure the check is looking for. That is the hand-verification, and
# every case carries a `why` stating it.
class Eval::Prompt::Corpus
  class Invalid < StandardError; end

  # The label a staged copy is loaded under, and `retitle:` puts the world's own
  # title back before anything reads it -- because a narrator IS told the story's
  # title and a bench measuring `The Unrecorded Hour (prompt bench: office)`
  # would be measuring a prompt no player gets. See `Eval::Classifier::Stage::LABEL`.
  STAGE_LABEL = "prompt bench".freeze

  # A rebuildable starting state, exactly `Eval::Classifier::Corpus::Position`'s
  # shape and read by exactly the same stager. Duplicated as a Data definition
  # rather than reused as a class because the two corpora are separate files
  # with separate ids; the STAGING is what is shared, and that is the expensive
  # half.
  Position = Data.define(:id, :story, :room, :cast, :setup, :why) do
    def initialize(cast: {}, setup: [], why: nil, **rest) = super
  end

  # ONE CASE: one turn, against one position.
  #
  # `act` and `target` are the answer the classifier would have given, and the
  # bench hands them to the engine in place of a classifier call -- so the
  # branch, the fact sentence and the prompt are the app's and not this file's.
  # `shape` is what the case is in the corpus FOR, and the board groups by it.
  Case = Data.define(:id, :position, :typed, :act, :target, :shape, :why) do
    def initialize(target: nil, shape: nil, why: nil, **rest) = super

    def move? = act == :move

    # WHICH PROSE PASS THIS CASE WILL LAND IN. The app decides it
    # (`Playthrough::Turn#play`) and the run records what really answered; this
    # is the prediction, and it exists for one reason -- the estimate has to be
    # printed before a call is made, and an arrival and a narration cost
    # different amounts.
    def pass = move? ? "arrival" : "narration"

    def to_s = "#{act}#{" -> #{target}" if target}"
  end

  def self.load(path = Eval::Prompt::CORPUS)
    document = YAML.safe_load(File.read(path))
    raise Invalid, "#{path}: expected a mapping with `positions` and `cases`" unless document.is_a?(Hash)

    new(path: path,
        positions: Array(document["positions"]).map { |row| position(row, path) },
        cases: Array(document["cases"]).map { |row| kase(row, path) })
  end

  def self.position(row, path)
    missing = %w[id story room] - row.keys
    raise Invalid, "#{path}: position #{row.inspect} is missing #{missing.join(", ")}" if missing.any?

    Position.new(id: row["id"], story: row["story"], room: row["room"],
                 cast: (row["cast"] || {}).to_h { |name, room| [ name.to_s, room ] },
                 setup: Array(row["setup"]), why: row["why"])
  end

  def self.kase(row, path)
    missing = %w[id position typed act] - row.keys
    raise Invalid, "#{path}: case #{row.inspect} is missing #{missing.join(", ")}" if missing.any?

    act = row["act"].to_sym
    unless Eval::Prompt::ACTS.include?(act)
      raise Invalid, "#{path}: case #{row["id"]} has act #{act.inspect}, " \
                     "which is not one of #{Eval::Prompt::ACTS.inspect}"
    end

    Case.new(id: row["id"], position: row["position"], typed: row["typed"], act: act,
             target: row["target"], shape: row["shape"], why: row["why"])
  end

  attr_reader :path, :positions, :cases

  def initialize(path:, positions:, cases:)
    @path = path
    @positions = positions
    @cases = cases
  end

  def size = cases.size

  def position(id) = positions.find { |row| row.id == id }

  def by_shape = cases.group_by(&:shape)

  def story_of(kase) = position(kase.position)&.story

  # The cases that answer one question, and only the positions they need -- the
  # same seam `Eval::Classifier::Corpus#subset` gives, and used for the same
  # thing: a targeted probe for a few cents rather than the whole corpus.
  def subset(&block)
    kept = cases.select(&block)
    needed = kept.map(&:position).uniq

    self.class.new(path: path, positions: positions.select { |row| needed.include?(row.id) }, cases: kept)
  end

  def for_shape(shape) = subset { |kase| kase.shape.to_s == shape.to_s }

  # THE VERIFICATION, run offline in the test suite. Returns the complaints
  # rather than raising them, so one failing test prints all of them at once.
  def problems
    found = structural_problems
    return found if found.any?

    Eval::Classifier::Stage.open(positions, label: STAGE_LABEL, retitle: true) do |stages|
      cases.each { |kase| found.concat(problems_for(kase, stages[kase.position])) }
    end
    found
  end

  def validate!
    found = problems
    raise Invalid, "#{path}:\n  #{found.join("\n  ")}" if found.any?

    true
  end

  private

  # The checks that need no records: ids, positions, worlds, acts.
  def structural_problems
    found = []

    cases.map(&:id).tally.select { |_id, count| count > 1 }.each_key do |id|
      found << "case id #{id.inspect} is used more than once"
    end
    positions.map(&:id).tally.select { |_id, count| count > 1 }.each_key do |id|
      found << "position id #{id.inspect} is used more than once"
    end

    positions.each do |row|
      next if Eval::Prompt::STORIES.include?(row.story)

      found << "#{row.id}: #{row.story.inspect} is not a world this bench plays " \
               "(#{Eval::Prompt::STORIES.join(", ")}) -- see Eval::Prompt::STORIES for why"
    end

    cases.each do |kase|
      found << "#{kase.id}: no position called #{kase.position.inspect}" if position(kase.position).nil?
      found << "#{kase.id}: a case needs a `shape`, which is what the board groups by" if kase.shape.blank?
      found << "#{kase.id}: a case needs a `why`, which is what makes it auditable" if kase.why.blank?

      if (reason = Eval::Prompt::UNSUPPORTED_ACTS[kase.act])
        found << "#{kase.id}: this bench does not measure a #{kase.act} -- #{reason}"
      end
    end

    found
  end

  # The checks that need the room.
  def problems_for(kase, standing)
    return [ "#{kase.id}: position #{kase.position.inspect} could not be staged" ] if standing.nil?

    record = resolve(kase, standing)
    return record if record.is_a?(Array)

    found = []
    found.concat(refusal_problems(kase, record))
    found.concat(extra_call_problems(kase, record))
    found
  end

  # THE TARGET, RESOLVED THROUGH THE ENGINE'S OWN CLOSED SET -- asked of
  # `Playthrough::Classifier#offered_for`, so a case cannot be validated against
  # a list the action does not actually read. Answers the record, or the
  # complaints.
  def resolve(kase, standing)
    return nil if kase.target.blank?

    offered = standing.offered_for(kase.act)
    if offered.empty?
      return [ "#{kase.id}: target #{kase.target.inspect} on a #{kase.act} -- that action resolves no record, " \
               "so the case can only ever act on nothing" ]
    end

    found = offered.find { |record| names_of(record).any? { |name| name.to_s.casecmp?(kase.target.to_s) } }
    return found if found

    [ "#{kase.id}: target #{kase.target.inspect} is not in the closed set a #{kase.act} reads against at " \
      "#{standing.position.id} -- that set is [#{offered.flat_map { |record| names_of(record) }.join(", ")}]" ]
  end

  # A CASE THE ENGINE WOULD REFUSE IS NOT A CASE. The three acts that reach for
  # a record are refused outright when they find none (the captain's ruling of
  # 2026-09-04), so no prose is asked for and there is nothing to score.
  def refusal_problems(kase, record)
    return [] unless record.nil?
    return [] unless Playthrough::Drift::ACTIONS.include?(kase.act.to_s)

    [ "#{kase.id}: a #{kase.act} that resolves nothing is REFUSED, not narrated " \
      "(Playthrough::Refusal) -- there would be no passage to score" ]
  end

  # ONE MODEL CALL A CASE, AND NOT ONE MORE. Two shapes would quietly buy a
  # second: an unrealized destination pays for `Location::Generator`, and a
  # readable thing with no words yet pays for `Item::Inscriber` -- on the first
  # repetition only, which is worse than paying every time because the run's own
  # repetitions would then disagree for a reason that is not the model.
  def extra_call_problems(kase, record)
    return [] if record.nil?

    if kase.move? && !record.realized?
      return [ "#{kase.id}: #{record.name.inspect} is a stub, so this move would call Location::Generator " \
               "-- two more calls, and arrival prose about a room the run had just invented" ]
    end

    if kase.act == :examine && record.is_a?(Item) && record.readable? && record.inscription.blank?
      return [ "#{kase.id}: #{record.name.inspect} is readable with no inscription on record, so the first " \
               "repetition would call Item::Inscriber and the rest would not" ]
    end

    []
  end

  def names_of(record)
    return [ record.fullname, record.nickname ].compact_blank if record.respond_to?(:fullname)

    [ record.name ].compact_blank
  end
end
