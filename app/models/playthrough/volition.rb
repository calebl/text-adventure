# WHAT SOMEBODY WHO IS NOT FIGHTING YOU DOES WHILE YOU ARE DOING SOMETHING ELSE.
#
# THE EXACT TWIN OF `Playthrough::NpcAction`, and everything worth knowing
# about the shape is in that class's header: a choice is an opaque token in a
# table built from THIS GAME's records, the table is rebuilt when the answer
# arrives so a stale token cannot act, and the receipt says which token was
# applied or rejected. Read it before changing this.
#
# WHAT IS DIFFERENT IS WHO ASKS AND WHEN. `NpcAction` is reached only from a
# conversation the player started, so a peaceful person standing in a room was
# inert: the world's whole repertoire between two typed lines was one hostile
# swing (`Playthrough::Riposte`). This runs in the riposte's own slot, on the
# room the turn BEGAN in, for everybody in it who is not fighting -- so a
# clerk can walk out while you read a docket, and you turned your back.
#
# AND WHAT DECIDES IT IS A DIE AND NOT A MODEL. `characters.desire_pursuit` is
# one of seven words (`Character::PURSUITS`); `Playthrough::Volition::Weights`
# is what that word does, in code; `Roll` throws the die off this game's own
# seed. Three consequences, all of them the reason it is built this way:
# `rake game:sweep` can walk it, a turn costs nothing extra, and the same turn
# replays the same decision for ever.
#
# ------------------------------------------------------------------------
# WHAT IS NOT ON THE LIST, AND WHY EACH ONE IS NOT.
#
#   attack     Hostility is a world column no model and no typed line writes,
#              and `EngineSweep::Invariants#hostility_unmoved` asserts it. A
#              pick that could start a fight would put every peaceful world one
#              roll away from a war. Provoking stays the player's and the
#              world's.
#   speak      Speech is prose, and prose is a streamed model call. A roomful
#              of people all choosing to talk is an unbounded number of them on
#              one turn. A character's act is narrated in the third person by
#              the paragraph the turn already pays for, and the player still
#              has a voice by typing at somebody.
#   accept     There is nobody offering. `accept:` is `NpcAction`'s answer to a
#              gift held out during a conversation, and nothing is held out
#              here.
#   ceasefire  Only somebody fighting you can stop, and nobody fighting you
#              gets a volition -- the riposte acted for them.
# ------------------------------------------------------------------------
#
# NO WORLD ROW MOVES. Every effect below goes through a writer that touches
# this playthrough's layer only: `Playthrough::NpcState#location` for a walk
# (never `characters.location_id`, which is shared by every game of this world
# and which `EngineSweep::Invariants#cast_unmoved` holds still), and this
# game's own copy of an item for a transfer.
#
# NO PURSUIT, NO BEHAVIOUR, and it is the most important line in the file.
# Somebody the world has stated no `desire_pursuit` for gets no turn at all --
# no roll, no row, no fact (`Playthrough::Volition::Weights.row_for`). Two
# things follow, and both are the point: a world supplying no parameter gets no
# behaviour invented for it, and every story written before these columns
# existed plays exactly as it did yesterday. That is what lets this ship
# without a backfill, and it is why `rake game:backfill_desires` is opt-in
# rather than something a pull runs for you.
#
# AND IT HAS TO RUN IN BOTH PLACES. `Playthrough::Turn#play_serially` and
# `Playthrough::Mechanics#answered_by_the_world`, in the matching slot, or the
# browser and an offline walk disagree about whether the world moved -- the
# note `Playthrough::Arc`'s header makes about itself. It inherits that slot's
# rules whole: a refused line evaluates nothing, an engine-view instrument
# evaluates nothing, and it runs on every line the engine PLAYED.
#
# WHAT THE NARRATOR IS TOLD IS `playthrough_volitions.fact` AND NOTHING ELSE
# (`Playthrough::Moment#volition_fact`): what somebody DID, never why, and
# never what anybody wants. The four objects of desire reach exactly one
# prompt, which is the character's own sheet.
class Playthrough::Volition
  WAIT = "wait".freeze

  # THE THREE TOKENS THAT NAME A ROW, and the ids in them may be NEGATIVE.
  #
  # `-?` IS NOT DEFENSIVE, IT IS REQUIRED. A staged fixture assigns its rows
  # ids of its own so that a measured request is byte-identical run to run
  # (`Eval::Dialogue::Stage`), and those ids are negative. A pattern that
  # matched only digits built a token out of one, offered it, accepted it back
  # into the closed set and then matched none of the branches below -- so the
  # act was applied with no sentence for it, and the row was refused by its own
  # `fact` validation. The bench found it; nothing in the play path would have.
  MOVE = /\Amove:(-?\d+)\z/
  TAKE = /\Atake:(-?\d+)\z/
  GIVE = /\Agive:(-?\d+)\z/

  # `Playthrough::NpcAction::Result`'s three, and the same three words for the
  # same three outcomes: something moved, the token was not in the freshly
  # built set, or the choice was to change nothing.
  STATUSES = %w[applied rejected none].freeze

  # WHICH OF THE FOUR OBJECTS OF DESIRE THE ACT SERVED.
  #
  # FIVE VALUES AND THIS SLICE WRITES TWO OF THEM, which is worth saying out
  # loud rather than leaving a reader to discover. The engine's own answer is
  # derivable only for the conscious desire, because the conscious pursuit is
  # the only one weighting the roll (`Playthrough::Volition::Weights`); the
  # other three are what a typed judgment will answer when there is one, and
  # the column is the right shape for it now so that the tally a later slice
  # counts does not have to be rebuilt.
  SERVES = %w[conscious unconscious recognized unrecognized none].freeze

  # WHO DECIDED A ROW: the seeded die, a typed System One act, or the die
  # because the System One call failed (its reason is in `system_one_error`).
  DECIDED_BY_DIE = "die".freeze
  DECIDED_BY_SYSTEM_ONE = "system_one".freeze
  DECIDED_BY_DIE_AFTER_FAILURE = "die_after_system_one_failed".freeze
  DECIDERS = [ DECIDED_BY_DIE, DECIDED_BY_SYSTEM_ONE, DECIDED_BY_DIE_AFTER_FAILURE ].freeze

  Result = Data.define(:chosen, :status, :fact, :serves) do
    def applied? = status == "applied"
  end

  attr_reader :playthrough, :character, :location, :round

  def initialize(playthrough, character, location:, round: 1, decided_by: DECIDED_BY_DIE, system_one_error: nil)
    @playthrough = playthrough
    @character = character
    @location = location
    @round = round
    @decided_by = decided_by
    @system_one_error = system_one_error
  end

  # EVERYBODY IN ONE ROOM GETS ONE TURN, IN `id` ORDER -- `Playthrough::Riposte`'s
  # own sentence, and `id` order for its reason: it is the app's answer to "in
  # what order do two records in one room come out" (`Character.present_in`,
  # `Item.lying_in`), reused rather than reinvented.
  #
  # WHO IS LEFT OUT:
  #
  #   the player and the protagonist  their act is the line they typed.
  #   the dead                        `#cast_in` has already dropped them.
  #   anybody fighting the party      the riposte acted for them a moment ago,
  #                                   out of this same set. A foe swings; it
  #                                   does not also wander off.
  #
  # ONE TRANSACTION PER CHARACTER AND NEVER ONE FOR THE ROOM, which is two
  # reasons rather than a preference: a rejected pick for one person must not
  # roll back an applied one for another, and SQLite has one writer -- a
  # transaction held across the whole cast is a lock held across the whole
  # cast, on every turn of every game.
  #
  # IT STOPS THE MOMENT THE GAME IS OVER, which is `Playthrough::Riposte`'s
  # rule: a game that is over is a game nothing will ever change again.
  #
  # AND IT STOPS WHILE A CALLER HAS ASKED IT TO HOLD. `hold` is the engine-level
  # switch evaluation staging engages so a typed setup line can rebuild a
  # labelled position without anybody walking out of the room underneath it --
  # see `Eval::Classifier::Stage`. The live game and `EngineSweep::Walk` never
  # enter it; a global constant or environment flag would reach them.
  #
  # THE TYPED DECISION COMES FIRST AND THE DIE DECIDES WHATEVER IT DID NOT.
  # `line:` is the line the player typed, for the System One state; every row
  # says which of the two decided it (`decided_by`), and a failed call is
  # written onto the rows the die then decided rather than dropped.
  def self.run!(playthrough, location:, round: 1, line: nil)
    return [] if playthrough.nil? || location.nil? || playthrough.over? || held?

    fighting = playthrough.foes_in(location).map(&:id).to_set
    cast = playthrough.cast_in(location).sort_by(&:id).select do |who|
      who != playthrough.character && !who.is_protagonist? && !fighting.include?(who.id) && Playthrough::Volition::Weights.weighted?(who.desire_pursuit)
    end
    typed = Playthrough::Volition::SystemOne.new(playthrough, cast, location: location, line: line).decisions

    cast.filter_map do |who|
      chosen = typed.acts&.fetch(who.id, nil)
      if chosen
        new(playthrough, who, location: location, round: round, decided_by: DECIDED_BY_SYSTEM_ONE).apply!(chosen)
      else
        by = typed.failure ? DECIDED_BY_DIE_AFTER_FAILURE : DECIDED_BY_DIE
        new(playthrough, who, location: location, round: round, decided_by: by, system_one_error: typed.failure).decide!
      end
    end
  end

  # HOLD THE ROOM STILL FOR THE DURATION OF THE BLOCK. Nested holds nest: the
  # outer caller's setting is restored when the inner block returns, so a stage
  # that holds while another helper also holds cannot leak "held" into the live
  # game afterwards. Thread-local because a bench may stage on several workers
  # and one worker's still room must not quiet another's.
  def self.hold
    previous = Thread.current[:playthrough_volition_held]
    Thread.current[:playthrough_volition_held] = true
    yield
  ensure
    Thread.current[:playthrough_volition_held] = previous
  end

  def self.held? = Thread.current[:playthrough_volition_held] == true

  # WHAT THE TOKEN IS A TOKEN OF: `move:412` is a `move`. Public because
  # `Playthrough::Volition::Weights` reads it, and one spelling of a token
  # belongs in one place.
  def self.shape_of(token) = token.to_s.split(":", 2).first.to_s

  # THE CLOSED SET, REBUILT FROM THE RECORDS EVERY TIME IT IS ASKED FOR.
  #
  # `NpcAction#choices`' contract, unchanged: a hash of token to a sentence
  # saying what taking it would do. The sentences are not sent to anybody in
  # this slice -- nothing asks a model to choose -- and they are written anyway,
  # because the typed-judgment slice sends exactly this hash and a set whose
  # descriptions only appeared the day somebody paid for a call would be a set
  # nobody had ever read.
  def choices
    available = { WAIT => "Stay where you are and change nothing." }
    return available unless present?

    location.exits.order(:id).each do |way|
      available["move:#{way.id}"] = "Walk out of #{location.name} to #{way.name}."
    end
    # AND WHAT IS LYING HERE THAT ANYBODY COULD ACTUALLY LIFT.
    #
    # `#throwable?` IS THE ENGINE'S OWN ANSWER TO "DOES THIS MOVE", and it is
    # the one asked here rather than a second reading of `bulk`: the player's
    # own `take` is REFUSED for a thing that does not move
    # (`Playthrough::Classifier::Intent#takes_the_immovable?` ->
    # `Playthrough::Refusal`'s `:immovable`), and a clerk who could walk off
    # with a cast-iron press bolted through the floorboards would be doing what
    # the engine refuses the player. One rule, one predicate, both sides of the
    # counter.
    playthrough.items_lying_in(location).each do |item|
      next unless item.throwable?

      available["take:#{item.id}"] = "Pick up #{item.name} from #{location.name}."
    end
    return available unless player_present?

    playthrough.items_held_by(character).each do |item|
      available["give:#{item.id}"] = "Give #{item.name} to #{playthrough.character.fullname}."
    end
    if following?
      available["stop_following"] = "Stay in #{location.name} when the player leaves."
    else
      available["follow"] = "Accompany #{playthrough.character.fullname} when they leave this room."
    end
    available
  end

  # PICK, THEN APPLY. The pick is a weighted die off this game's own seed and
  # the apply re-checks the set, so the two halves cannot be collapsed: what is
  # offered when the die is thrown and what is offered when the row is written
  # are read twice on purpose.
  # NIL FOR SOMEBODY THE ENGINE HAS NOTHING TO WEIGHT A DIE WITH, and nothing
  # is written for them. `.run!` skips them before they get here; this is the
  # same statement said where it cannot be skipped, so a caller reaching for
  # one person directly gets the same answer the room loop would have given.
  def decide!
    chosen = Playthrough::Volition::Weights.pick(choices.keys, pursuit: character.desire_pursuit, rng: generator)
    return nil if chosen.nil?

    apply!(chosen)
  end

  # EXACTLY ONE TOKEN, AND THE SET IS BUILT AGAIN FIRST.
  #
  # `NpcAction#apply!`'s three rules, kept: a token outside the freshly built
  # set is REJECTED with a receipt saying so rather than silently dropped; the
  # effect and the row are written in one transaction; and nothing outside this
  # method writes a `playthrough_volitions` row.
  def apply!(chosen)
    chosen = chosen.to_s
    return record!(chosen, "none", "#{character.fullname} stayed in #{location.name} and changed nothing.", "none") if chosen == WAIT

    Playthrough::Volition::Record.transaction do
      offered = choices
      unless offered.key?(chosen)
        return record!(chosen, "rejected",
                       "#{character.fullname} was going to act and could not: the act is no longer available. " \
                       "Nothing moved.", "none")
      end

      fact = case chosen
      when MOVE
        walk_to!(Regexp.last_match(1))
      when TAKE
        item = playthrough.items_lying_in(location).find(Regexp.last_match(1))
        item.update!(character: character, location: nil, **Location::Placement.unplaced)
        "#{character.fullname} picked up #{item.name} in #{location.name} and now holds it."
      when GIVE
        item = playthrough.items_held_by(character).find(Regexp.last_match(1))
        item.update!(character: nil, location: nil, **Location::Placement.unplaced)
        "#{character.fullname} handed #{item.name} to #{playthrough.character.fullname}; the player now carries it."
      when "follow"
        state!.update!(following: true, location: playthrough.current_location)
        "#{character.fullname} decided to go with #{playthrough.character.fullname} and will travel with them."
      when "stop_following"
        state!.update!(following: false, location: location)
        "#{character.fullname} stopped accompanying the player and remains in #{location.name}."
      end

      record!(chosen, "applied", fact, serves_for(chosen))
    end
  end

  private

  # A WALK, AND THE ONE COLUMN IT IS ALLOWED TO WRITE.
  #
  # `playthrough_npc_states.location` and NEVER `characters.location_id`: the
  # second is the world layer, shared by every game of this world, and
  # `EngineSweep::Invariants#cast_unmoved` asserts that no typed line moves it.
  # The per-game override already exists, is already resolved by every reader
  # (`Playthrough#location_of`, `#characters_located_in`) and is already written
  # by `follow` -- so a person walking off costs no change to the world layer
  # and no change to any invariant.
  #
  # AND IT ENDS ANY TRAVEL AGREEMENT. Somebody who walks away has stopped
  # accompanying the player, whatever they agreed earlier; leaving the flag set
  # would have `Playthrough#advance_followers_to!` drag them back on the
  # player's next move, which is the agreement outliving the decision.
  def walk_to!(location_id)
    destination = location.exits.find(location_id)
    state!.update!(location: destination, following: false)
    "#{character.fullname} walked out of #{location.name} to #{destination.name} and is no longer in #{location.name}."
  end

  # WHICH OF THE FOUR THE ACT SERVED, derived and never asked.
  #
  # The conscious pursuit is the only one weighting the roll in this slice, so
  # the only honest answer is whether the token the die landed on is one that
  # pursuit pulls toward. A token this person's pursuit has no opinion about
  # serves nothing, and `none` says so.
  def serves_for(chosen)
    row = Playthrough::Volition::Weights.row_for(character.desire_pursuit).to_h
    row.fetch(self.class.shape_of(chosen), 0).positive? ? "conscious" : "none"
  end

  # THE ROW, VALIDATED BEFORE IT IS WRITTEN, and the receipt that names it.
  #
  # `#validate!` in front of `#save!` rather than relying on the save, because
  # the same-story and same-room checks on the record are the ones that say
  # this decision belongs to this world at all, and a caller reading a receipt
  # should never be told something applied by a row that did not save.
  def record!(chosen, status, fact, serves)
    row = Playthrough::Volition::Record.new(
      playthrough: playthrough, character: character, location: location,
      chosen: chosen, status: status, fact: fact, serves: serves, round: round,
      decided_by: @decided_by, system_one_error: @system_one_error
    )
    row.validate!
    row.save!
    Result.new(chosen: chosen, status: status, fact: fact, serves: serves)
  end

  # ONE DIE PER PERSON PER STORY MOMENT. `sequence` is WHICH PERSON, which is a
  # `characters.id`, and `kind:` is what keeps that from colliding with the two
  # other rolls already keyed on a character id -- see `Roll::VOLITION`.
  def generator
    Roll.generator(story: playthrough.story_id, playthrough: playthrough.id,
                   at: playthrough.story_now.to_i, sequence: character.id, kind: Roll::VOLITION)
  end

  # `NpcAction#present?`, one room over: this asks about the room the TURN
  # began in rather than about wherever the party is standing now, because that
  # is the room these people are in.
  def present?
    playthrough && !playthrough.over? && character != playthrough.character &&
      character.story_id == playthrough.story_id && playthrough.cast_in(location).include?(character)
  end

  # WHETHER THE PLAYER IS STANDING HERE, WHICH IS NOT THE SAME AS "THIS IS THE
  # ROOM THE TURN BEGAN IN". A move puts the party somewhere else before this
  # runs, so the people in the room they LEFT have nobody to hand anything to
  # and nobody to agree to travel with. Those three tokens are offered only
  # when there is still somebody there.
  def player_present?
    playthrough.character.present? && playthrough.current_location_id == location.id
  end

  def state = playthrough.npc_states.find_by(character: character)

  def following?
    row = state
    row ? row.following? : character.is_companion?
  end

  def state!
    playthrough.npc_states.find_or_create_by!(character: character) do |row|
      row.location = playthrough.location_of(character) || location
    end
  end
end
