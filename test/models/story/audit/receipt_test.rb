require "test_helper"

# `dead_shown_alive`, `carried_shown_lying` AND `handover_invented`, MEASURED
# THE WAY EVERY OTHER CHECK HERE WAS -- and they are the first to read
# `Scene#engine_fact`, the receipt of what the engine handed a scene's writer.
#
# THE DEFECT BEHIND THEM is the arrival and NPC study kept under
# `db/eval/adversarial-20260909`: with the right facts in the prompt, prose
# still put a carried key back on the desk, stood a dead woman up to watch the
# player come in, and had a character hand over a key the engine never moved.
# Its own conclusion was that correct context does not guarantee correct
# prose. The receipt makes the facts durable; these read the prose against it.
#
# THE MEASUREMENT, ON EVERY STORED SET THAT CARRIES A RECEIPT BESIDE ITS PROSE:
#
#   set                          rows  receipt            flags
#   adversarial arrival, after     12  in the prompt      1  carried_key:2
#   arrival-branches               32  facts.current      2  carried_key:2,
#                                                            floor_and_carried:4
#   adversarial NPC, after         20  fact               0
#   dialogue-2026-09-10            36  effect.fact        2  reject-stale-gift:1, :4
#   desires-dialogue-20260919      36  effect.fact        0
#
# FIVE FLAGS ON 136 REAL RECEIPTS, AND EVERY ONE WAS READ. The arrival flag in
# the study is one its readers labelled a contradiction ("the brass key resting
# there", of a key the player carries); the two arrival-branches flags are the
# same sentence in a later run of the same case. The two dialogue flags are a
# refused gift -- the receipt says the engine REJECTED it and nothing moved --
# narrated as "hands it to you" and "places the brass key in your hand". Those
# four were read by the author of this check, not by an independent reader, and
# say so here rather than borrowing the study's authority.
#
# THE LABELS, where the study's readers left them. Arrival descriptions were
# labelled blind by two readers who agreed on every contradiction; the NPC
# narrations by the study's own audit. The study's BEFORE arms predate the
# receipt, so their receipts are supplied rather than recorded -- the arrival
# case's own after-arm receipt (the fixture's records are identical in both
# arms), and for NPC turns the engine's receipt for a turn that moved nothing,
# which is what the before arm's engine did on every row:
#
#   check                 scope                      TP  FP  FN  TN
#   dead_shown_alive      8 dead_resident arrivals    4   0   0   4
#   carried_shown_lying   8 carried_key arrivals      4   0   0   4
#   handover_invented     28 unchanged NPC turns      1   0   5  22
#
# The arrival pair catches all eight labelled arrival contradictions and
# nothing else. The handover's five misses are stated below: one handover the
# negation guard gives up, and four ceasefires accepted in dialogue, which no
# grammar tells from a proposal and which the check does not claim to read.
#
# AND BECAUSE THOSE SETS ARE ONE WORLD, ONE KEY AND ONE WOMAN, the grammars were
# also pointed at the four corpora they were not written against -- 424 real
# passages -- with a receipt PLANTED under each: everybody the checked-in worlds
# name recorded dead, every item carried, no possession moved. Every detection
# was read. Each of the living-act detections is a named person really
# standing, watching or speaking; each of the lying detections really puts the
# thing on a surface or lifts it off one; the handover grammar reads nothing.
# That is the reading precision on prose nobody tuned it to: whenever the
# receipt says the opposite, those sentences are contradictions.
class Story::Audit::ReceiptTest < ActiveSupport::TestCase
  Prose = Story::Audit::Prose
  Receipt = Story::Audit::Receipt
  EVAL = Rails.root.join("db/eval")
  STUDY = EVAL.join("adversarial-20260909")

  # One stored passage and the receipt its writer was handed. `supplied` marks
  # the study's before arms, whose receipt is supplied rather than recorded.
  Row = Data.define(:set, :id, :receipt, :prose, :supplied)

  # The receipt a turn that moved nothing gets, in `Playthrough::NpcAction`'s
  # words for the study's one speaker. Pinned to the writer below.
  UNCHANGED = "Maren changes no possessions, travel agreement or ceasefire.".freeze

  def self.json(path) = JSON.parse(path.read)

  # THE ARRIVAL RECEIPT THE AFTER ARM WAS HANDED, cut out of its stored prompt:
  # the lines under the three-line preamble of "Current State On Arrival" are
  # `Scene::ArrivalContext#facts`, joined the way `engine_fact` joins them.
  def self.arrival_receipt(prompt)
    lines = prompt.split("## Current State On Arrival\n", 2).last.split("\n")
    lines.drop(lines.index { |line| line.start_with?("recorded crossing result") } + 1).join("\n")
  end

  def self.rows
    @rows ||= begin
      after = json(STUDY.join("arrival-after.json")).fetch("rows")
      supplied = after.to_h { |row| [ row["case"], arrival_receipt(row["prompt"]) ] }
      rows = after.map { |row| Row.new("arrival-after", "#{row["case"]}:#{row["rep"]}", arrival_receipt(row["prompt"]), row["description"], false) }
      rows += json(STUDY.join("arrival-before.json")).fetch("rows").map do |row|
        Row.new("arrival-before", "#{row["case"]}:#{row["rep"]}", supplied.fetch(row["case"]), row["description"], true)
      end
      # The two opening cases stage the world's shared first scene, which
      # carries no receipt by design -- they are not rows here.
      rows += json(EVAL.join("arrival-branches/arrival.json")).fetch("rows").filter_map do |row|
        current = row.dig("facts", "current")
        Row.new("arrival-branches", "#{row["id"]}:#{row["rep"]}", current.join("\n"), row["description"], false) if current
      end
      rows += json(STUDY.join("npc-after.json")).fetch("results").map do |row|
        Row.new("npc-after", "#{row["case"]}:#{row["rep"]}", row["fact"], row["narration"].to_s, false)
      end
      rows += json(STUDY.join("npc-before.json")).fetch("results").map do |row|
        Row.new("npc-before", "#{row["case"]}:#{row["rep"]}", UNCHANGED, row["narration"].to_s, true)
      end
      rows + %w[dialogue-2026-09-10 desires-dialogue-20260919].flat_map do |set|
        json(EVAL.join(set, "dialogue.json")).fetch("rows").map do |row|
          Row.new(set, "#{row["id"]}:#{row["rep"]}", row.dig("effect", "fact"), row["narration"].to_s, false)
        end
      end
    end
  end

  def self.recorded = rows.reject(&:supplied)

  # Every flag the check raises on a row, as "set id code".
  def self.flags(rows)
    rows.flat_map do |row|
      Receipt.new(row.receipt).contradictions(row.prose).map { |found| "#{row.set} #{row.id} #{found.code}" }
    end
  end

  # THE STUDY'S LABELS: for arrivals, both blind readers' description readings
  # through the reading key; for NPC turns, the study's contradiction audit.
  def self.arrival_labels
    @arrival_labels ||= begin
      key = json(STUDY.join("arrival-reading-key.json"))
      first = json(STUDY.join("arrival-independent-annotations.json")).fetch("annotations")
                                                                      .to_h { |row| [ row["id"], row.dig("description", "contradiction") ] }
      second = json(STUDY.join("arrival-root-annotations.json")).fetch("readings").transform_values { |row| row["contradiction"] }
      key.to_h { |blind, row| [ "arrival-#{row["arm"]} #{row["case"]}:#{row["rep"]}", [ first.fetch(blind), second.fetch(blind) ] ] }
    end
  end

  def self.npc_labels
    @npc_labels ||= json(STUDY.join("npc-contradiction-audit.json")).flat_map do |arm, rows|
      rows.map { |id, row| [ "npc-#{arm} #{id}", row["contradiction"] ] }
    end.to_h
  end

  # TP/FP/FN/TN of one check over the labelled rows whose receipt states what it reads.
  def self.confusion(code, labels)
    scope = rows.select { |row| labels.key?("#{row.set} #{row.id}") && Receipt.new(row.receipt).states?(code) }
    scope.each_with_object(Hash.new(0)) do |row, counts|
      flagged = Receipt.new(row.receipt).contradictions(row.prose).any? { |found| found.code == code }
      labelled = labels.fetch("#{row.set} #{row.id}")
      counts[flagged ? (labelled ? :tp : :fp) : (labelled ? :fn : :tn)] += 1
    end
  end

  # --- the readers are the writers' own words -------------------------------

  test "an arrival receipt the generator wrote reads back as the dead and the carried" do
    story = create(:story)
    game = create(:playthrough, :started, story: story)
    destination = create(:location, story: story)
    person = create(:character, story: story, location: destination, fullname: "Maren Vosk")
    key = lying_here(game, destination, name: "brass key")
    turn = Playthrough::Turn.new(game)
    turn.harm!(person, person.max_hp)
    turn.carry!(key)

    scene = BaseAgent.stub(:new, FakeAgent.new("description" => "You come in.", "summary" => "Arrived.")) do
      Scene::Generator.new(destination, playthrough: game).generate!
    end
    receipt = Receipt.for(scene)

    assert_equal [ "Maren Vosk" ], receipt.dead
    assert_equal [ "brass key" ], receipt.carried
    assert_equal [], receipt.lying
    assert receipt.states?(:dead_shown_alive)
    assert receipt.states?(:carried_shown_lying)
    assert_not receipt.states?(:handover_invented)
  end

  test "the NPC receipts for no effect and a refused effect both read as nothing moved" do
    story = create(:story)
    here = create(:location, story: story)
    game = create(:playthrough, :started, story: story, current_location: here)
    maren = create(:character, story: story, location: here, fullname: "Maren")

    none = Playthrough::NpcAction.new(game, maren).apply!(Playthrough::NpcAction::NONE)
    refused = Playthrough::NpcAction.new(game, maren).apply!("give:0")

    assert_equal UNCHANGED, none.fact
    assert_equal "rejected", refused.status
    assert Receipt.new(none.fact).possessions_unchanged?
    assert Receipt.new(refused.fact).possessions_unchanged?
  end

  test "a receipt that moved a possession, or says nothing a check reads, states nothing" do
    [ "Maren gave brass key to Cal; the player now carries it.",
      "Maren stopped fighting the player. The ceasefire holds unless the player attacks again.",
      "You are unhurt.\nNobody else is alive here.\nLying here: brass key.\nYou are carrying: nothing." ].each do |text|
      Receipt::SHAPES.each_key { |code| assert_not Receipt.new(text).states?(code), "#{code} on #{text.inspect}" }
    end
  end

  # --- the measurement ------------------------------------------------------

  test "the stored sets carry 136 recorded receipts and 32 supplied ones" do
    assert_equal({ "arrival-after" => 12, "arrival-branches" => 32, "npc-after" => 20,
                   "dialogue-2026-09-10" => 36, "desires-dialogue-20260919" => 36 },
                 self.class.recorded.map(&:set).tally)
    assert_equal({ "arrival-before" => 12, "npc-before" => 20 }, self.class.rows.select(&:supplied).map(&:set).tally)
  end

  test "each check's denominator over the recorded receipts" do
    judgeable = Receipt::SHAPES.keys.index_with do |code|
      self.class.recorded.count { |row| Receipt.new(row.receipt).states?(code) }
    end

    assert_equal({ dead_shown_alive: 8, carried_shown_lying: 12, handover_invented: 40 }, judgeable)
  end

  # FIVE FLAGS, EACH READ. A sixth appearing is not a pass: read it.
  test "the recorded receipts raise exactly the five flags that were read as contradictions" do
    assert_equal [ "arrival-after carried_key:2 carried_shown_lying",
                   "arrival-branches carried_key:2 carried_shown_lying",
                   "arrival-branches floor_and_carried:4 carried_shown_lying",
                   "dialogue-2026-09-10 reject-stale-gift:1 handover_invented",
                   "dialogue-2026-09-10 reject-stale-gift:4 handover_invented" ],
                 self.class.flags(self.class.recorded).sort
  end

  test "the study's two arrival readers agree on every description contradiction" do
    disagreements = self.class.arrival_labels.reject { |_, (first, second)| first == second }

    assert_empty disagreements
    assert_equal 8, self.class.arrival_labels.count { |_, (first, _)| first }
  end

  test "against the study's readers the arrival checks find all eight contradictions and nothing else" do
    labels = self.class.arrival_labels.transform_values(&:first)

    assert_equal({ tp: 4, tn: 4 }, self.class.confusion(:dead_shown_alive, labels))
    assert_equal({ tp: 4, tn: 4 }, self.class.confusion(:carried_shown_lying, labels))
  end

  # THE MISSES ARE THE STATED ONES. `give-owned-key:2` is a real handover --
  # "reaches into her pocket without hesitation, pulls out the brass key, and
  # places it in your hand" -- whose "without" is the negation guard's; the four
  # ceasefires are "I accept your truce", which is speech.
  test "against the study's audit the handover check is exact and misses what it says it misses" do
    assert_equal({ tp: 1, fn: 5, tn: 22 }, self.class.confusion(:handover_invented, self.class.npc_labels))

    missed = self.class.rows.select do |row|
      self.class.npc_labels["#{row.set} #{row.id}"] && Receipt.new(row.receipt).contradictions(row.prose).empty?
    end
    assert_equal [ "give-owned-key:2", "honor-ceasefire:1", "honor-ceasefire:2", "honor-ceasefire:3", "honor-ceasefire:4" ],
                 missed.map(&:id).sort
  end

  test "the supplied receipts flag the before arms where the readers did" do
    assert_equal [ "arrival-before carried_key:1 carried_shown_lying", "arrival-before carried_key:2 carried_shown_lying",
                   "arrival-before carried_key:4 carried_shown_lying", "arrival-before dead_resident:1 dead_shown_alive",
                   "arrival-before dead_resident:2 dead_shown_alive", "arrival-before dead_resident:3 dead_shown_alive",
                   "arrival-before dead_resident:4 dead_shown_alive", "npc-before give-owned-key:1 handover_invented" ],
                 self.class.flags(self.class.rows.select(&:supplied)).sort
  end

  # --- through the audit: one real passage each way, and no receipt ---------

  ARRIVAL_DEAD = "You are unhurt.\nNobody else is alive here.\nDead here: Maren Vosk. They cannot speak or act.\n" \
                 "Lying here: brass key.\nYou are carrying: nothing.".freeze
  ARRIVAL_CARRIED = "You are unhurt.\nAlso here: Maren Vosk. Nobody else is alive here.\nLying here: nothing.\n" \
                    "You are carrying: brass key.".freeze
  REFUSED = "The proposed action was rejected: it is unavailable. No possessions, travel agreement or ceasefire changed.".freeze

  def prose(set, id) = self.class.rows.find { |row| row.set == set && row.id == id }.prose

  def audit_of(description, engine_fact, action:)
    story = create(:story)
    room = create(:location, story: story)
    acted_on = action == "talk" ? create(:character, story: story, location: room, fullname: "Maren") : room
    scene = create(:scene, story: story, location: room, description: description, engine_fact: engine_fact,
                           resolved_action: action, acted_on: acted_on, story_timestamp: story.start_time)
    [ Story::Audit.new(story), scene ]
  end

  def codes(audit) = audit.flags.map(&:code)

  # The receipt checks' own unjudged rows; a story with no protagonist also
  # leaves `third_person_protagonist` unjudged, which is not these checks' count.
  def receipt_unjudged(audit)
    audit.unjudged.select { |skipped| Receipt::SHAPES.key?(skipped.code) }.map { |skipped| [ skipped.code, skipped.scene ] }
  end

  test "an arrival that stands the dead up is flagged, with the receipt and the sentence as evidence" do
    audit, scene = audit_of(prose("arrival-before", "dead_resident:1"), ARRIVAL_DEAD, action: "move")

    assert_equal [ :dead_shown_alive ], codes(audit)
    flag = audit.flags.first
    assert flag.contradiction?
    assert_equal scene, flag.scene
    assert_equal "Maren Vosk", flag.evidence[:person]
    assert_equal "Dead here: Maren Vosk.", flag.evidence["the receipt says"]
    assert_includes flag.evidence[:claim], "Maren Vosk stands motionless"
    assert_equal 1, audit.judgeable_for(:dead_shown_alive)
  end

  test "an arrival that writes the body as a body is not flagged" do
    audit, = audit_of(prose("arrival-after", "dead_resident:4"), ARRIVAL_DEAD, action: "move")

    assert_empty audit.flags
  end

  test "an arrival that puts the carried key back on the desk is flagged" do
    audit, = audit_of(prose("arrival-before", "carried_key:1"), ARRIVAL_CARRIED, action: "move")

    assert_equal [ :carried_shown_lying ], codes(audit)
    assert_equal "brass key", audit.flags.first.evidence[:item]
    assert_equal 1, audit.judgeable_for(:carried_shown_lying)
  end

  test "an arrival with the key heavy in the player's palm is not flagged" do
    audit, = audit_of(prose("arrival-after", "carried_key:3"), ARRIVAL_CARRIED, action: "move")

    assert_empty audit.flags
  end

  test "a conversation that hands over a key the engine refused to move is flagged" do
    audit, = audit_of(prose("dialogue-2026-09-10", "reject-stale-gift:4"), REFUSED, action: "talk")

    assert_equal [ :handover_invented ], codes(audit)
    assert_includes audit.flags.first.evidence[:claim], "places the brass key in your hand"
    assert_equal 1, audit.judgeable_for(:handover_invented)
  end

  test "a refusal on an unchanged receipt, and a handover the engine made, are not flagged" do
    refusal, = audit_of(prose("dialogue-2026-09-10", "refuse-trusted-key:1"), UNCHANGED, action: "talk")
    given, = audit_of(prose("npc-after", "give-owned-key:1"), "Maren gave brass key to Cal; the player now carries it.",
                      action: "talk")

    assert_empty refusal.flags
    assert_empty given.flags
    assert_equal 0, given.judgeable_for(:handover_invented)
  end

  # THE SAME PROSE WITH NO RECEIPT UNDER IT is the historical scene: never
  # flagged, never counted clean, and counted as unjudged for each check its
  # shape would have answered.
  test "an arrival with no receipt is skipped and counted, never flagged" do
    audit, scene = audit_of(prose("arrival-before", "dead_resident:1"), nil, action: "move")

    assert_empty audit.flags
    assert_equal [ [ :dead_shown_alive, scene ], [ :carried_shown_lying, scene ] ], receipt_unjudged(audit)
    assert_equal 0, audit.judgeable_for(:dead_shown_alive)
  end

  test "a conversation with no receipt is skipped and counted, never flagged" do
    audit, scene = audit_of(prose("dialogue-2026-09-10", "reject-stale-gift:4"), nil, action: "talk")

    assert_empty audit.flags
    assert_equal [ [ :handover_invented, scene ] ], receipt_unjudged(audit)
  end

  test "a turn of neither shape with no receipt is not counted either" do
    audit, = audit_of(prose("arrival-before", "dead_resident:1"), nil, action: "examine")

    assert_empty audit.flags
    assert_empty receipt_unjudged(audit)
  end

  # THE WHOLE PATH, FROM THE WRITER: a real arrival, its receipt written by
  # `Scene::Generator`, and a stored before-arm paragraph as the model's answer.
  test "an arrival the generator wrote is read against its own receipt" do
    story = create(:story)
    game = create(:playthrough, :started, story: story)
    destination = create(:location, story: story)
    person = create(:character, story: story, location: destination, fullname: "Maren Vosk")
    Playthrough::Turn.new(game).harm!(person, person.max_hp)
    answer = { "description" => prose("arrival-before", "dead_resident:2"), "summary" => "Iri arrives." }

    BaseAgent.stub(:new, FakeAgent.new(answer)) { Scene::Generator.new(destination, playthrough: game).generate! }

    assert_equal [ :dead_shown_alive ], Story::Audit.new(story).flags.map(&:code)
  end

  # --- the grammars on prose nobody tuned them to ---------------------------

  # The people and things the checked-in worlds and the corpora name, frozen
  # here so a new world file cannot move the measurement silently.
  PEOPLE = [ "Ammon Brace", "Bell", "Cal", "Coraith Vell", "Gorva the Wanderer", "Grenn Ollivar", "Halkett Rowe",
             "Isbet Marrow", "Lyssa of the Mist", "Marek Sollen", "Maren", "Neb Halloran", "Nell Cawsand", "Odile Vance",
             "Perrin Lasco", "Prince Aurel Durn", "Veythra the Silent", "Wick" ].freeze
  ITEMS = [ "Assize tide-slate", "Perrin's private index", "Ward Office 12 daybook", "bell-rope tally", "brass key",
            "charred amulet", "charred bone", "copy-room apron", "damp scroll", "filing press", "healing draught",
            "iron coin", "iron flake", "iron key", "iron lever", "iron nail", "iron shard", "prince's signet ring",
            "quarter receipt", "red coin", "rusted dagger", "seal ledger", "tattered cloth", "travel ration",
            "troll-bone shard", "ward stamp", "workshop key" ].freeze

  PLANTED = [
    "Dead here: #{PEOPLE.join(", ")}. They cannot speak or act.",
    "You are carrying: #{ITEMS.join(", ")}.",
    UNCHANGED
  ].join("\n").freeze

  CORPORA = { "eval_corpus" => "text", "narration_corpus" => "narration",
              "whole_run_corpus" => "text", "transition_corpus" => "text" }.freeze

  def self.passages
    @passages ||= CORPORA.flat_map do |file, key|
      JSON.parse(Rails.root.join("test/fixtures/files/#{file}.json").read).map do |row|
        [ "#{file} #{row["label"] || row["case"] || "#{row["world"]}/#{row["turn"]}"}", row.fetch(key).to_s ]
      end
    end
  end

  def self.planted
    @planted ||= passages.flat_map do |label, text|
      Receipt.new(PLANTED).contradictions(text).map { |found| [ found.code, label, found.subject, found.claim.sentence ] }
    end
  end

  test "the planted receipt is read the way a recorded one is" do
    receipt = Receipt.new(PLANTED)

    assert_equal PEOPLE, receipt.dead
    assert_equal ITEMS, receipt.carried
    assert receipt.possessions_unchanged?
  end

  # EVERY ONE OF THESE WAS READ, and every one is a correct reading of what the
  # prose claims: somebody named standing, watching, saying or turning; a thing
  # lying on a surface or lifted off one. A count that moves means a detection
  # nobody has read -- read it before changing the number.
  test "on 424 passages under a planted receipt, every detection is a correct reading" do
    assert_equal 424, self.class.passages.size
    assert_equal({ dead_shown_alive: 42, carried_shown_lying: 29 }, self.class.planted.map(&:first).tally)
  end

  # THE SHAPES THE LYING GRAMMAR WAS NARROWED AWAY FROM, each a real sentence
  # from those corpora: a thing resting in a hand is held, a thing being set
  # down is an act and not a standing claim, and "where the index lay" is where
  # it is not.
  test "the lying grammar does not read a held thing, a put-down thing or a thing that was there" do
    [ "The ledger rests in her hands, its familiar weight slightly off-balance now.",
      "The quarter-bound ledger rests against your palm, its familiar weight slightly off.",
      "You set the Ward Office 12 daybook down on the desk, its spine aligning with the edge of the wood.",
      "You lay the daybook flat on the desk and let go of it.",
      "Yet the gap on the shelf where the index lay is now just a little too precise." ].each do |sentence|
      assert_empty Prose.lying_claims(sentence, %w[ledger daybook index]), sentence
    end
  end

  test "the handover grammar reads a completed transfer and not an offer or a memory" do
    assert_equal 1, Prose.handover_claims("She reaches into her pocket, retrieves the brass key, and hands it to you.").size
    assert_equal 1, Prose.handover_claims("\"Here it is,\" she says, pressing the brass key into your palm.").size

    [ "She reaches into her pocket, her fingers brushing the brass key before pulling it free. She holds it out to you.",
      "She slips a hand into her pocket and brings out the brass key, offering it to you.",
      "Someone pressed it into your hand, and your fingers copied the words.",
      "\"I will put it in your hand when you have earned it,\" she says." ].each do |text|
      assert_empty Prose.handover_claims(text), text
    end
  end

  test "the living grammar reads an act and not a body" do
    assert_equal 1, Prose.living_claims("Maren Vosk stands motionless beside a brass key on the desk.", [ "Maren Vosk" ]).size

    [ "Maren Vosk lies motionless beside the desk, their stillness unnatural.",
      "Then you see Maren Vosk, slumped beside the desk, her stillness unnatural.",
      "The pale, outstretched hand of Maren Vosk floating beside the desk.",
      "Maren Vosk no longer breathes.",
      "\"Maren Vosk said she would be here,\" you recall." ].each do |text|
      assert_empty Prose.living_claims(text, [ "Maren Vosk" ]), text
    end
  end
end
