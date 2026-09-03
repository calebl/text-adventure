# WHAT A TURN DID, FROZEN, WITH THE PROSE THAT ARGUED WITH IT.
#
# The third corpus `Story::Scoreboard` reports on, and the only one that can
# answer a check about a CHANGE. `Story::Scoreboard::Corpus` freezes passages
# with the state around them written down -- where the player is, who is in the
# room -- and that is enough for four checks and no more. `take_denied` and
# `pickup_invented` read a transition, so what has to be frozen beside the
# passage is the transition: what the classifier resolved the line to, which
# item it resolved to, and where that item was before the turn and after it.
#
# WHERE THE PASSAGES COME FROM. Every turn of every `rake eval:run` set on the
# machine on 2026-09-03 that the classifier resolved to a `take` or a `drop`:
# 119 turns over four sets, of which `main20` is the 24-run, 480-turn baseline
# the manual read of that day was done against and carries 32 takes and 32
# drops exactly. The run databases are gitignored and live under `tmp/eval/`;
# they were cut before they were lost, which is the whole reason this file
# exists rather than a re-run costing money.
#
# THE RESOLVED ACTION IS RECOVERED, NOT ASSUMED. `Scene#resolved_action` did
# not exist when these runs were played, so each row's action was read back out
# of the classifier's own stored answer (`messages.content_raw`, kept by default
# since PR 97) and confirmed against the closed set that same prompt offered --
# `offered` on every row is that list. A row whose target was not on the list
# the action reads against is not in this file.
#
# AND THE POSITION BEFORE AND AFTER IS EXACT WITHOUT AN ITEM HISTORY, which
# `items` does not have. It does not need one: `Playthrough::Classifier`
# resolves a `take` against what is lying in the room and a `drop` against what
# the player is carrying, so the action itself says where the row was. That is
# the same argument `Story::Audit#check_take` makes and it is why these checks
# are exact rather than inferred.
#
# WHAT IT CANNOT ANSWER: everything else. A passage here carries a transition
# and no graph, no drift rows, no protagonist names and no still-run length, so
# the other nine checks are reported UNAVAILABLE rather than scored as clean.
class Story::Scoreboard::Transitions
  PATH = "test/fixtures/files/transition_corpus.json".freeze

  # THE SET THE ACCEPTANCE FIGURES ARE QUOTED AGAINST: the 24-run, 480-turn
  # sweep of 2026-09-03, which is the run the captain's manual read was done on
  # and the one every figure in `Story::Audit::TransitionTest` is stated for.
  # The other three sets are smaller sweeps of the same worlds, kept because
  # more real prose is better evidence and thrown away nowhere.
  BASELINE_SET = "main20".freeze

  # ONE TURN, and everything a transition check needs to judge it. It answers
  # enough of `Scene` for a `Story::Audit::Flag` and the report to hold it, on
  # the same terms `Story::Scoreboard::Corpus::Passage` does -- and it answers
  # `took?` and `dropped?`, which is the whole of what is new.
  Passage = Data.define(:label, :set, :run, :story, :room, :scene_id, :typed,
                        :action, :item, :protagonist, :offered, :before, :after, :text) do
    def id = scene_id
    def description = text
    def location = nil
    # Every row here is a played turn: a `take` or a `drop` is something a
    # player typed, so there is always a turn before it.
    def follows_a_turn? = true
    def took? = action == "take"
    def dropped? = action == "drop"
    def baseline? = set == BASELINE_SET
    def verdict = nil
    def note = nil
  end

  attr_reader :passages

  def initialize(passages)
    @passages = passages
  end

  def self.load(path = PATH)
    rows = JSON.parse(File.read(Rails.root.join(path)))

    new(rows.map { |row| passage_from(row) })
  end

  def self.passage_from(row)
    Passage.new(
      label: row.fetch("label"), set: row["set"], run: row["run"], story: row["story"],
      room: row["room"], scene_id: row["scene_id"], typed: row["typed"],
      action: row.fetch("action"), item: row.fetch("item"), protagonist: row["protagonist"],
      offered: Array(row["offered"]), before: row["before"], after: row["after"],
      text: row.fetch("text")
    )
  end

  # The same readers `Story::Audit` offers, so `Story::Scoreboard` reads one
  # shape and does not care which corpus it holds.
  def scenes = passages
  def scanned = passages.size
  def unjudged = []
  def verdicts = {}

  def available_checks = %i[take_denied pickup_invented]

  def judgeable_for(code)
    case code
    when :take_denied then passages.count(&:took?)
    when :pickup_invented then passages.count(&:dropped?)
    else 0
    end
  end

  # THE SAME READING THE DATABASE GETS, out of the same module. Nothing here
  # re-implements a check: `Story::Audit::Prose` holds both predicates and this
  # supplies the frozen transition in place of a real `Scene`.
  def flags
    @flags ||= passages.flat_map { |passage| check(passage) }
  end

  # The rows of one run set, for a figure quoted against the baseline rather
  # than against the pooled file. `Story::Audit::TransitionTest` reads it.
  def flags_in(set) = flags.select { |flag| flag.scene.set == set }

  private

  def check(passage)
    names = Story::Audit::Prose.item_names(passage.item)

    if passage.took?
      claim = Story::Audit::Prose.prior_possession_claims(passage.text, names).first
      return [] if claim.nil?

      [ flag(:take_denied, passage,
             "this turn picked the #{passage.item} up, and the narration tells the player they already had it",
             claim) ]
    else
      claim = Story::Audit::Prose.invented_pickup_claims(passage.text, names).first
      return [] if claim.nil?

      [ flag(:pickup_invented, passage,
             "this turn put the #{passage.item} down, and the narration has the player pick it up first",
             claim) ]
    end
  end

  def flag(code, passage, headline, claim)
    Story::Audit::Flag.new(
      code: code, scene: passage, headline: headline,
      evidence: { source: passage.label, where: passage.room, typed: passage.typed,
                  item: passage.item, "named as" => claim.name,
                  "the turn did" => "#{passage.action} #{passage.item}",
                  "so before it" => passage.before,
                  claim: claim.sentence.truncate(220) }
    )
  end
end
