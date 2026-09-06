# THE PICTURE OF THE WORLD, for the person building it.
#
# The scout's words on why it is here at all: *"coordinates come before
# pictures"* -- slice 1 put a footprint on a place and a box on a room, and a
# geometry programme with no way to look at its own output debugs itself by
# reading integers out of a table. `Story::Map` owns everything the page shows;
# this class chooses the world and renders.
#
# AN OBSERVER, exactly like `DebugController` and `MachineryController`, and for
# their reason: it reads, and it does not classify, generate, catch the world up
# or touch `session[:playthrough_token]`. Looking at a world must not move it,
# and looking at somebody's playthrough must not bind this browser to it.
#
# TWO WAYS IN, because the map is about two different things depending on which
# you came through:
#
#   PER STORY      the durable world and its template items. Nobody is standing
#                  anywhere, so there is no "you are here" and the walk starts
#                  from `Story#opening_location`. This is the one to look at
#                  after `rake game:new`, before anybody has played. Linked
#                  from the playthroughs index, one per listed story, gated
#                  there on the same flag this controller gates on; and from a
#                  playthrough's debug page, beside the playthrough map, drawn
#                  unconditionally because that page is already behind the flag.
#   PER PLAYTHROUGH  the same graph with the party on it: the column count is
#                  hops from where they are standing, and the things lying
#                  around are that game's own copies rather than the world's
#                  templates (`Item`'s two layers).
#
# GATED ON `Playthrough::Debug.enabled?`, the same flag as the debug page, the
# machinery panel and the verdict buttons -- the four answer one question: is
# the person at this keyboard the one building the game. Gated HERE rather than
# only on the link, because this app has no auth at all and an endpoint standing
# behind a hidden link is an endpoint anybody with the link can read.
class MapController < ApplicationController
  layout "debug"

  before_action :require_debug_view
  before_action :load_world

  def show
    @map = Story::Map.new(@story, playthrough: @playthrough)
  end

  private

  # THE STORY, EITHER WAY ROUND. A playthrough names its story, and a story is
  # asked for by id -- there is no `Story` resource in this app and this page is
  # not the start of one; it is the debug surface's own second route.
  def load_world
    if params[:playthrough_id]
      @playthrough = Playthrough.find(params[:playthrough_id])
      @story = @playthrough.story
    else
      @story = Story.find(params[:story_id])
    end
  end

  # Same gate as `DebugController#require_debug_view`, and deliberately the same
  # flag rather than one of its own.
  def require_debug_view
    head :not_found unless Playthrough::Debug.enabled?
  end
end
