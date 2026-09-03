# THE NUMBER THAT MOVES WHEN THE GAME GETS BETTER.
#
# `rake game:score` is this class. It runs `Story::Audit` over a corpus, prints
# a rate per check, prints the difference from a stored baseline, and prints
# every flag with the turn, what the player typed and the offending passage.
# **Offline, deterministic, free**: no model call, no API key, no network, so
# it can be run on a whim and it can be run in the test suite.
#
# WHY IT EXISTS, in the captain's words: *"It feels like we are flailing around
# a bit right now without being able to measurably improve the experience.
# Having me review everything manually is too slow and I start losing focus
# from reading variations on the same thing too many times."* Two separate
# asks, and the second one shapes the output as much as the first: the report
# is organised so his attention goes only to turns a check caught. He never
# reads a clean turn again.
#
# WHAT IT DOES NOT DO, and will not: score prose. There is no quality number
# here, no judge model, no aggregate. Every check counts an error that is
# objectively either present or absent, and each one was measured for false
# positives against real stored prose before it shipped -- the precedent is
# `BaseAgent::Refusal`, and the two prose heuristics this project has already
# killed on measurement are recorded in `Story::Audit`'s header.
# `data/ta-model-bench/report.md` §9 has the argument against a judge in full.
#
# TWO CORPORA, REPORTED SEPARATELY AND NEVER POOLED.
#
#   DATABASE  every `Story` on this machine -- the captain's own playthroughs.
#             True, because it is what he actually read, and the only corpus
#             his verdicts attach to. Small, and it drifts: the world changes
#             under it as features land, so a number from last week is not
#             strictly the same measurement as today's. Every check runs.
#
#   CORPUS    `test/fixtures/files/eval_corpus.json` -- real passages, frozen,
#             checked in, and reproducible on a machine with no database at
#             all. This is the precision instrument and the regression guard:
#             `Story::AuditPrecisionTest` pins the exact flags it earns. The
#             checks that need records around the passage cannot run on it and
#             are reported UNAVAILABLE rather than quietly scored as clean.
#             See `Story::Scoreboard::Corpus`.
#
# Adding the two together would produce a number that is neither, so nothing
# here sums them.
class Story::Scoreboard
  # Every check the scoreboard reports on, in the order it prints them, with
  # what each is worth. The order is the trust ordering from
  # `data/ta-model-bench/report.md` §13: what the records prove first, what
  # they witness after.
  CHECKS = {
    unreachable_transition: "the player got somewhere the graph has no edge to",
    unrecorded_departure: "the prose closed a door behind a player who never left",
    unrecorded_arrival: "the prose walked the player into a room the records did not move them to",
    item_not_held: "the prose handed the player something somebody else holds",
    truncated_prose: "stored prose stops mid-sentence",
    third_person_protagonist: "the narration wrote the player as somebody else",
    reached_for_nothing: "the player reached for something the records do not have",
    named_more_than_one: "the line named two things the records have and the turn did one",
    still_run: "#{Story::Audit::STILL_RUN} turns running with nothing changing and somebody in the room"
  }.freeze

  # ONE CHECK'S READING ON ONE CORPUS.
  #
  # `scanned` is the denominator and it is per check rather than global on
  # purpose: `still_run` can only be judged on a turn that has a previous turn,
  # and reporting it out of every scene would understate it. `available` is
  # false for a check the corpus cannot answer -- reported, never counted as
  # zero.
  Reading = Data.define(:code, :flagged, :scanned, :available) do
    def rate = scanned.positive? ? flagged.fdiv(scanned) : 0.0
    def percentage = (rate * 100).round(1)
    def description = CHECKS.fetch(code, code.to_s)
  end

  # WHAT A CHECK IS WORTH AGAINST THE CAPTAIN'S OWN VERDICTS.
  #
  # `Playthrough::Feedback` carries his `good` / `weak` / `bad` labels on real
  # turns, which is ground truth most projects do not have. A check that fires
  # on turns he called `good` is suspect; one that fires on what he called
  # `bad` is earning its keep.
  #
  # IT IS NOT A SCORE AND MUST NOT BE READ AS ONE UNTIL THE LABELS EXIST. He
  # has three verdicts today. `#established?` is false below `MIN_VERDICTS` and
  # the printer says so in words rather than showing a percentage of three.
  Agreement = Data.define(:code, :on_good, :on_weak, :on_bad, :labelled) do
    def flagged = on_good + on_weak + on_bad
    def established? = labelled >= MIN_VERDICTS
  end

  # HOW MANY LABELLED TURNS BEFORE AN AGREEMENT FIGURE IS WORTH PRINTING AS A
  # FIGURE. Thirty is not a statistical threshold -- nothing here is doing
  # inference -- it is the point at which a per-check cross-tab has more than a
  # handful of cells with anything in them. Below it the counts are printed and
  # the correlation is stated as UNESTABLISHED, because dressing up n=3 is the
  # one thing this instrument must not do.
  MIN_VERDICTS = 30

  attr_reader :name, :audits, :note

  # `audits` is any list of `Story::Audit`-shaped objects: the real thing for
  # the database corpus, `Story::Scoreboard::Corpus` for the frozen one. Both
  # answer `scenes`, `flags`, `unjudged` and `scanned`, which is the whole of
  # what this reads.
  def initialize(name, audits, note: nil)
    @name = name
    @audits = Array(audits)
    @note = note
  end

  # EVERY STORY ON THIS MACHINE. The captain's own playthroughs, and the only
  # corpus his verdicts attach to.
  def self.database(scope = Story.all)
    new("database", Story::Audit.all(scope),
        note: "every story in this database -- what he actually played, and the only corpus his verdicts attach to")
  end

  # THE FROZEN CORPUS. Real passages, checked in, reproducible with no database.
  def self.corpus
    new("corpus", [ Story::Scoreboard::Corpus.load ],
        note: "#{Story::Scoreboard::Corpus::PATH} -- real passages, frozen, no database needed")
  end

  # Both, in the order they should be read: the true one first, the
  # reproducible one after it.
  def self.all
    [ database, corpus ]
  end

  def scenes = @scenes ||= audits.flat_map(&:scenes)

  def scanned = scenes.size

  def flags = @flags ||= audits.flat_map(&:flags)

  def unjudged = @unjudged ||= audits.flat_map(&:unjudged)

  def available_checks = @available_checks ||= audits.flat_map(&:available_checks).uniq

  # One reading per check, in `CHECKS` order, whether or not it fired -- a zero
  # that is printed is a measurement and a zero that is missing is an absence.
  def readings
    @readings ||= CHECKS.keys.map do |code|
      Reading.new(code: code,
                  flagged: flags.count { |flag| flag.code == code },
                  scanned: denominator_for(code),
                  available: available_checks.include?(code))
    end
  end

  def reading(code) = readings.find { |r| r.code == code }

  # THE FLAGS, IN THE ORDER HE SHOULD READ THEM: worst class first, then oldest
  # turn first inside each class, so a report reads in the order the story was
  # played.
  def flags_in_reading_order
    order = [ :contradiction?, :defect?, :drift?, :limit?, :pacing? ]

    order.flat_map { |kind| flags.select { |flag| flag.public_send(kind) } }
  end

  # ------------------------------------------------------------------------
  # AGAINST HIS OWN VERDICTS.
  # ------------------------------------------------------------------------

  # EVERY VERDICT RECORDED ON A TURN IN THIS CORPUS, keyed by the turn itself
  # rather than by an id, because the frozen corpus has passages and the
  # database has `Scene`s and this class must not care which it holds. Each
  # audit answers for its own: `Story::Audit` reads `Playthrough::Feedback`,
  # `Story::Scoreboard::Corpus` reads the verdict written beside the passage.
  def verdicts
    @verdicts ||= audits.map(&:verdicts).reduce({}, :merge)
  end

  def labelled = verdicts.size

  def verdict_tally = @verdict_tally ||= verdicts.values.tally

  # AGREEMENT, PER CHECK. How many of each verdict this check fired on. The
  # denominator is the labelled turns, not the corpus, because a turn with no
  # verdict says nothing either way.
  def agreements
    @agreements ||= CHECKS.keys.map do |code|
      # DISTINCT TURNS, not flags: `third_person_protagonist` fires twice on a
      # narration that breaks the rule in two sentences, and counting that turn
      # twice against one verdict would inflate the agreement with the length
      # of the passage.
      hit = flags.select { |flag| flag.code == code }
                 .filter_map(&:scene).uniq
                 .filter_map { |turn| verdicts[turn] }
                 .tally

      Agreement.new(code: code, labelled: labelled,
                    on_good: hit["good"].to_i, on_weak: hit["weak"].to_i, on_bad: hit["bad"].to_i)
    end
  end

  def agreement_established? = labelled >= MIN_VERDICTS

  # THE LABELLED TURNS NO CHECK CAUGHT. The other half of the agreement
  # question and the more useful half while the labels are few: a turn he
  # called `bad` that nothing here flags is a check this loop is missing, and
  # naming it is how the next check gets chosen.
  def missed_verdicts
    caught = flags.filter_map(&:scene).uniq

    verdicts.reject { |turn, verdict| caught.include?(turn) || verdict == "good" }
  end

  # ------------------------------------------------------------------------
  # AGAINST LAST TIME.
  # ------------------------------------------------------------------------

  def baseline = @baseline ||= Story::Scoreboard::Baseline.read(name)

  # What each reading was when the baseline was taken, and the difference. Nil
  # for a check the baseline does not carry, which is what a newly added check
  # looks like and is printed as "new" rather than as an improvement.
  Movement = Data.define(:code, :now, :then_rate, :then_flagged) do
    def new_check? = then_rate.nil?
    def delta = new_check? ? nil : (now.rate - then_rate)
    def moved? = !new_check? && delta.abs >= 0.0001
    def better? = moved? && delta.negative?
  end

  def movements
    readings.map do |reading|
      recorded = baseline&.dig("checks", reading.code.to_s)
      Movement.new(code: reading.code, now: reading,
                   then_rate: recorded&.fetch("rate", nil),
                   then_flagged: recorded&.fetch("flagged", nil))
    end
  end

  # WHETHER THE CORPUS IS EVEN THE SAME SIZE IT WAS. This is why the snapshot
  # stores counts as well as rates: the `database` corpus grows as he plays and
  # can shrink outright if a story is deleted, and a rate compared across a
  # corpus that changed underneath it reads as an improvement nobody made. Nil
  # when there is no baseline or the size is unchanged; otherwise the number of
  # turns it held then, for the report to say so out loud.
  def baseline_scenes
    recorded = baseline&.fetch("scenes", nil)

    recorded if recorded && recorded != scanned
  end

  # The snapshot this run would leave behind. Rates AND counts, because a rate
  # alone cannot be sanity-checked against a corpus that grew.
  def snapshot
    {
      "corpus" => name,
      "recorded_at" => Time.current.utc.iso8601,
      "scenes" => scanned,
      "stories" => audits.size,
      "labelled_turns" => labelled,
      "checks" => readings.to_h do |reading|
        [ reading.code.to_s,
          { "flagged" => reading.flagged, "scanned" => reading.scanned,
            "rate" => reading.rate.round(6), "available" => reading.available } ]
      end
    }
  end

  def save_baseline! = Story::Scoreboard::Baseline.write(name, snapshot)

  def headline
    parts = readings.select { |reading| reading.flagged.positive? }
                    .map { |reading| "#{reading.flagged} #{reading.code}" }

    "#{scanned} turn#{"s" unless scanned == 1}: #{parts.any? ? parts.join(", ") : "nothing flagged"}"
  end

  private

  # WHAT A CHECK COULD HAVE FIRED ON. Asked of each audit rather than worked
  # out here: only the audit knows which of its passages carry the records a
  # given check reads. See `Story::Audit#judgeable_for`.
  def denominator_for(code)
    audits.sum { |audit| audit.judgeable_for(code) }
  end
end
