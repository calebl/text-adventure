# One turn of the game: the player types something, the world answers, and the
# playthrough ends up wherever that left them.
#
# This is the loop, and it lives in `app/models` rather than in a controller or
# a rake task on purpose -- there is no `rake game:play` and there is not meant
# to be. The browser is the only front end, and its whole share of the loop is
# handing this class a string and a block to write chunks into.
#
# `move`, `talk`, `take` and `drop` are the four outcomes that do something
# particular, and each of them writes a record before any prose exists. Reading
# is the fifth: an `examine` that resolved to a thing the records say has WRITING
# on it is answered out of `Item#inscription`, which the narrator is handed
# verbatim, so what a note says cannot change between two readings of it. It
# writes a record too, on the one turn where there is not one yet -- see
# `#read_item`.
#
# AND `attack` IS THE SIXTH, and the only one of them that produces no prose at
# all: it writes a `Playthrough::Blow`, the world's live foes answer it in the
# same turn (`Playthrough::Riposte`, step 7 below), and ONE `Scene` closes the
# fight when it ends (`Playthrough::Fight`). It is not one of
# `Playthrough::IntentSchema::INTENTS` -- no model ever answers with it -- so it
# reaches this loop only through `Playthrough::Grammar`, behind a slash.
#
# Everything else -- a look at something with nothing written on it, and anything
# unclassifiable -- falls through to `Scene::Narrator`, which answers the raw
# command in prose. They are told apart so the classification is honest and so
# the branches that need to exist have somewhere to land.
#
# AND A GAME THAT IS OVER, WHICH IS NOT A TURN EITHER: once the player is dead
# `#play` refuses every line in front of everything else it does -- before the
# world catches up, before the snapshot, before the classifier -- so a line
# typed into a finished game costs no model call and writes nothing at all. The
# captain's ruling of 2026-09-04: *"zero hit points means death. Playthrough is
# over and you can't do anything else. You have to start a new playthrough."*
# See `Playthrough::DeathNotice` for the words and `#harm!` for the one
# statement that ends a game.
#
# AND A LAST OUTCOME THAT IS NOT A TURN AT ALL, SINCE 2026-09-04: a line the
# engine will not play. Two acts on one line, a reach that resolved to nothing,
# or a classifier answer the app cannot read are REFUSED whole -- no write, no
# narrator, no `Scene`, no story time -- and `#play` answers with a
# `Playthrough::Refusal` instead of a turn. That is the captain's ruling, and it
# replaced narrating the attempt: a `move` to a door that is not there, a `talk`
# to nobody, a `take` of what is not lying here and a `drop` of what is not
# carried all used to reach `Scene::Narrator` with a fact saying so. A look at
# something with nothing written on it is NOT one of them -- an `examine` is not
# reaching for a record it can miss, so it narrates exactly as it always did.
# Read `Playthrough::Refusal`'s header before changing which lines land there.
#
# AND THE LINE IS NOT ALWAYS READ BY A MODEL, since the captain's ruling of
# 2026-09-04, evening: *"support a slash prefix autocomplete in the text box,
# and resolve those and verb-prefixed lines offline then fallback to the
# model."* A line beginning with `/` goes to `Playthrough::Grammar` first and
# reaches `Playthrough::Classifier` only when the grammar could not resolve the
# noun; a line WITHOUT one is not claimed at all, whatever it begins with, which
# is his ruling of 2026-09-05 -- *"I think we should only auto accept the slash
# commands"* -- after he objected that *"a line beginning with `move`"* should
# not always be a move. `#read_line` is the whole of it, `scenes.resolved_by` is
# which reader answered, and everything below the read is one path either way --
# the grammar builds the same `Intent` the classifier does, on purpose.
class Playthrough::Turn
  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # Plays `command` and returns the Scene it produced, or nil if it produced
  # none, or a `Playthrough::Refusal` for a line the engine will not play at
  # all. Chunks of prose are yielded as they become available: `Scene::Narrator`
  # streams token by token, and a schema'd generator yields its finished
  # paragraph in one piece, because a schema'd call cannot stream (see the
  # comment on `Scene::Narrator`).
  #
  # THE THIRD RETURN IS THE ONE THING A CONSUMER HAS TO KNOW about this method:
  # a refusal is not a turn, so there is no Scene to hand back, and the text is
  # the app's own rather than anything a model wrote. `NarrationJob` shows it
  # where `Playthrough::SafetyNotice` goes and for the same reason.
  def play(command, &block)
    # THE GAME BEING OVER COMES BEFORE EVERYTHING, and it is first for a reason
    # rather than for tidiness: everything below this line costs something. The
    # world catching up writes rows, the snapshot writes rows, and the
    # classifier is a MODEL CALL. A dead playthrough is a playthrough nothing
    # will ever change again, so the honest cost of typing into one is nothing.
    return Playthrough::Refusal.dead(typed: command, character: playthrough.character) if playthrough.over?

    # THE WORLD MOVES FIRST, and it moves whether or not anybody was watching.
    # Every boundary the story's clock has passed since the last turn is applied
    # here, in Ruby, before the player's command is even read -- so the exits
    # the classifier resolves against are tonight's exits and not last night's.
    # One `SELECT MAX` and one row per mechanic when nothing is due, which is
    # almost every turn; zero tokens either way. See WorldMechanic.
    playthrough.story.catch_up_world!

    # AND THIS GAME TAKES ITS SNAPSHOT OF WHERE IT IS STANDING, before the
    # closed sets are read. The world layer is the template and the playthrough
    # owns the instances (the captain's ruling of 2026-09-04), so what is lying
    # here for THIS party has to exist before `Playthrough::Classifier` offers
    # it. Idempotent per template, so this is one query on every turn after the
    # first in a room -- and it is here rather than only on arrival because a
    # room can gain a template, or a person carrying one, long after the party
    # walked in. See `Item::Snapshot`.
    Playthrough::Snapshot.new(playthrough).of_the_room!(playthrough.current_location)

    # THE LINE IS READ, BY THE GRAMMAR FIRST AND BY THE MODEL AFTER. See
    # `#read_line`: `typed` is the line with its slash taken off, and
    # `resolved_by` is which of the two answered.
    typed = Playthrough::Grammar.unslashed(command)
    intent, resolved_by = read_line(command, typed)

    # THE LINE THE ENGINE WILL NOT PLAY, and it stops HERE -- in front of the
    # dispatch, so nothing moves, no `Scene` exists, `Location`'s visit stamp is
    # untouched, the story's clock does not advance and no narrator is asked for
    # a sentence about a turn that did not happen. Two acts on one line, a reach
    # that found nothing, or a classifier answer the app cannot read: the
    # captain's ruling of 2026-09-04. `Playthrough::Refusal` has the three
    # shapes, the wording, and what is deliberately NOT refused.
    return refuse(intent, typed) if intent.refused?

    # WHERE THE TURN BEGAN, and it is read before the dispatch for one reason:
    # a move puts the party somewhere else, and the foes in the room they LEFT
    # act before they go (`Playthrough::Riposte`). You turned your back.
    from = playthrough.current_location

    # WHICH TURN OF A FIGHT THIS IS, read ONCE per turn and off a record. A
    # round is a turn (the captain's call C5), so the player's own blow and
    # every one of the riposte's carry the same number, and `Playthrough::Fight`
    # counts distinct rounds to work out what the fight cost in story time.
    fight = Playthrough::Fight.new(playthrough)
    round = fight.next_round

    scene = if intent.destination
      move_to(intent.destination, &block)
    elsif intent.speaker
      # TWO THINGS A LINE CAN DO TO ONE PERSON, dispatched on the action the way
      # the item branch below dispatches its three. The person is the resolved
      # record either way; the action says whether it is a conversation or a
      # blow.
      #
      # AN ATTACK WRITES NO `Scene` OF ITS OWN, which is why this branch answers
      # nil: the exchange is `playthrough_blows` and ONE Scene closes the fight
      # (`Playthrough::Fight`). See that class for why a Scene per round is the
      # wrong shape.
      intent.attack? ? strike_at(intent.speaker, round: round) : talk_to(intent.speaker, typed, &block)
    elsif intent.item
      # THREE THINGS A LINE CAN DO TO ONE THING. The item is the resolved record
      # in every case; the action says which. Dispatching on the action here
      # rather than on three different fields keeps the branch on a record --
      # `intent.item` is what makes this branch reachable at all.
      #
      # Reading is first because it is the one that changes nothing about where
      # the item is: `take` and `drop` move a row and this only reads one.
      intent.examine? ? read_item(intent.item, typed, &block) : move_item(intent, typed, &block)
    else
      narrate(typed, intent: intent, &block)
    end

    # WHAT THE PLAYER TYPED, AND WHAT THE TURN DID WITH IT, filed under the turn
    # it produced.
    #
    # Here rather than in each of the four branches, and for the same reason
    # the classifier is stamped here: this is the one place that has the
    # command AND the scene for every branch, so a branch added later cannot
    # forget to record it. `Scene#typed` is the durable answer -- it used to be
    # recoverable only by scraping the classifier's stored prompt, which the
    # conversation pruner can still be asked to throw away (Chat::KEEP_TURNS),
    # so the player's own words disappeared from older turns.
    #
    # `resolved_action` and `acted_on` are the same argument taken one step
    # further. `typed` is what the player SAID; the records around it are what
    # the world IS afterwards. Neither is what the turn DID, and without that
    # a check reading a narration against the state before it has nothing to
    # read -- which is why the prose denying a resolved `take` was invisible to
    # every check in `Story::Audit`. See `#resolution_for`.
    #
    # AND WHO WAS IN THE ROOM, on every branch too, which is the third column
    # this one place now owns. `characters_scenes` used to be written by the
    # two branches that happened to have a cast in hand -- an arrival and a
    # talk -- so 184 of the 480 baseline turns of 2026-09-03 had no record of
    # who was present at all, and the one thing the records could say about
    # presence was said on 62% of turns. It is a DERIVED SNAPSHOT now: taken
    # from `Character.present_in` and never the source of it (see
    # `#cast_of`), so the direction the Tide Post defect ran in is reversed.
    scene&.update!(typed: typed, characters: cast_of(scene), resolved_by: resolved_by,
                   **resolution_for(intent))

    # AND THEN THE WORLD ANSWERS: every live foe in the room the turn began in
    # strikes once, in `id` order. It runs on EVERY line the engine played and
    # not only on an attack -- that is what makes a fight a fight, and it is the
    # captain's call C5 (a round is the turn). A refused line never reaches
    # here, because a refused line writes nothing.
    Playthrough::Riposte.new(playthrough, turn: self).run!(location: from, round: round)

    # AND A FIGHT THAT HAS ENDED IS CLOSED, with one `Scene` carrying what the
    # exchange cost in story time. Nil on every turn of every game that is not
    # in a fight, which is almost all of them.
    closing = fight.close!

    # THE CONVERSATIONS THIS TURN HAD, filed under the turn.
    #
    # The classifier is stamped here rather than in its own class because it
    # runs before the branch that produces the scene -- it is the one call every
    # turn makes and the only record of what the player actually typed on a turn
    # that was not a conversation. Every branch stamps its own; see
    # `BaseAgent#attribute_to!`.
    # THE CLASSIFIER ONLY IF IT RAN. A turn the grammar resolved made no call at
    # all, and `BaseAgent#attribute_to!` on an agent that never spoke would file
    # an empty conversation under the turn.
    classifier.agent.attribute_to!(scene) if scene && resolved_by == "model"

    # And the retention cap is applied -- which by default does nothing at all,
    # because nothing is pruned unless `TA_CHAT_KEEP_TURNS` says so. Still called
    # on every turn so that setting it takes effect without a sweep.
    # See Playthrough#prune_conversations!.
    playthrough.prune_conversations!

    # THE CLOSING SCENE IS THE TURN'S ANSWER WHEN THE TURN ITSELF WROTE NONE,
    # which is every attack: `#strike_at` returns nil, so what the consumer is
    # handed is the one Scene that closed the fight, on the turn it ended, and
    # nil on the rounds before it. See `Playthrough::Fight` -- the browser's
    # per-round view is the battle panel, which is a later slice.
    scene || closing
  end

  # THE PLAYER'S OWN BLOW. The record moves first and there is no prose at all:
  # an attack turn writes `playthrough_blows` and nothing else, and the one
  # `Scene` a fight produces is written by `Playthrough::Fight` when it ends.
  #
  # It answers nil deliberately -- there is no Scene for `#play` to stamp with
  # `typed` and `resolved_action`, because the blow row IS the record of what
  # this turn did, and a second one would put engine copy in the column
  # `Story::Audit` reads as narration once per round rather than once per fight.
  #
  # A playthrough with no protagonist has nobody to swing, which nothing in the
  # app produces and `Playthrough#character` is optional enough to allow.
  def strike_at(target, round:)
    striker = playthrough.character
    return nil if striker.nil?

    strike!(striker, target, round: round)
    nil
  end

  # WHICH READER ANSWERS THE LINE, AND THE GRAMMAR GETS FIRST REFUSAL.
  #
  # THE CAPTAIN'S RULING OF 2026-09-04, EVENING, in his words: *"support a slash
  # prefix autocomplete in the text box, and resolve those and verb-prefixed
  # lines offline then fallback to the model."*
  #
  # And then, 2026-09-05, after he objected that a line beginning with `move`
  # might be *"move the lamp off the desk"*: ***"I think we should only auto
  # accept the slash commands."*** He was right and it was worse than the
  # example -- `Playthrough::Grammar::MEANS_SOMETHING_ELSE` has the four
  # measured wrong answers a leading verb alone produced.
  #
  # So A LINE THAT BEGINS WITH `/` is read by `Playthrough::Grammar` before
  # anything is spent on it, and a line without one is not claimed at all
  # whatever its first word. If the grammar RESOLVED A RECORD out of the same
  # closed set the classifier would have been offered, that is the answer and
  # there is no model call at all: the turn saves ~0.6s of the player's time and
  # the app a call, and `Eval::Classifier` measured the verb half at
  # ~0.98 while the TARGET half is where the misses are -- and a target is a
  # match against ONE closed list, which is not a thing a model is needed for.
  #
  # EVERYTHING ELSE GOES TO THE CLASSIFIER, EXACTLY AS BEFORE -- which since the
  # slash became the whole claim is every line a player types without one,
  # measured at 300 of 300 on `Eval::Classifier`'s corpus. And a SLASHED line the
  # grammar could not RESOLVE falls through too -- a name it could not place, a
  # name that matched two records, a verb it does not have. That is deliberate
  # and it is the whole reason the model is still here: every one of those
  # refusals is "I could not read the noun", which is `Playthrough::Classifier`'s
  # job, and taking the grammar's word for it would refuse lines the model plays
  # today. The grammar answers when it is sure and gets out of the way when it
  # is not.
  #
  # ONE LINE ONE ACT SURVIVES THIS, and it survives without a second copy of the
  # rule. The grammar has no `also_named` -- nothing in a fixed verb table
  # produces one -- so a line naming two things out of one closed set would
  # resolve the first and PLAY it. `Playthrough::Grammar::JOINING_WORDS` is what
  # stops that: such a line is handed on, the classifier sees both names, and the
  # refusal and the `Playthrough::Overreach` row happen exactly where they always
  # did. Measured on `Eval::Classifier`'s 300 lines; the constant has the figures.
  #
  # WHAT THIS COSTS, STATED. A grammar-resolved turn writes no
  # `Playthrough::Drift` and no `Playthrough::Overreach` row -- both are taken
  # inside `Playthrough::Classifier#classify`, which did not run -- so it is
  # invisible to those counters and to the classifier bench.
  # `scenes.resolved_by` is what makes that legible instead of silent: every
  # instrument can size its denominator on the turns its reader actually read.
  #
  # Returns `[intent, resolved_by]`, and `resolved_by` is one of
  # `Playthrough::Grammar::PATHS` -- never `engine_view`, because the browser has
  # no engine view: `stats`, `harm 5` and `check the ledger` are not claimed and
  # reach the classifier the way they always did.
  def read_line(command, typed)
    reading = grammar.reading_first(command)
    return [ reading.intent, "grammar" ] if reading&.resolved?

    [ classifier.classify(typed), "model" ]
  end

  # THE REFUSAL, RETURNED RATHER THAN NARRATED.
  #
  # It writes nothing and calls nothing: the whole of a refused turn is the
  # sentence, built out of the closed set the action reads against. The counter
  # row is ALREADY WRITTEN by the time this is reached --
  # `Playthrough::Classifier#classify` takes the `Playthrough::Overreach` or
  # `Playthrough::Drift` measurement before it returns, which is why the ruling
  # cost the instruments nothing.
  #
  # The retention cap is still applied, for the same reason the played path
  # applies it: the classifier had a conversation, and `TA_CHAT_KEEP_TURNS`
  # should take effect on every turn rather than on the ones that landed.
  def refuse(intent, command)
    playthrough.prune_conversations!

    Playthrough::Refusal.for(intent, typed: command, offered: classifier.offered_for(intent.action))
  end

  # THE LOAD-OR-GENERATE SEAM. Everything the project is about is these four
  # lines, and the reason there is no branch in them is the design:
  #
  #   * `Location::Generator#realize!` writes a stub out in full and returns an
  #     already-realized location untouched. So walking somewhere new writes it
  #     once and walking back reads what was written -- the same call, and no
  #     code path that can regenerate a place the player has already seen.
  #   * `Scene::Generator` then narrates arriving, and reads differently the
  #     second time: `Location#last_protagonist_visit` is stamped by `Scene`'s
  #     own after_create, so the room the player left an hour ago is narrated
  #     as coming back rather than as finding. That is what makes a persisted
  #     world feel persisted instead of merely being persisted.
  #   * `Scene::Generator` raises on a stub, which is why realizing is first
  #     and not optional.
  #
  # The playthrough moves only once both calls have landed, so a failed arrival
  # leaves the player where they were rather than in a room with nothing in it.
  def move_to(destination, &block)
    realizer = Location::Generator.new(destination, playthrough: playthrough)
    realizer.realize!

    # REALIZED, THEN COPIED, THEN NARRATED, and the order is the point.
    # `Item::Registry` writes the room's furniture into the WORLD layer as part
    # of realizing it and `Character::Registry` writes its people; this party's
    # own copies of both -- what is lying here, and how much is left of whoever
    # is standing here -- have to exist before
    # `Scene::Generator` builds the moment, or the arrival narration would be
    # written about a room the records say is empty for this game. A room that
    # was already realized copies whatever this playthrough has not seen yet,
    # which is how a second player walks into the office as it was generated.
    Playthrough::Snapshot.new(playthrough).of_the_room!(destination)

    scene = Scene::Generator.new(
      destination, previous_scene: playthrough.current_scene, playthrough: playthrough
    ).generate!
    stand_in!(destination, scene: scene)

    # Realizing the room is the most expensive thing this branch does -- two
    # calls, ~670 output tokens -- and it happens before there is a scene to file
    # it under, so the scene it paid for stamps it here. The arrival's own
    # conversation is stamped by `Scene::Generator`.
    realizer.agent.attribute_to!(scene)

    block&.call(scene.description)
    scene
  end

  # Talking is the other thing a player does with a room, and it is the one turn
  # that keeps two records rather than one:
  #
  #   the Scene        -- the moment, the prose the player reads, the line the
  #                       turn log shows. Its cast is stamped by `#play` from
  #                       the whereabouts records, along with `typed` and what
  #                       the turn did; this branch used to write the
  #                       protagonist and the person spoken to, because that
  #                       cast was the only thing keeping them in the room.
  #                       `Character.present_in` keeps them now.
  #   the Interaction  -- what the character thought and felt on either side of
  #                       answering. The player never sees it; nothing in this
  #                       app had ever written one.
  #
  # The narration streams, because it is prose the player is watching arrive.
  # Blank prose is not a turn: `Scene` validates a description, and a record
  # written from nothing would be a turn the player cannot read.
  def talk_to(character, command, &block)
    agent = InteractionAgent.new(character, playthrough: playthrough)
    exchange = agent.ask(command, &block)
    return if exchange.narration.blank?

    scene = Scene.create!(
      story: playthrough.story,
      location: playthrough.current_location,
      previous_scene: playthrough.current_scene,
      description: exchange.narration,
      summary: "The player spoke with #{character.fullname}. #{exchange.reaction[:action]}".strip,
      story_timestamp: playthrough.story_time_after("conversation")
    )

    # `exchange.reaction` is keyed exactly as `Interaction::Schema` names its
    # fields, which is the same contract the narrator prompt reads it under.
    Interaction.create!(
      **exchange.reaction,
      character: character,
      scene: scene,
      location: playthrough.current_location,
      user_input: command
    )

    agent.attribute_to!(scene)
    playthrough.update!(current_scene: scene)
    scene
  end

  # WHICH WAY THE ITEM GOES. One method because the two are one guarantee: an
  # app that owns picking up but leaves putting down to the narrator asserting
  # it has records that go stale the first time a player sets something on a
  # table. Both directions, or neither is real.
  def move_item(intent, command, &block)
    return drop_item(intent.item, command, &block) if intent.drop?

    take_item(intent.item, command, &block)
  end

  # PICKING SOMETHING UP, and the app does the picking up.
  #
  # THE ORDER IS THE POINT. The row moves first and the prose is written
  # afterwards, which is the opposite way round from a narrator-driven take and
  # is the whole of what makes this ownable: `Item#character` is the app's
  # answer to "does the player have it", written out of the closed set
  # `Playthrough::Classifier` resolved against, so a narration that forgets the
  # compass -- or invents one -- cannot change who holds what. The narrator is
  # then TOLD what already happened and turns it into a sentence. That is the
  # generator/narrator split: the app owns the facts of a scene, the narrator
  # owns the story made out of them.
  #
  # So a failed narration leaves the item taken, and that is the honest way
  # round. `move_to` is the other way -- it moves the playthrough only once
  # both calls land -- because a failed arrival would leave the player in a room
  # with nothing in it. A taken item with no sentence about it is a record the
  # next turn can still read.
  #
  # A playthrough with no character has nobody to NAME as having picked the
  # thing up, so it narrates the attempt instead. Since the inventory moved to
  # `items.playthrough_id` the record itself no longer needs one -- the guard is
  # about the sentence handed to the narrator, and it stays because a fact that
  # says "somebody picked it up" is not a fact. Nothing in the app creates such
  # a playthrough, but `Playthrough#character` is optional and a world can be
  # seeded without a protagonist.
  def take_item(item, command, &block)
    taker = playthrough.character
    return narrate(command, &block) if taker.nil?

    carry!(item)

    Scene::Narrator.new(playthrough).narrate(command, fact: taken_fact(item, taker), &block)
  end

  # PUTTING SOMETHING DOWN, and the app does the putting down.
  #
  # The mirror of `take_item` in every respect that matters: the row moves
  # first, out of the closed set of what the records say the player is carrying,
  # and the narrator is told afterwards. The item lands in the room rather than
  # nowhere -- `Item` is in exactly one place at a time -- so the next turn can
  # pick it up again, and a player who walks away leaves it where they left it.
  # That is what makes an inventory a record of the world and not a note the
  # narrator keeps.
  #
  # A playthrough standing nowhere has no room to put anything down in, so it
  # narrates the attempt. Nothing in the app produces one; `current_location` is
  # optional and a hand-made playthrough can.
  def drop_item(item, command, &block)
    here = playthrough.current_location
    return narrate(command, &block) if here.nil?

    put_down!(item)

    Scene::Narrator.new(playthrough).narrate(command, fact: dropped_fact(item, here), &block)
  end

  # READING WHAT IS WRITTEN ON SOMETHING, and the words come out of the records.
  #
  # THE ORDER IS THE POINT, exactly as it is in `#take_item`: the inscription is
  # a record before there is a sentence about it, and the narrator is then told
  # what the thing says rather than asked what it might say. That is what makes
  # two readings of one note agree -- the second read is a database read, and
  # `#read_fact` quotes the same string both times.
  #
  # A THING WITH NOTHING WRITTEN ON IT NARRATES AS IT ALWAYS DID. `Item#readable?`
  # is the whole gate, and it is set at the moment the thing came to exist
  # (`Item::Registry`, or a seed file) rather than decided here: an examine that
  # resolved to a ward stamp is a look at a ward stamp, and no text is generated
  # for it, ever. The classifier still resolved the record, so the turn is
  # recorded as an `examine` OF that stamp either way -- see `#resolution_for`.
  #
  # `Item::Inscriber` is the one call this branch can make, and only for a
  # readable thing that arrived with no words: a seeded one whose file did not
  # spell them out, or a row older than the columns. It writes them once. On
  # every later reading it makes no call at all.
  def read_item(item, command, &block)
    return narrate(command, &block) unless item.readable?

    inscriber = Item::Inscriber.new(item, playthrough: playthrough)
    words = inscriber.inscribe!

    scene = Scene::Narrator.new(playthrough).narrate(command, fact: read_fact(item, words), &block)

    # The words cost a call on the one turn that wrote them, and that call
    # happens before there is a scene to file it under -- so the scene it paid
    # for stamps it here, the way `#move_to` stamps a realization.
    inscriber.agent.attribute_to!(scene) if scene && inscriber.asked?

    scene
  end

  # THE THREE WRITES THAT MOVE THE WORLD, each one named rather than left inline
  # in the branch above it.
  #
  # They are named because `Playthrough::Mechanics` -- the mechanics-only mode,
  # which bypasses the classifier and the narrator and makes no model call at
  # all -- has to write the world through exactly these statements. A mode built
  # to test movement and possession on their own is worth nothing if it moves
  # the player with a second copy of the line that moves the player: it would
  # then be testing itself. So the line lives here, in the loop that owns it,
  # and both modes call it.
  #
  # Nothing else about these is new. They are the same updates, in the same
  # order relative to the prose, with the same guards in the callers.

  # `scene:` defaults to the one the playthrough is already on, so a caller with
  # no scene to hand -- which is every caller in mechanics mode, where a turn
  # produces no prose -- moves the player without wiping the turn log.
  def stand_in!(destination, scene: playthrough.current_scene)
    playthrough.update!(current_location: destination, current_scene: scene)
  end

  # INTO THE PARTY'S HANDS, which since the captain's ruling of 2026-09-04 is
  # the ABSENCE of a room and a holder on a row that is already this
  # playthrough's own. The party's hands are a place inside a game, not a layer:
  # `playthrough_id` says whose game the row belongs to and it is written here
  # only because it is already true -- the classifier resolved this item out of
  # `Playthrough#items_lying_in`, which offers nothing else.
  #
  # WHAT IT MUST NEVER DO IS MOVE A TEMPLATE. The world's own row stays lying in
  # the room it was seeded or generated in, whoever picks up their copy of it;
  # that is the whole of the ruling. Nothing offers a template to a `take`, so
  # this cannot be reached with one, and `Item` refuses the row either way -- a
  # template with a `template_id` is a copy of a copy.
  def carry!(item)
    item.update!(playthrough: playthrough, character: nil, location: nil)
  end

  # AND BACK ONTO THE FLOOR OF THIS GAME. `playthrough` is deliberately NOT
  # cleared: clearing it is what would turn one player's copy back into one of
  # the world's own rows and put it on every other player's floor. It used to
  # be written nil here, when the column meant "carried"; the drop that
  # exercised it is `lib/engine_sweep/scripts/the-unrecorded-hour-two-players.yml`.
  def put_down!(item)
    item.update!(playthrough: playthrough, character: nil, location: playthrough.current_location)
  end

  # TAKING HIT POINTS OFF A BODY, AND THE ONE PLACE A PLAYTHROUGH ENDS.
  #
  # The damage half of `#carry!`, and closed for the same reason: `Playthrough`
  # has one reader of a condition and this class has the only two writers of one.
  # NO PROSE EVER REACHES THIS -- there is no narrator tool for damage and there
  # is not going to be one (AGENTS.md -> *The standing constraint*). What calls
  # it today is `rake game:mechanics`'s `harm <n>`, which is an engine-view
  # command; what will call it is whatever mechanic the captain rules on next.
  #
  # THE FLOOR IS ZERO AND ZERO IS DEATH. `amount` is clamped rather than allowed
  # to go negative, because "how far past dead" is a number this game has no use
  # for -- the ruling is that zero ends it, with no death saves, no unconscious
  # state and no scars.
  #
  # AND IF THE BODY IS THE PLAYER'S, THE GAME ENDS IN THE SAME STATEMENT. That
  # is the whole of the terminal state: one transaction writes the last hit
  # point and `playthroughs.ended_at` together, so there is no moment in which
  # the records say a player is dead and the game is still running.
  #
  # Returns the `Playthrough::Vitals::Condition` afterwards -- what the caller
  # wants is what is left, and handing back the record would hand back a second
  # writer. Nil for somebody with no stat block: there is no body to hurt, and
  # inventing one to hurt it is what `characters.hit_die` is nullable to avoid.
  def harm!(character, amount)
    row = Playthrough::Vitals.instantiate!(playthrough, character)
    return nil if row.nil?

    Playthrough::Vitals.transaction do
      row.update!(hp_current: [ row.hp_current - amount.to_i, 0 ].max)

      if row.dead?
        # WHAT A BODY LETS GO OF, in the same transaction as the last hit point,
        # so there is no moment in which the records say somebody is dead and
        # still holding things.
        spill!(character)
        playthrough.end! if character == playthrough.character
      end
    end

    row.condition
  end

  # WHAT A BODY LETS GO OF, IN THIS GAME ONLY.
  #
  # The instances in a dead person's hands land on the floor of the room they
  # are standing in, so what they were carrying becomes something the party can
  # pick up -- and THE WORLD'S OWN ROWS STAY EXACTLY WHERE THE FILE PUT THEM,
  # which is the whole of the captain's ruling of 2026-09-04.
  # `Playthrough#items_held_by` reads the playthrough layer and nothing else, so
  # this cannot reach a template, and `EngineSweep::Invariants#world_items_unmoved`
  # proves it after every walk.
  #
  # THE PARTY IS A NO-OP AND HAS TO BE. The protagonist carries nothing through
  # `items_held_by` -- the party's hands are an instance with no room and no
  # holder (`Playthrough#carried`) -- and they stand in no room to drop anything
  # into, so a player dying leaves the game's inventory exactly as it was. There
  # is no restore-from-save and no revival to hand it back to; loot is what a
  # fight the party WON leaves on the floor.
  #
  # It is in the house of `#carry!` and `#put_down!` because it is the same
  # statement they are: the row moves, and nothing else does.
  def spill!(character)
    room = character&.location
    return [] if room.nil?

    playthrough.items_held_by(character).to_a.each do |item|
      item.update!(playthrough: playthrough, character: nil, location: room)
    end
  end

  # ONE BLOW, AND IT ALWAYS CONNECTS.
  #
  # THE CAPTAIN'S CALL C2, measured rather than chosen: damage is one die of the
  # attacker's `hit_die` and there is no roll to see whether it lands. No
  # to-hit, no armour, no critical, no initiative. `data/ta-combat-scout` §7.2
  # has the four candidate rules at 100,000 fights a cell, and the figure that
  # decided it is the last column: with death terminal, a to-hit roll makes the
  # UNDERDOG more likely to win (a level-1 rat kills a level-3 player 14% of the
  # time under an opposed roll and 0.0% under this one), which is the opposite
  # of what levels are for.
  def damage_for(attacker, rng:) = Roll.die(attacker.hit_die, rng: rng)

  # ONE BLOW, WRITTEN DOWN. The damage half of `#carry!`, and the ONE writer of
  # `playthrough_blows`.
  #
  # THE SEED IS THE ROLL'S IDENTITY, which is `Roll`'s whole doctrine, and the
  # one part of it a fight had to be careful about: a fight does not advance the
  # story's clock until it ends (`Playthrough::Fight`), so every blow of one is
  # thrown at the same moment and only `sequence` tells them apart. IT COMES OFF
  # A RECORD -- `Playthrough::Blow.next_sequence`, the count of this game's
  # blows -- and never off a counter in memory, or a fight replayed in a second
  # process would throw different dice and `rake game:sweep` could not assert
  # one. `#play`'s per-turn `round` is a record for the same reason.
  #
  # THE OFFSET IS SO A CHECK AND A BLOW AT ONE MOMENT ARE TWO ROLLS.
  # `Playthrough::Turn#check` seeds on the ability's index in
  # `Character::ABILITIES`, and without this a first blow and a `check strength`
  # at one story moment would be the same die.
  #
  # IT MARKS THE TARGET PROVOKED, in the same transaction, which is the captain's
  # sixth ruling of 2026-09-05: *"anyone can be attacked"*, and being attacked
  # makes somebody this game's foe from the next turn. It is marked whoever
  # struck them -- a mark on the party is inert by construction, because
  # `Playthrough#foes_in` reads `Character.present_in` and the party carries no
  # whereabouts at all.
  #
  # Nil for a body with no stat block, which is `#harm!`'s answer and the same
  # honest nothing: there is no maximum, so there is nothing to take off it.
  # `rake game:doctor` reports the person (`hostile_without_a_stat_block`).
  SEQUENCE_OFFSET = Character::ABILITIES.size + 1

  # `room:` is WHERE THE BLOW LANDED, and it defaults to where the party is
  # standing because that is where all but one of them land. The exception is
  # the riposte on a move: the foes in the room you LEFT act before you go, and
  # by then `playthrough.current_location` is the room you arrived in. The blow
  # belongs to the room it was thrown in, and `Playthrough::Fight` reads that
  # column to know which room the fight is in.
  def strike!(attacker, target, round:, room: playthrough.current_location)
    return nil if attacker.nil? || target.nil? || !attacker.stat_block? || room.nil?

    sequence = SEQUENCE_OFFSET + Playthrough::Blow.next_sequence(playthrough)
    rng = Roll.generator(story: playthrough.story_id, playthrough: playthrough.id,
                         at: playthrough.story_now.to_i, sequence: sequence)
    damage = damage_for(attacker, rng: rng)

    Playthrough::Blow.transaction do
      # NO EARLY RETURN OUT OF THIS BLOCK: since Rails 6.1 a `return` inside a
      # transaction COMMITS it, so a guard written that way would leave the mark
      # behind for a blow that never landed.
      after = harm!(target, damage)
      next nil if after.nil?

      provoke!(target)
      Playthrough::Blow.create!(
        playthrough: playthrough, attacker: attacker, target: target, location: room,
        damage: damage, hp_after: after.hp, round: round, sequence: sequence,
        story_timestamp: playthrough.story_now
      )
    end
  end

  # THIS GAME HAS PICKED A FIGHT WITH SOMEBODY, and it is one writer in one
  # place: `#strike!`, inside the transaction that writes the first blow. The
  # mark is on the per-playthrough row, never on `characters.hostile` -- the
  # world's hostility is the world's, and playthrough A swinging at the landlord
  # must not make him an enemy in playthrough B.
  #
  # Nobody with no stat block is marked: `Playthrough::Vitals.instantiate!`
  # writes no row for them, and there is nothing for a fight to read.
  def provoke!(character)
    Playthrough::Vitals.instantiate!(playthrough, character)&.provoke!(playthrough.story_now)
  end

  # PUTTING THEM BACK, and the mirror of `#harm!` in every respect but one: IT
  # NEVER RAISES THE DEAD. A body at zero stays at zero, because death is
  # terminal -- the captain's ruling of 2026-09-04 -- and a mend that revived
  # somebody would be building the restore-from-save he deferred, one row at a
  # time and by accident.
  #
  # The ceiling is `Character#max_hp`, so a mend past full is full: a body
  # cannot hold more than the template says it can, which is the same statement
  # `Playthrough::Vitals` refuses to save a row against.
  def mend!(character, amount)
    row = Playthrough::Vitals.instantiate!(playthrough, character)
    return nil if row.nil?
    return row.condition if row.dead?

    row.update!(hp_current: [ row.hp_current + amount.to_i, character.max_hp ].min)
    row.condition
  end

  # ONE ATTEMPT AT SOMETHING, ROLLED FROM THIS GAME'S OWN SEED, and it writes
  # NOTHING. `Character#check` is the kernel -- d20-under the ability, the
  # penalty subtracted from the target -- and this is where the generator it
  # needs is built, beside `#harm!` and `#mend!` for the same reason those live
  # here: the statement belongs to the turn, and a caller with its own copy of it
  # would be testing itself. `rake game:mechanics`'s `check <ability> [penalty]`
  # is what calls it today; what will call it is whatever mechanic the captain
  # rules on next.
  #
  # THE SEED IS THE ROLL'S IDENTITY, which is `Roll`'s whole doctrine: which
  # world, which game, where the STORY's clock stood, and which roll within that
  # moment. So one ability checked twice at one story moment is ONE roll and
  # comes up the same die -- the property that lets `rake game:sweep` assert a
  # check outcome offline -- and the three abilities are three rolls because
  # `Character::ABILITIES`'s index is the sequence.
  #
  # THE PENALTY IS NOT IN THE SEED, deliberately: it moves the TARGET and not the
  # die, so `check strength` and `check strength 4` at one moment throw the same
  # d20 at two different numbers. That is the kernel's shape read back out of it.
  #
  # Nil for somebody with no abilities, which is `Character#check`'s answer and
  # the same honest nothing `#harm!` gives a body with no stat block.
  def check(character, ability, penalty: 0)
    return nil if character.nil?

    # A name outside `Character::ABILITIES` falls through to `Character#check`,
    # which raises -- one error about one thing, from the class that owns the
    # list, rather than a second refusal invented here.
    sequence = Character::ABILITIES.index(ability.to_s.to_sym).to_i + 1
    rng = Roll.generator(story: playthrough.story_id, playthrough: playthrough.id,
                         at: playthrough.story.clock.to_i, sequence: sequence)

    character.check(ability, penalty: penalty, rng: rng)
  end

  # What the narrator is told, in the app's own words. Stated as done, because
  # it is: the row is already written by the time this is read.
  # AND WHAT IS WRITTEN ON IT, WHEN THE RECORDS ALREADY HOLD THE WORDS. The turn
  # that produced the whole complaint was a `take`, not a read: *"pickup the
  # note. what does it say?"* is one line, the loop does one act, and the act it
  # did was picking the note up. Handing over the words the records already have
  # costs nothing and closes that case; NOT generating them here is the other
  # half of the rule, because picking a thing up is not reading it and a take
  # must not silently become a model call. A readable thing with no words yet is
  # simply not quoted, and the first read writes them.
  def taken_fact(item, taker)
    "#{taker.fullname} has picked up the #{item.name} and is now carrying it" \
      "#{" -- #{item.description}" if item.description.present?}." \
      "#{" #{written_words_fact(item)}" if item.inscribed?}"
  end

  def dropped_fact(item, here)
    "The #{item.name} is no longer carried: it is now lying in #{here.name}, " \
      "where it stays until somebody picks it up."
  end

  # WHAT IS WRITTEN ON IT, QUOTED, and this is the one fact in the app that is
  # handed over word for word rather than summarised. The records hold the text;
  # a paraphrase of it in the prompt is a paraphrase the player reads, and the
  # next reading would paraphrase the paraphrase.
  #
  # It says the words are fixed as well as saying what they are. That is not a
  # rule the narrator has to obey for the mechanic to hold -- the record is the
  # record whatever the paragraph does with it, and `inscription_misquoted`
  # measures the difference -- it is the cheap half of *inform the prose*.
  #
  # `words` is nil only for a readable thing whose inscription could not be
  # written, which `#read_item` does not reach; the guard is here so the fact is
  # never the string "quoted nothing".
  def read_fact(item, words)
    return nil if words.blank?

    "The #{item.name} has writing on it. #{written_words_fact(item, words)}"
  end

  # THE WORDS THEMSELVES, and this is the one fact in the app that is handed
  # over word for word rather than summarised, from the one place that builds
  # it. The records hold the text; a paraphrase of it in the prompt is a
  # paraphrase the player reads, and the next reading would paraphrase the
  # paraphrase.
  def written_words_fact(item, words = item.inscription)
    "This is exactly what is written on it, word for word: \"#{words}\" -- those are " \
      "the words on it, and they do not change between readings. Quote them as they " \
      "are; do not add to them, and do not write different ones."
  end

  # Everything else. `Scene::Narrator` owns its own turn end to end: it streams,
  # it persists in an `ensure` so a closed tab does not lose the prose, and it
  # sets `current_scene` itself. Movement is the one thing it cannot do, which
  # is why it does not touch `current_location`.
  #
  # `intent` is what the classifier decided, when the caller has one, and it
  # goes along only as the label for the narrator's one line about what kind of
  # turn this is (`Scene::Narrator::DOING`) -- so a look is narrated as a look.
  #
  # WHAT USED TO ARRIVE HERE AND NO LONGER DOES is a reach that resolved to
  # nothing. `#reach_fact` stated it to the narrator as a fact -- the ways out
  # are exactly the ones listed, nothing moved -- because before that the
  # narrator got the bare command and walked the player through a door that did
  # not exist. It was the right answer while a failed reach still had to produce
  # a turn; on the captain's ruling of 2026-09-04 it does not, so the whole
  # branch is gone and `#refuse` answers instead. That also retires its one
  # known cost: a classifier miss on a real exit used to read as prose denying a
  # door that is there, and now nothing is written at all.
  def narrate(command, intent: nil, &block)
    Scene::Narrator.new(playthrough).narrate(command, intent: intent&.action, &block)
  end

  # WHAT THE TURN DID, in the two columns `Scene` keeps it in.
  #
  # The classifier's answer, with one correction: the two branches that resolve
  # a record and then cannot act on it. `take_item` narrates instead when the
  # playthrough has no protagonist to carry anything, and `drop_item` when it is
  # standing nowhere to put anything down in -- nothing in the app produces
  # either, and both are shapes a hand-made playthrough really has. The action
  # is still what the player was doing; the RECORD is dropped, because writing
  # one there would say a row moved that did not, and `Scene#took?` is the seam
  # a check trusts outright.
  #
  # Everything else is recorded exactly as it resolved. An action with no record
  # here is `other`, which resolves to none by design -- a reach that found
  # nothing never reaches this method now, because the turn it would have
  # produced is refused instead (`#refuse`). An `examine` DOES carry one, and
  # keeps it even when the thing turned out to have nothing written on it: the
  # classifier resolved the record, so the turn was a look at THAT stamp.
  # WHO WAS IN THE ROOM WHEN THIS TURN HAPPENED, snapshotted onto the turn.
  #
  # A SNAPSHOT AND NOT THE RECORD. `Playthrough#cast_in` is who is standing
  # there NOW in this game; this is who was there then, and the two are
  # different questions that
  # a single column cannot answer. `Eval::Richness` asks whether a narration
  # named the person who was standing there, `Story::Audit#check_stillness`
  # asks whether anybody was in the room on a run of turns that changed
  # nothing, and both frozen corpora carry the answer beside the prose -- all
  # three read a past moment that the whereabouts column, which has no history,
  # cannot reconstruct. So the join table is KEPT, and only its direction
  # changed: it is written from the records rather than being the only place
  # the records ever lived.
  #
  # AND IT IS THIS GAME'S CAST, not the world's: `Playthrough#cast_in` subtracts
  # whoever this playthrough has killed. Playthrough A recording that it stood
  # in a room with a body it had already put down would be recording a person
  # this game could no longer speak to, while playthrough B goes on meeting them
  # alive -- which is the layer split, and the reason the four readers all come
  # through that one method.
  #
  # Read off `scene.location` rather than `playthrough.current_location`,
  # because on a move the two are the same room only after `#stand_in!` has
  # run, and the cast belongs to the room the scene is in either way.
  def cast_of(scene)
    here = scene.location || playthrough.current_location
    return [] if here.nil?

    playthrough.cast_in(here)
  end

  def resolution_for(intent)
    acted_on =
      if (intent.take? && playthrough.character.nil?) || (intent.drop? && playthrough.current_location.nil?)
        nil
      else
        intent.subject
      end

    { resolved_action: intent.action.to_s, acted_on: acted_on }
  end

  def classifier
    @classifier ||= Playthrough::Classifier.new(playthrough)
  end

  # The fixed grammar, handed this turn's own classifier so the list it matches
  # a typed name against is the same list the model would have been offered.
  # Building either makes no model call.
  def grammar
    @grammar ||= Playthrough::Grammar.new(playthrough, classifier: classifier)
  end
end
