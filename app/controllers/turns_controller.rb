class TurnsController < ApplicationController
  # Takes the player's typed command and hands it straight back to the play
  # page as a query param. The narration itself is streamed by NarrationsController
  # once the browser has the page and can show the text arriving; doing it here
  # would mean a form POST that hangs for 20-30 seconds with no feedback.
  def create
    playthrough = Playthrough.find(params[:playthrough_id])
    command = params[:command].to_s.strip

    if command.empty?
      redirect_to playthrough
    else
      redirect_to playthrough_path(playthrough, command: command)
    end
  end
end
