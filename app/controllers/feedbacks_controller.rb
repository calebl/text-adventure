# The captain's verdict on one turn, recorded while he is playing it.
#
# ONE CLICK, AND IT MUST NOT INTERRUPT THE GAME. A turn is a `NarrationJob`
# broadcasting Turbo Streams over Action Cable, so this answers with a stream
# that replaces ONE element -- the verdict footer on the turn that was judged --
# and touches nothing else. No reload, no redirect, no new page: the input keeps
# focus, a turn already in flight keeps streaming into `#stream`, and the next
# command is not blocked on anything here.
#
# It also cannot fight that broadcast, and the reason is that neither side holds
# any state. `NarrationJob` replaces the whole of `#turn_log` when a turn lands,
# which re-renders every footer in it out of the records -- so a verdict recorded
# a moment earlier survives as the records, and a verdict recorded a moment later
# lands on the footer the broadcast just drew.
#
# GATED LIKE THE DEBUG VIEW, on `Playthrough::Debug.enabled?` -- local by
# default, `TA_DEBUG_VIEW` either way. The two answer the same question: is the
# person at this keyboard the one building the game. There is no auth in this
# app at all, so a playthrough link is the whole of a player's credentials, and
# someone handed one to read a story should be no more able to file evaluation
# data than to read the prompts behind it.
class FeedbacksController < ApplicationController
  before_action :require_instrument
  before_action :load_turn

  # Records the verdict, or amends the one already there -- the same request
  # either way, because there is at most one verdict per turn and he will change
  # his mind about a turn after the next one lands.
  def create
    Playthrough::Feedback.record(
      playthrough: @playthrough, scene: @scene,
      verdict: params[:verdict], note: params[:note]
    )

    respond_with_verdict
  end

  # Clearing is amendment's other half. A mis-click on a forty-turn log is
  # noise in the measurement, so there has to be a way to take one back that is
  # not "record a verdict you do not mean".
  def destroy
    @playthrough.feedbacks.find_by(scene: @scene)&.destroy!

    respond_with_verdict
  end

  private

  # THE TURN, RESOLVED AGAINST THE CLOSED SET OF THIS PLAYTHROUGH'S OWN TURNS.
  #
  # `Playthrough#scene_chain` is that set -- the same walk the play page and
  # `Playthrough::Debug` both read, so the three cannot disagree about which
  # turns belong to this playthrough. A bare `Scene.find` would accept a scene
  # id from another playthrough of the same story, which every playthrough URL
  # in the app hands out.
  def load_turn
    @playthrough = Playthrough.find(params[:playthrough_id])
    @scene = @playthrough.scene_chain.find { |turn| turn.id == params[:scene_id].to_i }

    head :not_found if @scene.nil?
  end

  # The footer for that one turn, in whatever state the records now hold. The
  # same partial the log renders, so a verdict looks identical whether it
  # arrived here, on a page load, or in the broadcast that ended a turn.
  #
  # The HTML fallback is a redirect back to the play page, for scripts blocked
  # or the module still loading: the verdict is recorded by the time we get
  # here either way.
  def respond_with_verdict
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          helpers.dom_id(@scene, :verdict),
          partial: "feedbacks/verdict",
          locals: { playthrough: @playthrough, scene: @scene,
                    feedback: @playthrough.feedbacks.find_by(scene: @scene) }
        )
      end
      format.html { redirect_to playthrough_path(@playthrough, anchor: "bottom") }
    end
  end

  # Same gate as `DebugController#require_debug_view`, and deliberately the same
  # flag rather than one of its own -- see the note at the top of this class.
  def require_instrument
    head :not_found unless Playthrough::Debug.enabled?
  end
end
