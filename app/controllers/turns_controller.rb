class TurnsController < ApplicationController
  # Letting go of an old interruption is `Playthrough::Session`'s; see
  # `#acknowledge_interruption!` for what it may and may not close.
  def acknowledge_interruption
    playthrough = Playthrough.find(params[:playthrough_id])
    Playthrough::Session.new(playthrough).acknowledge_interruption!(params[:command_id])
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
    submission = Playthrough::Session.new(playthrough).accept!(params[:command], params[:request_token])

    # Nothing typed is not a turn. Send the player back to an untouched page
    # rather than enqueuing a job to narrate the empty string.
    if submission.nil?
      redirect_to playthrough_path(playthrough)
      return
    end

    NarrationJob.perform_later(playthrough.id, submission.command, submission.request_token)
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
  rescue Player::Allowance::LimitReached
    # A game an API player owns, typed into from the browser: the allowance
    # binds here too, and nothing was written.
    head :payment_required
  end
end
