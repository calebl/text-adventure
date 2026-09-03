require "test_helper"

# `item_not_held`, RE-MEASURED AFTER TWO CHANGES THAT `ta-eval-pipeline` FORCED.
#
# The check shipped in PR 99 with 8 signed flags on the narration corpus and
# then, pointed at 132 whole-run narrations of a world whose one item exists,
# flagged NOTHING. Two separate faults, both found by measurement and both fixed
# here, and this test is the measurement that keeps them fixed.
#
# 1. THE RECORDS' NAME IS NOT THE PROSE'S NAME. `Item#name` is "Ward Office 12
#    daybook". Matched on that string the check raises NOTHING on all 132 --
#    the eleven passages that contain it in full are echoing the command that
#    named it, never claiming it -- while the prose calls the thing "daybook"
#    in a third of them. A check that is live and permanently silent reads as a
#    clean result, which is the exact failure `Story::Audit`'s header warns
#    about. `Story::Audit::Prose.item_names` adds the head-noun alias.
#
# 2. A POSSESSIVE IS OWNERSHIP, NOT CUSTODY. With the alias in, the possessive
#    grammar raised 8 flags on those transcripts -- and 6 of them were
#    "your daybook lies open on your desk", said of a daybook the records had
#    lying on that desk. True sentences. So grammar 2 is dropped when the thing
#    is in the room the player is standing in; grammars 1 and 3 (a possession
#    verb, or the thing on the player's person) still fire, because those are
#    claims about custody and custody is what the records hold.
#
# THE TRADE, STATED RATHER THAN BURIED. On those 132 passages:
#
#   loose (possessive counted everywhere)   8 flags, 3 true, 5 FALSE  -- 38%
#   strict (possessive needs the thing to
#   be somewhere the player is not)         2 flags, 2 true, 0 false  -- 100%
#
# So the narrowing costs one true positive and removes five false ones. The one
# it costs is pinned in `SACRIFICED` below: "your daybook ... lies waiting under
# your hand" is a custody claim, and the only grammar that would still catch it
# is the on-the-person one, whose 60-character window this sentence is two
# characters too long for. Widening that window to 80 recovers it AND changes
# two flags on the pinned corpora, which is a separate change with its own
# measurement to do; it is not made here. `#the window on the on-the-person
# grammar is a measured constant` pins the figures so the trade can be re-taken
# deliberately.
#
# WHAT SURVIVES is the captain's own `ta-narrator-invents-exit` sighting --
# *"losing the location of the ledger when it is put down and picked up"* --
# caught on the turn after the drop.
class Story::Audit::ItemCustodyTest < ActiveSupport::TestCase
  CORPUS = JSON.parse(Rails.root.join("test/fixtures/files/whole_run_corpus.json").read).freeze

  # The daybook's real position on each turn, as the run recorded it.
  def positions
    CORPUS.map do |row|
      item = row.fetch("items").first
      { text: row.fetch("text"), room: row["room"], arm: row["arm"], rep: row["rep"], turn: row["turn"],
        held: item["held_by"].present?, lying_in: item["lying_in"] }
    end
  end

  def claims?(text, name, custody_only:)
    Story::Audit.allocate.send(:possession_claimed?, text, name, custody_only: custody_only)
  end

  test "the corpus carries the item's position on every turn, which is what makes this measurable" do
    assert_equal 132, CORPUS.size
    assert(CORPUS.all? { |row| row.fetch("items").size == 1 })
    assert_equal [ "Ward Office 12 daybook" ], CORPUS.flat_map { |row| row["items"].map { |item| item["name"] } }.uniq
    assert_equal %w[false true], CORPUS.map { |row| row["items"].first["held_by"].present?.to_s }.uniq.sort
  end

  # 1. THE ALIAS. Without it the check cannot fire at all on this world.
  test "matched on the recorded name the check is live and permanently silent" do
    loose = positions.reject { |row| row[:held] }

    assert_equal 0, loose.count { |row| claims?(row[:text], "Ward Office 12 daybook", custody_only: false) },
                 "the full recorded name claims nothing in 132 real narrations"
    assert_operator loose.count { |row| claims?(row[:text], "daybook", custody_only: false) }, :>, 0,
                    "the head noun is the only name the prose ever makes a claim with"
    assert_equal [ "Ward Office 12 daybook", "daybook" ], Story::Audit::Prose.item_names("Ward Office 12 daybook")
  end

  # 2. THE MEASUREMENT THAT FORCED THE CUSTODY RULE, both sides of it.
  test "counting the bare possessive raises six false positives on real prose" do
    loose = positions.reject { |row| row[:held] }
                     .select { |row| claims?(row[:text], "daybook", custody_only: false) }
    strict = positions.reject { |row| row[:held] }
                      .select { |row| claims?(row[:text], "daybook", custody_only: row[:lying_in] == row[:room]) }

    assert_equal 8, loose.size, "the loose rule used to raise these: #{loose.map { |r| r[:turn] }.tally.inspect}"
    assert_equal 2, strict.size, strict.map { |row| "#{row[:arm]} r#{row[:rep]} #{row[:turn]}" }.join(", ")
  end

  # THE TWO THAT SURVIVE, quoted so every flag this raises on real prose is one
  # somebody has read. Both say the book is in her hand on a turn the records
  # have it lying on the desk she put it down on.
  SURVIVOR = "Your daybook lies open under your hand with the stamp beside it".freeze

  # THE ONE TRUE POSITIVE THE NARROWING COSTS, kept here so the trade stays a
  # decision. Grammar 3 would catch it and does not: there are 62 characters
  # between "daybook" and "under your hand" and its window is 60.
  SACRIFICED = "lies waiting under your hand".freeze

  test "the flags that survive are the captain's own sighting" do
    strict = positions.reject { |row| row[:held] }
                      .select { |row| claims?(row[:text], "daybook", custody_only: row[:lying_in] == row[:room]) }

    assert_equal 2, strict.size
    strict.each { |row| assert_includes row[:text], SURVIVOR }
    assert(strict.all? { |row| row[:lying_in] == row[:room] },
           "both are turns where the records have the book on the desk in this very room")
  end

  # THE SIX THAT ARE DROPPED: five true sentences and one real miss, named.
  test "five of the six sentences the custody rule drops are compatible with the records" do
    dropped = positions.reject { |row| row[:held] }
                       .select { |row| claims?(row[:text], "daybook", custody_only: false) }
                       .reject { |row| claims?(row[:text], "daybook", custody_only: row[:lying_in] == row[:room]) }

    assert_equal 6, dropped.size

    sentences = dropped.map { |row| Story::Audit::Prose.sentences(row[:text]).find { |line| line.match?(/\bdaybook\b/i) } }
    compatible, missed = sentences.partition { |line| !line.include?(SACRIFICED) }

    assert_equal 5, compatible.size
    compatible.each do |line|
      assert_match(/\byour\b/i, line, "the compatible ones are bare possessives")
      assert_no_match(/\b(?:in|on|at|against|under)\s+your\s+(?:hand|hands|palm|fingers)\b/i, line,
                      "a custody claim must not be counted as compatible: #{line}")
    end

    assert_equal 1, missed.size, "the sacrificed true positive is still exactly one"
  end

  # THE WINDOW THAT LOSES IT, measured, so widening it is a decision with a
  # price rather than a tweak. At 80 the sacrificed claim comes back and two
  # more passages on the pinned corpora start matching -- both would have to be
  # read and signed for, which is a change with its own measurement.
  test "the window on the on-the-person grammar is a measured constant" do
    at = lambda do |window|
      places = Regexp.union(Story::Audit::ON_THE_PERSON)
      pattern = /\bdaybook\b[^.!?;:]{0,#{window}}?\b(?:in|on|at|against|under)\s+your\s+(?:#{places})\b/i
      positions.reject { |row| row[:held] }.count { |row| row[:text].match?(pattern) }
    end

    assert_equal 2, at.call(60)
    assert_equal 3, at.call(80), "80 is what would recover the sacrificed claim"
  end

  # AND THE RULE DOES NOT COST THE PINNED CORPUS ANYTHING, which is the other
  # half of a narrowing being safe. `Story::AuditPrecisionTest` pins the flags
  # themselves; this states why they survive.
  test "an item in somebody else's hands is still claimed by a bare possessive" do
    assert claims?("The ruled gap in your daybook seems to deepen in the dimness.", "daybook", custody_only: false)
    assert claims?("The ruled gap in your daybook seems to deepen in the dimness.", "daybook", custody_only: false)
    assert_not claims?("The ruled gap in your daybook seems to deepen in the dimness.", "daybook", custody_only: true)
    assert claims?("You lift the daybook from your desk, the pages stiff under your fingers.", "daybook", custody_only: true)
  end

  # END TO END, through the records rather than through the predicate: the same
  # real sentence, with the book on the desk in front of her.
  test "a narration that puts a dropped book back in the player's hand is flagged" do
    story = WorldSeed::Loader.load_all(io: nil).find { |world| world.title == "The Unrecorded Hour" }
    office = story.locations.find_by!(name: "Ward Office 12")
    daybook = Item.find_by!(name: "Ward Office 12 daybook")
    daybook.update!(character: nil, location: office)
    Item.update_all(updated_at: 1.year.ago)

    scene = Scene.create!(story: story, location: office, previous_scene: story.opening_scene,
                          typed: "walk back into Ward Office 12", summary: "a turn written by this test",
                          description: "You step back in. Your daybook lies open under your hand with the stamp beside it.",
                          story_timestamp: story.start_time + 5.minutes)

    flags = Story::Audit.new(story, scenes: story.scenes.where(id: scene.id)).flags

    assert_equal [ :item_not_held ], flags.map(&:code)
    assert_equal "daybook", flags.first.evidence["named as"]
    assert_equal "lying in Ward Office 12", flags.first.evidence["records say"]
  end

  test "the same room and a bare possessive is not a flag" do
    story = WorldSeed::Loader.load_all(io: nil).find { |world| world.title == "The Unrecorded Hour" }
    office = story.locations.find_by!(name: "Ward Office 12")
    Item.find_by!(name: "Ward Office 12 daybook").update!(character: nil, location: office)
    Item.update_all(updated_at: 1.year.ago)

    scene = Scene.create!(story: story, location: office, previous_scene: story.opening_scene,
                          typed: "look around", summary: "a turn written by this test",
                          description: "Your daybook still lies open on your desk, the gap between four and five as stark as ever.",
                          story_timestamp: story.start_time + 5.minutes)

    assert_empty Story::Audit.new(story, scenes: story.scenes.where(id: scene.id)).flags
  end
end
