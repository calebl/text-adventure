# THE MACHINERY BEHIND ONE TURN, fetched while the captain is playing.
#
# The captain's words, 2026-09-05: *"having to switch over to debug mode is too
# slow and I can't compare the two side by side."* So the prompt a turn was
# written from and the state it was played in are fetched a TURN AT A TIME,
# into a Turbo Frame beside that turn's prose, rather than precomputed for the
# whole log. `#turn_log` is replaced by a Turbo Stream at the end of every turn
# and the log is the entire playthrough, so a panel per turn built on every
# render would put forty of these on the wire for one typed line.
#
# AN OBSERVER, exactly like `DebugController`: it reads a playthrough, hands one
# of its turns to `Playthrough::Machinery` and renders. It does not classify,
# generate, catch the world up, or touch `session[:playthrough_token]` --
# looking at a turn must not bind a browser to the playthrough it belongs to,
# and must not move the world.
#
# GATED ON `Playthrough::Debug.enabled?`, the same flag as the debug page and
# the verdict buttons, and gated HERE rather than only on the control that
# reaches it. This app has no auth at all: a playthrough URL is the whole of a
# player's credentials, so an endpoint standing behind a hidden control is an
# endpoint anybody with the link can read -- and what it answers with is the
# prompt text.
#
# TWO LAYOUTS, and the second is the no-JavaScript case. A Turbo Frame request
# wants the frame and nothing else; a plain request -- the placeholder link
# followed with scripts blocked -- gets the game's own layout, so the panel is
# still readable as a page of its own rather than as unstyled markup.
class MachineryController < ApplicationController
  layout -> { turbo_frame_request? ? false : "application" }

  before_action :require_debug_view
  before_action :load_turn

  def show
    @machinery = Playthrough::Machinery.new(@playthrough, @scene)
  end

  private

  # THE TURN, RESOLVED AGAINST THE CLOSED SET OF THIS PLAYTHROUGH'S OWN TURNS --
  # `Playthrough#scene_chain`, which is what `FeedbacksController` resolves
  # against and what the play page and `Playthrough::Debug` both read. A bare
  # `Scene.find` would answer with the prompts behind a turn from ANOTHER
  # playthrough of the same story, and every playthrough URL in the app is
  # handed out.
  def load_turn
    @playthrough = Playthrough.find(params[:playthrough_id])
    @scene = @playthrough.scene_chain.find { |turn| turn.id == params[:scene_id].to_i }

    head :not_found if @scene.nil?
  end

  # Same gate as `DebugController#require_debug_view` and
  # `FeedbacksController#require_instrument`, and deliberately the same flag
  # rather than one of its own -- the three answer one question: is the person
  # at this keyboard the one building the game.
  def require_debug_view
    head :not_found unless Playthrough::Debug.enabled?
  end
end
