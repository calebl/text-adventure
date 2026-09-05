# REAL PROSE, FROZEN, WITH THE RECORDS AROUND IT WRITTEN DOWN.
#
# The second corpus `Story::Scoreboard` reports on, and the reason the first
# one is not enough: the captain's database is what he actually read, but it is
# 54 scenes, it changes every time he plays, and it exists on exactly one
# machine. Nothing in it can be a regression test. This file can: it is checked
# in, it needs no database, and it is the same passages every run, so a check
# that starts flagging something new fails the build instead of quietly
# changing a number.
#
# WHERE THE PASSAGES COME FROM, all of them real, none of them written for this:
#
#   * every turn the captain judged, verdict and note included, because those
#     are the four errors this whole loop was built to catch and a corpus that
#     cannot demonstrate them proves nothing;
#   * the turns around them, so a check has to tell the flagged turn from its
#     neighbours rather than from the corpus being all defects;
#   * the narrations `test/fixtures/files/narration_corpus.json` already holds
#     -- 24 passages two remote models really wrote against six commands
#     designed to break a world's laws. They are the hardest available negative
#     case: prose that argues about weapons, memory and locked doors, from the
#     same worlds, and NOT ONE OF THEM MAY FLAG.
#
# WHAT IT CANNOT ANSWER, and says so rather than scoring clean. A passage is
# prose plus the facts declared beside it, so a check that reads a record this
# file does not carry is UNAVAILABLE here:
#
#   unreachable_transition  needs the `location_connections` graph
#   item_not_held           needs `items` rows
#   reached_for_nothing     needs `Playthrough::Drift` rows
#
# The other four run in full, because everything they need -- the passage, the
# protagonist's names, whether the location changed, how long the still run
# was, who was in the room -- is a fact that can be written down next to the
# prose. `Story::Scoreboard` prints the unavailable ones as unavailable; a zero
# there would be a lie.
class Story::Scoreboard::Corpus
  PATH = "test/fixtures/files/eval_corpus.json".freeze

  # ONE PASSAGE, and everything a check needs to judge it.
  #
  # It answers enough of `Scene` for a `Story::Audit::Flag` and the report to
  # hold it: `id`, `typed`, `description`, `follows_a_turn?`, `location`. The
  # `id` is the id the passage had in the database it was captured from, kept
  # so a flag can be traced back to the turn it is a copy of, and never used to
  # read anything -- this class touches no table. `location` is nil because
  # there is no `Location` row behind a frozen passage; `room` is its name.
  #
  # `moved` is nil for a passage with no turn before it, which is how a first
  # turn is told from a turn that stayed put.
  Passage = Data.define(:id, :label, :story, :room, :typed, :text, :protagonist,
                        :moved, :still_run, :present, :verdict, :note, :expect) do
    def description = text
    def location = nil
    def follows_a_turn? = !moved.nil?
    def moved? = moved == true
  end

  attr_reader :passages

  def initialize(passages)
    @passages = passages
  end

  def self.load(path = PATH)
    file = Rails.root.join(path)
    rows = JSON.parse(File.read(file))

    new(rows.map { |row| passage_from(row) })
  end

  def self.passage_from(row)
    Passage.new(
      id: row["id"], label: row.fetch("label"), story: row["story"], room: row["room"],
      typed: row["typed"], text: row.fetch("text"), protagonist: row["protagonist"],
      moved: row["moved"], still_run: row["still_run"].to_i, present: Array(row["present"]),
      verdict: row["verdict"], note: row["note"], expect: Array(row["expect"]).map(&:to_sym)
    )
  end

  # The same four readers `Story::Audit` offers, so `Story::Scoreboard` reads
  # one shape and does not care which corpus it has.
  def scenes = passages
  def scanned = passages.size
  def unjudged = []
  # A FROZEN CORPUS CARRIES NO FIGHT, so nothing in it is engine-authored and
  # nothing is excluded. It is stated rather than omitted because
  # `Story::Scoreboard` prints the figure for every corpus, and a missing reader
  # would read as a corpus that had not been asked.
  def excluded = 0

  # The checks a passage can answer. See the header for the three it cannot.
  def available_checks
    %i[truncated_prose third_person_protagonist unrecorded_departure still_run]
  end

  # A PASSAGE CARRIES ONLY THE FACTS WRITTEN NEXT TO IT, so the denominator per
  # check is the passages that carry the facts that check reads -- an
  # `Interaction#action` has no protagonist declared and no turn before it, and
  # counting it into either rate would understate both. Mirrors
  # `Story::Audit#judgeable_for`.
  def judgeable_for(code)
    return 0 unless available_checks.include?(code)

    case code
    when :unrecorded_departure, :still_run then passages.count(&:follows_a_turn?)
    when :third_person_protagonist then passages.count { |passage| passage.protagonist.present? }
    else passages.size
    end
  end

  def verdicts
    passages.filter_map { |passage| [ passage, passage.verdict ] if passage.verdict.present? }.to_h
  end

  # THE SAME READING THE DATABASE GETS, out of the same module. Nothing in here
  # re-implements a check: `Story::Audit::Prose` holds every predicate and this
  # supplies the declared records in place of real ones, which is the whole
  # point of the module being pure.
  def flags
    @flags ||= passages.flat_map { |passage| check(passage) }
  end

  private

  def check(passage)
    found = []
    found.concat(truncation(passage))
    found.concat(third_person(passage))
    found.concat(departure(passage))
    found.concat(stillness(passage))
    found
  end

  def truncation(passage)
    return [] unless Story::Audit::Prose.truncated?(passage.text)

    [ flag(:truncated_prose, passage,
           "the prose the model wrote stops mid-sentence",
           claim: "…#{passage.text.rstrip.last(80)}",
           "last character" => Story::Audit::Prose.sentence_ending(passage.text).inspect) ]
  end

  def third_person(passage)
    names = Array(passage.protagonist)
    return [] if names.empty?

    Story::Audit::Prose.third_person_references(passage.text, names).map do |reference|
      flag(:third_person_protagonist, passage,
           "the narration writes #{reference.name.inspect} as a third person, and that is the player " \
           "(#{names.first}), who is only ever \"you\"",
           grammar: reference.kind, name: reference.name, claim: reference.sentence.truncate(220))
    end
  end

  def departure(passage)
    return [] if !passage.follows_a_turn? || passage.moved?

    Story::Audit::Prose.departure_claims(passage.text).map do |claim|
      flag(:unrecorded_departure, passage,
           "the narration closes a door behind the player, and the records have them still in #{passage.room.inspect}",
           claim: claim.truncate(220), "records say" => "still in #{passage.room}")
    end
  end

  def stillness(passage)
    return [] if passage.still_run != Story::Audit::STILL_RUN
    return [] if passage.present.empty?

    [ flag(:still_run, passage,
           "#{Story::Audit::STILL_RUN} turns running, the records show nothing changed, and " \
           "#{passage.present.join(", ")} #{passage.present.one? ? "is" : "are"} in the room",
           present: passage.present.join(", ")) ]
  end

  def flag(code, passage, headline, **evidence)
    Story::Audit::Flag.new(
      code: code, scene: passage, headline: headline,
      evidence: { source: passage.label, where: passage.room, typed: passage.typed }.compact.merge(evidence)
    )
  end
end
