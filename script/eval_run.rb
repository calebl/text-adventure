# ONE RUN: one world, one script, played straight through the app's own loop.
#
# PORTED FROM `data/ta-conversation-read-2/lab/run.rb` (firstmate repo), which
# is the harness the four-arm whole-run sweep of 2026-09-02 used, and kept
# deliberately close to it rather than rewritten -- the numbers in
# `Eval::Cost::PER_TURN` and every noise figure quoted in `Eval::Noise` come out
# of that harness, and a rewrite would have quietly invalidated them. What is
# new here is that the RUN DATABASE IS KEPT. The lab wrote a JSON transcript and
# threw the rows away, which is exactly why `unreachable_transition`,
# `item_not_held` and `reached_for_nothing` could not be run on it: you cannot
# check prose against records you did not keep.
#
# Every turn goes through `Playthrough::Turn#play` as `NarrationJob` calls it --
# classifier, then generator / narrator / InteractionAgent as the input dictates
# -- against a per-run copy of `tmp/eval/base.sqlite3`.
#
# TWO THINGS THIS CHANGES, and neither is in the app:
#
#   1. `OPENROUTER_MODEL` puts one model FIRST in the rotation. That is
#      `BaseAgent.remote_model_options`' own documented seam and it is how the
#      captain's `.envrc` pins a model today, so rotation stays available and is
#      recorded rather than switched off. Pinning is a noise control: a turn
#      answered by a different model is a different measurement.
#   2. `LOCAL_MODEL_OPTIONS` is emptied. This is belt and braces since the local
#      rotation became opt-in (`TA_LOCAL_MODELS`), and it stays because a sweep
#      run on a machine that HAS set that variable would otherwise let a third
#      attempt be answered by a 4k-context CPU model and land its prose in the
#      corpus.
#
# Nothing else is patched, and in particular NOTHING TOUCHES TEMPERATURE. The
# sweep has to measure the game the player gets; a run at a temperature the app
# never uses is a measurement of a different app.
require "json"
require "stringio"
require "fileutils"

STORY_TITLE = ENV.fetch("EVAL_STORY")
REP         = ENV.fetch("EVAL_REP", "1").to_i
OUT         = ENV.fetch("EVAL_OUT")
TURN_LIMIT  = ENV["EVAL_TURNS"].presence&.to_i

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3", database: ENV.fetch("EVAL_DB"), timeout: 15_000, pool: 5
)

BaseAgent.send(:remove_const, :LOCAL_MODEL_OPTIONS)
BaseAgent.const_set(:LOCAL_MODEL_OPTIONS, [].freeze)

# ------------------------------------------------------------------ the probe
#
# Records and changes nothing. `BaseAgent` logs "<model> failed (<class>:
# <message>), rotating model" from inside its own attempt loop, which is the
# only place a per-attempt failure exists -- `#ask` re-raises only the last one
# -- so the logger is tapped rather than the loop reached into.
module Probe
  CALLS = []
  ROTATIONS = []
  INTENTS = []
  SINK = StringIO.new

  class << self
    attr_accessor :sink_mark
  end

  def self.reset_turn!
    CALLS.clear
    ROTATIONS.clear
    INTENTS.clear
    self.sink_mark = SINK.string.length
  end

  def self.turn_warnings
    SINK.string[sink_mark..].to_s.lines.map(&:strip).reject(&:empty?)
        .grep(/rotating model|\[refusal\]|\[crisis\]/)
        .map { |line| line.sub(/\A.*?WARN\s+--\s*:?\s*/, "") }
  end
end

sink_logger = Logger.new(Probe::SINK)
sink_logger.level = Logger::WARN
sink_logger.formatter = proc { |severity, _time, _progname, message| "#{severity} -- : #{message}\n" }
Rails.logger.broadcast_to(sink_logger)

module AskProbe
  def ask(prompt, verify: nil, &block)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = super
    Probe::CALLS << { purpose: purpose, answered_by: current_model[:model], ok: true,
                      seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3) }
    response
  rescue => error
    Probe::CALLS << { purpose: purpose, answered_by: current_model[:model], ok: false,
                      error: "#{error.class}: #{error.message}",
                      seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3) }
    raise
  end

  def rotate_model
    from = current_model[:model]
    super
    Probe::ROTATIONS << { purpose: purpose, from: from, to: current_model[:model] }
  end
end
BaseAgent.prepend(AskProbe)

# WHAT THE CLASSIFIER DECIDED, recorded rather than inferred. The branch a turn
# took is visible from its records; the intent it was given is not, and a `move`
# that resolved to nothing looks identical to an `examine` from the outside.
module IntentProbe
  def classify(command)
    intent = super
    Probe::INTENTS << {
      action: intent.action.to_s,
      subject: intent.subject.respond_to?(:name) ? intent.subject.name : intent.subject&.fullname,
      reached_for_nothing: intent.reached_for_nothing?
    }
    intent
  end
end
Playthrough::Classifier.prepend(IntentProbe)

# ------------------------------------------------------------------ the world
script = Eval::Script.for(STORY_TITLE)
script = script.first(TURN_LIMIT) if TURN_LIMIT

story = Story.find_by!(title: STORY_TITLE)
opening = story.opening_scene
abort "#{story.title} has no opening scene, so a run of it would start on a room description" if opening.nil?

playthrough = Playthrough.create!(
  story: story, character: story.protagonist,
  current_location: opening.location, current_scene: opening
)
opening.location.mark_protagonist_visit!(story.clock)

record = {
  story: story.title, held_out: Eval.held_out?(story.title),
  rep: REP, script_turns: script.size,
  pinned_model: ENV["OPENROUTER_MODEL"],
  rotation_pool: BaseAgent.default_model_options.map { |option| option[:model] },
  started_at: Time.now.utc.iso8601,
  playthrough_id: playthrough.id,
  opening_scene_id: opening.id,
  turns: []
}

script.turns.each_with_index do |spec, index|
  Probe.reset_turn!
  scene = nil
  failure = nil
  before = playthrough.current_location&.name
  drifts_before = playthrough.drifts.count
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  begin
    scene = Playthrough::Turn.new(playthrough).play(spec.command)
  rescue BaseAgent::CrisisResponseError => error
    failure = { kind: "crisis", shown: Playthrough::SafetyNotice::HEADING, error: "#{error.class}: #{error.message}" }
  rescue => error
    failure = { kind: "turn_failed", shown: Playthrough::TurnFailureNotice::MESSAGE, error: "#{error.class}: #{error.message}" }
  end

  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  playthrough.reload
  intent = Probe::INTENTS.last
  acted = intent && %w[move talk take drop].include?(intent[:action]) && !intent[:reached_for_nothing]

  record[:turns] << {
    index: index + 1, id: spec.id, command: spec.command, expect: spec.expect, beat: spec.beat,
    branch: failure ? "failed" : (acted ? intent[:action] : "narrate"),
    scene_id: scene&.id,
    prose_chars: scene&.description&.length,
    location_before: before,
    location_after: playthrough.current_location&.name,
    seconds: elapsed.round(3),
    failure: failure,
    drifts: playthrough.drifts.order(:id).offset(drifts_before).map { |drift| { action: drift.action, command: drift.command } },
    intents: Probe::INTENTS.map(&:dup),
    warnings: Probe.turn_warnings,
    calls: Probe::CALLS.map(&:dup),
    rotations: Probe::ROTATIONS.map(&:dup)
  }

  warn format("  [%s r%d] %-16s %-8s %6.2fs  %s",
              WorldSeed.slug(story.title), REP, spec.id, record[:turns].last[:branch], elapsed,
              failure ? "FAILED #{failure[:error][0, 90]}" : "#{record[:turns].last[:prose_chars]} chars")
end

# ------------------------------------------------------- tokens, so the spend
# can be reported rather than estimated twice.
record[:usage] = Message.joins(:chat).where(chats: { playthrough_id: playthrough.id })
  .where(role: "assistant")
  .joins("LEFT JOIN models ON models.id = messages.model_id")
  .pluck(Arel.sql("COALESCE(messages.model_id_string, models.model_id, 'unknown')"), :input_tokens, :output_tokens)
  .group_by(&:first)
  .map do |model, rows|
    { model: model, calls: rows.length,
      input_tokens: rows.sum { |row| row[1].to_i }, output_tokens: rows.sum { |row| row[2].to_i } }
  end
record[:finished_at] = Time.now.utc.iso8601

FileUtils.mkdir_p(File.dirname(OUT))
File.write(OUT, JSON.pretty_generate(record))
warn "  [#{WorldSeed.slug(story.title)} r#{REP}] wrote #{OUT}"
