require "test_helper"

# `take_denied` AND `pickup_invented`, MEASURED THE WAY EVERY OTHER CHECK HERE
# WAS -- and they are the first two that read a CHANGE rather than a state.
#
# THE COMPLAINT BEHIND THEM is the captain's `ta-narrator-invents-exit`, "the
# narrator asserts state changes the game never records", and specifically his
# sighting of *"losing the location of the ledger when it is put down and picked
# up"*, seen across all four model arms. `Playthrough::Turn#taken_fact` hands
# the narrator the right sentence in the app's own words and the narrator writes
# the opposite. Nine checks were blind to it because `scenes` carried what the
# world IS after a turn and never what the turn DID; `Scene#resolved_action` and
# `Scene#acted_on` are that record and these are the first checks to read one.
#
# THE FALSE-POSITIVE MEASUREMENT: 248 real passages that are not transition
# turns, ZERO FLAGS.
#
#   92   `eval_corpus.json`      take grammar 0 detections, drop grammar 2
#   24   `narration_corpus.json` take grammar 0 detections, drop grammar 2 --
#                                the same two lab narrations, which
#                                `eval_corpus.json` also carries
#   132  `whole_run_corpus.json` take grammar 6 detections, drop grammar 0
#
# Every one of the six take detections is on one of the twelve turns that
# corpus records as a `take`, so all six are TRUE POSITIVES on a corpus neither
# grammar was written against. None of the four drop detections is on a turn
# recorded as a `drop` -- they are the two lab narrations of "burn the daybook
# in the grate", which really do lift the daybook off the desk and are not drop
# turns -- so neither check raises a flag on any of the three.
#
# AND THE POSITIVE CASE IS NOT ONLY THE FROZEN RATE. Two of the tests below
# take a real sentence and put the record underneath it, the way
# `Story::Audit::ArrivalTest` does, because a check that cannot fire looks
# exactly like a clean result.
#
# THE HELD-OUT WORLD, STATED RATHER THAN HIDDEN. `The Salt Assizes` is
# `Eval::HELD_OUT` and EVALUATION.md's convention is not to read its passages
# while building a check. `transition_corpus.json` carries it, because the run
# databases it was cut from were about to be lost and freezing half of them
# would have thrown away half the evidence for nothing. The consequence is
# uneven and worth knowing when reading the numbers:
#
#   take_denied      has positives in BOTH worlds, and its independent
#                    confirmation is `whole_run_corpus.json` -- six real
#                    detections in the tuning world alone.
#   pickup_invented  has positives ONLY in the held-out world. Its tuning-world
#                    evidence is the two lab narrations above (the grammar
#                    fires on real tuning prose) and the constructed positive
#                    case below, not an independent rate.
class Story::Audit::TransitionTest < ActiveSupport::TestCase
  TRANSITIONS = JSON.parse(Rails.root.join(Story::Scoreboard::Transitions::PATH).read).freeze
  EVAL_CORPUS = JSON.parse(Rails.root.join("test/fixtures/files/eval_corpus.json").read).freeze
  NARRATIONS = JSON.parse(Rails.root.join("test/fixtures/files/narration_corpus.json").read).freeze
  RUN_CORPUS = JSON.parse(Rails.root.join("test/fixtures/files/whole_run_corpus.json").read).freeze

  # The names the two seeded worlds' items are argued about under, plus the
  # lures `Story::AuditPrecisionTest` plants, so the grammars are pointed at
  # the hardest available target on every corpus rather than only at the rows
  # that declare an item.
  LURES = %w[daybook ledger revolver pistol compass].freeze

  def names_in(row)
    (Array(row["items"]).map { |item| item["name"] } + [ row["item"] ].compact + LURES)
      .flat_map { |name| Story::Audit::Prose.item_names(name) }
      .uniq
  end

  # --- the corpus is what it claims to be -----------------------------------

  test "the transition corpus is 119 real take and drop turns" do
    assert_equal 119, TRANSITIONS.size
    assert_equal %w[drop take], TRANSITIONS.map { |row| row["action"] }.uniq.sort
    assert(TRANSITIONS.all? { |row| row["text"].present? && row["typed"].present? })
    # Every row's item was on the closed set the classifier was offered for that
    # action, read back out of its own stored prompt. That is what makes the
    # recovered action a record rather than a reading of the prose.
    assert(TRANSITIONS.all? { |row| Array(row["offered"]).any? { |name| name.casecmp?(row["item"]) } })
  end

  # The 24-run, 480-turn sweep the manual read of 2026-09-03 was done against,
  # and the set every headline figure here is quoted for.
  test "the baseline set is the 32 takes and 32 drops the manual read counted" do
    baseline = TRANSITIONS.select { |row| row["set"] == Story::Scoreboard::Transitions::BASELINE_SET }

    assert_equal({ "take" => 32, "drop" => 32 }, baseline.group_by { |row| row["action"] }.transform_values(&:size))
  end

  # --- the headline ---------------------------------------------------------

  # THE NUMBER THE INSTRUMENT EXISTS TO MOVE. The prose fix is a separate task;
  # this is the reading it will be judged against.
  test "on the 480-turn baseline the prose denies 28 of 32 takes and invents 4 of 32 pickups" do
    flags = Story::Scoreboard::Transitions.load.flags_in(Story::Scoreboard::Transitions::BASELINE_SET)

    assert_equal 28, flags.count { |flag| flag.code == :take_denied }
    assert_equal 4, flags.count { |flag| flag.code == :pickup_invented }
  end

  # THE FOUR BASELINE TAKES THIS GIVES UP, named so the miss is a decision. All
  # four deny the pickup by handing the thing to somebody else -- and the
  # somebody is Odile Vance, who is the player. That is the opposite claim,
  # reading it needs the protagonist's name rather than the item's, and
  # `third_person_protagonist` catches every one of them from its own side.
  MISSED_TAKES = [
    "but Odile Vance has already lifted it from the desk",
    "your fingers close on empty air—Odile Vance has already taken it",
    "your fingers find only the cool wood of the desk",
    "but it is no longer there—Odile Vance already holds it"
  ].freeze

  test "the four baseline takes the grammar gives up are still given up" do
    corpus = Story::Scoreboard::Transitions.load
    flagged = corpus.flags_in(Story::Scoreboard::Transitions::BASELINE_SET).map { |flag| flag.scene.label }
    baseline = corpus.passages.select { |p| p.baseline? && p.took? }

    missed = baseline.reject { |passage| flagged.include?(passage.label) }

    assert_equal 4, missed.size
    MISSED_TAKES.each do |sentence|
      assert(missed.any? { |passage| passage.text.include?(sentence) },
             "the passage this trade was measured on is gone: #{sentence}")
    end
  end

  # The other measured miss, and it is the alias rule rather than the grammar:
  # `Story::Audit::Prose.item_names` gives "Assize tide-slate" and "tide-slate"
  # and prose is free to write "slate". Widening it here would move counts
  # `item_not_held` and `unrecorded_arrival` are pinned on.
  test "a name the records do not hold is missed, and the alias rule is why" do
    assert_equal [ "Assize tide-slate", "tide-slate" ], Story::Audit::Prose.item_names("Assize tide-slate")

    sentence = "The slate is already in your hands."

    assert_empty Story::Audit::Prose.prior_possession_claims(sentence, Story::Audit::Prose.item_names("Assize tide-slate"))
    assert_not_empty Story::Audit::Prose.prior_possession_claims(sentence, [ "slate" ])
  end

  # --- false positives on the three existing corpora ------------------------

  # Detections, not flags: what the grammar finds before a record is consulted.
  def detections(rows, text_key, &block)
    rows.flat_map do |row|
      names = names_in(row)
      takes = Story::Audit::Prose.prior_possession_claims(row.fetch(text_key), names).map { |c| [ :take, row, c ] }
      drops = Story::Audit::Prose.invented_pickup_claims(row.fetch(text_key), names).map { |c| [ :drop, row, c ] }
      (takes + drops).uniq { |kind, _, claim| [ kind, claim.sentence ] }
    end.select(&block || ->(_) { true })
  end

  test "on 92 frozen passages the take grammar finds nothing and the drop grammar finds two" do
    found = detections(EVAL_CORPUS, "text")

    assert_empty found.select { |kind, _, _| kind == :take }
    assert_equal 2, found.count { |kind, _, _| kind == :drop }
    # Both are the same lab narration of "burn the daybook in the grate", which
    # really does lift the daybook off the desk. Neither passage is a turn the
    # records call a `drop`, so neither is a flag -- and if one ever were, the
    # flag would be right.
    assert(found.all? { |_, row, _| row["typed"].to_s.start_with?("burn the daybook") })
  end

  test "on the 24 lab narrations the take grammar finds nothing and the drop grammar finds two" do
    found = detections(NARRATIONS, "narration")

    assert_empty found.select { |kind, _, _| kind == :take }
    assert_equal [ 6 ], found.map { |_, row, _| row["case"] }.uniq
  end

  # THE INDEPENDENT CONFIRMATION, and the reason `take_denied` is not resting on
  # the held-out world: `whole_run_corpus.json` is twelve complete playthroughs
  # of the TUNING world across four model arms, with the branch each turn took
  # written down. The take grammar fires six times and every one is on a turn
  # that corpus records as a `take`.
  test "on 132 whole-run narrations every take detection is on a recorded take" do
    found = detections(RUN_CORPUS, "text")
    takes = found.select { |kind, _, _| kind == :take }

    assert_equal 6, takes.size
    assert_equal [ "take" ], takes.map { |_, row, _| row["branch"] }.uniq
    assert_empty found.select { |kind, _, _| kind == :drop }
  end

  test "no passage of the three existing corpora is a turn either check would flag" do
    flags = detections(RUN_CORPUS, "text").select do |kind, row, _|
      (kind == :take && row["branch"] == "take") || (kind == :drop && row["branch"] == "drop")
    end

    # Six, and all six are real. They are counted here as what they are -- true
    # positives on a corpus written before either grammar existed -- and they
    # are not flags on the scoreboard, because `whole_run_corpus.json` is not
    # one of the corpora it scores.
    assert_equal 6, flags.size
    assert(flags.all? { |_, _, claim| claim.sentence.match?(/\balready\b/i) })
  end

  # --- the positive case, with the record moved under a real sentence -------

  test "a real sentence flags when the records say this turn made the pickup" do
    story = seeded("The Unrecorded Hour")
    room = story.locations.find_by!(name: "Ward Office 12")
    item = Item.create!(name: "Ward Office 12 daybook", description: "Quarter-bound.",
                        character: story.protagonist)

    sentence = "You already hold the Ward Office 12 daybook, its weight familiar in your hands."
    scene = played(story, room, sentence, action: "take", acted_on: item)

    flags = audit(story, scene).flags

    assert_equal [ :take_denied ], flags.map(&:code)
    assert_equal "take Ward Office 12 daybook", flags.first.evidence["the turn did"]
    assert_match(/already had it/, flags.first.headline)
  end

  # The same sentence on a turn that was NOT a take is not a claim about a
  # change and is not flagged. This is the whole difference between this check
  # and `item_not_held`, which reads the same prose against a different record.
  test "the same sentence on a turn that picked nothing up is not flagged" do
    story = seeded("The Unrecorded Hour")
    room = story.locations.find_by!(name: "Ward Office 12")
    Item.create!(name: "Ward Office 12 daybook", description: "Quarter-bound.", character: story.protagonist)

    scene = played(story, room, "You already hold the Ward Office 12 daybook, its weight familiar in your hands.",
                   action: "examine", acted_on: nil)

    assert_empty audit(story, scene).flags
  end

  # A REAL SENTENCE FROM THE TUNING WORLD, with the record moved: the lab
  # narration of "burn the daybook in the grate" lifts the daybook off the desk,
  # and on a turn the records call a `drop` that is a pickup the app never made.
  DROP_SENTENCE = "You lift the daybook from the desk, its pages stiff with ink and time, " \
                  "and carry it to the small iron grate set into the wall.".freeze

  test "a real tuning-world sentence flags when the records say this turn put it down" do
    assert(NARRATIONS.any? { |row| row["narration"].include?(DROP_SENTENCE) },
           "the corpus no longer holds the sentence this positive case is built on")

    story = seeded("The Unrecorded Hour")
    room = story.locations.find_by!(name: "Ward Office 12")
    item = Item.create!(name: "daybook", description: "Quarter-bound.", location: room)

    scene = played(story, room, DROP_SENTENCE, action: "drop", acted_on: item)
    # SCOPED TO THE TWO NEW CODES, because the same sentence is a possession
    # claim about a thing the records have lying in this room and `item_not_held`
    # answers that on its own terms. Two checks reading one sentence for two
    # different reasons is the design; this test is about one of them.
    flags = transition_flags(story, scene)

    assert_equal [ :pickup_invented ], flags.map(&:code)
    assert_equal "drop daybook", flags.first.evidence["the turn did"]
    assert_equal "the daybook was in the player's hands, not lying anywhere", flags.first.evidence["so before it"]
  end

  # THE LINE THIS CHECK MUST NOT CROSS. Lifting a thing out of your own hands is
  # what putting it down IS, and five of the 32 baseline drops are written that
  # way. Flagging them would be flagging the prose for describing the turn
  # correctly.
  test "lifting a thing without saying where from is not an invented pickup" do
    story = seeded("The Salt Assizes")
    room = story.locations.find_by!(name: "The Causeway Court")
    item = Item.create!(name: "Assize tide-slate", description: "Ruled in chalk.", location: room)

    [
      "You lift the Assize tide-slate and set it carefully on the Justicar's bench.",
      "You lift the Assize tide-slate with both hands, its weight familiar, and set it down.",
      "You set the Assize tide-slate down on the Justicar's bench, its chalked surface facing upward.",
      "You take the Assize tide-slate from your hands and lay it flat.",
      "You lift the Assize tide-slate from your satchel and set it on the bench."
    ].each do |passage|
      scene = played(story, room, passage, action: "drop", acted_on: item)

      assert_empty transition_flags(story, scene), "flagged a description of putting it down: #{passage}"
    end
  end

  # And the mirror: possession without `already` is what a good take narration
  # says AFTER the pickup, and it is correct.
  test "saying the player has the thing is not saying they always had it" do
    story = seeded("The Salt Assizes")
    room = story.locations.find_by!(name: "The Causeway Court")
    item = Item.create!(name: "Assize tide-slate", description: "Ruled in chalk.",
                        character: story.protagonist)

    [
      "You lift the Assize tide-slate from the flagstones, its weight settling into your hands.",
      "The Assize tide-slate is heavy in your hands, the chalk cold under your thumb.",
      "You do not already hold the Assize tide-slate; you have only just picked it up."
    ].each do |passage|
      scene = played(story, room, passage, action: "take", acted_on: item)

      assert_empty transition_flags(story, scene), "flagged a correct take narration: #{passage}"
    end
  end

  # --- the denominator ------------------------------------------------------

  # A check that reads a change can only be run on a turn that made one, and
  # saying so is the difference between a rate and a number.
  test "the denominator is the recorded transitions and nothing else" do
    story = seeded("The Unrecorded Hour")
    room = story.locations.find_by!(name: "Ward Office 12")
    item = Item.create!(name: "Ward Office 12 daybook", description: "Quarter-bound.", location: room)

    taken = played(story, room, "You lift it, and the gap stares up at you.", action: "take", acted_on: item)
    played(story, room, "You read the gap again.", action: "examine", acted_on: nil, after: taken)

    audit = Story::Audit.new(story, scenes: story.scenes.where(id: [ taken.id ] + story.scenes.where.not(id: taken.id).where.not(is_opening: true).ids))

    assert_equal 1, audit.judgeable_for(:take_denied)
    assert_equal 0, audit.judgeable_for(:pickup_invented)
    assert_includes audit.available_checks, :take_denied
    assert_includes audit.available_checks, :pickup_invented
  end

  # A turn whose action resolved to no record moved nothing, so it is not a
  # transition and cannot be judged as one. That is the drift case, and
  # `Playthrough::Drift` already counts it.
  test "an action that resolved to no record is not a transition" do
    story = seeded("The Unrecorded Hour")
    room = story.locations.find_by!(name: "Ward Office 12")

    scene = played(story, room, "You already hold the Ward Office 12 daybook.", action: "take", acted_on: nil)

    assert_not scene.took?
    assert_equal 0, audit(story, scene).judgeable_for(:take_denied)
    assert_empty audit(story, scene).flags
  end

  private

  def seeded(title)
    @seeded ||= WorldSeed::Loader.load_all(io: nil).index_by(&:title)
    @seeded.fetch(title)
  end

  def played(story, room, description, action:, acted_on:, after: nil)
    previous = after || story.opening_scene

    Scene.create!(story: story, location: room, previous_scene: previous, description: description,
                  typed: "a line this test typed", summary: "a turn written by this test",
                  resolved_action: action, acted_on: acted_on,
                  story_timestamp: (previous&.story_timestamp || story.start_time) + 5.minutes)
  end

  def audit(story, scene) = Story::Audit.new(story, scenes: story.scenes.where(id: scene.id))

  # The two checks this file is about. Everything else in the sweep still runs
  # over these constructed scenes and is somebody else's measurement.
  def transition_flags(story, scene)
    audit(story, scene).flags.select { |flag| %i[take_denied pickup_invented].include?(flag.code) }
  end
end
