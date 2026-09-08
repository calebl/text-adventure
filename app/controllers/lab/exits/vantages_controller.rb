# THE EXITS LAB: a place typed, the model asked what lies beyond it, and every
# pick counted against what he said it should be.
#
# `Lab::Exits`'s header is the design and the captain's answers in his own words.
# What belongs here is what makes this page different from the five behind the
# same flag, and it is the same two things `Lab::KindsController` says:
#
# A GET NEVER BUYS A CALL. `Lab::Exits::SamplesController#create` is the only
# thing in this namespace that spends money, and #create here writes a row and
# nothing else. Every action on this controller is free, including #update:
# every pick is already on every stored sample row, so declaring an expectation
# re-computes the hit rate over draws already paid for.
#
# GATED ON `Playthrough::Debug.enabled?`, IN THE CONTROLLER, on the same flag as
# the debug page, the machinery panel, the map and the realization lab -- they
# answer one question: is the person at this keyboard the one building the game.
# Gated here rather than only on a link, because this app has no auth at all and
# an endpoint behind a hidden link is an endpoint anybody with the link can read.
#
# ITS OWN LAYOUT, `debug`, so nothing here can reach the game's stylesheet.
# Restyling the reading experience is `ta-api-iface`, a stage of its own, and the
# two only stay separable while the two pages share no CSS.
#
# THE FACTS ARE NOT EDITABLE AND THE EXPECTATION IS. `#update` takes the
# quantifier and the population set and nothing else, which is
# `Lab::KindsController#update`'s rule and its reason: a vantage's name, teaser,
# way in and `absent` list are what its samples were drawn against, so editing
# one would leave a rate computed over draws of a different vantage. Type a new
# vantage instead; a vantage is a row and costs nothing.
class Lab::Exits::VantagesController < ApplicationController
  layout "debug"

  before_action :require_debug_view
  before_action :load_vantage, only: [ :show, :update, :destroy ]

  def index
    @vantages = Lab::Exits::Vantage.newest_first.includes(:samples, :judgements)
    @vantage = Lab::Exits::Vantage.new
    # THE COUNTER-FIGURE AND THE REFUSAL BELONG TO THE SET, so they are read here
    # and never on one vantage's page -- `Lab::Exits::Alignment`'s header has why.
    @alignment = Lab::Exits::Alignment.new(@vantages)
  end

  def show
    @samples = @vantage.samples.newest_first
    @hit_rate = Lab::Exits::HitRate.new(@vantage, samples: @vantage.samples.in_draw_order)
  end

  def create
    @vantage = Lab::Exits::Vantage.new(vantage_params)
    declare_expectations(@vantage)

    return redirect_to lab_exits_vantage_path(@vantage) if @vantage.save

    @vantages = Lab::Exits::Vantage.newest_first.includes(:samples, :judgements)
    @alignment = Lab::Exits::Alignment.new(@vantages)
    render :index, status: :unprocessable_content
  end

  def update
    declare_expectations(@vantage)

    return redirect_to lab_exits_vantage_path(@vantage) if @vantage.save

    @samples = @vantage.samples.newest_first
    @hit_rate = Lab::Exits::HitRate.new(@vantage, samples: @vantage.samples.in_draw_order)
    render :show, status: :unprocessable_content
  end

  # A VANTAGE, EVERY SAMPLE OF IT AND EVERY JUDGEMENT ON IT, because a mis-typed
  # vantage is noise in the measurement and its draws were bought against words
  # he did not mean. `dependent: :destroy` on both associations is what takes
  # them; nothing else in the app references either row.
  def destroy
    @vantage.destroy!
    redirect_to lab_exits_vantages_path
  end

  private

  def load_vantage
    @vantage = Lab::Exits::Vantage.find(params[:id])
  end

  # WHAT HE SAYS THE ANSWER SHOULD BE, off the form, and the same reader for
  # #create and #update -- `Lab::KindsController#declare_expectations`' shape.
  # Either half absent is *don't care* and is stored as NULL, which takes the
  # vantage out of that figure entirely; so an absent key and an empty list are
  # the same answer here, and both are the ordinary one.
  #
  # THE PER-NAME HALF IS NOT HERE. It is keyed on a place rather than on the
  # vantage, so it is `Lab::Exits::JudgementsController`'s -- see
  # `Lab::Exits::Judgement`'s header.
  def declare_expectations(vantage)
    vantage.expects_inside_quantifier = params[:expects_inside_quantifier].presence
    vantage.declare_population(params[:expects_population])
  end

  # THE FIVE FACTS AND NOT ONE MORE, and the absence of an `inside` band is the
  # point: a vantage that carried one would become a laid-out place and
  # `Location::Generator#write_exits!` would never make the call this lab
  # measures. There is no prompt field here and there must never be one -- see
  # `Lab::Exits`'s header.
  def vantage_params
    params.expect(vantage: [ :world, :name, :teaser, :reached_from, :danger, :absent ])
  end

  def require_debug_view
    head :not_found unless Playthrough::Debug.enabled?
  end
end
