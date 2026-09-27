# ONE TURN, PLAYED BY THE RUST ENGINE, with `Playthrough::Turn#play`'s contract:
# the same arguments, the same callbacks at the same moments, the same return.
# `Playthrough::Session#play` is the only caller; see `Playthrough::RustEngine`
# for when it is asked at all.
#
# UNDER THE SAME LOCK. The engine plays on its own connection and knows nothing
# of `GameLock`, so the lock the Ruby engine takes is taken here, around the
# whole call: two workers delivering lines of one game still play them one at a
# time, in the order they were accepted, whichever engine each is on.
#
# THE CALLBACKS. `on_start` is told the line as the engine is handed it, and
# `on_finish` the outcome once it is back -- once for the line this job
# delivered. The Ruby engine also tells them about each earlier line it drains
# from the queue on the way; the engine drains those too, but tells nobody,
# and the page the finish draws is read from the records either way. A
# redelivery of a completed line finishes without starting, and a line the game
# has since moved past says nothing at all, as in the Ruby engine.
#
# HANDING A TURN BACK. An engine error leaves the submission as a worker that
# stopped at that point leaves it: its journal holds every step the engine
# committed, in the Ruby engine's own encoding. `#hand_back!` puts the row where
# the Ruby engine expects to find a stopped worker's -- `running`, or `pending`
# when nothing was committed -- and answers `HANDED_BACK`, and the session plays
# the line on Ruby, which finishes it from that journal. One step is not written
# the way Ruby writes it: the engine stops with `unsupported` on the turn an
# arc concludes, having journaled the `arc` step with no value, where Ruby
# journals the conclusion it is about to narrate. `#concluded` writes that
# conclusion back from the ending the engine recorded, so the Ruby engine tells
# the ending instead of skipping it.
class Playthrough::RustEngine::Turn
  HANDED_BACK = Object.new.freeze

  attr_reader :playthrough, :safety_notice

  def initialize(playthrough)
    @playthrough = playthrough
  end

  def play(line, request_token: nil, on_start: nil, on_finish: nil, on_error: nil, &block)
    reason = Playthrough::RustEngine.unplayable(request_token)
    return handed_back(reason, Playthrough::RustEngine.load_error) if reason

    deliver = observer("streaming", block)
    began = observer("start notice", on_start)
    finished = observer("finish notice", on_finish)
    failed = observer("failure notice", on_error)
    GameLock.synchronize("playthrough", playthrough.id) do
      playthrough.reload
      mine = playthrough.commands.find_by(request_token: request_token, command: line)
      return mine.outcome if mine&.overtaken?

      before = queue
      began.call(line) unless mine&.completed?
      answer = Playthrough::RustEngine.submit(playthrough, line, request_token) { |chunk| deliver.call(chunk) }
      playthrough.reload
      if (error = answer["error"])
        if Playthrough::RustEngine::HANDED_BACK.include?(error.fetch("kind"))
          hand_back!(before)
          return handed_back(error.fetch("kind"), error.fetch("message"))
        end
        raise Playthrough::RustEngine.exception_for(error)
      end

      outcome = playthrough.commands.find_by!(request_token: request_token, command: line).outcome
      @safety_notice = answer.dig("turned", "safety_notice") ? true : (outcome.safety_notice if outcome.is_a?(Scene))
      finished.call(outcome)
      outcome
    rescue StandardError => e
      failed.call(e)
      raise
    end
  end

  private

  # A consumer receives progress and does not own the turn, as in
  # `Playthrough::Turn#observer`.
  def observer(what, consumer)
    lambda do |value|
      consumer&.call(value)
    rescue StandardError => e
      Rails.logger.warn { "Turn #{what} failed: #{e.class}: #{e.message}" }
    end
  end

  def handed_back(reason, detail)
    Playthrough::RustEngine.fell_back!(reason, detail)
    HANDED_BACK
  end

  # The game's submissions and endings before the engine is handed the line.
  def queue
    { statuses: playthrough.commands.pluck(:id, :status).to_h, ending: playthrough.endings.maximum(:id) }
  end

  def hand_back!(before)
    playthrough.commands.where(status: "failed", error_kind: "error").find_each do |row|
      next if before[:statuses][row.id] == "failed"

      steps = row.journal.fetch("steps", {})
      attributes = { status: steps.empty? ? "pending" : "running", error_kind: nil }
      if steps.key?("arc") && steps["arc"].nil? && (conclusion = concluded(before[:ending]))
        attributes[:journal] = row.journal.merge("steps" => steps.merge("arc" => conclusion))
      end
      row.update!(attributes)
    end
  end

  # The ending the engine recorded on this line, as `Playthrough::Arc#conclude!`
  # hands it to the narrator, in the journal's encoding -- or nil if there is
  # none.
  def concluded(previous)
    ending = playthrough.endings.where("id > ?", previous.to_i).order(:id).last
    return nil if ending.nil?

    value = Playthrough::Arc::Concluded.new(ending: ending, outcome: ending.quest_outcome, scene: playthrough.current_scene)
    Playthrough::Command::Journal.encode(value)
  end
end
