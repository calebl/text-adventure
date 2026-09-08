# ONE DRAW OF A KIND, AND HIS JUDGEMENT OF IT.
#
# THE ONE ENDPOINT IN THE DEBUG SURFACE THAT SPENDS MONEY. #create makes two
# real model calls through `Location::Generator#realize!` and costs about a
# quarter of a cent; #show and #update cost nothing. That is why it is a POST and
# why nothing on the lab's pages fetches it: a page load that bought a call would
# turn a reload into a purchase, and a browser reloads on its own.
#
# ONE DRAW PER REQUEST, DELIBERATELY. `Lab::Realization::Runner` holds one
# transaction per sample and the development database has one writer, so a
# request that drew ten would lock the database for the length of ten model
# calls -- and the captain plays on this database. Ten draws is ten clicks, which
# is also what makes an interrupted run leave nine usable samples instead of
# none.
#
# AND A FAILED CALL IS STILL A SAMPLE. `Eval::Realization::Bench#build` rescues
# the realization and records the error on the reading rather than raising, which
# is what stops a provider dropping one call in a hundred from costing the whole
# look -- and a refusal is the one failure that is ABOUT the prompt
# (`Eval::Realization::Scorer::Reading#refused?`), so it is worth a row. What
# does raise is a kind that cannot be staged at all: a world with no file, or a
# way back the world does not have. Those are a person's mistake and get a
# sentence.
#
# GATED ON `Playthrough::Debug.enabled?`, in the controller, on the same flag as
# every other instrument page -- `Lab::KindsController`'s note has why it matters
# more here.
class Lab::SamplesController < ApplicationController
  layout "debug"

  before_action :require_debug_view

  def show
    @sample = Lab::Realization::Sample.find(params[:id])
    @kind = @sample.kind
    # THE FLOOR PLAN, OR NIL. Built here rather than in the view for
    # `Story::Map`'s rule -- the view emits markup and does no arithmetic -- and
    # nil for a sample drawn before positions were stored, which the page says
    # out loud (`Lab::Realization::Plan`).
    @plan = Lab::Realization::Plan.for(@sample.reading, name: @kind.name)
  end

  def create
    kind = Lab::Realization::Kind.find(params[:kind_id])
    sample = Lab::Realization::Runner.new(kind).draw!

    redirect_to lab_sample_path(sample)
  rescue Lab::Realization::Runner::Unrunnable, Eval::Realization::Stage::Unstageable => error
    redirect_to lab_kind_path(params[:kind_id]), alert: error.message
  end

  # HIS VERDICT, RECORDED OR AMENDED -- the same request either way, because
  # there is at most one per sample and he will change his mind about one once he
  # has seen the next. `Lab::Realization::Sample#record!` is
  # `Playthrough::Feedback.record`'s shape and its reasoning.
  def update
    @sample = Lab::Realization::Sample.find(params[:id])
    @sample.record!(verdict: params[:verdict], aspects: params[:aspects] || [], note: params[:note])

    redirect_to lab_sample_path(@sample)
  end

  private

  def require_debug_view
    head :not_found unless Playthrough::Debug.enabled?
  end
end
