# ONE TURN OF `rake eval:run`, played the way the player's turn is played.
#
# `script/eval_run.rb` hands every scripted line to `Playthrough::Session#play`
# -- the one way into the turn loop for every front end -- so the run is played
# by the Rust engine through its native extension, exactly as the browser's
# turn is. It never constructs a `Playthrough::Turn`: that is the Ruby parity
# reference, and a run measured on it would be a measurement of an engine no
# player is given.
#
# It lives here rather than in the script because the script is never loaded
# by the suite (it spends money), and this half of it has to be tested.
#
# WHAT THE TURN RESOLVED TO is read from the records the engine wrote, not from
# a probe on `Playthrough::Classifier`: the engine makes its own classifier call
# in Rust, so no Ruby method sees the intent. The scene's `resolved_action` and
# `acted_on` are the same intent, kept on the row. An action with no record to
# act on is what a probe used to call `reached_for_nothing`.
module Eval::RunTurn
  # The kinds of action a turn can take on a record. A turn that resolved to
  # one of these with nothing to act on reached for nothing.
  ACTS_ON_A_RECORD = %w[move talk take drop].freeze

  Result = Data.define(:scene, :failure, :intent)

  def self.play(playthrough, command)
    outcome = Playthrough::Session.new(playthrough).play(command)
    scene = outcome if outcome.is_a?(Scene)
    Result.new(scene: scene, failure: nil, intent: intent_of(scene))
  rescue BaseAgent::CrisisResponseError => error
    Result.new(scene: nil, failure: failure("crisis", Playthrough::SafetyNotice::HEADING, error), intent: nil)
  rescue => error
    shown = Playthrough::Session.ending_for(error, playthrough_id: playthrough.id)&.error || Playthrough::TurnFailureNotice::MESSAGE
    Result.new(scene: nil, failure: failure("turn_failed", shown, error), intent: nil)
  end

  # The intent as the run's manifest has always written it, or nil for a turn
  # with no action on record.
  def self.intent_of(scene)
    action = scene&.recorded_action
    return nil if action.blank?

    { action: action, subject: scene.acted_on_label,
      reached_for_nothing: ACTS_ON_A_RECORD.include?(action) && scene.acted_on_record.nil? }
  end

  def self.failure(kind, shown, error) = { kind: kind, shown: shown, error: "#{error.class}: #{error.message}" }
end
