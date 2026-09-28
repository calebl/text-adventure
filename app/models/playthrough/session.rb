# THE ONE WAY INTO THE TURN LOOP, for every front end.
#
# `Playthrough::Turn` is the loop. This is what stands between it and whatever
# the player is looking at: it starts a game, accepts a typed line, plays it,
# and turns how the turn ended into what the player is told. A front end hands
# it a line and a block, and renders what it answers. It owns its layout, its
# input and its transport and nothing else -- so the browser (`NarrationJob`,
# `PlaythroughsController`, `TurnsController`) keeps Turbo, the request and the
# cable, and every decision about the game or the words for an outcome lives
# here, once. What a front end needs and this does not answer is added here,
# never to the front end. `test/models/playthrough/session_test.rb` holds the
# guard: no front end constructs a `Playthrough::Turn` of its own.
#
# WHY "SESSION" AND NOT "DRIVER". It is one player's hold on one playthrough,
# for as long as they are typing into it, which is what a session is in every
# front end it serves; "driver" would describe the code, not the thing. The
# browser's cookie session is a different object and is not touched here.
#
# THE STREAM IS A PREVIEW; THE PERSISTED SCENE IS THE RECORD. The block receives
# prose as it is generated, and nothing more: the narrator's fallback words are
# never yielded, and a rotation yields both attempts' chunks. So a front end
# redraws the finished turn from `playthrough.turn_log` when `on_finish` is
# called, never from what streamed -- the browser does exactly that by
# replacing `#turn_log` from the records.
#
# It is plumbing. It makes no model call of its own and holds no prompt text:
# every call a turn makes is the loop's.
class Playthrough::Session
  # How a Play button ended: a new playthrough, or the sentence that says why a
  # story cannot be played. Exactly one is present.
  Start = Data.define(:playthrough, :refusal) do
    def started? = !playthrough.nil?
  end

  # WHAT THE PLAYER IS TOLD WHEN A TURN ENDS, whichever way it ended. `error` is
  # the app's own copy for a turn that did not finish or had no narrator,
  # `safety_notice` the crisis notice, `refusal` the engine's refusal. All three
  # empty is an ordinary finished turn.
  Ending = Data.define(:error, :safety_notice, :refusal) do
    def self.plain = new(error: nil, safety_notice: false, refusal: nil)
  end

  # WHERE A GAME STANDS BETWEEN TURNS, for a front end that is not looking at
  # the log: whether it is over, whether a turn is still in hand, and the saved
  # turn a player may have to resume or let go (`saved_turn`, a
  # `Playthrough::Command`, and `saved_action`, `:resume` or `:acknowledge`
  # or `:none` -- the same three states the play page draws). `running_turn`
  # is the command still in hand while `busy`, oldest first, so a front end
  # that reconnects mid-turn can find the turn it is waiting on.
  Standing = Data.define(:over, :ended, :busy, :saved_turn, :saved_action, :running_turn)

  # STARTING A GAME, which is the protagonist's arrival in the story's first
  # realized room. A story that has neither cannot be played, and the answer is
  # a refusal with the remedy, never an invented room or an invented person.
  # `player` files the game under whoever may play it over the API; the
  # browser starts games that belong to nobody.
  def self.begin!(story, player: nil)
    location = opening_location(story)
    return Start.new(playthrough: nil, refusal: no_opening_location_message(story)) if location.nil?

    # AND A STORY WITH NO PLAYER CHARACTER IS NOT PLAYABLE EITHER, which is the
    # fix of 2026-09-05. A story whose cast nobody has marked `is_protagonist`
    # answers nil to `#protagonist` (`Story::Doctor`'s `:no_protagonist` has been
    # reporting it all along), and this line used to hand that nil straight to
    # `Playthrough.create!`, which accepts it, because `Playthrough#character` is
    # optional.
    #
    # The game that came out could be walked around and talked in and could not
    # PICK ANYTHING UP: the owner's playthrough 24 took a signet ring and a
    # key, read a perfect paragraph about pocketing both, and left them lying on
    # the floor. The engine refuses those lines now
    # (`Playthrough::Refusal`'s `:unplayable`), and this refuses the game.
    #
    # NO CHARACTER IS CREATED HERE, deliberately. `Story#create_character` is a
    # model call -- it invents a person, a name and a body -- and quietly
    # spending tokens inside a Play button is not a thing a button should do.
    # Where a story GETS its player character is a separate question and a
    # separate change; this only refuses to start a game without one, and says
    # the doctor's remedy for the worlds that already exist.
    return Start.new(playthrough: nil, refusal: no_protagonist_message(story)) if story.protagonist.nil?

    playthrough = Playthrough.create!(
      story: story,
      player: player,
      character: story.protagonist,
      current_location: location,
      current_scene: opening_scene(story, location)
    )

    # THE PROTAGONIST ARRIVES NOW, and this is the only place that can say so.
    #
    # A world's opening arrival is written at world-building time and loaded out
    # of a seed file, so `Scene`'s after_create deliberately does not stamp the
    # visit for it -- stamping then would date the protagonist's presence to
    # whenever the file was seeded, and the first walk back into the opening room
    # would be narrated as a return after however long that was. Nobody was in
    # the room until this request.
    #
    # #73 dropped this call because the scene it created here stamped the visit
    # at exactly this moment, which made the two equivalent. That equivalence
    # does not survive the scene moving into the world, so the explicit stamp
    # comes back. It is also harmless on the fallback path below, where the
    # after_create has already written the same value.
    #
    # Stamped with the STORY's clock rather than with `Time.current`: the
    # protagonist arrives at the moment the story opens, which is the opening
    # arrival's own `story_timestamp`. Reaching for the wall clock here is the
    # defect `Location#time_since_last_visit` used to have, one layer up.
    location.mark_protagonist_visit!(story.clock)

    Start.new(playthrough: playthrough, refusal: nil)
  end

  # WHAT THE PLAYER IS TOLD ABOUT A TURN THAT RAISED, or nil when there is
  # nobody to tell. Exceptions are for the log; the player gets the app's own
  # copy, which makes no claim that effects rolled back.
  def self.ending_for(error, playthrough_id: nil)
    case error
    when ActiveRecord::RecordNotFound
      Rails.logger.info { "Narration skipped: playthrough #{playthrough_id} no longer exists" }
      nil
    when BaseAgent::CrisisResponseError
      Rails.logger.warn { "Narration intercepted: #{error.class}: #{error.message}" }
      Ending.new(error: nil, safety_notice: true, refusal: nil)
    when Playthrough::RustEngine::EngineError
      # The engine's own words: a turn it could not play is never played again
      # on Ruby, so the player is told what stopped it, as it said it.
      Ending.new(error: error.notice, safety_notice: false, refusal: nil)
    when *Playthrough::SetupNotice::FAILURES
      # Nothing here is internal: the install has no model to ask, and whoever
      # is running it can say so in one environment variable. Nothing was
      # narrated either -- the turn stopped at the call -- so this is the
      # unfinished copy and not the one a completed Scene gets.
      Rails.logger.error { "Narration unconfigured: #{error.class}: #{error.message}" }
      Ending.new(error: Playthrough::SetupNotice::UNFINISHED, safety_notice: false, refusal: nil)
    else
      # Ordinary provider failures after a committed action have already
      # completed with factual prose before reaching here.
      Rails.logger.error { "Narration failed: #{error.class}: #{error.message}" }
      Ending.new(error: Playthrough::TurnFailureNotice::MESSAGE, safety_notice: false, refusal: nil)
    end
  end

  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # A typed line, accepted in order. Nothing typed is not a turn, so a blank
  # line answers nil and writes nothing. The request token is what makes a
  # second submit of the same line a second turn rather than a redelivery of
  # the first; see `Playthrough::Command`.
  #
  # A GAME THAT BELONGS TO A PLAYER IS PAID FOR BEFORE IT IS PLAYED. The line is
  # accepted only inside `Player::Allowance#admit!`, which raises
  # `Player::Allowance::LimitReached` -- having written nothing and called
  # nothing -- when one more turn would not fit this month's limit. This is
  # the gate, and it is here, before the job that makes the model calls is
  # ever enqueued.
  def accept!(line, request_token = nil)
    line = line.to_s.strip
    return nil if line.empty?

    token = request_token.presence || SecureRandom.uuid
    return Playthrough::Command.accept!(playthrough, line, token) if playthrough.player.nil?

    playthrough.player.allowance.admit! { Playthrough::Command.accept!(playthrough, line, token) }
  end

  # Plays a line through the one loop. `on_start` receives the line as the turn
  # begins; `on_finish` receives an `Ending` exactly once, when the turn ended
  # either way -- including when it raised, in which case the error still
  # propagates afterwards. The block receives prose chunks (a preview; see the
  # header). `on_error` receives a raised error after it has been told, for a
  # front end that has to know the turn's own ending was already delivered.
  # Returns the turn's outcome.
  #
  # THE RUST ENGINE PLAYS IT, the whole turn, through its extension; see
  # `Playthrough::RustEngine`. A line with no request token is given one, since
  # the engine keeps every line in the submission queue. The Ruby loop plays
  # only where `Playthrough::RustEngine.engine` says it is wanted -- the test
  # suite's default -- and never for a player.
  def play(line, request_token: nil, on_start: nil, on_finish: nil, on_error: nil, &block)
    failure = lambda do |error|
      told = self.class.ending_for(error, playthrough_id: playthrough.id)
      on_finish&.call(told) if told
      on_error&.call(error)
    end
    turn = if Playthrough::RustEngine.engine == :rust
      request_token ||= SecureRandom.uuid
      Playthrough::RustEngine::Turn.new(playthrough)
    else
      Playthrough::Turn.new(playthrough)
    end
    # Every call this turn makes is spent on the game's player; see `Current`.
    Current.set(player: playthrough.player, playthrough: playthrough) do
      turn.play(line, request_token: request_token, on_start: on_start,
                on_finish: ->(outcome) { on_finish&.call(ending(outcome, turn)) }, on_error: failure, &block)
    end
  end

  # WHERE THE GAME STANDS NOW; see `Standing`. Reads only.
  def standing
    playthrough.reload
    saved = Playthrough::Command.resume_target(playthrough)
    running = playthrough.commands.where(status: %w[pending running]).order(:id).first
    action =
      if saved.nil? then nil
      elsif saved.status == "running" && !saved.recoverable?
        saved.journal.blank? ? :acknowledge : :none
      else :resume
      end
    Standing.new(over: playthrough.over?,
                 ended: (Playthrough::EndNotice.for(playthrough).sentence if playthrough.over?),
                 busy: !running.nil?, running_turn: running,
                 saved_turn: saved, saved_action: action)
  end

  # LETTING GO OF AN OLD INTERRUPTED TURN, which is the one thing a player may
  # do to a turn that cannot be resumed. Pre-journal workers left no evidence
  # from which to replay safely, so only an explicit acknowledgement closes
  # one, retaining every saved effect. Taking the game's lock waits for any
  # still-live worker; it cannot discard a recoverable command or a completed
  # turn. Raises RecordNotFound for a command of another game.
  def acknowledge_interruption!(command_id)
    GameLock.synchronize("playthrough", playthrough.id) do
      submission = playthrough.commands.find(command_id)
      if submission.status == "running" && submission.journal.blank?
        submission.update!(status: "failed", error_kind: "interruption_acknowledged")
      end
      submission
    end
  end

  # WHAT THE LAST TURN LEFT THE PLAYER TOLD, rebuilt from its submission row so
  # a reload says what the broadcast said: the refusal, the crisis notice, the
  # setup or failure copy. Only the newest finished submission speaks, and only
  # while nothing is queued behind it -- a later line is its own answer. The
  # engine's own words for a turn it could not play are not stored, so a failed
  # row reads as the app's failure copy. Reads only.
  def last_ending
    latest = playthrough.commands.order(:id).last
    return Ending.plain if latest.nil? || latest.status.in?(%w[pending running])

    case latest.status
    when "failed"
      case latest.error_kind
      when "crisis" then Ending.new(error: nil, safety_notice: true, refusal: nil)
      when "error" then Ending.new(error: Playthrough::TurnFailureNotice::MESSAGE, safety_notice: false, refusal: nil)
      else Ending.plain
      end
    else
      outcome = latest.outcome
      Ending.new(
        error: (Playthrough::SetupNotice.for(outcome.rendering_error) if outcome.is_a?(Scene)),
        safety_notice: outcome.is_a?(Scene) && outcome.safety_notice.present?,
        refusal: (outcome if outcome.is_a?(Playthrough::Refusal))
      )
    end
  end

  # WHAT THE SIDE PANELS SHOW NOW, and which verbs are open from here: a fresh
  # read of the records every call, so a front end asks again after a turn.
  # Reads only; see `Playthrough::Glance`.
  def glance = Playthrough::Glance.new(playthrough.reload)

  private

  # A committed turn whose prose fell back to the engine's own words because the
  # app has no narrator to ask. The turn is finished and its effects stand, so
  # this is not a `TurnFailureNotice` -- but it must not read as a working game
  # either. `Scene#rendering_error` is the receipt the fallback left behind.
  def ending(outcome, turn)
    Ending.new(
      error: (Playthrough::SetupNotice.for(outcome.rendering_error) if outcome.is_a?(Scene)),
      safety_notice: turn.safety_notice,
      refusal: (outcome if outcome.is_a?(Playthrough::Refusal))
    )
  end

  # `game:new` generates the opening location and realizes it, so it is the
  # story's first realized location. Stubs are skipped: they are exits nobody
  # has walked into yet, with a name and a teaser but nothing to read.
  #
  # Returns nil for a story generated before opening locations existed. There
  # is nothing honest to start such a story at -- inventing a room would put
  # the player somewhere the story does not contain -- so `begin!` refuses with
  # an explanation instead.
  def self.opening_location(story)
    story.locations.realized.order(:id).first
  end

  # The first entry in the turn log, and the reason a playthrough does not start
  # with an empty one.
  #
  # A world carries its own opening arrival: `rake game:new` narrates it once
  # with `Scene::Generator.opening`, the exporter writes it into the seed file
  # where it is hand-authored, and the loader loads it. So the normal answer
  # here is to hand the playthrough that Scene -- no model call on the one
  # screen a new player sees first, and real narrated prose rather than a room
  # description standing in for an arrival nobody wrote.
  #
  # Every playthrough of a story starts on the SAME opening Scene, which is what
  # makes it world rather than progress. The turn log walks backwards from
  # `current_scene`, so two playthroughs branching off one opening still each
  # read their own turns; `Scene#next_scenes` is plural for the forward
  # direction that stopped being single-valued.
  #
  # The fallback covers a story built before opening arrivals existed, and the
  # in-memory stories tests build: the room's own description, as #73 wrote it.
  # That scene is per-playthrough progress, so it is NOT marked `is_opening`.
  def self.opening_scene(story, location)
    story.opening_scene || Scene.create!(
      story: story,
      location: location,
      description: location.description,
      summary: "The story opens in #{location.name}.",
      story_timestamp: story.start_time
    )
  end

  def self.no_opening_location_message(story)
    "#{story.title} has no realized opening location -- either it predates " \
      "`rake game:new` generating them, or its opening room is still a stub. " \
      "Generate a new story to play."
  end

  # THE DOCTOR'S REMEDY, IN THE OPERATOR'S OWN TERMINAL. It is the same advice
  # `Story::Doctor`'s `:no_protagonist` finding gives and it is split the same
  # way, because telling somebody to mark a character that does not exist is
  # worse than useless: a `rake game:new` world has no characters at all and
  # needs one made first, while a world that has people needs one of them
  # promoted.
  def self.no_protagonist_message(story)
    remedy =
      if story.characters.none?
        "It has no characters at all -- make one with " \
          "`rails runner \"Story.find(#{story.id}).create_character\"`, then mark them the player with " \
          "`rails runner \"Story.find(#{story.id}).characters.first.update!(is_protagonist: true)\"`."
      else
        "Mark one of its characters the player with " \
          "`rails runner \"Story.find(#{story.id}).characters.first.update!(is_protagonist: true)\"`."
      end

    "#{story.title} has no player character yet, so there would be nobody to play: " \
      "nothing could be picked up or carried in it. #{remedy}"
  end
  private_class_method :opening_location, :opening_scene, :no_opening_location_message,
                       :no_protagonist_message
end
