# THE ENGINE'S RECORDS AS THE V1 PROTOCOL SPELLS THEM, and nothing else.
#
# docs/protocol/v1.md is the contract and docs/protocol/v1/ its schemas; this
# is the one place the engine's objects become that JSON, so a field is named
# once. It decides nothing: every value is read from `Playthrough::Session`,
# `Playthrough::Glance` or a record the driver handed over. Ids are opaque
# strings, times are ISO 8601, money is a number of US dollars, and no class
# name, table name or Rails type crosses the wire -- a client written against
# the spec must be able to talk to an engine that is not this one.
#
# WITHIN V1 THIS ONLY GROWS. A field may be added; none is renamed, retyped or
# removed. `test/contract/protocol_v1_test.rb` validates what comes out of
# here against the checked-in schemas.
module Protocol::V1
  VERSION = 1
  PROTOCOL = "text-adventure-engine".freeze
  CAPABILITIES = %w[worlds games turns turn_events interruptions spend_limit].freeze
  LOG_TAIL = 20
  ENGINE_NAME = "text-adventure-rails".freeze

  # WHAT A TURN DID, as a closed list a second engine can produce without
  # knowing this one's labels. Keyed by `scenes.resolved_action`; anything the
  # table does not name was narrated. `safety` and `failed` are the two ways a
  # turn ends without a scene of its own.
  OUTCOME_KINDS = {
    "move" => "moved", "talk" => "talked", "take" => "took", "drop" => "dropped", "examine" => "read",
    "attack" => "attacked", "throw" => "threw", "use" => "used", "conclude" => "ended", "ending" => "ended"
  }.freeze
  OUTCOMES = (OUTCOME_KINDS.values.uniq + %w[narrated refused safety failed]).freeze

  module_function

  def id(record) = record.id.to_s

  def service(player)
    allowance = player.allowance
    {
      protocol: PROTOCOL, version: VERSION, capabilities: CAPABILITIES,
      engine: { name: ENGINE_NAME, version: engine_version }, world_schema: world_schema,
      player: {
        name: player.name,
        spend: {
          used_usd: money(allowance.spent), held_usd: money(allowance.reserved),
          limit_usd: money(allowance.limit), turn_reservation_usd: money(Player::Allowance::TURN_RESERVATION_USD),
          period_ends_at: allowance.period_end.iso8601
        }
      }
    }
  end

  def world(story) = { id: id(story), title: story.title.to_s, summary: story.summary.to_s }

  def game(playthrough)
    { id: playthrough.token, world: world(playthrough.story), over: playthrough.over?,
      started_at: playthrough.created_at.iso8601 }
  end

  def screen(session)
    playthrough = session.playthrough
    { game: game(playthrough), glance: glance(session.glance), standing: standing(session.standing),
      log: playthrough.turn_log.last(LOG_TAIL).map { |scene| entry(scene, playthrough) } }
  end

  def entry(scene, playthrough)
    {
      id: id(scene), typed: scene.typed, text: scene.description.to_s,
      talking_to: scene.interactions.map(&:character_name).uniq,
      notices: scene.tolls.select { |toll| toll.playthrough_id == playthrough.id }.sort_by(&:id).map(&:to_s)
    }
  end

  def glance(glance)
    room = glance.room
    {
      room: room && { name: room.name, within: room.within },
      exits: glance.exits.map { |exit| { name: exit.name, written: exit.written, open: exit.open } },
      people: glance.people.map do |person|
        { name: person.name, condition: person.condition, foe: person.foe, provoked: person.provoked }
      end,
      lying_here: glance.lying_here.map { |item| { name: item.name } },
      carrying: glance.carrying.map { |item| { name: item.name } },
      condition: glance.condition,
      sheet: glance.sheet,
      next_beat: glance.next_beat,
      story_time: glance.story_time&.iso8601,
      over: glance.over? ? true : false,
      ended: glance.ended,
      verbs: glance.verbs.map { |verb| verb(verb) }
    }
  end

  # `word` is what follows the slash for this verb, and `lines` -- for `use`
  # alone, whose targets are attempts rather than names -- the line that plays
  # each target, in the targets' order. Both are the engine's, never a copy.
  def verb(verb)
    {
      name: verb.name.to_s, available: verb.available?, reason: verb.reason,
      targets: verb.targets.map(&:name),
      aims: verb.aims&.map(&:name),
      word: verb.word,
      lines: (verb.targets.map(&:line) if verb.name == :use)
    }
  end

  def standing(standing)
    saved = standing.saved_turn
    {
      over: standing.over, ended: standing.ended, busy: standing.busy,
      running_turn: standing.running_turn && id(standing.running_turn),
      saved_turn: saved && { turn: id(saved), line: saved.command, request_token: saved.request_token,
                            action: standing.saved_action.to_s }
    }
  end

  def turn(command) = { id: id(command), line: command.command, request_token: command.request_token }

  # HOW A TURN ENDED, as the closed list the spec names. `ending` is the
  # driver's `Playthrough::Session::Ending`; `outcome` the command's record.
  #
  # A ROUND OF A FIGHT THAT DID NOT END IT has neither: the blows are its
  # record (`Playthrough::Session::Round`), so it is `attacked`, its rolls are
  # its blows and its text is the battle panel's line. It used to read as
  # `failed` with nothing else said, while the blow had landed.
  #
  # AND `failed` IS NEVER SILENT: a failed turn with no notice of the driver's
  # carries the app's failure copy, so a client always has a reason to show.
  def finished(session, command, ending)
    command.reload
    outcome = command.completed? ? command.outcome : nil
    round = session.round_fought(command) if command.completed? && outcome.nil?
    kind = outcome_kind(outcome, ending, round)
    notices = [ ending&.error ].compact
    notices = [ Playthrough::TurnFailureNotice::MESSAGE ] if kind == "failed" && notices.empty?
    {
      turn: id(command),
      outcome: { kind: kind },
      refusal: (outcome.is_a?(Playthrough::Refusal) ? { kind: outcome.kind.to_s, text: outcome.text } : nil),
      resolved_by: (outcome.resolved_by if outcome.is_a?(Scene)),
      rolls: rolls(command, outcome, round: round),
      text: finished_text(outcome, ending, round),
      notices: notices,
      glance: glance(session.glance),
      standing: standing(session.standing)
    }
  end

  def outcome_kind(outcome, ending, round = nil)
    return "safety" if ending&.safety_notice
    return "refused" if outcome.is_a?(Playthrough::Refusal)
    return OUTCOME_KINDS.fetch(outcome.resolved_action.to_s, "narrated") if outcome.is_a?(Scene)
    return OUTCOME_KINDS.fetch("attack") if round

    "failed"
  end

  # EVERY DIE THE TURN THREW, off the records that kept it: each ability check
  # the turn's journal saved (`kind: "check"`, a d20 against its target), then
  # each blow and each hazard toll written against the turn's scene, whose
  # rows keep the damage dealt but not the die that dealt it (`die` and
  # `target` null). In that order, and within each in the order written. A
  # round fought with no Scene reports its own blows.
  def rolls(command, outcome, round: nil)
    checks = checks_in(command.journal.fetch("steps", {})).map do |fields|
      { kind: "check", die: Character::CHECK_DIE, result: fields["die"], target: fields["score"].to_i - fields["penalty"].to_i }
    end
    return checks + round.blows.sort_by(&:id).map { |blow| { kind: "blow", die: nil, result: blow.damage, target: nil } } if round
    return checks unless outcome.is_a?(Scene)

    playthrough = command.playthrough
    blows = playthrough.blows.where(scene: outcome).order(:id).map { |blow| { kind: "blow", die: nil, result: blow.damage, target: nil } }
    tolls = playthrough.tolls.where(scene: outcome).order(:id).map { |toll| { kind: "toll", die: nil, result: toll.damage, target: nil } }
    checks + blows + tolls
  end

  def checks_in(value)
    case value
    when Hash
      return [ value["fields"] ] if value["data"] == "Character::Check" && value.dig("fields", "die")

      value.values.flat_map { |entry| checks_in(entry) }
    when Array then value.flat_map { |entry| checks_in(entry) }
    else []
    end
  end

  def engine_version = ENV["TA_ENGINE_VERSION"].presence || "dev"

  def world_schema = ActiveRecord::Base.connection_pool.migration_context.current_version.to_s

  def finished_text(outcome, ending, round = nil)
    return [ Playthrough::SafetyNotice::HEADING, *Playthrough::SafetyNotice::PARAGRAPHS ].join("\n\n") if ending&.safety_notice
    return outcome.text if outcome.is_a?(Playthrough::Refusal)
    return round.sentence if round

    outcome.description.to_s if outcome.is_a?(Scene)
  end

  def error(code, message) = { error: { code: code, message: message } }

  def money(amount) = amount.to_d.round(6).to_f
end
