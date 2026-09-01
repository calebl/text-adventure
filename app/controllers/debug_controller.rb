# The captain's window into the machine while he plays: everything one
# playthrough generated and decided behind the prose.
#
# AN OBSERVER, and the whole class is written to be one. It reads a playthrough,
# hands it to `Playthrough::Debug` and renders. It does not classify, generate,
# catch the world up or touch `session[:playthrough_token]` -- looking at a
# playthrough must not bind a browser to it, and looking at a world must not
# move it.
#
# ITS OWN LAYOUT, so nothing here can reach the game's stylesheet. The reading
# experience is deliberately deferred (`ta-api-iface`) and this view is allowed
# to be as dense and technical as it likes; those two facts only coexist while
# the two pages share no CSS.
class DebugController < ApplicationController
  layout "debug"

  # Off unless `Playthrough::Debug.enabled?`, which is local-only by default.
  # THE GATE IS HERE rather than only on the link that reaches it: this app has
  # no auth at all, so a playthrough URL is the whole of a player's credentials
  # and hiding the link would leave the page standing behind it.
  before_action :require_debug_view

  def show
    @playthrough = Playthrough.find(params[:playthrough_id])
    @debug = Playthrough::Debug.new(@playthrough)
  end

  private

  def require_debug_view
    head :not_found unless Playthrough::Debug.enabled?
  end
end
