# ONE DRAW OF A VANTAGE, AND HIS VERDICT ON THE ANSWER AS A WHOLE.
#
# THE SECOND ENDPOINT IN THE DEBUG SURFACE THAT SPENDS MONEY, and the same rules
# as the first (`Lab::SamplesController`). #create makes two real model calls
# through `Location::Generator#realize!`; #show and #update cost nothing. That is
# why it is a POST and why nothing on these pages fetches it: a page load that
# bought a call would turn a reload into a purchase, and a browser reloads on its
# own.
#
# ONE DRAW PER REQUEST, DELIBERATELY. `Lab::Realization::Runner` holds one
# transaction per sample and the development database has one writer, so a
# request that drew ten would lock the database for the length of ten model
# calls -- and the captain plays on this database. Ten draws is ten clicks, which
# is also what makes an interrupted run leave nine usable samples instead of
# none. `rake lab:exits:draw` is the same draws without the clicking.
#
# AND A FAILED CALL IS STILL A SAMPLE. `Eval::Realization::Bench#build` rescues
# the realization and records the error on the reading rather than raising, which
# is what stops a provider dropping one call in a hundred from costing the whole
# look -- and a refusal is the one failure that is ABOUT the prompt, so it is
# worth a row. What does raise is a vantage that cannot be staged at all: a world
# with no file, a way back the world does not have, or an `absent` name it does
# not hold. Those are a person's mistake and get a sentence.
#
# THE `absent` LIST IS THE COMMONEST OF THOSE MISTAKES, which is why the flash
# matters here more than on the other lab: a name has to match a place in the
# world file, `Eval::Realization::Stage#find_room!` is what says so, and the
# whole draw is refused rather than quietly staged without the surgery -- because
# a draw staged without it measures nothing (`Lab::Exits`'s header).
class Lab::Exits::SamplesController < ApplicationController
  layout "debug"

  before_action :require_debug_view

  def show
    @sample = Lab::Exits::Sample.find(params[:id])
    @vantage = @sample.vantage
  end

  def create
    vantage = Lab::Exits::Vantage.find(params[:vantage_id])
    sample = Lab::Exits::Runner.new(vantage).draw!

    redirect_to lab_exits_sample_path(sample)
  rescue Eval::Realization::Stage::Unstageable => error
    redirect_to lab_exits_vantage_path(params[:vantage_id]), alert: error.message
  end

  # HIS VERDICT ON THE SET OF WAYS OUT, recorded or amended -- the same request
  # either way, because there is at most one per sample and he will change his
  # mind once he has seen the next. Every claim about a PARTICULAR named place is
  # a judgement and goes to `Lab::Exits::JudgementsController` instead;
  # `Lab::Exits::Sample`'s header has the split and why one verdict cannot carry
  # both.
  def update
    @sample = Lab::Exits::Sample.find(params[:id])
    @sample.record!(verdict: params[:verdict], aspects: params[:aspects] || [], note: params[:note])

    redirect_to lab_exits_sample_path(@sample)
  end

  private

  def require_debug_view
    head :not_found unless Playthrough::Debug.enabled?
  end
end
