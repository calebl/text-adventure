require "test_helper"

# THE PRECISION OF THE SWEEP, MEASURED ON REAL NARRATION.
#
# `test/fixtures/files/narration_corpus.json` is 24 narrations that two remote
# models actually wrote: six commands, each aimed at breaking one of a seeded
# world's laws, run against both `minimax/minimax-m3` and
# `mistralai/mistral-medium-3.1`, in two arms (with and without the world's
# rules in the prompt). They were captured live against the two checked-in
# worlds, which is why this test can replay them: the rooms and the cast the
# narrations were written about are `db/seeds/worlds`.
#
# WHY IT IS A TEST AND NOT A NOTE IN A PULL REQUEST. A false-positive rate that
# lives in a commit message decays the first time somebody widens a regex to
# catch one more case. Here, widening a pattern until it flags "There is no
# revolver, no pistol, no weapon of any kind on your person" fails the build.
#
# THE MEASUREMENT, as it stands:
#
#   as seeded, no items in the world      24 narrations, 0 flags
#   with items planted under the names
#   the prose argues about                24 narrations, 8 flags,
#                                         8 true positives, 0 FALSE POSITIVES
#   narrations naming one of those items  15 -- so a vocabulary scan would have
#                                         raised 15 flags where this raises 8
#   real possession claims missed         about half, and one of them
#                                         deliberately (see SACRIFICED)
#
# The eight are enumerated below, one line each, so every flag this sweep raises
# on real prose is a flag somebody has read and signed for. If a change here
# makes the set bigger, the new one has to be read and signed for too -- and if
# it cannot be defended, the change is wrong rather than the test.
class Story::AuditPrecisionTest < ActiveSupport::TestCase
  CORPUS = JSON.parse(Rails.root.join("test/fixtures/files/narration_corpus.json").read).freeze

  # Names drawn from the corpus commands and prose, so the possession check has
  # the hardest target there is: prose that discusses a thing at length while
  # denying the player has it. None of these items exists in the seeded worlds;
  # they are planted here to give the check something to be wrong about.
  LURES = {
    "The Lunar Cartographer" => %w[revolver pistol gun ledger] + [ "lunar compass", "field notes" ],
    "The Unrecorded Hour" => %w[daybook seal ink] + [ "electric light" ]
  }.freeze

  # EVERY FLAG THE SWEEP RAISES ON THE CORPUS, judged one by one. `[case, model,
  # arm, item]`, with the sentence that earned it above each. All eight say the
  # player HAS the thing; the records say somebody else does.
  EXPECTED = [
    # "You reach into your coat and draw your revolver, its weight familiar in your hand."
    [ 1, "mistralai/mistral-medium-3.1", "plain", "revolver" ],
    # "You stand by the door, the weight of the cold iron revolver heavy in your palm."
    [ 2, "mistralai/mistral-medium-3.1", "plain", "revolver" ],
    # "...the weight of the Nocturna-infused pistol heavy in your hand as you wait."
    [ 2, "mistralai/mistral-medium-3.1", "ruled", "pistol" ],
    # "You kneel beside the chair and fish the lunar compass from the satchel,
    #  its brass casing warm against your palm..."
    [ 4, "minimax/minimax-m3", "ruled", "lunar compass" ],
    # "The ruled gap in your daybook seems to deepen in the dimness..."
    [ 5, "mistralai/mistral-medium-3.1", "plain", "daybook" ],
    # "...the ruled gap in your daybook seems, if anything, a shade more definite in the dim."
    [ 5, "mistralai/mistral-medium-3.1", "ruled", "daybook" ],
    # "You lift the daybook from your desk, the pages stiff under your fingers..."
    [ 6, "mistralai/mistral-medium-3.1", "plain", "daybook" ],
    # "You lift the daybook from the desk, its pages stiff with ink and time..."
    [ 6, "mistralai/mistral-medium-3.1", "ruled", "daybook" ]
  ].freeze

  # THE ONE TRUE POSITIVE GIVEN UP ON PURPOSE, kept here so the trade is visible
  # rather than merely commented. Case 2, minimax, ruled:
  #
  #   "You pull the door open and rest your hand on the grip of the pistol at
  #    your hip -- but Grenn does not flinch."
  #
  # A real possession claim, missed because the negation guard reads the whole
  # sentence and the sentence contains "not" -- about Grenn, not about the
  # pistol, and no regex tells those apart. Guarding only the matched span
  # instead flags "You reach for the revolver at your hip, but your fingers find
  # only the empty holster", which is a denial. One miss was the price of that
  # one false positive, and precision is what this sweep optimises. See
  # `Story::Audit#possession_claimed?`.
  SACRIFICED = [ 2, "minimax/minimax-m3", "ruled" ].freeze

  def setup
    @stories = WorldSeed::Loader.load_all(io: nil).index_by(&:title)
  end

  test "the corpus is what it claims to be" do
    assert_equal 24, CORPUS.size
    assert_equal 6, CORPUS.map { |row| row["case"] }.uniq.size
    assert_equal 2, CORPUS.map { |row| row["model"] }.uniq.size
    assert_equal %w[plain ruled], CORPUS.map { |row| row["arm"] }.uniq.sort
    assert(CORPUS.all? { |row| row["narration"].present? })
  end

  test "every corpus narration was written about a room the seeded worlds still have" do
    CORPUS.each do |row|
      story = @stories.fetch(row["world"])

      assert story.locations.find_by(name: row["room"]),
             "#{row["world"]} no longer has #{row["room"].inspect}, so the corpus cannot be replayed against it"
    end
  end

  # THE HEADLINE RESULT. The seeded worlds carry no items, so the possession
  # check has nothing to check and the sweep is left with the state transitions
  # -- which these scenes do not make. Zero flags on 24 real narrations.
  test "the sweep raises nothing on 24 real narrations of a world with no items" do
    replay

    flags = Story::Audit.all.flat_map(&:flags)

    assert_empty flags, flags.map(&:headline).join("\n")
  end

  # THE MEASUREMENT THAT MATTERS, because it is the one where the check can be
  # wrong: 15 of the 24 narrations name one of the planted items, and the sweep
  # flags the nine that claim the player has it.
  test "with items planted under the names the prose argues about, every flag is a possession claim" do
    plant_lures
    scenes = replay

    flags = flags_on(scenes)
    raised = flags.map { |flag| key_for(scenes.fetch(flag.scene.id), flag.evidence[:item]) }

    assert_equal EXPECTED.sort, raised.sort, <<~MESSAGE
      The set of flags on the real corpus changed.

      Read every new one and judge it before changing EXPECTED. A flag that
      cannot be defended sentence by sentence is the change being wrong, not
      the test.

      #{flags.map { |flag| "  [#{flag.code}] #{flag.headline}\n      #{flag.evidence[:claim]}" }.join("\n")}
    MESSAGE
  end

  test "every flag on the corpus is a possession claim about the player" do
    plant_lures
    scenes = replay

    flags_on(scenes).each do |flag|
      assert_equal :item_not_held, flag.code
      assert_match(/\byou(r|'re| are)?\b/i, flag.evidence[:claim], "the claim has to be about the player")
    end
  end

  # The number that says what the precision is worth: a scan built on "which
  # known names appear in this prose" would have raised a flag on every one of
  # these, and the report that measured the spike found all of its flags to be
  # false positives.
  test "far more narrations name a planted item than claim to hold one" do
    plant_lures

    naming = CORPUS.count { |row| LURES.fetch(row["world"]).any? { |name| row["narration"].match?(/\b#{Regexp.escape(name)}\b/i) } }

    assert_equal 15, naming
    assert_equal 8, EXPECTED.size
    assert_operator EXPECTED.size, :<, naming
  end

  # The denials are the false positives a vocabulary scanner produces, and they
  # are real sentences from this corpus. Named individually so a regression
  # points at the sentence rather than at a count.
  test "the narrations that deny the player has the thing are not flagged" do
    plant_lures
    scenes = replay
    flagged = flags_on(scenes).map { |flag| scenes.fetch(flag.scene.id) }
                              .map { |row| [ row["case"], row["model"], row["arm"] ] }

    [
      # "There is no revolver, no pistol, no weapon of any kind on your person
      #  -- you left that sort of thinking behind in the marshes."
      [ 1, "minimax/minimax-m3", "plain" ],
      # "You reach for the revolver at your hip, but your fingers find only the
      #  empty holster."
      [ 1, "mistralai/mistral-medium-3.1", "ruled" ],
      # "You have no gun."
      [ 2, "minimax/minimax-m3", "plain" ]
    ].each do |row|
      assert_not_includes flagged, row, "case #{row[0]} #{row[1]} #{row[2]} denies the claim and must not be flagged"
    end
  end

  # THE SWEEP READS WORLD DATA TOO, and here it catches the seeded world's own
  # opening arrival -- "The gap in your daybook is still under your hand" -- once
  # a planted record gives the daybook to somebody else. That is the check
  # working on prose nobody wrote for this test, and it is why the corpus
  # measurement above counts only the corpus scenes.
  test "the seeded opening arrivals are audited on the same terms" do
    plant_lures
    scenes = replay

    openings = Story::Audit.all.flat_map(&:flags).reject { |flag| scenes.key?(flag.scene.id) }

    assert(openings.all? { |flag| flag.scene.is_opening? },
           "a flag landed on neither a corpus scene nor an opening: #{openings.map(&:headline)}")
    assert_includes openings.map { |flag| flag.evidence[:item] }, "daybook"
  end

  # Pinned so the trade stays a decision rather than an accident. If a future
  # change catches this one, that is an improvement -- and this test is where it
  # gets noticed and re-judged.
  test "the one true positive given up to the negation guard is still given up" do
    plant_lures
    scenes = replay
    flagged = flags_on(scenes).map { |flag| scenes.fetch(flag.scene.id) }
                              .map { |row| [ row["case"], row["model"], row["arm"] ] }

    assert_not_includes flagged, SACRIFICED,
                        "this case is now caught -- read it, confirm it is right, and move it into EXPECTED"
  end

  test "the sweep stays offline and fast enough to run over everything ever written" do
    plant_lures
    replay

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    audits = Story::Audit.all
    audits.each(&:flags)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    per_scene = elapsed * 1000 / audits.sum(&:scanned)

    assert_operator per_scene, :<, 100, "the sweep is meant to be cheap enough to run over every scene ever written"
  end

  private

  # Each narration as the Scene it would have been: in the room it was written
  # about, following that world's opening arrival. Returns `{ scene_id => row }`.
  def replay
    scenes = {}

    CORPUS.each_with_index do |row, index|
      story = @stories.fetch(row["world"])
      room = story.locations.find_by!(name: row["room"])
      opening = story.opening_scene

      scene = Scene.create!(
        story: story, location: room, previous_scene: opening,
        description: row["narration"], typed: row["command"],
        summary: "corpus case #{row["case"]} #{row["model"]} #{row["arm"]}",
        story_timestamp: (opening&.story_timestamp || story.start_time) + ((index + 1) * 5).minutes
      )
      scenes[scene.id] = row
    end

    scenes
  end

  # Half in another character's hands, half lying in a room the player is not
  # in -- both are "not the player's", and the flag says which.
  def plant_lures
    @stories.each_value do |story|
      other = story.characters.where(is_protagonist: false).first
      elsewhere = story.locations.order(:id).last

      LURES.fetch(story.title).each_with_index do |name, index|
        if other && index.even?
          Item.create!(name: name, description: "Planted by the precision test.", character: other)
        else
          Item.create!(name: name, description: "Planted by the precision test.", location: elsewhere)
        end
      end
    end

    # Items are world data: in a real world they are written when the world is,
    # long before any scene. Backdating them keeps the `updated_at` guard in
    # `Story::Audit#check_items` out of the way of what is being measured.
    Item.update_all(updated_at: 1.year.ago)
  end

  # Flags on the replayed corpus narrations only. A seeded world carries its own
  # opening arrival, which is prose too and is audited on the same terms -- see
  # the test above -- but it is not part of the 24.
  def flags_on(scenes)
    Story::Audit.all.flat_map(&:flags).select { |flag| scenes.key?(flag.scene&.id) }
  end

  def key_for(row, item)
    [ row["case"], row["model"], row["arm"], item ]
  end
end
