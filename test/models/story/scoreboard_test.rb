require "test_helper"

# The scoreboard: rates, movement, and the agreement with the captain's own
# verdicts. Nothing here scores prose, and one test says so by construction.
class Story::ScoreboardTest < ActiveSupport::TestCase
  def setup
    @story = create(:story, start_time: Time.utc(2026, 3, 1, 21, 0))
    @protagonist = create(:character, story: @story, fullname: "Odile Vance", nickname: "Vance",
                                      is_protagonist: true)
    @here = create(:location, story: @story, name: "Ward Office 12")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
  end

  def scene_at(description, previous: nil, **attributes)
    create(:scene, story: @story, location: @here, previous_scene: previous, description: description,
                   story_timestamp: (previous&.story_timestamp || @story.start_time) + 5.minutes, **attributes)
  end

  def board = Story::Scoreboard.database(Story.where(id: @story.id))

  # --- rates ----------------------------------------------------------------

  test "every check is reported, whether or not it fired" do
    scene_at("The lamp gutters.")

    codes = board.readings.map(&:code)

    assert_equal Story::Scoreboard::CHECKS.keys, codes
    assert(board.readings.all? { |reading| reading.flagged.zero? })
  end

  test "a check that fired reports how many turns out of how many, and the rate" do
    first = scene_at("The lamp gutters.")
    scene_at("His pen laid across the page as though he is", previous: first)

    reading = board.reading(:truncated_prose)

    assert_equal 1, reading.flagged
    assert_equal 2, reading.scanned
    assert_in_delta 0.5, reading.rate
    assert_in_delta 50.0, reading.percentage
    assert reading.available
  end

  # The denominator is per check, because a check that compares two turns
  # cannot be run on the first one.
  test "a check that compares two turns is scored out of the turns that have one before them" do
    first = scene_at("The lamp gutters.")
    scene_at("Still gutters.", previous: first)

    assert_equal 2, board.reading(:truncated_prose).scanned
    assert_equal 1, board.reading(:unrecorded_departure).scanned
  end

  test "a check the corpus cannot answer is unavailable, not zero" do
    @protagonist.destroy!
    scene_at("The lamp gutters.")

    reading = board.reading(:third_person_protagonist)

    assert_not reading.available
    assert_equal 0, reading.scanned
  end

  test "the flags read worst class first" do
    landlord = create(:character, story: @story, fullname: "Halkett Rowe")
    first = scene_at("He is at the end desk.", characters: [ @protagonist, landlord ])
    previous = scene_at("The door clicks shut behind you, and he waits.", previous: first)
    (Story::Audit::STILL_RUN - 1).times { |i| previous = scene_at("You wait, turn #{i}.", previous: previous) }

    codes = board.flags_in_reading_order.map(&:code)

    assert_equal [ :unrecorded_departure, :still_run ], codes
  end

  # --- against his verdicts -------------------------------------------------

  test "a check that fires on a turn he called bad is reported against that verdict" do
    first = scene_at("The lamp gutters.")
    flagged = scene_at("The door clicks shut behind you, and he waits.", previous: first)
    create(:playthrough_feedback, playthrough: @playthrough, scene: flagged, verdict: "bad")

    result = board
    agreement = result.agreements.find { |a| a.code == :unrecorded_departure }

    assert_equal 1, result.labelled
    assert_equal 1, agreement.on_bad
    assert_equal 0, agreement.on_good
  end

  # THE SMALL-SAMPLE CAVEAT IS A PROPERTY OF THE OBJECT, not a sentence in the
  # printer: three verdicts is not a correlation and nothing here may say it is.
  test "the agreement is unestablished until there are enough verdicts to establish it" do
    scene = scene_at("The lamp gutters.")
    create(:playthrough_feedback, playthrough: @playthrough, scene: scene, verdict: "good")

    result = board

    assert_not result.agreement_established?
    assert_operator Story::Scoreboard::MIN_VERDICTS, :>, result.labelled
    assert(result.agreements.none?(&:established?))
  end

  # A check firing twice on one turn must not count that turn's verdict twice.
  test "agreement counts turns, not flags" do
    scene = scene_at("Vance's mouth tightens. Vance watches it, jaw tight.")
    create(:playthrough_feedback, playthrough: @playthrough, scene: scene, verdict: "bad")

    result = board

    assert_equal 2, result.reading(:third_person_protagonist).flagged
    assert_equal 1, result.agreements.find { |a| a.code == :third_person_protagonist }.on_bad
  end

  # THE MORE USEFUL HALF WHILE THE LABELS ARE FEW: a turn he disliked that
  # nothing caught is where the next check comes from.
  test "a turn he marked bad that no check caught is named" do
    scene = scene_at("An entirely ordinary sentence, correctly punctuated.")
    create(:playthrough_feedback, playthrough: @playthrough, scene: scene, verdict: "bad")

    assert_equal({ scene => "bad" }, board.missed_verdicts)
  end

  test "a turn he liked is not a miss, whatever the checks did" do
    scene = scene_at("An entirely ordinary sentence, correctly punctuated.")
    create(:playthrough_feedback, playthrough: @playthrough, scene: scene, verdict: "good")

    assert_empty board.missed_verdicts
  end

  # --- against last time ----------------------------------------------------

  test "with no baseline every check reads as new rather than as an improvement" do
    scene_at("The lamp gutters.")

    Story::Scoreboard::Baseline.stub(:read, nil) do
      assert(board.movements.all?(&:new_check?))
      assert(board.movements.none?(&:moved?))
    end
  end

  test "a rate that fell reads as better and one that rose reads as worse" do
    first = scene_at("The lamp gutters.")
    scene_at("His pen laid across the page as though he is", previous: first)

    was = { "checks" => { "truncated_prose" => { "rate" => 1.0, "flagged" => 2 } } }

    Story::Scoreboard::Baseline.stub(:read, was) do
      movement = board.movements.find { |m| m.code == :truncated_prose }

      assert movement.moved?
      assert movement.better?
      assert_in_delta(-0.5, movement.delta)
      assert_equal 2, movement.then_flagged
    end
  end

  test "an unchanged rate is reported as unchanged" do
    first = scene_at("The lamp gutters.")
    scene_at("His pen laid across the page as though he is", previous: first)

    Story::Scoreboard::Baseline.stub(:read, { "checks" => { "truncated_prose" => { "rate" => 0.5, "flagged" => 1 } } }) do
      assert_not board.movements.find { |m| m.code == :truncated_prose }.moved?
    end
  end

  # A rate compared across a corpus that changed underneath it reads as an
  # improvement nobody made, which is why the snapshot stores counts.
  test "a corpus that changed size since the baseline says so" do
    scene_at("The lamp gutters.")

    Story::Scoreboard::Baseline.stub(:read, { "scenes" => 54, "checks" => {} }) do
      assert_equal 54, board.baseline_scenes
    end

    Story::Scoreboard::Baseline.stub(:read, { "scenes" => 1, "checks" => {} }) do
      assert_nil board.baseline_scenes
    end
  end

  test "no baseline means no size warning" do
    scene_at("The lamp gutters.")

    Story::Scoreboard::Baseline.stub(:read, nil) do
      assert_nil board.baseline_scenes
    end
  end

  test "the snapshot carries counts as well as rates, so a grown corpus is visible" do
    scene_at("The lamp gutters.")

    snapshot = board.snapshot

    assert_equal "database", snapshot["corpus"]
    assert_equal 1, snapshot["scenes"]
    assert_equal 1, snapshot["stories"]
    assert_equal 0, snapshot["labelled_turns"]
    assert_equal Story::Scoreboard::CHECKS.keys.map(&:to_s), snapshot["checks"].keys
    assert_equal %w[flagged scanned rate available], snapshot["checks"]["truncated_prose"].keys
  end

  # --- what it is and is not ------------------------------------------------

  test "the two corpora are reported separately and never pooled" do
    scene_at("The lamp gutters.")

    boards = Story::Scoreboard.all

    assert_equal %w[database corpus], boards.map(&:name)
    assert(boards.all? { |b| b.note.present? })
  end

  test "scoring reads records and never a model" do
    scene_at("The lamp gutters.")

    BaseAgent.stub(:new, ->(*) { raise "the scoreboard must not call a model" }) do
      assert_predicate board.readings, :any?
      assert_predicate Story::Scoreboard.corpus.readings, :any?
    end
  end

  # It is meant to be run on a whim, over everything ever written.
  test "scoring both corpora is fast enough to run on a whim" do
    scene_at("The lamp gutters.")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    boards = Story::Scoreboard.all
    boards.each(&:readings)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :<, 10, "the scoreboard has to be cheap enough that nobody thinks before running it"
  end

  test "the headline says what was scanned and what was found" do
    first = scene_at("The lamp gutters.")
    scene_at("His pen laid across the page as though he is", previous: first)

    assert_equal "2 turns: 1 truncated_prose", board.headline
  end

  test "a corpus with nothing flagged says so" do
    scene_at("The lamp gutters.")

    assert_equal "1 turn: nothing flagged", board.headline
  end
end
