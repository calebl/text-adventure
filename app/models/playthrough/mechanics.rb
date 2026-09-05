# THE GAME WITH THE PROSE TAKEN OUT, and nothing else taken out with it.
#
# WHY IT EXISTS. A turn that goes wrong could have gone wrong in the classifier,
# in the prose, or in the engine underneath, and the three arrive together. This
# mode removes exactly one of them:
#
#   the classifier   KEPT. Free text goes to `Playthrough::Classifier` and the
#                    intent it resolved is printed -- `understood: take -> ward
#                    stamp` -- so how the typing was read is visible instead of
#                    inferred from what happened next. One model call per
#                    command, which is why this path needs a key.
#   generating the   KEPT. Walking into a stub calls `Playthrough::Turn#move_to`
#   world            whole: `Location::Generator` writes the room, its exits and
#                    the connection rows, and `Scene::Generator` writes the
#                    arrival that stamps the visit and records who is standing
#                    there. The world auto-generates exactly as it does in the
#                    browser, so what is walked is the real world and not a
#                    frozen one.
#   the narration    DROPPED. No `Scene::Narrator`, no `InteractionAgent`, no
#                    character prose, and nothing prose-shaped is printed. What
#                    comes back is the engine's own view of the records after
#                    the command, plus one line saying what changed.
#   what is written  KEPT, because it is a record. `read the folded note` prints
#   on a thing        `Item#inscription` verbatim, with no model call at all: the
#                    words belong to the engine, so this mode can read them out
#                    the way it reads out an exit. What it will NOT do is write
#                    them -- a readable thing nobody has read yet says so
#                    plainly, because generating one is a model call and this
#                    mode never makes one on this branch.
#
# The arrival Scene is still written, because it is world state -- the cast, the
# visit stamp and the story clock all hang off it -- and its prose is simply not
# shown. That is the one place this mode pays for words nobody reads, and it is
# the price of the world moving the way it really does.
#
# WITHOUT A MODEL AT ALL: `model: false`. `Playthrough::Grammar` replaces the
# classifier and a move stands the player in the room without realizing it. That
# is the fallback for a machine with no key and the mode the engine-direct tests
# run in; it is not the default, because a mode that cannot read what was typed
# is testing a smaller thing than the one that can.
#
# THE GRAMMAR IS NO LONGER THIS CLASS'S OWN, since the captain's ruling of
# 2026-09-04, evening: *"support a slash prefix autocomplete in the text box, and
# resolve those and verb-prefixed lines offline then fallback to the model."* It
# lives in `Playthrough::Grammar`, `Playthrough::Turn` reads a SLASHED browser
# line with it first, and this mode reads one with it first too -- in
# `#classify`, in front of the model call -- so `rake game:mechanics` cannot
# report a reading the browser would never have made. A line with NO slash goes
# to the classifier in both, which is his ruling of 2026-09-05: *"I think we
# should only auto accept the slash commands."* `#parse` survives as a private
# hop, because `Eval::Classifier::Offline` reaches for it -- and it has no slash
# rule at all, because `model: false` has nothing to defer to.
#
# WHAT IT WRITES is `playthroughs.current_location_id` and `items.playthrough_id`
# / `items.location_id`, through `Playthrough::Turn#move_to`, `#stand_in!`,
# `#carry!`, `#put_down!` and `#throw_item!` -- the same statements the narrated
# loop moves the world with. A mechanics mode with its own copy of the line that
# moves the player would be testing itself.
#
# WHAT IT IS NOT is `rake game:play`, which is still ruled out. It renders no
# prose and duplicates no part of the loop; the moment it grew a narrator it
# would be the second UI that rule exists to prevent. The dispatch below is the
# one thing it does not share with `Playthrough::Turn#play`, and deliberately:
# that method returns a Scene and streams prose into a block, and this one has
# to be able to say what changed, what was refused and why.
class Playthrough::Mechanics
  # WHAT A REFUSED LINE LEFT BEHIND, said out loud and only in this mode. The
  # counter is what this instrument exists to take, so a refusal that took one
  # should say which table now has a row -- and naming a Ruby class at the
  # person typing is exactly right here and exactly wrong in the browser, which
  # is why `Playthrough::Refusal` does not carry it. `:unreadable` counts
  # nothing: it is a defect on our side, and it goes to the log.
  ROW_WRITTEN = {
    unresolved: "A Playthrough::Drift row was written.",
    named_more_than_one: "A Playthrough::Overreach row was written."
  }.freeze

  # What the classifier mode says instead, since there is no grammar to learn.
  CLASSIFIER_HELP = [
    "Type what you would type in the game. `Playthrough::Classifier` reads it",
    "against the exits, the cast, what is lying here and what you are carrying,",
    "and the line above each read-out says what it resolved to.",
    "",
    "move, take, drop and throw change the world and are shown as a diff.",
    "examine of a thing with writing on it prints what is written, out of the",
    "records. talk, and a look at anything else, are prose -- this mode says so",
    "and changes nothing.",
    "",
    "Walking into a room nobody has written generates it, exactly as the browser",
    "does. `quit` to stop."
  ].freeze

  # WHERE THE PLAYTHROUGH STANDS, read out of the records after the command ran.
  # Every field is a fresh read rather than anything carried along from before
  # the write, so the read-out is what the database says and not what this class
  # believed it had done.
  State = Data.define(:location, :exits, :items_here, :carried, :present, :foes, :provoked, :conditions,
                      :condition, :character, :over, :hazard, :hazards_out) do
    # THE WORLD'S OWN NUMBERS FOR THE PLAYER, one line's worth. Read straight off
    # the character, because that is where they live: a stat block and three
    # abilities are the STORY's (`Character`'s header), and printing them beside
    # a condition that is this GAME's is the layer split on the screen.
    #
    # Empty for a playthrough with no protagonist and for one whose protagonist
    # has neither half of the sheet. Half a sheet prints the half that is there:
    # the two predicates do not merge, so the read-out must not pretend they do.
    def sheet
      return [] if character.nil?

      [
        ("level #{character.level}, d#{character.hit_die}" if character.stat_block?),
        (Character::ABILITIES.map { |ability| "#{ability} #{character[ability]}" }.join(" ") if character.abilities?)
      ].compact
    end

    # `Name is unhurt` per person present, in `#present`'s order. Empty for a
    # room with nobody in it and for anybody with no stat block, which is the
    # same honest nothing `#sheet` gives.
    def others_condition
      present.filter_map { |person| "#{person.fullname} #{conditions[person.id]&.in_words}" if conditions[person.id] }
    end

    def to_s
      [ heading, *rows ].join("\n")
    end

    def heading
      return "nowhere -- this playthrough has no current location" if location.nil?

      "#{location.name} [##{location.id}, #{location.detail_level}]"
    end

    def rows
      [
        [ "exits", exits.map { |exit| "#{exit.name} [#{exit.detail_level}]" }, "no way out of here" ],
        [ "lying here", items_here.map { |item| "#{item.name} [##{item.id}]" }, "nothing to pick up" ],
        [ "carrying", carried.map { |item| "#{item.name} [##{item.id}]" }, "nothing" ],
        [ "present", present.map(&:fullname), "nobody else" ],
        # WHO OF THEM MEANS THE PARTY HARM, out of `Playthrough#foes_in` -- the
        # one reader, so the world's hostility and this game's dead are asked
        # together and never separately. It is a SUBSET of the line above it and
        # printed as its own row rather than as a mark on a name, because
        # "somebody is standing here" and "somebody here is a foe" are two facts
        # and the sweep asserts them as two (`present:` and `foes:`).
        #
        # TWO WAYS ONTO THIS LINE since the captain's sixth ruling of 2026-09-05:
        # the world says somebody is hostile, or THIS GAME provoked them by
        # swinging at them. The row below says which of the two, because
        # "the file made him a monster" and "I hit the landlord" are different
        # facts about the same name.
        [ "foes", foes.map(&:fullname), "nobody is fighting you" ],
        # WHO THIS GAME PICKED THE FIGHT WITH -- `playthrough_vitals.provoked_at`,
        # which is per-playthrough and never touches `characters.hostile`. A
        # subset of the line above it, and empty in every game nobody swung in.
        [ "provoked", provoked.map(&:fullname), "nobody provoked" ],
        # HOW MUCH IS LEFT OF THE PLAYER, out of `Playthrough#vitals_for` -- the
        # same one reader `Playthrough::Moment` states it to the narrator from,
        # so the prose and the read-out cannot disagree about a number. Empty
        # for a playthrough whose protagonist has no stat block, which is the
        # honest nothing rather than an invented "unhurt".
        [ "condition", [ condition&.in_words, ("THIS PLAYTHROUGH IS OVER" if over) ].compact, "no stat block" ],
        # HOW MUCH IS LEFT OF EVERYBODY ELSE STANDING HERE, out of the same one
        # reader (`Playthrough#vitals_for`). `unhurt` is said here where the
        # narrator is not told it (`Playthrough::Moment`), because this is a
        # read-out and a blank line reads as a missing number rather than as a
        # whole body. Bounded by `Character::Registry::MAX_PER_ROOM`.
        [ "others", others_condition, "nobody else" ],
        # WHAT THE WORLD SAYS THIS BODY IS, beside how much is left of it. The
        # five columns are the story's and the condition above is this game's,
        # which is the layer split read out in two adjacent lines -- and
        # `EngineSweep::Invariants#stat_blocks_unmoved` is the assertion that no
        # typed line moves the top one.
        [ "sheet", sheet, "no stat block" ],
        # WHAT THIS PLACE DOES TO SOMEBODY STANDING IN IT, off `locations.hazard`
        # -- the WORLD's, like the sheet above it and unlike the condition. The
        # whole entry is printed rather than the bare key, because the key alone
        # does not say which ability saves or when it is paid, and those are the
        # two things somebody walking a hazardous room needs.
        [ "hazard", [ hazard ].compact, "nothing here hurts you" ],
        # AND THE WAYS OUT THAT COST SOMETHING, which is the whole visible half
        # of the directed edge: a doorway's hazard is on ONE of the two rows, so
        # this lists what leaving THIS WAY costs and says nothing about coming
        # back. An exit that hurts both ways would appear on both rooms' lines
        # and one that hurts one way appears on one, which is the record read
        # straight out.
        [ "hazards out", hazards_out, "every way out of here is free" ]
      ].map { |label, values, empty| format("  %-11s %s", label, values.presence&.join(", ") || empty) }
    end
  end

  # ONE COMMAND AND WHAT IT DID. `understood` is how the command was read --
  # the classifier's resolved intent, or the grammar's -- and it is printed even
  # when nothing happened, because "it did not do what I meant" and "it did not
  # understand me" are different bugs. `change` is the one-line diff of the
  # write; `refusal` is why there was none. Never both.
  #
  # `resolved_by` is WHICH READER ANSWERED -- one of `Playthrough::Grammar::PATHS`,
  # and nil for a read-out nobody typed (the state printed before the first
  # command, and a `reseed:` step). It is on the report rather than derived
  # because the two readers are told apart before anything acts, and
  # `EngineSweep::Expectation`'s `resolved_by:` is how a script pins that a
  # slashed line cost no model call.
  Report = Data.define(:command, :understood, :change, :refusal, :note, :resolved_by, :state) do
    def initialize(resolved_by: nil, **rest) = super

    def refused? = refusal.present?
    def changed? = change.present?

    def to_s
      lines = []
      lines << "  understood: #{understood}" if understood.present?
      lines << "  read by:    #{resolved_by}" if resolved_by.present?
      lines << "  changed:    #{change}" if changed?
      lines << "  refused:    #{refusal}" if refused?
      lines.concat(note.map { |line| "  #{line}" }) if note.present?
      lines << state.to_s
      lines.join("\n")
    end
  end

  attr_reader :playthrough

  # `model:` is the whole switch. True -- the default -- reads the command with
  # `Playthrough::Classifier` and lets a move generate the room it walks into.
  # False makes the mode offline: the fixed grammar, and a move that stands the
  # player in a stub without writing it.
  def initialize(playthrough, model: true)
    @playthrough = playthrough
    @model = model
  end

  def model? = @model

  # Runs one typed line and returns a Report. Raises only what the classifier
  # raises -- a model call that failed is a failed call, not a misunderstood
  # command, and the console says so and keeps going. Everything the player can
  # get wrong is a refusal carrying what would have worked.
  def run(command)
    # THE GAME BEING OVER COMES BEFORE EVERYTHING, exactly as it does in
    # `Playthrough::Turn#play` and out of the same `Playthrough::Refusal`, so
    # this mode and the browser cannot come to disagree about whether a
    # playthrough is finished. Nothing below runs: not the world catching up,
    # not the snapshot, and not the classifier.
    if playthrough.over?
      refusal = Playthrough::Refusal.dead(typed: command, character: playthrough.character)
      return refuse(refusal.reason).with(command: command)
    end

    # THE WORLD MOVES FIRST, exactly as it does in `Playthrough::Turn#play`, and
    # for the same reason: the exits a command resolves against have to be
    # tonight's. No model call, no tokens.
    playthrough.story.catch_up_world!

    # AND THIS GAME TAKES ITS SNAPSHOT OF WHERE IT IS STANDING, exactly as
    # `Playthrough::Turn#play` does and before the same four closed sets are
    # read. The two modes have to agree about what is lying here, and the only
    # way they can is by taking the copy at the same point. No model call.
    Playthrough::Snapshot.new(playthrough).of_the_room!(playthrough.current_location)

    reading = model? ? classify(command) : parse(command)

    # WHERE THE TURN BEGAN, read before anything acts, because a move puts the
    # party somewhere else and the foes in the room they LEFT answer before they
    # go. `Playthrough::Turn#play` reads it in the same place for the same
    # reason.
    from = playthrough.current_location

    # WHICH TURN OF A FIGHT THIS IS, read ONCE and off a record -- the captain's
    # call C5: a round is a turn, so the player's blow and every one of the
    # answers carry the same number. `Playthrough::Fight` is built here rather
    # than in the branch because the same object is asked to close the fight
    # after the answers have landed.
    @fight = Playthrough::Fight.new(playthrough)
    @round = @fight.next_round

    # AND WHERE THIS GAME'S TOLLS STOOD BEFORE THE LINE RAN, so the ones this
    # line caused can be read back off the rows afterwards. A high-water mark
    # rather than a return value, because a hazard is paid in two places -- the
    # arrival, deep inside `Playthrough::Turn#move_to`, and step 7 -- and
    # threading a list back out of the first would put a second copy of the
    # engine's own bookkeeping in this mode. `EngineSweep::Walk` counts the same
    # rows the same way.
    @tolls_before = playthrough.tolls.maximum(:id).to_i

    report =
      if reading.refusal
        refuse(reading.refusal, note: reading.note, understood: reading.understood)
      elsif reading.wound
        wound(reading.wound, reading.understood)
      elsif reading.attempt
        attempt(reading.attempt, reading.understood)
      elsif reading.intent.nil?
        read(note: reading.note)
      else
        act(reading.intent, command, reading.understood, reading.resolved_by)
      end

    report = answered_by_the_world(report, reading, from: from)

    # WHICH READER ANSWERED THE LINE, carried onto the report from the reading
    # rather than worked out again here. `rake game:sweep` asserts it
    # (`resolved_by:`), and it is the same value `Playthrough::Turn` writes to
    # `scenes.resolved_by` -- one vocabulary, `Playthrough::Grammar::PATHS`.
    report.with(command: command, resolved_by: reading.resolved_by)
  end

  # AND THEN THE WORLD ANSWERS, in exactly the place and on exactly the terms
  # `Playthrough::Turn#play` lets it: every live foe in the room the turn began
  # in strikes once (`Playthrough::Riposte`), and a fight that has ended is
  # closed with one `Scene` (`Playthrough::Fight`).
  #
  # ON EVERY LINE THE ENGINE PLAYED, and not only on an attack -- that is what
  # makes a fight a fight, and it is why a walk can assert that looking at the
  # ceiling costs hit points. A REFUSED LINE IS NOT ONE: *"a refused line writes
  # nothing"* is the captain's ruling of 2026-09-04, and a foe acting would
  # write something. It reads `Playthrough::Classifier::Intent#refused?` -- the
  # ENGINE's ruling -- rather than this mode's own report, because `talk` is
  # refused here as prose and a hound does not care that this mode writes none.
  #
  # The report is rebuilt on fresh state, because the read-out printed under a
  # line has to be the records after everything that line caused.
  def answered_by_the_world(report, reading, from:)
    intent = reading.intent
    return report if intent.nil? || intent.refused?

    blows = Playthrough::Riposte.new(playthrough, turn: turn).run!(location: from, round: round)

    # AND THE PLACE ITSELF GETS ITS TURN, beside the foes and after them, on the
    # room the turn began in -- the same call `Playthrough::Turn#play` makes in
    # the same place, so a hazard in this mode and a hazard in the browser
    # cannot come apart. A REFUSED line never reaches here, which is the same
    # ruling the riposte above is under.
    Playthrough::Hazards.new(playthrough, turn: turn).every_turn!(location: from)

    closing = @fight.close!
    # EVERY TOLL THIS LINE CAUSED, read off the rows: the arrival's -- which was
    # paid inside `Playthrough::Turn#move_to`, before this method existed for
    # the turn -- and step 7's, together and in the order they were written.
    taken = playthrough.tolls.where("id > ?", @tolls_before).chronological.to_a
    return report if blows.empty? && closing.nil? && taken.empty?

    notes = blows.map { |blow| "answered: #{blow}" }
    notes.concat(taken.map { |toll| "the world: #{toll}" })
    notes << "the fight is over: #{closing.description}" if closing

    report.with(note: [ *report.note, *notes ], state: state)
  end

  # The read-out with nothing changed. What the console prints before the first
  # command.
  def read(note: nil, understood: nil)
    Report.new(command: nil, understood: understood, change: nil, refusal: nil, note: note,
               resolved_by: nil, state: state)
  end

  def help = read(note: model? ? CLASSIFIER_HELP : Playthrough::Grammar::HELP)

  # THE ENGINE'S VIEW, out of the same four readers `Playthrough::Classifier`
  # offers a model. Rebuilt on every call: `classifier` memoizes nothing it
  # reads.
  def state
    State.new(
      location: playthrough.current_location,
      exits: classifier.exits_here,
      items_here: classifier.items_here,
      carried: classifier.items_carried,
      present: classifier.characters_here,
      # WHO IS FIGHTING THIS PARTY HERE, through the one reader. Read off the
      # playthrough rather than off the classifier: hostility is not one of the
      # closed sets a typed line resolves against -- there is no verb for it yet
      # -- and `#foes_in` is where the world's flag and this game's condition
      # are asked together.
      foes: playthrough.foes_in(playthrough.current_location),
      # WHO THIS GAME PROVOKED, out of `playthrough_vitals.provoked_at`. Read
      # off the same rows `#foes_in` reads and printed apart from them, because
      # a name that is on the foes line because the FILE says so and a name that
      # is there because the player swung at them are two different facts.
      provoked: classifier.characters_here.select { |who| playthrough.provoked?(who) },
      # HOW MUCH IS LEFT OF EVERYBODY PRESENT, keyed by character id, through the
      # one reader. It is what `EngineSweep::Expectation`'s `hp_of:` asserts,
      # off the records rather than off the printed line.
      conditions: classifier.characters_here.to_h { |who| [ who.id, playthrough.vitals_for(who) ] }.compact,
      condition: playthrough.condition,
      # WHO THE PLAYER IS, so the read-out and `EngineSweep::Expectation` can
      # both reach the five columns the WORLD holds about this body -- `#sheet`
      # above prints them and the sweep's `abilities:` asserts them off the
      # record rather than off the screen. Nil for a playthrough with no
      # protagonist, which every reader here already handles.
      character: playthrough.character,
      # WHETHER THE GAME IS OVER, off `playthroughs.ended_at` and not derived
      # from the condition beside it: a playthrough with no protagonist has no
      # condition and could still, one day, be ended by a mechanic nobody has
      # written. It is what `EngineSweep::Expectation`'s `dead:` reads.
      over: playthrough.over?,
      # WHAT THE PLACE ITSELF DOES, and what leaving it costs. Both off the
      # WORLD's rows through the one reader each model owns
      # (`Location#hazard_entry`, `LocationConnection#hazard_entry`), so the
      # read-out and `Playthrough::Hazards` cannot come to disagree about which
      # ability saves.
      hazard: hazard_of(playthrough.current_location),
      hazards_out: hazards_out_of(playthrough.current_location)
    )
  end

  # `flooded d4, strength save, on arrival -- the water takes your legs`, or nil
  # for a room that does nothing to anybody. Every number is off the row.
  def hazard_of(room)
    return nil unless room&.hazardous?

    entry = room.hazard_entry
    "#{room.hazard} d#{room.hazard_die}, #{entry[:save] ? "#{entry[:save]} save" : "no save"}, " \
      "#{entry.fetch(:when).to_s.tr("_", " ")} -- #{entry.fetch(:words)}"
  end

  # ONE LINE PER WAY OUT THAT COSTS SOMETHING, in `Location#exits`' order. The
  # row read is the one that would actually be WALKED -- `from here to there` --
  # which is what makes this the one-way answer rather than the door's.
  def hazards_out_of(room)
    return [] if room.nil?

    room.exits.filter_map do |exit|
      edge = LocationConnection.walked(room, exit)
      next unless edge&.hazardous?

      "#{exit.name}: #{edge.hazard} d#{edge.hazard_die}, " \
        "#{edge.hazard_entry[:save] ? "#{edge.hazard_entry[:save]} save" : "no save"}"
    end
  end

  # The classifier, and in the no-model mode still the classifier -- for its
  # four closed-set readers and nothing else. It is the inverse of
  # `Playthrough::Grammar#resolve`: the list a model is offered is the list a
  # typed name is matched against, and sharing it is what stops the two ways in
  # drifting apart about what is reachable from here. Building one makes no
  # model call; `#classify` is the only method on it that talks to one.
  def classifier
    @classifier ||= Playthrough::Classifier.new(playthrough)
  end

  # THE FIXED GRAMMAR, and it is the same object `Playthrough::Turn` reads a
  # browser line with. It was this class's own private half until the captain's
  # ruling of 2026-09-04, evening; keeping a copy here is what would let the two
  # modes come to read one line two ways. It is handed this mode's own
  # classifier so both are offered exactly the same closed sets.
  def grammar
    @grammar ||= Playthrough::Grammar.new(playthrough, classifier: classifier)
  end

  private

  # --- reading the command --------------------------------------------------

  # THE CLASSIFIER PATH, WITH THE GRAMMAR IN FRONT OF IT. One model call, against
  # the closed sets, and the intent it returns is the same `Intent` the real loop
  # branches on. A reach that resolved to nothing still writes a
  # `Playthrough::Drift` row -- that happens inside `Playthrough::Classifier#classify`
  # and is deliberately not bypassed here, because drift is what this mode is
  # for measuring.
  #
  # THE ORDER IS THE BROWSER'S ORDER, and it is the same order for the same
  # reason: `Playthrough::Turn#play` reads a slashed or verb-first line with the
  # grammar before it spends a call, so this mode has to as well or
  # `rake game:mechanics` would report a reading the browser never made.
  def classify(command)
    return Playthrough::Grammar::Reading.new if command.to_s.strip.empty?

    # THE ENGINE'S OWN INSTRUMENTS ARE NOT CLASSIFIED, in either mode. `help`
    # was always read here rather than sent to a model; `vitals`, `harm <n>` and
    # `mend <n>` join it for the reason `Playthrough::Grammar::ENGINE_VIEW`
    # states -- there is no intent in the closed enum for any of them, so the
    # call could only ever come back `other`, and it would cost a model call to
    # do it. They are read FIRST, so a slash cannot turn one into a fiction verb.
    engine_view = engine_view_reading(command)
    return engine_view if engine_view

    # AND THE LINE THE GRAMMAR CAN ANSWER ON ITS OWN, for no call at all. Only a
    # reading that resolved a record is taken: a refusal here is a name the
    # grammar could not place, which is exactly what the model is bought for.
    offline = grammar.reading_first(command)
    return offline if offline&.resolved?

    intent = classifier.classify(Playthrough::Grammar.unslashed(command))
    Playthrough::Grammar::Reading.new(intent: intent, understood: describe(intent), resolved_by: "model")
  end

  # ONE OF THE ENGINE-VIEW COMMANDS, READ BY THE FIXED GRAMMAR, whichever mode
  # is running. Nil for anything else, which is what sends the line on to the
  # grammar and then to the classifier.
  def engine_view_reading(command)
    reading = grammar.engine_view_reading(command, model: model?)
    return nil if reading.nil?

    return Playthrough::Grammar::Reading.new(note: CLASSIFIER_HELP, resolved_by: "engine_view") if help?(command) && model?

    reading
  end

  def help?(command)
    verb = grammar.verb_for(Playthrough::Grammar.unslashed(command))

    verb && Playthrough::Grammar::VERBS[verb] == :help
  end

  # How the command was read, in the same shape whichever read it, out of the
  # one place that builds it.
  def describe(intent) = Playthrough::Grammar.describe(intent)

  # The name a record answers to, out of the class that owns the closed sets a
  # typed name is matched against. One definition, so the read-out, the refusals
  # and the counter rows cannot name the same person three ways.
  def label(record) = Playthrough::Classifier.label_for(record)

  # THE FIXED GRAMMAR'S OWN READING OF A LINE, kept as a private hop because
  # `Eval::Classifier::Offline` -- the free floor a classifier call is bought
  # against -- reaches for exactly this and must not have to know the grammar
  # moved house.
  def parse(command) = grammar.parse(command)

  # --- acting on it ---------------------------------------------------------

  # THE DISPATCH, branch for branch the one `Playthrough::Turn#play` makes, over
  # the same `Intent`. What differs is only the two ends: nothing streams, and
  # the branches that exist to produce prose say so instead.
  def act(intent, command, understood, resolved_by)
    return refuse_line(intent, command, understood) if intent.refused?

    if intent.destination
      move(intent.destination, command, understood, resolved_by)
    elsif intent.speaker
      person_branch(intent, understood)
    elsif intent.item
      item_branch(intent, understood)
    else
      nothing(intent, understood)
    end
  end

  # THE TWO THINGS A LINE CAN DO TO ONE PERSON, dispatched on the action the way
  # `Playthrough::Turn#play` dispatches them and the way `#item_branch` below
  # dispatches its three. Talking is prose and this mode writes none; a blow is
  # arithmetic over records, so this mode does the whole of it.
  def person_branch(intent, understood)
    return strike(intent.speaker, understood) if intent.attack?

    talk(intent.speaker, understood)
  end

  # SWINGING AT SOMEBODY, THROUGH THE ENGINE'S OWN WRITER. It calls
  # `Playthrough::Turn#strike!` and holds no copy of it, which is the rule
  # `#take`, `#drop`, `#wound` and `#attempt` are already under: a mechanics
  # mode with its own version of the statement that hurts somebody would be
  # testing itself. So a kill here happens exactly as it happens in the browser
  # -- the last hit point, the body letting go of what it held, and
  # `playthroughs.ended_at` if the body was the player's, all in one
  # transaction.
  #
  # THE FOES' ANSWER IS NOT HERE. Every live foe in the room strikes back in the
  # same turn, and that happens in `#run` for every line this mode PLAYS rather
  # than in this branch -- because a fight answers a look and a move too, which
  # is what makes it a fight.
  def strike(target, understood)
    who = playthrough.character
    return refuse("this playthrough has no protagonist, so there is nobody to swing", understood: understood) if who.nil?

    unless who.stat_block?
      return refuse("#{who.fullname} has no stat block, so there is no hit die to hit with. " \
                    "`rake game:backfill_stat_blocks` rolls one, offline",
                    understood: understood)
    end

    blow = turn.strike!(who, target, round: round)
    if blow.nil?
      return refuse("#{target.fullname} has no stat block, so there is no body to hurt. " \
                    "`rake game:backfill_stat_blocks` rolls one, offline",
                    understood: understood)
    end

    change("struck: #{blow}", understood)
  end

  # THE FOUR THINGS A LINE CAN DO TO ONE THING, dispatched on the action the way
  # `Playthrough::Turn#play` dispatches them, and reading is first because it is
  # the one that moves nothing.
  def item_branch(intent, understood)
    return recite(intent.item, understood) if intent.examine?
    return throw_it(intent, understood) if intent.throw?

    intent.drop? ? drop(intent.item, understood) : take(intent.item, understood)
  end

  # THROWING SOMETHING, THROUGH THE ENGINE'S OWN WRITER. It calls
  # `Playthrough::Turn#throw_item!` and holds no copy of it, which is the rule
  # `#take`, `#drop`, `#strike`, `#wound` and `#attempt` are already under: a
  # mechanics mode with its own version of the statement that moves the world
  # would be testing itself. So a throw that kills somebody kills them here
  # exactly as it does in the browser -- the last hit point, the body letting go
  # of what it held, and the game ending if the body was the player's.
  #
  # `throw_it` AND NOT `throw`, because `throw` is `Kernel#throw` and a private
  # method here that shadowed it would be a trap for the next reader.
  #
  # THE FOES' ANSWER IS NOT HERE, exactly as it is not in `#strike`: every live
  # foe in the room answers in the same turn, and that happens in `#run` for
  # every line this mode PLAYED. A throw is a played line whichever way the die
  # went -- including a failed lift, which is a spent turn and not a refusal.
  def throw_it(intent, understood)
    who = playthrough.character
    return refuse("this playthrough has no protagonist, so there is nobody to throw anything", understood: understood) if who.nil?

    outcome = turn.throw_item!(intent.item, at: intent.at, round: round)
    if outcome.nil?
      return refuse("#{who.fullname} has no abilities, so there is no strength to throw with. " \
                    "`rake game:backfill_stat_blocks` rolls them, offline",
                    understood: understood)
    end

    # THE ACT GOES IN THE NOTE AND THE OUTCOME IN THE DIFF, and the split is not
    # cosmetic. `changed:` in this mode means A ROW MOVED, and on a failed lift
    # none did -- a fumble is a turn the engine PLAYED (the whole distinction
    # `Playthrough::Refusal`'s header draws) and it is not a change and not a
    # refusal, exactly as `check` is neither. So the line naming what was thrown
    # at what, and the target the d20 was thrown at, is printed on EVERY outcome,
    # and only a throw that moved something also carries a `changed:`.
    #
    # That is also the one thing `rake game:sweep` can honestly assert about a
    # throw: `Roll`'s seed is built out of row ids, so the FACE is not
    # re-derivable across two databases and the act is.
    #
    # A THROW THAT MOVED NOTHING STILL SAYS WHAT HAPPENED -- the outcome joins
    # the note where there is no diff to carry it, so a failed lift is never
    # reported as a line with no answer.
    Report.new(command: nil, understood: understood,
               change: (outcome.outcome_in_words if outcome.landed?),
               refusal: nil,
               note: [ outcome.attempt_in_words, (outcome.outcome_in_words unless outcome.landed?) ].compact,
               state: state)
  end

  # THE LINE THIS MODE WILL NOT PLAY EITHER, and it is the same rule read out of
  # the same place: `Playthrough::Classifier::Intent#refused?` decides and
  # `Playthrough::Refusal` says it, so the two modes cannot come to disagree
  # about a line. The captain's ruling of 2026-09-04.
  #
  # WHAT THIS REPLACED. Two acts on one line used to do the FIRST and add a note
  # -- `also named: copy-room apron -- one line is one act, so this turn did not
  # touch it` -- which was the honest report of a half-played turn, and the half
  # a turn the ruling struck. Nothing is done now and nothing is left undone.
  #
  # `#reason` and never `#text`: the read-out is printed under every report in
  # this mode, so a refusal that also listed what is here would say it twice.
  # The browser, which has no read-out, reads `#text`.
  def refuse_line(intent, command, understood)
    refusal = Playthrough::Refusal.for(intent, typed: command, offered: classifier.offered_for(intent.action))

    refuse([ refusal.reason, ROW_WRITTEN[refusal.kind] ].compact.join(" "), understood: understood)
  end

  # MOVING, and with a model in the loop this is `Playthrough::Turn#move_to`
  # whole: the stub is realized, the arrival is written, the visit is stamped
  # and the playthrough moves only once both calls have landed. The prose that
  # arrival contains is not printed, and that is the only thing this branch does
  # differently from the browser.
  def move(destination, command, understood, resolved_by)
    from = playthrough.current_location
    return stand_in(from, destination, understood) unless model?

    unwritten = destination.stub?
    scene = turn.move_to(destination)

    # What was typed and what the turn did, filed under the turn it produced,
    # and the classifier's own exchange filed with it -- the stamps
    # `Playthrough::Turn#play` makes for every branch. A turn this mode wrote
    # should be as readable afterwards as one the browser wrote, and a sweep
    # must not be able to tell them apart: `move` is the only branch here that
    # writes a `Scene` at all, so this is the whole of that obligation.
    scene.update!(typed: Playthrough::Grammar.unslashed(command), resolved_action: "move",
                  acted_on: destination, resolved_by: resolved_by)
    # THE CLASSIFIER ONLY IF IT RAN, exactly as `Playthrough::Turn#play` does it:
    # a move the grammar resolved made no call, and filing an empty conversation
    # under the turn would say it had.
    classifier.agent.attribute_to!(scene) if resolved_by == "model"
    playthrough.prune_conversations!

    change("moved: #{label(from) || "nowhere"} -> #{destination.name} " \
           "(#{unwritten ? "written for the first time" : "already written"}, " \
           "arrival scene ##{scene.id}; its prose is not shown)", understood)
  end

  # The same move with no model available: the row moves and the room stays
  # unwritten. Said out loud, because a stub is the one thing the offline mode
  # reads differently from the real loop.
  def stand_in(from, destination, understood)
    # `Playthrough::Turn#move_to` snapshots after realizing; this is the offline
    # half of the same statement, and it is here rather than left to the next
    # turn because the read-out printed under THIS move is what a sweep script
    # asserts `here:` against.
    Playthrough::Snapshot.new(playthrough).of_the_room!(destination)
    # AND THE WALK IS PAID FOR -- after the snapshot and BEFORE the player is
    # stood in the room, which is `Playthrough::Turn#move_to`'s own order for
    # its own reasons: this game has to have its copy of the room before
    # anything can cost anybody anything, and the room the party is still
    # standing in is what names the direction the doorway was walked in.
    Playthrough::Hazards.new(playthrough, turn: turn).on_arrival!(destination, from: from)
    turn.stand_in!(destination)

    change("moved: #{label(from) || "nowhere"} -> #{destination.name}" \
           "#{" (a stub -- nobody has written this room, and no-model mode cannot)" if destination.stub?}",
           understood)
  end

  # The guard is `Playthrough::Turn#take_item`'s and it is about the SENTENCE,
  # not about the record: the row goes onto `items.playthrough_id`, which needs
  # no character at all, but the fact the narrator is handed names whoever
  # picked the thing up. Nothing in the app makes a playthrough without one.
  def take(item, understood)
    return refuse("this playthrough has no protagonist, so there is nobody to name as carrying anything", understood: understood) if playthrough.character.nil?

    was = item.location
    turn.carry!(item)

    change("took: #{item.name} (was lying in #{label(was) || "nowhere"}, now carried by #{playthrough.character.fullname})", understood)
  end

  def drop(item, understood)
    return refuse("this playthrough is standing nowhere, so there is no room to put anything down in", understood: understood) if playthrough.current_location.nil?

    turn.put_down!(item)

    change("dropped: #{item.name} (was carried by #{playthrough.character&.fullname || "the party"}, " \
           "now lying in #{playthrough.current_location.name})", understood)
  end

  # WHAT IS WRITTEN ON IT, STRAIGHT OUT OF THE RECORDS, and this is the one
  # branch here that answers a command with content rather than with a diff.
  # That is not this mode growing a narrator: `Item#inscription` is a column, so
  # printing it is printing a record, exactly as the read-out prints an exit
  # name. Nothing is generated and nothing is written.
  #
  # THE THREE ANSWERS, told apart because they are three different facts:
  #
  #   words on record  printed verbatim, as a note rather than a change, because
  #                    reading something does not change anything.
  #   readable, none   said plainly. Writing them is one model call
  #   written yet      (`Item::Inscriber`) and this mode makes none on this
  #                    branch -- so it says what is missing rather than
  #                    inventing it or pretending the thing is blank.
  #   nothing written  a refusal, because there is nothing to read: the world
  #   on it            says this thing has no writing on it at all.
  def recite(item, understood)
    unless item.readable?
      return refuse("there is nothing written on the #{item.name}. Looking at something that has no " \
                    "writing on it is prose, and this mode writes none. Nothing changed.",
                    understood: understood)
    end

    unless item.inscribed?
      return refuse("the #{item.name} has writing on it and the records do not hold the words yet. " \
                    "Writing them down is one model call (Item::Inscriber) and this mode makes none " \
                    "here. Read it in the browser once and it is a record from then on.",
                    understood: understood)
    end

    Report.new(command: nil, understood: understood, change: nil, refusal: nil,
               note: [ "reads: #{item.name}", "  #{item.inscription}" ], state: state)
  end

  # HURTING AND MENDING THE PLAYER, THROUGH THE ENGINE'S OWN TWO WRITERS.
  #
  # It calls `Playthrough::Turn#harm!` and `#mend!` and holds no copy of either,
  # which is the same rule `#take` and `#drop` are under: a mechanics mode with
  # its own version of the statement that moves the world would be testing
  # itself. So death happens HERE exactly as it happens in the browser -- the
  # last hit point and `playthroughs.ended_at` in one transaction -- and the
  # next line typed into this mode is refused by the same
  # `Playthrough::Refusal.dead` the browser refuses it with.
  #
  # IT IS ALWAYS THE PLAYER. Hurting an NPC is a mechanic nobody has ruled on
  # and there is no verb for it; this is an instrument for walking the one body
  # whose zero ends a game.
  def wound(pair, understood)
    kind, amount = pair
    who = playthrough.character
    return refuse("this playthrough has no protagonist, so there is no body to #{kind}", understood: understood) if who.nil?

    before = playthrough.vitals_for(who)
    if before.nil?
      return refuse("#{who.fullname} has no stat block, so there is nothing to #{kind}. " \
                    "`rake game:backfill_stat_blocks` rolls one, offline",
                    understood: understood)
    end

    after = kind == :harm ? turn.harm!(who, amount) : turn.mend!(who, amount)

    change("#{kind == :harm ? "harmed" : "mended"}: #{who.fullname} #{before.in_words} -> #{after.in_words}" \
           "#{". THIS PLAYTHROUGH IS OVER -- every line from here is refused" if playthrough.over?}" \
           "#{" (nothing changed: death is terminal and a mend never raises the dead)" if after.dead? && kind == :mend}",
           understood)
  end

  # ONE d20 AGAINST ONE ABILITY, THROUGH THE ENGINE'S OWN KERNEL. It calls
  # `Playthrough::Turn#check` and holds no copy of it, which is the rule `#take`,
  # `#drop` and `#wound` are already under: a mechanics mode with its own version
  # of the roll would be testing itself.
  #
  # IT WRITES NOTHING, which is what makes it the one verb here that is safe to
  # type into a real game as often as you like -- and what
  # `EngineSweep::Invariants#stat_blocks_unmoved` asserts after a walk that used
  # it. So it is reported as a `note` rather than as a `change`: `changed:` in
  # this mode means a row moved, and no row moved.
  #
  # AT A TARGET OF ZERO OR LESS IT IS A REFUSAL AND NOT A ROLL. The pass rate
  # there is zero for ever, so `Character::Check#impossible?` is the honest
  # answer and printing a die would be printing a number that decided nothing.
  #
  # IT IS ALWAYS THE PLAYER, exactly as `#wound` is: checking an NPC's strength
  # is a mechanic nobody has ruled on and there is no verb for it.
  def attempt(pair, understood)
    ability, penalty = pair
    who = playthrough.character
    return refuse("this playthrough has no protagonist, so there is nobody to check", understood: understood) if who.nil?

    result = turn.check(who, ability, penalty: penalty)
    if result.nil?
      return refuse("#{who.fullname} has no abilities, so there is nothing to check. " \
                    "`rake game:backfill_stat_blocks` rolls them, offline",
                    understood: understood)
    end

    if result.impossible?
      return refuse("#{who.fullname} cannot do it at all: #{ability} #{result.score} less a penalty of " \
                    "#{result.penalty} is #{result.target}, and no d#{Character::CHECK_DIE} comes up that low. " \
                    "No die was thrown.",
                    understood: understood)
    end

    Report.new(command: nil, understood: understood, change: nil, refusal: nil,
               note: [ "check #{result}" ], state: state)
  end

  # TALKING IS PROSE, and prose is the one thing this mode does not do. The
  # person it resolved to is named anyway: that the classifier found them is
  # worth seeing, and it is the half of the turn this mode can still check.
  def talk(character, understood)
    refuse("#{character.fullname} is here and the classifier resolved them, but talking is prose " \
           "and this mode writes none. Nothing changed. Play the browser game to speak to somebody.",
           understood: understood)
  end

  # A turn that resolved to no record and was NOT refused: `other`, and an
  # `examine` that landed on nothing -- looking at the sky is not reaching for a
  # record it can miss. Both are answered in prose, and this mode writes none. A
  # `move`, `talk`, `take` or `drop` that resolved to nothing used to arrive here
  # too and does not any more: it is refused above, by the same rule and in the
  # same words the browser refuses it in.
  def nothing(intent, understood)
    refuse("`#{intent.action}` does not move anything: it is answered in prose, and this mode writes none. " \
           "Nothing changed.", understood: understood)
  end

  # --- reports --------------------------------------------------------------

  def change(line, understood = nil)
    Report.new(command: nil, understood: understood, change: line, refusal: nil, note: nil, state: state)
  end

  def refuse(reason, note: nil, understood: nil)
    Report.new(command: nil, understood: understood, change: nil, refusal: reason, note: note, state: state)
  end

  # WHICH TURN OF A FIGHT THIS ONE IS, set at the top of every `#run` off
  # `Playthrough::Fight#next_round` -- a record, never a counter that survives
  # between commands. Nil before the first line, which no branch that strikes
  # can be reached before.
  attr_reader :round

  # The loop that owns the writes. Built once; it holds nothing but the
  # playthrough, and no model call is made by building it.
  def turn
    @turn ||= Playthrough::Turn.new(playthrough)
  end
end
