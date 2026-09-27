# ONE TURN, PLAYED BY THE RUST ENGINE, with `Playthrough::Turn#play`'s contract:
# the same arguments, the same callbacks at the same moments, the same return.
# `Playthrough::Session#play` is the only caller; see `Playthrough::RustEngine`.
#
# UNDER THE SAME LOCK. The engine plays on its own connection and knows nothing
# of `GameLock`, so the lock is taken here, around the whole call: two workers
# delivering lines of one game still play them one at a time, in the order they
# were accepted.
#
# THE CALLBACKS. `on_start` is told the line as the engine is handed it, and
# `on_finish` the outcome once it is back -- once, for the line this job
# delivered. The engine also drains the earlier lines still owed a finish, and
# tells nobody about them; the page the finish draws is read from the records
# either way. A redelivery of a completed line finishes without starting, and a
# line the game has since moved past says nothing at all.
#
# A TURN THE ENGINE COULD NOT PLAY raises `Playthrough::RustEngine::EngineError`
# through `on_error`, exactly as a failed Ruby turn raises: the session tells
# the player in the engine's words, the error is logged and counted, and the
# submission is left `failed`. Nothing plays it again on Ruby.
class Playthrough::RustEngine::Turn
  attr_reader :playthrough, :safety_notice

  def initialize(playthrough)
    @playthrough = playthrough
  end

  def play(line, request_token:, on_start: nil, on_finish: nil, on_error: nil, &block)
    deliver = observer("streaming", block)
    began = observer("start notice", on_start)
    finished = observer("finish notice", on_finish)
    failed = observer("failure notice", on_error)
    begin
      unplayable = Playthrough::RustEngine.unplayable
      raise unplayable if unplayable

      GameLock.synchronize("playthrough", playthrough.id) { take_turn(line, request_token, began, finished, deliver) }
    rescue StandardError => e
      if e.is_a?(Playthrough::RustEngine::EngineError)
        Playthrough::RustEngine.failed!(e)
        fail_submission!(line, request_token)
      end
      failed.call(e)
      raise
    end
  end

  private

  def take_turn(line, request_token, began, finished, deliver)
    playthrough.reload
    mine = playthrough.commands.find_by(request_token: request_token, command: line)
    return mine.outcome if mine&.overtaken?

    began.call(line) unless mine&.completed?
    answer = Playthrough::RustEngine.submit(playthrough, line, request_token) { |chunk| deliver.call(chunk) }
    playthrough.reload
    raise Playthrough::RustEngine.exception_for(answer["error"]) if answer["error"]

    outcome = playthrough.commands.find_by!(request_token: request_token, command: line).outcome
    @safety_notice = answer.dig("turned", "safety_notice") ? true : (outcome.safety_notice if outcome.is_a?(Scene))
    finished.call(outcome)
    outcome
  end

  # A consumer receives progress and does not own the turn, as in
  # `Playthrough::Turn#observer`.
  def observer(what, consumer)
    lambda do |value|
      consumer&.call(value)
    rescue StandardError => e
      Rails.logger.warn { "Turn #{what} failed: #{e.class}: #{e.message}" }
    end
  end

  # The engine marks a submission it failed; one it never reached (the
  # extension missing, the database refused at open) is marked here, as
  # `Playthrough::Command#execute!` marks a Ruby turn that raised.
  def fail_submission!(line, request_token)
    playthrough.commands.where(request_token: request_token, command: line, status: %w[pending running])
               .update_all(status: "failed", error_kind: "error", updated_at: Time.current)
  end
end
