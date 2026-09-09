class TurnsController < ApplicationController
  # Takes the player's typed command, hands the turn to a background job, and
  # acknowledges the submission immediately. The job broadcasts the pending
  # page, prose and final page in order while it owns the turn's process lock.
  #
  # The request does NOT run the turn. That is the point of the job:
  #
  #   * a turn outlives its connection -- close the tab mid-narration and the
  #     generation carries on, where `ActionController::Live` used to kill it;
  #   * no Puma thread is held for the twenty to thirty seconds a narration
  #     takes, where SSE held one for the whole of it and three readers stalled
  #     the site on a default 3-thread Puma.
  #
  # The HTTP response must not replace the log. A grammar command or factual
  # fallback can finish before this response reaches the browser; a pending
  # page sent here would then erase the completed turn and strand the input.
  def create
    playthrough = Playthrough.find(params[:playthrough_id])
    command = params[:command].to_s.strip

    # Nothing typed is not a turn. Send the player back to an untouched page
    # rather than enqueuing a job to narrate the empty string.
    if command.empty?
      redirect_to playthrough_path(playthrough)
      return
    end

    request_token = params[:request_token].presence || SecureRandom.uuid
    Playthrough::Command.accept!(playthrough, command, request_token)
    NarrationJob.perform_later(playthrough.id, command, request_token)

    respond_to do |format|
      format.turbo_stream { head :no_content }
      # Without Turbo -- scripts blocked, or the module still loading -- the turn
      # still runs; the player just has to reload to read it. The job is already
      # enqueued by the time we get here.
      format.html { redirect_to playthrough_path(playthrough, anchor: "bottom") }
    end
  rescue Playthrough::Command::TokenConflict, ActiveRecord::RecordInvalid
    head :conflict
  end
end
