require "test_helper"

# `Playthrough::Session` is the one way a front end reaches the turn loop. The
# browser's own tests (the playthroughs and turns controllers, `NarrationJob`
# and the engine sweep's browser turns) are what prove the browser plays
# through it unchanged; these pin the session's own answers, and the guard.
class Playthrough::SessionTest < ActiveSupport::TestCase
  # ONE LOOP, ONE WAY IN. A front end that builds its own `Playthrough::Turn`
  # has taken a share of the loop the session exists to own -- the outcome's
  # wording, the start of a game, the order lines are accepted in -- and the
  # engine can then disagree with itself. So the places front ends live are
  # read for the call, and a new one there fails here with its file named.
  #
  # `lib/eval/` stages are measuring instruments, not front ends: each plants
  # a fixture inside a turn (a fixed classifier, a scripted blow) to hold the
  # rest of the loop still while one prompt is measured, which is exactly what
  # a front end must not do. They are named one by one, so a new file there
  # is still read.
  FRONT_ENDS = %w[app/controllers app/jobs bin lib].freeze
  INSTRUMENTS = %w[
    lib/eval/dialogue/stage.rb
    lib/eval/prompt/bench.rb
    lib/eval/prompt/branches/stage.rb
  ].freeze

  test "no front end constructs a turn of its own" do
    offenders = FRONT_ENDS.flat_map { |dir| Dir[Rails.root.join(dir, "**", "*")] }
                          .select { |path| File.file?(path) }
                          .map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
                          .reject { |path| INSTRUMENTS.include?(path) }
                          .select { |path| File.read(path).match?(/\bPlaythrough::Turn\.new\b/) }

    assert_empty offenders, "a front end reaches the loop through Playthrough::Session, never Playthrough::Turn.new"
  end

  test "the named instruments still build a turn, so the exemption is not stale" do
    INSTRUMENTS.each do |path|
      assert_match(/\bPlaythrough::Turn\.new\b/, Rails.root.join(path).read, "#{path} no longer needs its exemption")
    end
  end

  test "begin! starts the protagonist in the first realized room and stamps the arrival on the story clock" do
    story = create(:story)
    protagonist = create(:character, story: story, is_protagonist: true)
    create(:location, :stub, story: story)
    opening = create(:location, story: story, last_protagonist_visit: nil)

    start = Playthrough::Session.begin!(story)

    assert start.started?
    assert_nil start.refusal
    assert_equal protagonist, start.playthrough.character
    assert_equal opening, start.playthrough.current_location
    assert_equal story.start_time, opening.reload.last_protagonist_visit
  end

  test "begin! refuses a story with nobody to play, and writes nothing" do
    story = create(:story)
    create(:location, story: story)

    start = assert_no_difference(-> { Playthrough.count }) { Playthrough::Session.begin!(story) }

    assert_not start.started?
    assert_match "no player character yet", start.refusal
  end

  test "begin! refuses a story with no realized room to start in" do
    story = create(:story)
    create(:character, story: story, is_protagonist: true)
    create(:location, :stub, story: story)

    start = Playthrough::Session.begin!(story)

    assert_not start.started?
    assert_match "no realized opening location", start.refusal
  end

  test "a blank line is not a turn and writes no command" do
    playthrough = create(:playthrough, :started)

    assert_no_difference -> { playthrough.commands.count } do
      assert_nil Playthrough::Session.new(playthrough).accept!("   ", "token")
    end
  end

  test "a typed line is accepted stripped, under its token" do
    playthrough = create(:playthrough, :started)

    submission = Playthrough::Session.new(playthrough).accept!("  look  ", "form-1")

    assert_equal "look", submission.command
    assert_equal "form-1", submission.request_token
  end

  test "each way a turn can raise is told in the app's own words" do
    crisis = Playthrough::Session.ending_for(BaseAgent::CrisisResponseError.new("x"))
    assert crisis.safety_notice
    assert_nil crisis.error

    unconfigured = Playthrough::Session.ending_for(BaseAgent::NoModelConfiguredError.new("x"))
    assert_equal Playthrough::SetupNotice::UNFINISHED, unconfigured.error

    assert_equal Playthrough::TurnFailureNotice::MESSAGE, Playthrough::Session.ending_for(RuntimeError.new("x")).error
    assert_nil Playthrough::Session.ending_for(ActiveRecord::RecordNotFound.new("x"), playthrough_id: 1)
  end
end
