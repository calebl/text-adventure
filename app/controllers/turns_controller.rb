class TurnsController < ApplicationController
  # Takes the player's typed command, hands the turn to a background job, and
  # answers immediately with the streaming half of the play page: the command
  # echoed back, and an empty `#stream` for the job to append prose into.
  #
  # The request does NOT run the turn. That is the point of the job:
  #
  #   * a turn outlives its connection -- close the tab mid-narration and the
  #     generation carries on, where `ActionController::Live` used to kill it;
  #   * no Puma thread is held for the twenty to thirty seconds a narration
  #     takes, where SSE held one for the whole of it and three readers stalled
  #     the site on a default 3-thread Puma.
  #
  # Ordering: the job's first broadcast follows `catch_up_world!` and a
  # classification model call, so this response has reached the browser long
  # before there is anything to append. Turbo drops a stream action whose target
  # is missing, which is what that margin buys.
  def create
    playthrough = Playthrough.find(params[:playthrough_id])
    command = params[:command].to_s.strip

    # Nothing typed is not a turn. Send the player back to an untouched page
    # rather than enqueuing a job to narrate the empty string.
    if command.empty?
      redirect_to playthrough_path(playthrough)
      return
    end

    NarrationJob.perform_later(playthrough.id, command)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "turn_log",
          partial: "playthroughs/turn_log",
          locals: { playthrough: playthrough, command: command }
        )
      end
      # Without Turbo -- scripts blocked, or the module still loading -- the turn
      # still runs; the player just has to reload to read it. The job is already
      # enqueued by the time we get here.
      format.html { redirect_to playthrough_path(playthrough, anchor: "bottom") }
    end
  end
end
