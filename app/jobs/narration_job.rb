# Plays one turn away from the request that asked for it, and broadcasts what
# the player reads over Action Cable as Turbo Streams.
#
# This is the Turbo adapter of `Playthrough::Session` and nothing else. The loop
# still classifies, moves, talks and narrates exactly as it did behind the SSE
# controller this replaces -- the narrator (`Playthrough::Turn#narrate`) takes a
# block precisely so that swapping the consumer touches nothing that generates
# or persists prose.
#
# Four things a job fixes that a streaming request could not:
#
#   * A TURN OUTLIVES ITS CONNECTION. `ActionController::Live` raised
#     ClientDisconnected and killed the generation mid-sentence; the `ensure` in
#     the narrator (`Playthrough::Turn#narrate`) salvaged whatever had arrived.
#     Here nobody is watching in the first place, so closing the tab costs
#     nothing -- and the finished turn is broadcast to whoever reopens the page,
#     because the subscription is to the playthrough and not to a socket.
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

  # WHICH FRONT END IS WAITING. The browser listens on the cable; an API client
  # tails the turn's event rows, which `Events` writes instead. One job, one
  # call into the driver, two adapters -- the turn itself cannot tell them apart.
  TRANSPORTS = %w[turbo events].freeze

  def perform(playthrough_id, command, request_token = job_id, transport = "turbo")
    return Events.new(playthrough_id, command, request_token).perform if transport == "events"

    playthrough = Playthrough.find(playthrough_id)
    buffer = +""
    handled_error = false

    # All page changes travel over one ordered channel under the same lock.
    # The HTTP acknowledgement carries no competing pending page, so even an
    # immediate grammar command cannot be overwritten by a late response.
    beginning = ->(line) { start(playthrough, line) }
    completion = lambda do |ending|
      flush(playthrough, buffer)
      finish(playthrough, ending)
    end
    Playthrough::Session.new(playthrough).play(
      command, request_token: request_token, on_start: beginning,
               on_finish: completion, on_error: ->(_error) { handled_error = true }
    ) do |chunk|
      buffer << chunk
      flush(playthrough, buffer) if buffer.length >= BATCH_SIZE
    end
  rescue StandardError => e
    # Only finding the game or acquiring the lock can fail outside the
    # session's guarded callback. Never broadcast a second terminal surface
    # after unlock.
    unless handled_error
      ending = Playthrough::Session.ending_for(e, playthrough_id: playthrough_id)
      finish(playthrough, ending) if playthrough && ending
    end
  end

  private

  def start(playthrough, command)
    Turbo::StreamsChannel.broadcast_replace_to(
      playthrough, target: "turn_log", partial: "playthroughs/turn_log",
      locals: { playthrough: playthrough, command: command }
    )
  end

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
  #
  # What the player is told -- a setup notice, the crisis notice, a refusal --
  # is `Playthrough::Session`'s `Ending`; this only renders it.
  def finish(playthrough, ending)
    Turbo::StreamsChannel.broadcast_replace_to(
      playthrough,
      target: "turn_log",
      partial: "playthroughs/turn_log",
      locals: { playthrough: playthrough.reload, command: nil, error: ending.error,
                safety_notice: ending.safety_notice, refusal: ending.refusal }
    )
  end

  # THE EVENT-ROW ADAPTER, for a turn an API client asked for. It writes what
  # the protocol's events endpoint streams -- `started`, `prose` in the same
  # batches the cable gets, `glance` when the engine's facts have changed by
  # the time prose starts, and `finished` with the saved record -- as numbered
  # `Playthrough::TurnEvent` rows on the turn's own command, so a client that
  # drops its connection resumes from `Last-Event-ID`. What each event says is
  # `Protocol::V1`'s; how the turn went is `Playthrough::Session`'s.
  class Events
    def initialize(playthrough_id, line, request_token)
      @playthrough_id = playthrough_id
      @line = line
      @request_token = request_token
      @buffer = +""
      @finished = false
    end

    def perform
      @playthrough = Playthrough.find(@playthrough_id)
      @session = Playthrough::Session.new(@playthrough)
      @command = @playthrough.commands.find_by!(request_token: @request_token, command: @line)
      handled = false
      @session.play(@line, request_token: @request_token, on_start: ->(_line) { start },
                           on_finish: ->(ending) { finish(ending) },
                           on_error: ->(_error) { handled = true }) { |chunk| prose(chunk) }
    rescue StandardError => e
      return if handled || @command.nil? || @finished

      finish(Playthrough::Session.ending_for(e, playthrough_id: @playthrough_id))
    end

    private

    def start
      @opening = Protocol::V1.glance(reader.glance)
      append("started", turn: Protocol::V1.id(@command), line: @line)
    end

    def prose(chunk)
      unless @told_glance
        @told_glance = true
        now = Protocol::V1.glance(reader.glance)
        append("glance", turn: Protocol::V1.id(@command), glance: now) if now != @opening
      end
      @buffer << chunk
      flush if @buffer.length >= BATCH_SIZE
    end

    def flush
      return if @buffer.empty?

      append("prose", turn: Protocol::V1.id(@command), text: @buffer.dup)
      @buffer.clear
    end

    def finish(ending)
      return if @finished

      @finished = true
      flush
      append("finished", Protocol::V1.finished(reader, @command, ending))
    end

    # A SECOND HOLD ON THE SAME GAME, for reading. `Session#glance` reloads the
    # playthrough it holds, and the one the turn is playing must not be
    # reloaded under it mid-turn.
    def reader = Playthrough::Session.new(Playthrough.find(@playthrough_id))

    def append(kind, data) = Playthrough::TurnEvent.append!(@command, kind, data.as_json)
  end
end
