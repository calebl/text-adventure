# Plays one turn away from the request that asked for it, and broadcasts what
# the player reads over Action Cable as Turbo Streams.
#
# This is the consumer half of `Playthrough::Turn` and nothing else. The loop
# still classifies, moves, talks and narrates exactly as it did behind the SSE
# controller this replaces -- `Scene::Narrator` takes a block precisely so that
# swapping the consumer touches nothing that generates or persists prose.
#
# Four things a job fixes that a streaming request could not:
#
#   * A TURN OUTLIVES ITS CONNECTION. `ActionController::Live` raised
#     ClientDisconnected and killed the generation mid-sentence; the `ensure` in
#     `Scene::Narrator` salvaged whatever had arrived. Here nobody is watching in
#     the first place, so closing the tab costs nothing -- and the finished turn
#     is broadcast to whoever reopens the page, because the subscription is to
#     the playthrough and not to a socket.
#   * NO PUMA THREAD IS HELD. SSE held one for the whole 20-30 seconds; three
#     readers stalled the site on a default 3-thread Puma. WebSockets do not
#     consume request threads at all.
#   * NO RELOAD ENDS THE TURN. The old `done` handler had to do
#     `window.location = ...` because a streaming render has no form and no
#     "you are in X, ways out" line. Broadcasting the whole `#turn_log` supplies
#     both, so there is nothing left to reload for -- and so the player's scroll
#     position survives the end of a turn.
#
# One measured thing decided the shape of the broadcasting: see `BATCH_SIZE`.
class NarrationJob < ApplicationJob
  queue_as :default

  # HOW MUCH PROSE PER BROADCAST, and it is not "one token".
  #
  # Every broadcast is a `<turbo-stream>` element -- roughly 75 bytes of framing
  # around the text -- and in production it is also one row in
  # `solid_cable_messages`. Measured on a real narration (report §3c in
  # `data/ta-play-ui`): unbatched, 55 broadcasts and 7,225 bytes for ~250
  # characters; at 60 characters, 6 broadcasts and 1,049 bytes but visibly
  # chunky, with 3.4-second gaps. A hosted model writing a 400-token paragraph
  # would be ~400 inserts per turn unbatched.
  #
  # 20 characters is the middle the measurements point at: a handful of words at
  # a time, which reads as prose arriving rather than as blocks landing.
  BATCH_SIZE = 20

  def perform(playthrough_id, command)
    playthrough = Playthrough.find(playthrough_id)
    buffer = +""

    Playthrough::Turn.new(playthrough).play(command) do |chunk|
      buffer << chunk
      flush(playthrough, buffer) if buffer.length >= BATCH_SIZE
    end

    flush(playthrough, buffer)
    finish(playthrough)
  rescue ActiveRecord::RecordNotFound
    # The playthrough is gone. There is nobody to tell.
    Rails.logger.info { "Narration skipped: playthrough #{playthrough_id} no longer exists" }
  rescue BaseAgent::CrisisResponseError => e
    # THE ONE FAILURE THE APP ANSWERS ITSELF, and the one place this job knows
    # anything about what a turn contained -- which is a cost, and it is paid
    # here rather than in the loop on purpose. `Playthrough::Turn` produces
    # scenes; nothing it returns can carry "show the player something that is
    # not a scene". The consumer is what has a screen.
    #
    # No scene was written -- `BaseAgent` never handed the text back and
    # `Scene::Narrator` does not persist an unusable response -- so replacing
    # `#turn_log` is also what takes the suppressed prose off the page: the log
    # renders persisted scenes, and `#stream` goes with the element it lives in.
    Rails.logger.warn { "Narration intercepted: #{e.class}: #{e.message}" }
    finish(playthrough, safety_notice: true) if playthrough
  rescue => e
    # A failed turn used to leave the player with a dead cursor and no input --
    # the SSE `error` event removed the cursor and that was all, so the only way
    # back was a reload. Broadcasting the idle log returns the form along with
    # the reason, and the player is still standing where they were.
    Rails.logger.error { "Narration failed: #{e.class}: #{e.message}" }
    finish(playthrough, error: e.message) if playthrough
  end

  private

  # Appends the buffered prose to the streaming div and empties the buffer.
  #
  # `html:` is inserted verbatim, so the narrator's own text has to be escaped
  # here -- a model that writes "a < b" would otherwise open a tag inside the
  # turn. The div is `white-space: pre-wrap`, which is what keeps the paragraph
  # breaks the model wrote.
  def flush(playthrough, buffer)
    return if buffer.empty?

    Turbo::StreamsChannel.broadcast_append_to(
      playthrough, target: "stream", html: ERB::Util.html_escape(buffer)
    )
    buffer.clear
  end

  # The end of the turn: the same partial `PlaythroughsController#show` renders,
  # so the log, the new location line and the input all arrive in one element and
  # the page ends up exactly where a reload would have left it -- without the
  # reload, and so without losing where the player had scrolled to.
  def finish(playthrough, error: nil, safety_notice: false)
    Turbo::StreamsChannel.broadcast_replace_to(
      playthrough,
      target: "turn_log",
      partial: "playthroughs/turn_log",
      locals: { playthrough: playthrough.reload, command: nil, error: error,
                safety_notice: safety_notice }
    )
  end
end
