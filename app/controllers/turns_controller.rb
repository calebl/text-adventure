class TurnsController < ApplicationController
  # Pre-journal workers left no evidence from which to replay safely. Only an
  # explicit player acknowledgement may close that old interruption, retaining
  # every saved effect. Taking the same lock waits for any still-live worker;
  # it cannot discard a new recoverable command or a completed turn.
  def acknowledge_interruption
    playthrough = Playthrough.find(params[:playthrough_id])
    GameLock.synchronize("playthrough", playthrough.id) do
      submission = playthrough.commands.find(params[:command_id])
      if submission.status == "running" && submission.journal.blank?
        submission.update!(status: "failed", error_kind: "interruption_acknowledged")
      end
    end
    redirect_to playthrough_path(playthrough, anchor: "bottom"), status: :see_other
  end

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
  # THE HTTP RESPONSE MUST NOT REPLACE THE LOG. A grammar command or factual
  # fallback can finish before this response reaches the browser; a pending
  # page sent here would then erase the completed turn and strand the input.
  # What it does send is one spent submission token, replaced by a fresh one
  # (`turns/create.turbo_stream`), which is what makes a SECOND submit of the
  # same line a second turn rather than a redelivery of the first. The
  # non-Turbo path gets the same thing out of the redirect's re-render.
  #
  # ORDER IS THE ROW'S, NOT THIS ACTION'S. Two lines can be accepted while a
  # turn is still running, and `config/queue.yml` runs three worker threads, so
  # the jobs can reach `GameLock` in either order. `playthrough_commands.id` is
  # the accepted order and `Playthrough::Turn#play` plays up to its own row in
  # that order -- see both headers.
  def create
    playthrough = Playthrough.find(params[:playthrough_id])
    command = params[:command].to_s.strip

    # Nothing typed is not a turn. Send the player back to an untouched page
    # rather than enqueuing a job to narrate the empty string.
    if command.empty?
      redirect_to playthrough_path(playthrough)
      return
    end

    submission = Playthrough::Command.accept!(playthrough, command, params[:request_token].presence || SecureRandom.uuid)
    NarrationJob.perform_later(playthrough.id, command, submission.request_token)
    @request_token = SecureRandom.uuid

    respond_to do |format|
      format.turbo_stream
      # Without Turbo -- scripts blocked, or the module still loading -- the turn
      # still runs; the player just has to reload to read it. The job is already
      # enqueued by the time we get here.
      format.html { redirect_to playthrough_path(playthrough, anchor: "bottom") }
    end
  rescue ActiveRecord::RecordInvalid
    head :conflict
  end
end
