# Turns one line of typed input into something the game loop can act on.
#
# One schema'd `BaseAgent` call, and it is deliberately the cheapest call in the
# app: it runs on every single turn, in front of the narration the player is
# actually waiting for, so it gets the room's name, its exits and its cast and
# nothing else. No universe, no lore, no story summary -- none of that changes
# whether "go down the stairs" was a move.
#
# Resolution back to records lives here rather than in `Playthrough::Turn`,
# next to the candidate list it is the inverse of. The two have to agree about
# what counts as an exit and who counts as present; splitting them across two
# classes is how they stop agreeing.
#
# THIS CLASS HAS AN INSTRUMENT NOW, and it is the only place to read what it
# gets right: `rake eval:classifier` replays 339 hand-labelled typed lines
# through it against fixed seeded positions and reports an accuracy per intent,
# the closed-set misses, `also_named` precision and recall and refusal-kind
# agreement, each with its band across repetitions. `rake eval:classifier_offline`
# is the same corpus with no model at all -- what a call here is bought against.
# `Playthrough::Drift` and `Playthrough::Overreach` count this class's misses
# and NEITHER KNOWS WHETHER THE ANSWER WAS RIGHT; the bench is what does. See
# `Eval::Classifier` and EVALUATION.md -> The classifier bench. Anything that
# changes `INSTRUCTIONS` below is a change to judge with
# `rake eval:classifier_compare`, not by reading one turn.
#
# THE SYSTEM ONE CASCADE IS THE ENGINE'S. A turn the game plays reads its line
# through the Rust engine (`renderedstep_engine::classifier`): System One first
# where either `TYPESAFE_API_KEY` or `OPENROUTER_API_KEY` is in the environment,
# and the call below where it escalates or fails. The classifier bench reads its
# corpus the same way (`Playthrough::Requests.read_line`). This class is the
# Ruby reference loop's reader, which the test suite plays, and it reads with
# the model call alone; `#resolved_by` is always `model`. `PATHS` still names
# every reader a scene can record.
class Playthrough::Classifier
  # What one line of player input turned out to be.
  #
  # `destination` and `speaker` are RECORDS, and at most one of them is ever
  # set. A classification the loop cannot act on -- "go north" in a room with
  # no northward exit, "talk to the ghost" with nobody here -- leaves both nil
  # and keeps `action`, so the loop narrates the attempt instead of pretending
  # it worked. Being unable to do a thing is part of the game; silently doing a
  # different thing is not.
  # `item` carries both directions: what a `take` resolved to on the floor and
  # what a `drop` resolved to in the player's hands. Which way it moves is the
  # action's business, not the record's -- see `Playthrough::Turn`.
  # `also_named` is the ONE record the line named that this turn is not acting
  # on -- see `Playthrough::IntentSchema` for why one and not a list. It is
  # evidence and never a target: nothing in the loop reads it to do anything,
  # only to say what it left undone.
  # `unknown_action` is the word the model answered when it answered outside
  # `Playthrough::IntentSchema::INTENTS` and still named a record -- nil every
  # other time, which with a compliant provider is always. See `#unreadable?`.
  # `at` is THE ONE THING A LINE IS DIRECTED AT while it acts on something else,
  # and it is set by exactly one action: a `throw`. A throw is one act with an
  # object and an indirect object -- `throw the slate at Neb Halloran` -- which
  # is the first act in the game that legitimately names two records, and
  # neither `#subject` nor `#also_named` means that (`also_named` is the
  # opposite of a second target: it is the name a turn is NOT acting on). Two
  # readers write it: `Playthrough::Grammar#read_throw` behind a slash, and
  # `#build_intent` out of the model's `thrown_at`.
  # `physical` binds one closed attempt token to its engine-owned records.
  # It is internal only: the model still returns intent, target, also_named.
  Intent = Data.define(:action, :destination, :speaker, :item, :at, :also_named, :unknown_action, :physical) do
    # Defaulted so a caller naming only what it resolved reads the way it
    # means -- `Intent.new(action: :other)` is a turn that reached for nothing.
    def initialize(destination: nil, speaker: nil, item: nil, at: nil, also_named: nil, unknown_action: nil, physical: nil, **rest) = super

    def move? = action == :move
    def talk? = action == :talk
    def take? = action == :take
    def drop? = action == :drop
    def examine? = action == :examine

    # THE SEVENTH INTENT, AND SINCE COMBAT SLICE 8 A MODEL CAN ANSWER WITH IT.
    # `attack` is in `Playthrough::IntentSchema::INTENTS` now, so this is true of
    # an `Intent` the FIXED GRAMMAR built (behind a slash, or in
    # `rake game:mechanics`) AND of one the classifier read out of a free line --
    # "hit him", "go for the Ringer". Both resolve against the same closed set,
    # `#offered_for(:attack)`, which is everybody standing here: the captain's
    # ruling of 2026-09-05, *"anyone can be attacked"*.
    #
    # THE ENUM WIDENING IS WHAT THE INSTRUMENTS HAVE TO BE RE-READ AFTER. It put
    # `attack` in `Playthrough::Drift::ACTIONS` and through it in
    # `Playthrough::Overreach::ACTIONS`, so both counters can now be written by a
    # line neither could produce before; a baseline taken before slice 8 and one
    # taken after are not the same denominator. See those two classes' headers.
    def attack? = action == :attack

    # THE LAST WORD IN `Playthrough::IntentSchema::INTENTS`, and the one that
    # names two records: the thing (`#item`) and what it was aimed at (`#at`).
    def throw? = action == :throw

    # The record the loop acts on, whichever kind it turned out to be. There is
    # at most one, by construction -- and on a throw it is the THING THROWN and
    # not what it was aimed at, because the thing is the record that moves (the
    # shape `take` and `drop` already have). What it was aimed at is `#at`, and
    # what the throw COST is a `Playthrough::Blow` row.
    def subject = physical&.subject || destination || speaker || item

    # THE OVERREACH CASE. The line named two things the closed sets both know,
    # and one act is all a turn is. It used to do the first and say which one it
    # had left; on the captain's ruling of 2026-09-04 the whole line is refused
    # and the player is asked to pick one -- see `Playthrough::Refusal`. Only
    # ever true for an action that resolved: a reach that found nothing at all is
    # drift, and a different fact about the world.
    def named_more_than_one? = !also_named.nil? && !subject.nil?

    # THE DRIFT CASE. The player was reaching for something -- a way out, a
    # person, a thing to pick up -- and the closed set the app built had
    # nothing in it that matched. The turn still narrates, and the reach is
    # counted: see Playthrough::Drift.
    def reached_for_nothing?
      Playthrough::Drift::ACTIONS.include?(action.to_s) && subject.nil?
    end

    # THE ANSWER THE APP CANNOT READ. `intent` is a closed enum, so this should
    # never be true; it is a branch rather than a coercion because the coercion
    # read an out-of-table answer as `other`, threw the record it named away and
    # narrated the raw line -- a provider ignoring the table looked exactly like
    # a player musing about the weather.
    def unreadable? = !unknown_action.nil?

    # WHETHER THE ENGINE WILL PLAY THIS LINE AT ALL, and the captain's ruling of
    # 2026-09-04 is these predicates in this order. A refused line does
    # nothing: `Playthrough::Turn#play` stops before any branch and
    # `Playthrough::Mechanics#act` before any write, and the player is answered
    # by `Playthrough::Refusal` -- the app's own words, no narrator, no model
    # call. Read that class's header for the shapes and for what is deliberately
    # NOT refused.
    # THE LINE THAT NAMED A THING THAT DOES NOT MOVE. Taking or throwing
    # something whose `Item::BULK` has no penalty in it is not a hard lift: it
    # does not move. No die is rolled, no row moves and no story time is spent,
    # which is exactly the shape of a line the engine will not play. It is a
    # fact about the OBJECT rather than about the reading, which is why it is
    # its own predicate and its own `Playthrough::Refusal` shape.
    #
    # An unknown bulk lands here too, because `Item#bulk_penalty` answers nil
    # for a key the engine has no table for -- the safe reading of a word that
    # came from somewhere other than the engine is that the thing does not move.
    # `rake game:doctor` names the row (`item_with_an_unknown_bulk`).
    def throws_the_immovable? = throw? && !item.nil? && !item.throwable?
    def takes_the_immovable? = take? && !item.nil? && !item.throwable?
    def moves_the_immovable? = throws_the_immovable? || takes_the_immovable?

    # A THROW WITH ONE OF ITS TWO RECORDS MISSING: the thing named nothing in
    # the hands or on the floor, or the aim named nobody here and no way out --
    # a wall, a machine, the room. Nothing was thrown, and the thing stays
    # where it was. Counted by nothing: `Playthrough::Drift::ACTIONS` does not
    # carry `throw`, so neither counter's denominator moved when the word did.
    def throws_at_nothing? = throw? && (item.nil? || at.nil?)

    def refused?
      named_more_than_one? || reached_for_nothing? || unreadable? || throws_at_nothing? || moves_the_immovable?
    end
  end

  # WHICH SLOT AN ACTION'S RESOLVED RECORD LANDS IN, for every reader that
  # builds an `Intent`, so a `take` cannot land in `destination` on one path
  # and not another.
  #
  # `use` is absent and so is `other`: a `use` resolves to a whole closed
  # attempt token in `physical` rather than to a record, and `other` resolves to
  # no record at all and never will.
  SLOTS = {
    move: :destination,
    talk: :speaker,
    take: :item,
    drop: :item,
    examine: :item,
    # THE SAME SLOT AS A `talk` AND FOR THE SAME REASON: both read the cast, and
    # what the line does TO that person is the action, not the slot.
    attack: :speaker
  }.freeze

  # WHICH READER ANSWERED, out of the values `scenes.resolved_by` holds -- the
  # subset of `Playthrough::Grammar::PATHS` this class can produce, and the table
  # that list is built from.
  #
  #   model                     no System One key in this environment. One model
  #                             call, exactly as before any of this existed
  #   typed_model               the cascade answered; neither flag fired
  #   typed_model_escalated     the cascade flagged the line; the model call
  #                             answered it
  #   typed_model_unavailable   the cascade was tried and could not be believed;
  #                             the model call answered it
  #
  # WITH NO FLAG TO READ, THIS COLUMN IS THE ONLY INSTRUMENT. `model` rows on a
  # machine that is supposed to have a key is how a missing or rotted key is
  # noticed; a run of `typed_model_unavailable` is how an outage is noticed.
  # Both are otherwise silent, because the game keeps playing either way.
  PATHS = %w[model typed_model typed_model_escalated typed_model_unavailable].freeze

  # The paths on which the model call actually happened, so a caller that has to
  # know whether there is a conversation to file under this turn can ask rather
  # than compare strings (`Playthrough::Turn#play`, `Playthrough::Mechanics#move`).
  MODEL_PATHS = (PATHS - %w[typed_model]).freeze

  # Resolve the requested intent before asking whether a physical token fits.
  # The initial physical-action candidate made that rule sound universal: it
  # refused reading and putting down, and substituted available targets for
  # absent ones. The unchanged-case comparison and original requests are kept
  # in db/eval/physical-classifier-20260910. The first correction improved the
  # aggregate but still substituted a related exit, person or item, and treated
  # facing an open doorway as crossing it; its measured requests are kept in
  # db/eval/physical-classifier-revised-20260910 as this edit's direct baseline.
  #
  # THE `examine` LINE GAINED "or looking around the place in general", and it is
  # the one deliberate wording change in the System One cascade's ship. The
  # criterion said only "something", an object, while a targetless look at the
  # room is an `examine` in the corpus's own labels and the readers split on
  # exactly that. The SAME words are in the System One request's intent
  # criteria (`playthrough/classifier/request.yml`, the engine's): two readers
  # with two definitions of `examine` would make the escalation itself a source of
  # disagreement, which is the one thing a cascade must not add. Baselined either
  # side on `rake eval:classifier_offline` and `rake eval:prompt`, per
  # EVALUATION.md.
  INSTRUCTIONS = EngineData.fetch("playthrough/classifier").fetch("instructions")

  attr_reader :playthrough

  # WHICH READER ANSWERED THE LAST LINE THIS CLASSIFIER READ -- one of `PATHS`,
  # and nil before `#classify` has run. It is state on the object rather than a
  # second return value because `#classify` returns an `Intent` to five callers
  # and a bench, and widening that contract for a fact two of them need would
  # have been a change everywhere for the sake of one place.
  #
  # `Playthrough::Turn#play` and `Playthrough::Mechanics#classify` are what read
  # it, both to write `scenes.resolved_by`.
  attr_reader :resolved_by

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # Returns an Intent. Raises rather than guessing when the call fails, for the
  # same reason every generator here raises: a swallowed failure reads
  # downstream as the player typing something the game did not understand.
  #
  # The two measurements either side of it -- `Playthrough::Drift` and
  # `Playthrough::Overreach` -- are taken here, off the resolved `Intent`.
  def classify(command)
    exits = exits_here
    cast = characters_here
    items = items_here
    carried = items_carried

    @resolved_by = "model"
    intent = ask_the_model(command, exits, cast, items, carried)

    record_drift(command, intent, exits, cast, items, carried) if intent.reached_for_nothing?
    record_overreach(command, intent) if intent.named_more_than_one?
    intent
  end

  # The ways out of where the player is standing. Stubs are included and that
  # is the point: an exit nobody has walked through is a real Location record
  # with a name, and walking into it is what realizes it.
  def exits_here
    location = playthrough.current_location
    return [] if location.nil?

    location.exits.order(:id).to_a
  end

  # Who the player can speak to, which is whoever `Scene::Generator` says is
  # standing here, minus the player themselves. Asked of the generator rather
  # than worked out again: the arrival narration already told the player who is
  # in the room, and a classifier that disagreed with it would refuse to talk
  # to someone the game just introduced.
  #
  # THE ANSWER IS A RECORD NOW. `Character.present_in(location)` is the closed
  # set, so this is the exact counterpart of `#items_here` reading
  # `Item.lying_in` -- who is here and what is lying here are both one column,
  # read back. It used to be reconstructed from the last scene in this room
  # that had recorded a cast, which meant a room nobody had walked into had
  # nobody in it to talk to. See `Character`'s header.
  #
  # AND IT IS THIS GAME'S ANSWER, through `Playthrough#cast_in`: the world says
  # who is standing here and this playthrough says which of them can still
  # answer. Before that reader existed, `talk to Rowe` on a body this game had
  # killed resolved, reached the exchange (`Playthrough::Turn#converse`), and
  # the corpse replied -- the exact gap `Item.lying_in` had before the item
  # layers split.
  def characters_here
    location = playthrough.current_location
    return [] if location.nil?

    playthrough.cast_in(location) - [ playthrough.story.protagonist ].compact
  end

  # WHAT THE PLAYER CAN PICK UP: the items the records say are lying in this
  # room, IN THIS GAME. Not what anybody here is holding -- taking something off
  # a person is a different act, with somebody on the other side of it who has
  # an opinion, and no record says how that goes.
  #
  # THIS PLAYTHROUGH'S OWN FLOOR, asked of `Playthrough#items_lying_in`, and
  # that is the captain's ruling of 2026-09-04: the world's own row is the
  # template a game copies from, and what a party picks up off the floor is gone
  # from ITS floor and nobody else's. It used to read `Item.lying_in` flat, so a
  # room one player emptied was empty for every other play of that world.
  #
  # An empty list is still a normal answer -- most rooms hold nothing -- but it
  # is no longer the only one a generated room can give. `Item::Registry` writes
  # what is lying here when the room is realized and `Item::Snapshot` copies it
  # into this game, so this set fills itself with no change at this end of the
  # seam.
  def items_here
    playthrough.items_lying_in(playthrough.current_location).to_a
  end

  # WHAT THE PLAYER IS CARRYING, which is the closed set `drop` resolves
  # against -- and it is a closed set for the same reason `take`'s is: putting
  # something down is a state change, so the app has to know which row moved.
  # A player cannot drop what the records do not say they hold, however
  # confidently a narration once said they picked it up.
  #
  # THE ANSWER BELONGS TO THE PLAYTHROUGH, asked of `Playthrough#carried` --
  # the exact counterpart of `#items_here` reading `#items_lying_in`. It used to
  # be `Item.for_character(playthrough.character)`, and since every playthrough
  # of a story plays the same one protagonist row, one world had one inventory:
  # a second player opened holding the first one's loot.
  def items_carried
    playthrough.carried.to_a
  end

  # THE CLOSED SET AN ACTION READS AGAINST, asked for by the action rather than
  # by picking one of the four readers above.
  #
  # `Playthrough::Turn` and `Playthrough::Mechanics` both need it to say what
  # WOULD have worked when a reach resolved to nothing, and a second copy of
  # this table is how the two ways into the records start disagreeing about what
  # is reachable from here -- which is the same argument that keeps resolution
  # in this class next to the candidate list it is the inverse of.
  def offered_for(action)
    case action&.to_sym
    when :move then exits_here
    when :talk then characters_here
    when :take then items_here
    when :drop then items_carried
    # BOTH ITEM SETS, in the order `#build_intent` resolves an examine against.
    # Looking at a thing does not move it, so neither set is the wrong one.
    when :examine then items_here + items_carried
    # ANYBODY STANDING HERE, AND NOT ONLY THE HOSTILE ONES. The captain's sixth
    # ruling of 2026-09-05: *"anyone can be attacked"* -- so an attack reads the
    # same closed set a `talk` does, and swinging at the landlord is a thing the
    # engine lets you do and then remembers (`Playthrough::Vitals#provoked?`).
    # A separate, narrower set of "people you may hit" would be the app deciding
    # who is a legitimate target, which is a different game.
    when :attack then characters_here
    when :use then physical_actions
    else []
    end
  end

  # THE NAME A RECORD ANSWERS TO, as the player would have typed it: `fullname`
  # for a person, `name` for a place or a thing -- the same two the closed enum
  # is built from, which is why this lives here and not beside each caller.
  # `Playthrough::Mechanics` and `Playthrough::Refusal` both read it.
  def self.label_for(record)
    return nil if record.nil?

    record.respond_to?(:fullname) ? record.fullname : record.name
  end

  # Instructions go through `with_instructions` rather than the constructor to
  # match the two generators -- same shape, same FakeAgent seam in tests.
  #
  # The conversation is filed under this playthrough and thrown away next turn:
  # the classifier is stateless on purpose -- it gets the room's exits and cast
  # and nothing else -- so there is nothing in last turn's exchange worth
  # replaying. What is kept is the record of it, which is the only place the
  # intent LABEL and the raw typed command are written down at all.
  def agent
    @agent ||= BaseAgent.new(purpose: "classifier", playthrough: playthrough)
                        .with_instructions(INSTRUCTIONS)
                        .with_temperature(TEMPERATURE)
  end

  # NONE. This call picks one word from a fixed table and one name from a closed
  # enum; there is nothing here for sampling to improve and one thing for it to
  # ruin, which is that the same line typed twice in the same room resolves the
  # same way. Every other call in the app leaves the provider's default alone --
  # prose is where the wandering is wanted.
  TEMPERATURE = 0.0

  def physical_actions = Playthrough::PhysicalAction.new(playthrough).choices

  def command_prompt(command, exits, cast, items = [], carried = [])
    <<~PROMPT
      ## Where The Player Is
      #{playthrough.current_location&.name || "Nowhere in particular."}

      ## Ways Out
      #{exit_list(exits)}

      ## Who Is Here
      #{cast_list(cast)}

      ## What Is Lying Here
      #{item_list(items, empty: "Nothing. There is nothing here to pick up.")}

      ## What The Player Is Carrying
      #{item_list(carried, empty: "Nothing. The player is carrying nothing at all.")}

      ## Physical Actions (token: one attempt)
      #{physical_actions.map { |choice| "#{choice.token}: #{choice.name}" }.presence&.join("\n") || "None are available."}

      ## The Player Types
      #{command}
    PROMPT
  end

  private

  # THE ONE MODEL CALL THIS CLASS MAKES: the closed enum, the prompt, the
  # schema and the resolution.
  def ask_the_model(command, exits, cast, items, carried)
    answer = agent
      .with_schema(Playthrough::IntentSchema.for(
        exit_names(exits) + cast_names(cast) + item_names(items) + item_names(carried) + physical_actions.map(&:token)
      ))
      .ask(command_prompt(command, exits, cast, items, carried))
      .content

    build_intent(answer["intent"], answer["target"], exits, cast, items, carried, answer["also_named"],
                 answer["thrown_at"])
  end

  # Only ever one slot, and only when the name resolved. `other` carries no
  # target and never will: it falls through to the narrator
  # (`Playthrough::Turn#narrate`), which answers the raw command anyway, so
  # resolving one would be building a seam with nothing on the other side of it.
  #
  # `examine` DOES carry one now, and it is the only action that resolves
  # against BOTH item sets at once. Looking at a thing does not move it, so
  # neither closed set is the wrong one: a note in the player's hands and a note
  # on the floor are both in front of them. The floor comes first, because that
  # is the order the prompt lists them in and the order the engine's `moment`
  # states them to the narrator -- with two things of one name it resolves the
  # nearer one, stably. `Playthrough::Turn#read_item` is what is on the other
  # side of the seam: a readable thing is read out of the records, and anything
  # else narrates exactly as it always did.
  #
  # A `throw` resolves TWO names: `target` against the hands and the floor, and
  # `thrown_at` against the people here and the ways out, people first -- the
  # order `Playthrough::Grammar#read_throw` resolves an aim in. It carries no
  # `also_named`: on a throw the second name in the line is the aim.
  def build_intent(intent, target, exits, cast, items = [], carried = [], also = nil, thrown_at = nil)
    known = Playthrough::IntentSchema::INTENTS.include?(intent)
    action = known ? intent.to_sym : :other
    name = target.to_s

    # AN ANSWER OUTSIDE THE TABLE THAT STILL NAMED A RECORD is unusable, not
    # `other`: there is no branch to send it down and something real was named,
    # so the honest outcome is to refuse and ask again rather than to narrate
    # around it. An out-of-table answer that named `nothing` loses nothing by
    # being read as `other`, and is.
    return Intent.new(action: action, unknown_action: intent.to_s) if !known && named_something?(name)

    if action == :use
      choices = physical_actions
      found = choices.find { |choice| choice.token == name }
      extra = choices.find { |choice| choice.token == also && choice != found }
      extra_record = extra&.subject || (exits + cast + items + carried).find do |record|
        self.class.label_for(record) == also && !found&.records&.include?(record)
      end
      return Intent.new(action: action, physical: found, also_named: extra_record)
    end

    if action == :throw
      aim = thrown_at.to_s.strip
      return Intent.new(action: action, item: find_item(carried + items, name),
                        at: find_character(cast, aim) || find_exit(exits, aim))
    end

    # The closed set this action resolves against, the matcher that reads a
    # name out of it, and which of the Intent's slots the record lands in.
    # `also_named` goes through the same set and the same matcher, because a
    # second, looser way into the records is the thing a closed set exists to
    # prevent.
    set, finder = case action
    when :move then [ exits, :find_exit ]
    when :talk then [ cast, :find_character ]
    when :take then [ items, :find_item ]
    when :drop then [ carried, :find_item ]
    when :examine then [ items + carried, :find_item ]
    # THE SAME SET AS A `talk` AND THE SAME SLOT, which is what makes the loop's
    # dispatch one branch on a resolved person rather than two
    # (`Playthrough::Turn#play`). What the line does TO them is the action.
    when :attack then [ cast, :find_character ]
    else return Intent.new(action: action)
    end

    # The slot comes out of `SLOTS`, which the typed reader also reads, so the
    # two paths cannot disagree about where a resolved record lands.
    slot = SLOTS.fetch(action)
    found = send(finder, set, name)

    Intent.new(
      action: action,
      also_named: also_record(set, finder, also, found),
      **{ slot => found }
    )
  end

  # The second name, or nil. `nothing` and a blank both mean the line named one
  # thing. `other` never reaches here: it resolves to no record at all, so there
  # is no "the other one" for it to have.
  #
  # THE COMPARISON IS BETWEEN RECORDS AND NOT BETWEEN THE TYPED NAMES, because
  # one record answers to more than one name: `#find_character` matches a
  # fullname OR a nickname, so "Halkett Rowe" and "Rowe" are two strings for
  # one person -- and comparing the strings counted them as two things, wrote a
  # `Playthrough::Overreach` row naming him on both sides of it, and told the
  # player a turn had left him undone while he was the one it acted on. Two
  # items of the same name in one room resolve to the same first record for the
  # same reason (see `#find_item`).
  def also_record(set, finder, also, found)
    return nil unless named_something?(also)

    other = send(finder, set, also.to_s.strip)
    other unless other.nil? || other == found
  end

  # Whether an enum slot points at a record at all. `nothing` and a blank both
  # mean it does not, and the schema guarantees it is one of those two or a name
  # something in the room really has.
  def named_something?(value)
    name = value.to_s.strip

    !name.empty? && name != Playthrough::IntentSchema::NOTHING
  end

  def find_exit(exits, name)
    exits.find { |location| SameName.same?(location.name, name) }
  end

  # Either name resolves, because both are in the enum: a player types "talk to
  # Maren" as readily as they type the full name, and forcing the model to
  # translate one into the other is a step it can get wrong for no reason.
  def find_character(cast, name)
    cast.find { |character| SameName.same?(character.fullname, name) || SameName.same?(character.nickname, name) }
  end

  # By name, out of the list that was offered. Two items in one room with the
  # same name are indistinguishable to a player typing the name, so the first
  # is as right an answer as there is -- and `find` on the ordered list makes
  # which one it is stable rather than whatever the database felt like.
  def find_item(items, name)
    items.find { |item| SameName.same?(item.name, name) }
  end

  def exit_names(exits)
    exits.map(&:name)
  end

  def cast_names(cast)
    cast.flat_map { |character| [ character.fullname, character.nickname ] }
  end

  def item_names(items)
    items.map(&:name)
  end

  # The travel method comes along because it is how a player says where they
  # are going: "down the stairs" and "swim across" name an edge without naming
  # the place at the other end of it. It is one enum value, so it costs nothing.
  def exit_list(exits)
    lines = exits.map { |exit| "- #{exit.name}#{travel_note(exit)}" }

    lines.join("\n").presence || "None. The player cannot go anywhere from here."
  end

  def travel_note(exit)
    connection = LocationConnection.find_by(location: playthrough.current_location, connected_location: exit)
    return "" if connection.nil?

    barrier = connection.open_for?(playthrough) ? "" : "; #{connection.barrier == 'keyed' ? 'locked' : 'jammed'}, open before crossing"
    " (#{connection.distance}, #{connection.travel_method}#{barrier})"
  end

  def cast_list(cast)
    lines = cast.map { |character| "- #{character.fullname}#{" (#{character.nickname})" if character.nickname.present?}" }

    lines.join("\n").presence || "Nobody. There is no one here to talk to."
  end

  def item_list(items, empty: "Nothing.")
    lines = items.map { |item| "- #{item.name}" }

    lines.join("\n").presence || empty
  end

  # THE ROW THAT MAKES DRIFT A NUMBER. Written here rather than in
  # `Playthrough::Turn` because this is the only place that knows both halves:
  # that the reach failed, and what was on the table when it did. A turn that
  # asked the loop to remember to count would sooner or later forget.
  #
  # `offered` is the set for the action that was tried, not all three -- the
  # exits are the evidence for a move that found nothing, and the cast is not.
  def record_drift(command, intent, exits, cast, items, carried)
    offered = case intent.action
    when :move then exit_names(exits)
    when :talk then cast_names(cast)
    when :take then item_names(items)
    when :drop then item_names(carried)
    when :attack then cast_names(cast)
    else []
    end

    Playthrough::Drift.record(
      playthrough: playthrough,
      # The narration the player had just finished reading. If a cellar door
      # was invented, this is the scene that invented it.
      scene: playthrough.current_scene,
      location: playthrough.current_location,
      action: intent.action,
      command: command,
      offered: offered.compact,
      story_timestamp: playthrough.story_now
    )
  end

  # THE ROW THAT MAKES ONE-ACT-PER-LINE A NUMBER. Written here for the same
  # reason the drift row is: this is the only place that knows both halves --
  # what the line resolved to, and the thing the same line named beside it.
  # Neither half is a failure, which is why this is a separate table from drift
  # rather than another kind of it. See Playthrough::Overreach.
  #
  # STILL WRITTEN NOW THE LINE IS REFUSED, and from exactly here. The captain's
  # ruling of 2026-09-04 changed what the turn DOES, not what is measured, so
  # the counter is taken before the loop asks whether it will play the line at
  # all -- and `acted` is what the line resolved to rather than what was done to
  # it, which on a refused turn is nothing. See `Playthrough::Refusal`.
  def record_overreach(command, intent)
    Playthrough::Overreach.record(
      playthrough: playthrough,
      scene: playthrough.current_scene,
      location: playthrough.current_location,
      action: intent.action,
      command: command,
      acted: self.class.label_for(intent.subject),
      unacted: self.class.label_for(intent.also_named),
      story_timestamp: playthrough.story_now
    )
  end
end
