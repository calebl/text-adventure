# THE REALIZATION LAB: a kind of place typed, drawn, and counted against what he
# said the picks should be.
#
# `Lab::Realization`'s header is the design and the captain's ask in his own
# words. What belongs here is what makes this page different from the other four
# behind the same flag.
#
# THE FIRST DEBUG-GATED PAGE THAT SPENDS MONEY, and it is worth saying out loud
# because the other four say the opposite. `DebugController`,
# `MachineryController` and `MapController` each open by declaring themselves
# OBSERVERS -- they read, and they do not classify, generate or catch the world
# up. This one generates. So the rule that keeps it honest is the HTTP one: a GET
# never buys a call, `Lab::SamplesController#create` is the only thing that
# does, and #create here writes a row and nothing else.
#
# GATED ON `Playthrough::Debug.enabled?`, the same flag as the debug page, the
# machinery panel, the map and the verdict buttons -- the five answer one
# question: is the person at this keyboard the one building the game. Gated HERE
# rather than only on a link, because this app has no auth at all and an endpoint
# behind a hidden link is an endpoint anybody with the link can read. That
# matters more here than on the observers: this one can be made to spend the
# captain's money.
#
# ITS OWN LAYOUT, `debug`, so nothing here can reach the game's stylesheet --
# `DebugController`'s reason unchanged. Restyling the reading experience is
# `ta-api-iface`, a stage of its own, and the two only stay separable while the
# two pages share no CSS.
#
# AND THE EXPECTATION IS EDITED BY A PATCH THAT BUYS NOTHING. Every pick is
# already on every stored sample row, so #update re-computes the hit rate over
# samples already paid for. That is the whole reason the expectation is editable
# after the fact rather than fixed at creation: draw ten, look at them, THEN say
# what you think the picks should have been.
class Lab::KindsController < ApplicationController
  layout "debug"

  before_action :require_debug_view
  before_action :load_kind, only: [ :show, :update, :destroy ]

  def index
    @kinds = Lab::Realization::Kind.newest_first.includes(:samples)
    @kind = Lab::Realization::Kind.new
  end

  def show
    @samples = @kind.samples.newest_first
    @hit_rate = Lab::Realization::HitRate.new(@kind, samples: @kind.samples.in_draw_order)
  end

  def create
    @kind = Lab::Realization::Kind.new(kind_params)
    declare_expectations(@kind)

    return redirect_to lab_kind_path(@kind) if @kind.save

    @kinds = Lab::Realization::Kind.newest_first.includes(:samples)
    render :index, status: :unprocessable_content
  end

  # THE EXPECTATION, AND THE FACTS ARE NOT TOUCHED. A kind's name, teaser, band
  # and danger are what its samples were drawn against, so editing one would
  # leave a rate computed over draws of a different kind -- which is
  # `Eval::Realization.digest`'s objection to a corpus edited between two runs,
  # one level down. Type a new kind instead; a kind is a row and costs nothing.
  def update
    declare_expectations(@kind)

    return redirect_to lab_kind_path(@kind) if @kind.save

    @samples = @kind.samples.newest_first
    @hit_rate = Lab::Realization::HitRate.new(@kind, samples: @kind.samples.in_draw_order)
    render :show, status: :unprocessable_content
  end

  # A KIND AND EVERY SAMPLE OF IT, because a mis-typed kind is noise in the
  # measurement and the samples of it were drawn against words he did not mean.
  # `dependent: :destroy` on the association is what takes them; nothing else in
  # the app references either row.
  def destroy
    @kind.destroy!
    redirect_to lab_kinds_path
  end

  private

  def load_kind
    @kind = Lab::Realization::Kind.find(params[:id])
  end

  # THE FOUR PARAMETERS AND NOT ONE MORE, and the absence of a fifth is the
  # point: there is no prompt field here and there must never be one. See
  # `Lab::Realization`'s header for why a lab with a prompt box would be a second
  # prompt source with no baseline.
  def kind_params
    params.expect(kind: [ :world, :name, :teaser, :reached_from, :inside, :danger, :population ])
  end

  # WHAT HE SAYS EACH PICK SHOULD COME BACK AS, off a checkbox group per pick. A
  # pick with no box ticked is *don't care* and is stored as NULL, which takes
  # the kind out of that figure entirely -- so an absent key and an empty list
  # are the same answer here, and both are the ordinary one.
  def declare_expectations(kind)
    declared = params[:expects] || {}

    Lab::Realization.picks.each do |pick|
      kind.declare(pick, Array(declared[pick.name]))
    end
  end

  # Same gate as `DebugController#require_debug_view`, and deliberately the same
  # flag rather than one of its own -- see the note at the top of this class.
  def require_debug_view
    head :not_found unless Playthrough::Debug.enabled?
  end
end
