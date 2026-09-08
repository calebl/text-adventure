require "test_helper"

# THE TWO BLOCKS `ta-quest-outcomes` ADDED TO THE FILE FORMAT, THERE AND BACK.
#
#   an outcome's `when:` / `minutes:` / `ramification:` -- which of several
#   endings a game reaches, and what the world does about it afterwards
#   the story's `schedule:` -- a thing this world has already decided will
#   happen, which is the captain's Call 8 of 2026-09-06
#
# ROUND-TRIPPED AGAINST THE CHECKED-IN WORLDS rather than against a synthetic
# document, because those are the files that would break: the Iron Gate carries
# the only conditional ending in the repository and the Lunar Cartographer the
# only schedule, and an exporter that quietly dropped either would leave a
# re-exported world with an ending nobody can reach and a clock that owes
# nothing.
class WorldSeed::ArcRoundTripTest < ActiveSupport::TestCase
  # --- an ending's rule ------------------------------------------------------

  test "the Iron Gate's second ending loads with its rule and its ramification" do
    outcome = iron_gate.main_quest.outcomes.find_by(name: "too-late")

    assert_equal "out_of_order", outcome.condition
    assert_nil outcome.minutes, "out_of_order takes no number"
    assert_equal 180, outcome.ramification_minutes
    assert outcome.ramification_summary.present?
    assert_predicate outcome, :schedules_a_ramification?
  end

  test "the default ending carries no rule, and exports none" do
    story = iron_gate
    written = WorldSeed::Exporter.new(story).document
    outcomes = written.fetch("quests").sole.fetch("outcomes")
    default = outcomes.detect { |row| row["default"] }

    assert_not default.key?("when")
    assert_not default.key?("minutes")
    assert_not default.key?("ramification")
  end

  test "an exported arc reloads with the same rule and the same ramification" do
    reloaded = reload_through_the_exporter(iron_gate, "The Iron Gate Descends (round trip)")
    outcome = reloaded.main_quest.outcomes.find_by(name: "too-late")

    assert_equal "out_of_order", outcome.condition
    assert_equal 180, outcome.ramification_minutes
    assert_equal iron_gate.main_quest.outcomes.find_by(name: "too-late").ramification_summary,
                 outcome.ramification_summary
  end

  # --- the schedule ----------------------------------------------------------

  test "the Lunar Cartographer's schedule loads as pending rows on the one stream" do
    story = lunar_cartographer
    rows = story.world_events.from_a_world_file.order(:scheduled_for)

    assert_equal 2, rows.size
    assert rows.all?(&:pending?), "a seeded event is a schedule, never a log entry"
    assert_equal [ story.start_time + 5.minutes, story.start_time + 8.hours ], rows.map(&:scheduled_for)
    assert_equal [ story.start_time, story.start_time ], rows.map(&:occurred_at)
  end

  test "re-loading the same file does not schedule the same thing twice" do
    lunar_cartographer

    assert_no_difference "WorldEvent.count" do
      lunar_cartographer(reload: true)
    end
  end

  test "an exported schedule reloads at the same hours" do
    story = lunar_cartographer
    hours = story.world_events.from_a_world_file.order(:scheduled_for).map { |row| row.scheduled_for - story.start_time }

    reloaded = reload_through_the_exporter(story, "The Lunar Cartographer (round trip)")

    assert_equal hours,
                 reloaded.world_events.from_a_world_file.order(:scheduled_for)
                         .map { |row| row.scheduled_for - reloaded.start_time }
  end

  # A ROW THAT HAS FIRED IS HISTORY AND THE FILE IS NOT ITS AUTHOR ANY MORE:
  # the exporter leaves it behind, and a re-seed leaves it alone rather than
  # putting it back in the queue.
  test "a fired row is neither exported nor reset by a re-seed" do
    story = lunar_cartographer
    fired = story.world_events.from_a_world_file.order(:scheduled_for).first
    fired.fire!(at: story.start_time + 10.minutes)

    written = WorldSeed::Exporter.new(story).document

    assert_equal 1, written.fetch("schedule").size
    assert_not_includes written.fetch("schedule").map { |row| row["summary"] }, fired.summary

    lunar_cartographer(reload: true)

    assert_equal story.start_time + 10.minutes, fired.reload.fired_at
  end

  # AN UNFIRED ROW THE FILE HAS STOPPED DECLARING IS A CATASTROPHE THE AUTHOR
  # TOOK OUT -- `#load_quests!`' rule, applied to the stream.
  test "a schedule the file no longer declares is withdrawn" do
    story = lunar_cartographer
    document = lunar_document
    document["schedule"] = [ document["schedule"].last ]

    WorldSeed::Loader.new(document).load!

    assert_equal 1, story.world_events.from_a_world_file.count
  end

  # --- what the file will not load ------------------------------------------

  test "a misspelt rule is refused rather than loaded as an ending nobody reaches" do
    document = iron_gate_document
    document["quests"].first["outcomes"].last["when"] = "if_the_player_was_brave"

    error = assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(document).load! }
    assert_match(/if_the_player_was_brave/, error.message)
    assert_match(/out_of_order/, error.message)
  end

  test "the default may not also name a rule" do
    document = iron_gate_document
    document["quests"].first["outcomes"].first["when"] = "out_of_order"

    assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(document).load! }
  end

  test "a rule that takes a number is refused without one, and one that does not is refused with one" do
    without = iron_gate_document
    without["quests"].first["outcomes"].last["when"] = "slower_than"

    assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(without).load! }

    extra = iron_gate_document
    extra["quests"].first["outcomes"].last["minutes"] = 90

    assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(extra).load! }
  end

  test "half a ramification is refused" do
    document = iron_gate_document
    document["quests"].first["outcomes"].last["ramification"] = { "summary" => "The low door is barred." }

    assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(document).load! }
  end

  test "a scheduled event needs an hour and a sentence, and two of a sentence are one row" do
    no_hour = lunar_document
    no_hour["schedule"] = [ { "summary" => "The bell cracks." } ]

    assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(no_hour).load! }

    twice = lunar_document
    twice["schedule"] = [ { "summary" => "The bell cracks.", "after_minutes" => 5 },
                          { "summary" => "The bell cracks.", "after_minutes" => 9 } ]

    assert_raises(WorldSeed::Loader::InvalidWorld) { WorldSeed::Loader.new(twice).load! }
  end

  private

  def iron_gate_document = WorldSeed.parse(File.read(Rails.root.join("lib/engine_sweep/worlds/the-iron-gate-descends.yml")))

  def lunar_document = WorldSeed.parse(File.read(Rails.root.join("db/seeds/worlds/the-lunar-cartographer.yml")))

  def iron_gate = @iron_gate ||= WorldSeed::Loader.new(iron_gate_document).load!

  def lunar_cartographer(reload: false)
    return WorldSeed::Loader.new(lunar_document).load! if reload

    @lunar_cartographer ||= WorldSeed::Loader.new(lunar_document).load!
  end

  # Export the story and load what came out under a title of its own, which is
  # the only honest way to ask whether the file carried the block.
  def reload_through_the_exporter(story, title)
    written = WorldSeed::Exporter.new(story).document
    written["story"]["title"] = title

    WorldSeed::Loader.new(WorldSeed.parse(WorldSeed.dump(written))).load!
  end
end
