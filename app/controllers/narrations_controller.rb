class NarrationsController < ApplicationController
  include ActionController::Live

  # Streams one turn as server-sent events. The turn itself -- classifying what
  # the player typed, moving them, narrating what they find -- belongs to
  # `Playthrough::Turn`; this controller's entire job is to forward the chunks
  # it yields. Turbo Streams over Action Cable is a later stage, and the block
  # is the seam that makes that swap touch nothing but the consumer.
  #
  # A move is slower than a narrated turn and does not stream: realizing a room
  # is two schema'd calls, and the arrival is a third, so the player watches
  # the cursor for as long as that takes and then gets the paragraph at once.
  # The job-and-cable stage is what fixes the waiting, not this file.
  def show
    playthrough = Playthrough.find(params[:playthrough_id])
    command = params[:command].to_s.strip

    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    # Defensive: Thruster passes SSE through untouched, but a proxy in front of
    # it might not.
    response.headers["X-Accel-Buffering"] = "no"

    sse = SSE.new(response.stream, retry: 300)

    # Written before the model is touched, so the browser can show a cursor
    # during the four to six seconds of prompt processing that follow.
    sse.write({ ok: true }, event: "open")

    Playthrough::Turn.new(playthrough).play(command) do |chunk|
      sse.write({ t: chunk }, event: "token")
    end

    sse.write({ ok: true }, event: "done")
  rescue ActionController::Live::ClientDisconnected
    # The player closed the tab or reloaded. Scene::Narrator has already
    # persisted whatever it had, and a move persists before it yields, so there
    # is nothing to do but stop.
    Rails.logger.info { "Narration client disconnected" }
  rescue => e
    Rails.logger.error { "Narration failed: #{e.class}: #{e.message}" }
    sse&.write({ message: e.message }, event: "error")
  ensure
    sse&.close
    response.stream.close
  end
end
