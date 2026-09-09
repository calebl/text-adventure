# WHAT HE SAYS ABOUT ONE PLACE THIS VANTAGE NAMES -- typed before a draw or
# judged after one, and it is the same request either way.
#
# ONE ENDPOINT AND ONE ACTION, and the reason is `Lab::Exits::Judgement`'s: the
# expectation and the verdict are two halves of one row, keyed on the place. He
# types `the rust market` before he has ever seen it named (the captain's Call 4c)
# or clicks `weak` on a place a draw just produced (Call 3a), and
# `Lab::Exits::Vantage#judge!` finds or creates the row by
# `Lab::Exits.key_for` either way. Two endpoints would be two writers of one row
# and would need a rule about which of them may clear the other's half.
#
# A POST RATHER THAN A PATCH because the row may not exist: a place typed in
# advance has no id to address, and the name is the address. `#judge!` is
# idempotent on the key, so a second post about one place amends rather than
# duplicates -- and the unique index on `[vantage_id, name_key]` is what makes
# that a guarantee rather than a habit.
#
# IT BUYS NOTHING. Every figure this feeds is computed off sample rows already
# paid for, so a judgement written today re-scores every draw bought before it.
# That is the property worth using deliberately: draw first, look at what the
# model named, THEN say what you think of it.
#
# GATED ON `Playthrough::Debug.enabled?`, in the controller, on the same flag as
# every other instrument page.
class Lab::Exits::JudgementsController < ApplicationController
  layout "debug"

  before_action :require_debug_view

  def create
    vantage = Lab::Exits::Vantage.find(params[:vantage_id])
    vantage.judge!(params[:name], **recorded)

    redirect_to lab_exits_vantage_path(vantage, anchor: anchor_for(params[:name]))
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to lab_exits_vantage_path(params[:vantage_id]), alert: error.message
  end

  private

  # WHICH HALVES THIS REQUEST IS ACTUALLY WRITING, and an absent key is left
  # alone rather than cleared -- `Lab::Exits::Judgement#record!`'s contract. So
  # the expectation form does not throw away a verdict he gave last week and the
  # verdict buttons do not throw away an expectation he typed.
  #
  # AN EMPTY LIST IS HOW EITHER IS CLEARED, which is why `aspects` is passed as
  # `[]` when a verdict came in without any: clicking a different verdict must
  # not silently keep the aspects of the old one, and `Playthrough::Feedback`'s
  # rule is that clearing has to be expressible.
  def recorded
    written = {}
    written[:verdict] = params[:verdict] if params.key?(:verdict)
    written[:aspects] = params[:aspects] || [] if params.key?(:verdict) || params.key?(:aspects)
    written[:note] = params[:note] if params.key?(:note)
    written[:expects] = expects if params.key?(:expects)
    written
  end

  # THE TYPED EXPECTATION, held to the two picks this lab is about. A key naming
  # anything else is dropped here rather than saved and refused later, because
  # `Lab::Exits::PICKS` is what the page offers and a stray key is a hand-rolled
  # request rather than a mistake worth a sentence.
  def expects
    offered = params[:expects] || {}

    Lab::Exits.picks.to_h { |pick| [ pick.name, Array(offered[pick.name]) ] }
  end

  # WHERE ON THE PAGE TO LAND, so judging the fourth place of eleven does not
  # scroll him back to the top.
  def anchor_for(name)
    key = Lab::Exits.key_for(name)

    "place-#{key.parameterize}" if key.present?
  end

  def require_debug_view
    head :not_found unless Playthrough::Debug.enabled?
  end
end
