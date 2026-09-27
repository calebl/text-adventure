# `WorldMechanic`'s boundary arithmetic: when a scheduled change is due.
module EngineVectors::Boundaries
  SOURCES = [ "app/models/world_mechanic.rb" ].freeze
  NOTES = "Each case is a cadence, the story's start time, the mechanic's last run (null if never) and " \
          "now, in epoch seconds. next_boundary_after is next_boundary_after(last_run or start); " \
          "pending is pending_boundaries(now).".freeze

  START = 1_767_225_600 # 2026-01-01 00:00 UTC

  def self.constants_table = { "cadences" => EngineVectors.pairs(WorldMechanic::CADENCES.transform_values { |value| value.transform_keys(&:to_s) }) }

  def self.cases
    starts = [ START, START + 1, START + 59 * 60 + 59, 0, 86_399 ]
    last_runs = [ nil, :start, 3_600, 86_400 * 3 + 1 ]
    gaps = [ -60, 0, 1, 3_599, 3_600, 3_601, 7_200 * 5 + 17, 86_400, 86_400 * 2 + 123, 86_400 * 15 ]
    WorldMechanic::CADENCES.keys.product(starts, last_runs, gaps).map do |cadence, start, last_run, gap|
      last = last_run == :start ? start : last_run && start + last_run
      now = (last || start) + gap
      one(cadence, start, last, now)
    end
  end

  def self.one(cadence, start, last, now)
    mechanic = WorldMechanic.new(cadence: cadence, last_run_at: last && Time.at(last).utc,
                                 story: Story.new(start_time: Time.at(start).utc))
    EngineVectors.case_for("#{cadence} #{start} #{last.inspect} #{now}",
                           { "cadence" => cadence, "start_time" => start, "last_run_at" => last, "now" => now },
                           { "next_boundary_after" => mechanic.next_boundary_after(Time.at(last || start).utc).to_i,
                             "pending" => mechanic.pending_boundaries(Time.at(now).utc).map(&:to_i) })
  end
end
