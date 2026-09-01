class TurnsController < ApplicationController
  # Takes the player's typed command and hands it straight back to the play
  # page as a query param. The narration itself is streamed by NarrationsController
  # once the browser has the page and can show the text arriving; doing it here
  # would mean a form POST that hangs for 20-30 seconds with no feedback.
  def create
    playthrough = Playthrough.find(params[:playthrough_id])
    command = params[:command].to_s.strip

    # `#bottom` on both branches: the play page renders the newest turn at the
    # foot of the log, so landing at the top of the document would put the
    # answer to what he just typed below the fold. The anchor is what does the
    # scrolling, not script -- see the note beside #bottom in the view.
    if command.empty?
      redirect_to playthrough_path(playthrough, anchor: "bottom")
    else
      redirect_to playthrough_path(playthrough, command: command, anchor: "bottom")
    end
  end
end
