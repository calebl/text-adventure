class NarrationsController < ApplicationController
  include ActionController::Live

  # Streams one turn of narration as server-sent events. The consumer is six
  # lines of `EventSource` in the play page; Turbo Streams over Action Cable is
  # a later stage, and Scene::Narrator takes a block precisely so that swap
  # needs to touch nothing else.
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

    Scene::Narrator.new(playthrough).narrate(command) do |chunk|
      sse.write({ t: chunk }, event: "token")
    end

    sse.write({ ok: true }, event: "done")
  rescue ActionController::Live::ClientDisconnected
    # The player closed the tab or reloaded. Scene::Narrator has already
    # persisted whatever it had, so there is nothing to do but stop.
    Rails.logger.info { "Narration client disconnected" }
  rescue => e
    Rails.logger.error { "Narration failed: #{e.class}: #{e.message}" }
    sse&.write({ message: e.message }, event: "error")
  ensure
    sse&.close
    response.stream.close
  end
end
