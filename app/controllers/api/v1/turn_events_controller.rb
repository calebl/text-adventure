# `GET /api/v1/games/:game_id/turns/:turn_id/events`: one turn, as
# Server-Sent Events, tailed from the rows `NarrationJob::Events` writes.
#
# Each event's SSE `id` is its sequence within the turn. A client that loses
# the connection reconnects with `Last-Event-ID` (or `?last_event_id=`) and is
# sent only what came after; a finished turn replays whole and closes. The
# turn is found through the player's own game, so a turn id from another
# player's game answers 404 before any row is read -- resuming cannot reach
# anyone else's events.
#
# A stream holds a Puma thread while it waits, so it gives up after
# `IDLE_TIMEOUT` with nothing new and the client reconnects; nothing is lost,
# because the rows are the record and the stream only reads them.
class Api::V1::TurnEventsController < Api::V1::BaseController
  include ActionController::Live

  POLL_INTERVAL = 0.2
  IDLE_TIMEOUT = 30.seconds

  def index
    command = game.commands.find(params[:turn_id].to_s)
    last = (request.headers["Last-Event-ID"].presence || params[:last_event_id]).to_i

    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    stream(command, last)
  ensure
    response.stream.close
  end

  private

  def stream(command, last)
    idle_since = Time.current
    loop do
      events = command.turn_events.after(last).to_a
      events.each do |event|
        response.stream.write("id: #{event.sequence}\nevent: #{event.kind}\ndata: #{event.data.to_json}\n\n")
        last = event.sequence
        return if event.finished?
      end
      idle_since = Time.current if events.any?
      return if Time.current - idle_since > IDLE_TIMEOUT

      sleep POLL_INTERVAL
    end
  rescue ActionController::Live::ClientDisconnected, IOError
    nil
  end
end
