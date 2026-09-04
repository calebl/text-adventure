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
#
# The arrival Scene is still written, because it is world state -- the cast, the
# visit stamp and the story clock all hang off it -- and its prose is simply not
# shown. That is the one place this mode pays for words nobody reads, and it is
# the price of the world moving the way it really does.
#
# WITHOUT A MODEL AT ALL: `model: false`. A fixed grammar (`VERBS`) replaces the
# classifier and a move stands the player in the room without realizing it. That
# is the fallback for a machine with no key and the mode the engine-direct tests
# run in; it is not the default, because a mode that cannot read what was typed
# is testing a smaller thing than the one that can.
#
# WHAT IT WRITES is `playthroughs.current_location_id` and `items.playthrough_id`
# / `items.location_id`, through `Playthrough::Turn#move_to`, `#stand_in!`,
# `#carry!` and `#put_down!` -- the same statements the narrated loop moves the
# world with. A mechanics mode with its own copy of the line that moves the
# player would be testing itself.
#
# WHAT IT IS NOT is `rake game:play`, which is still ruled out. It renders no
# prose and duplicates no part of the loop; the moment it grew a narrator it
# would be the second UI that rule exists to prevent. The dispatch below is the
# one thing it does not share with `Playthrough::Turn#play`, and deliberately:
# that method returns a Scene and streams prose into a block, and this one has
# to be able to say what changed, what was refused and why.
class Playthrough::Mechanics
  # THE FALLBACK GRAMMAR, for `model: false`. A closed table rather than
  # anything clever: with the classifier switched off, the parser in front of
  # the engine has to be the part nobody has to wonder about.
  #
  # Everything that only reads goes to `:look`, because the read-out is always
  # the whole engine view. `inventory`, `exits`, `items` and `who` are in the
  # table so that typing the obvious word gets the records rather than a
  # refusal, not because each prints a different thing.
  VERBS = {
    "look" => :look, "l" => :look, "where" => :look, "state" => :look,
    "inventory" => :look, "inv" => :look, "i" => :look,
    "exits" => :look, "items" => :look, "who" => :look,
    "go" => :go, "move" => :go, "walk" => :go, "enter" => :go,
    "take" => :take, "get" => :take, "grab" => :take, "pick up" => :take,
    "drop" => :drop, "put down" => :drop, "leave" => :drop,
    # TALKING IS PROSE AND THIS MODE WRITES NONE, so `talk` here resolves a
    # person and then refuses -- which is the whole point of it. Who is
    # standing here is `Character.present_in`, a record, so whether a `talk`
    # RESOLVES is an engine question that can be answered with no model at all,
    # and answering it offline is what lets `rake game:sweep` regression-test
    # presence. Before the whereabouts column there was nothing to resolve
    # against: the room's cast was reconstructed from the last scene here that
    # recorded anybody, and an offline walk writes no scenes.
    "talk" => :talk, "speak" => :talk, "ask" => :talk,
    "help" => :help
  }.freeze

  # What `help` prints in the no-model mode, and what an unknown word is refused
  # with. Written out rather than derived from `VERBS` because the aliases
  # matter less than the shape of a command does.
  GRAMMAR = [
    "go <exit>        move into one of the ways out (also: move, walk, enter)",
    "take <item>      pick up something lying here (also: get, grab, pick up)",
    "drop <item>      put down something you are carrying (also: put down, leave)",
    "talk <person>    resolve somebody standing here (also: speak, ask). The",
    "                 talking itself is prose, so this mode names them and stops",
    "look             the engine's whole view of where you are (also: where,",
    "                 inventory, exits, items, who, state)",
    "help             this list",
    "",
    "A name is matched against the records: exactly first, then as an",
    "unambiguous prefix, then as an unambiguous fragment -- and a fragment is",
    "read both ways round, so `drop the tide-slate` finds the Assize",
    "tide-slate. A leading the/a/an/to/into/through/onto/at is dropped before",
    "any of that. Case and extra spaces do not matter. This is the no-model",
    "fallback -- drop it to have the classifier read what you type and the",
    "world generate as you walk."
  ].freeze

  # WORDS THAT NAME NOTHING, taken off the FRONT of a typed name and nowhere
  # else. `go to the Tide Post` and `drop the tide-slate` were both refused
  # underneath a refusal listing the very thing they named, because an article
  # or a preposition at the front is fatal to a prefix match and to a fragment
  # match alike. Only the front: "The Bell of Saint Aravel" has to keep its
  # "of", and a word in the middle of a name is part of the name.
  LEADING_WORDS = %w[the a an to into through onto at].freeze

  # THE THREE WAYS A NAME CAN MATCH once it is not exact, tried in this order
  # and each only on an unambiguous hit.
  #
  # The third one is the direction that was missing: what was TYPED holds the
  # record's whole name. It is the only one tested on word boundaries, because
  # it is the only one where a short record name could be swallowed by a long
  # typed line -- an item called "key" would otherwise be found by somebody
  # typing "monkey". The first two are left exactly as they were: `take aybook`
  # has always found the daybook and there is no reason today to stop it.
  HOW_A_NAME_MATCHES = [
    ->(name, typed) { name.start_with?(typed) },
    ->(name, typed) { name.include?(typed) },
    ->(name, typed) { typed.match?(/(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/) }
  ].freeze

  # What the classifier mode says instead, since there is no grammar to learn.
  CLASSIFIER_HELP = [
    "Type what you would type in the game. `Playthrough::Classifier` reads it",
    "against the exits, the cast, what is lying here and what you are carrying,",
    "and the line above each read-out says what it resolved to.",
    "",
    "move, take and drop change the world and are shown as a diff. talk and",
    "examine are prose, so this mode says so and changes nothing.",
    "",
    "Walking into a room nobody has written generates it, exactly as the browser",
    "does. `quit` to stop."
  ].freeze

  # WHERE THE PLAYTHROUGH STANDS, read out of the records after the command ran.
  # Every field is a fresh read rather than anything carried along from before
  # the write, so the read-out is what the database says and not what this class
  # believed it had done.
  State = Data.define(:location, :exits, :items_here, :carried, :present) do
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
        [ "present", present.map(&:fullname), "nobody else" ]
      ].map { |label, values, empty| format("  %-11s %s", label, values.presence&.join(", ") || empty) }
    end
  end

  # ONE COMMAND AND WHAT IT DID. `understood` is how the command was read --
  # the classifier's resolved intent, or the grammar's -- and it is printed even
  # when nothing happened, because "it did not do what I meant" and "it did not
  # understand me" are different bugs. `change` is the one-line diff of the
  # write; `refusal` is why there was none. Never both.
  Report = Data.define(:command, :understood, :change, :refusal, :note, :state) do
    def refused? = refusal.present?
    def changed? = change.present?

    def to_s
      lines = []
      lines << "  understood: #{understood}" if understood.present?
      lines << "  changed:    #{change}" if changed?
      lines << "  refused:    #{refusal}" if refused?
      lines.concat(note.map { |line| "  #{line}" }) if note.present?
      lines << state.to_s
      lines.join("\n")
    end
  end

  # HOW ONE TYPED LINE WAS READ, whichever of the two read it. `intent` is a
  # `Playthrough::Classifier::Intent` either way -- the grammar builds one
  # rather than inventing a second vocabulary -- so the dispatch below is one
  # path and not two, which is the whole reason the fallback is trustworthy.
  # A reading with no intent and no refusal is a command that only reads.
  Reading = Data.define(:intent, :refusal, :note, :understood) do
    def initialize(intent: nil, refusal: nil, note: nil, understood: nil, **rest) = super
  end

  # A typed name against the records it could have meant. `record` is what the
  # command acts on; `candidates` is what to say when it is nil.
  Match = Data.define(:record, :candidates) do
    def found? = !record.nil?
    def ambiguous? = record.nil? && candidates.any?
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
    # THE WORLD MOVES FIRST, exactly as it does in `Playthrough::Turn#play`, and
    # for the same reason: the exits a command resolves against have to be
    # tonight's. No model call, no tokens.
    playthrough.story.catch_up_world!

    reading = model? ? classify(command) : parse(command)

    report =
      if reading.refusal
        refuse(reading.refusal, note: reading.note, understood: reading.understood)
      elsif reading.intent.nil?
        read(note: reading.note)
      else
        act(reading.intent, command, reading.understood)
      end

    report.with(command: command)
  end

  # The read-out with nothing changed. What the console prints before the first
  # command.
  def read(note: nil, understood: nil)
    Report.new(command: nil, understood: understood, change: nil, refusal: nil, note: note, state: state)
  end

  def help = read(note: model? ? CLASSIFIER_HELP : GRAMMAR)

  # THE ENGINE'S VIEW, out of the same four readers `Playthrough::Classifier`
  # offers a model. Rebuilt on every call: `classifier` memoizes nothing it
  # reads.
  def state
    State.new(
      location: playthrough.current_location,
      exits: classifier.exits_here,
      items_here: classifier.items_here,
      carried: classifier.items_carried,
      present: classifier.characters_here
    )
  end

  # The classifier, and in the no-model mode still the classifier -- for its
  # four closed-set readers and nothing else. It is the inverse of `#resolve`
  # below: the list a model is offered is the list a typed name is matched
  # against, and sharing it is what stops the two ways in drifting apart about
  # what is reachable from here. Building one makes no model call; `#classify`
  # is the only method on it that talks to one.
  def classifier
    @classifier ||= Playthrough::Classifier.new(playthrough)
  end

  private

  # --- reading the command --------------------------------------------------

  # THE CLASSIFIER PATH. One model call, against the closed sets, and the intent
  # it returns is the same `Intent` the real loop branches on. A reach that
  # resolved to nothing still writes a `Playthrough::Drift` row -- that happens
  # inside `#classify` and is deliberately not bypassed here, because drift is
  # what this mode is for measuring.
  def classify(command)
    return Reading.new(note: CLASSIFIER_HELP) if command.to_s.strip.downcase == "help"
    return Reading.new if command.to_s.strip.empty?

    intent = classifier.classify(command)
    Reading.new(intent: intent, understood: describe(intent))
  end

  # How the command was read, in the same shape whichever read it.
  def describe(intent)
    "#{intent.action} -> #{label(intent.subject) || "nothing"}"
  end

  def label(record)
    return nil if record.nil?

    record.respond_to?(:fullname) ? record.fullname : record.name
  end

  # THE NO-MODEL PATH. Longest verb first so `pick up` is not read as `pick`,
  # and the verb has to be the whole line or be followed by a space -- otherwise
  # `lease the room` would parse as `l` and lose four words.
  #
  # A line that matches no verb at all gets one more chance against the exit
  # names, which is what makes a bare `north` work in a world whose exits are
  # named that way. It is tried last and only on an unambiguous match, so it can
  # never shadow a verb.
  def parse(command)
    text = command.to_s.strip.gsub(/\s+/, " ")
    return Reading.new if text.empty?

    verb = verb_for(text)
    argument = verb ? text[verb.length..].to_s.strip : text

    case verb && VERBS.fetch(verb)
    when :look then Reading.new
    when :help then Reading.new(note: GRAMMAR)
    when :go then read_move(argument)
    when :take then read_take(argument)
    when :drop then read_drop(argument)
    when :talk then read_talk(argument)
    else resolve(classifier.exits_here, text).found? ? read_move(text) : unknown(text)
    end
  end

  def verb_for(text)
    downcased = text.downcase

    VERBS.keys.sort_by { |verb| -verb.length }
         .find { |verb| downcased == verb || downcased.start_with?("#{verb} ") }
  end

  def read_move(argument)
    return Reading.new(refusal: "go where? The ways out are: #{names(classifier.exits_here)}") if argument.blank?

    exits = classifier.exits_here
    match = resolve(exits, argument)
    return Reading.new(refusal: cannot_find("way out", argument, match, exits)) unless match.found?

    intent(:move, destination: match.record)
  end

  def read_take(argument)
    here = classifier.items_here
    return Reading.new(refusal: "take what? Lying here: #{names(here)}") if argument.blank?

    match = resolve(here, argument)
    return Reading.new(refusal: cannot_find("thing lying here", argument, match, here)) unless match.found?

    intent(:take, item: match.record)
  end

  def read_drop(argument)
    carried = classifier.items_carried
    return Reading.new(refusal: "drop what? Carrying: #{names(carried)}") if argument.blank?

    match = resolve(carried, argument)
    return Reading.new(refusal: cannot_find("thing you are carrying", argument, match, carried)) unless match.found?

    intent(:drop, item: match.record)
  end

  # WHO IS HERE IS A RECORD, so this resolves out of `Character.present_in` --
  # the same closed set `Playthrough::Classifier` offers a model, read through
  # the same method. A name that lands on nobody is refused with the cast that
  # IS here, which is the answer a player standing in the wrong room needs.
  def read_talk(argument)
    cast = classifier.characters_here
    if argument.blank?
      return Reading.new(refusal: cast.any? ? "talk to whom? Here: #{names(cast)}" : "talk to whom? There is nobody here.")
    end

    match = resolve(cast, argument)
    return Reading.new(refusal: cannot_find("person here", argument, match, cast)) unless match.found?

    intent(:talk, speaker: match.record)
  end

  # The grammar's answer, in the classifier's own vocabulary.
  def intent(action, **resolved)
    built = Playthrough::Classifier::Intent.new(action: action, **resolved)
    Reading.new(intent: built, understood: describe(built))
  end

  # A word that is not in the table. The grammar comes with the refusal rather
  # than a suggestion to type `help`: with the classifier switched off there is
  # nothing here to guess what was meant, so the honest answer is the whole of
  # what this mode understands.
  def unknown(text)
    Reading.new(
      refusal: "I do not understand #{text.to_s.split.first.inspect}. The no-model grammar is fixed:",
      note: GRAMMAR
    )
  end

  # --- acting on it ---------------------------------------------------------

  # THE DISPATCH, branch for branch the one `Playthrough::Turn#play` makes, over
  # the same `Intent`. What differs is only the two ends: nothing streams, and
  # the branches that exist to produce prose say so instead.
  def act(intent, command, understood)
    report =
      if intent.destination
        move(intent.destination, command, understood)
      elsif intent.speaker
        talk(intent.speaker, understood)
      elsif intent.item
        intent.drop? ? drop(intent.item, understood) : take(intent.item, understood)
      else
        nothing(intent, understood)
      end

    overreach(report, intent)
  end

  # WHAT THE LINE ALSO NAMED AND THIS TURN DID NOT DO. One typed line is one
  # act, so "take the index and the apron" takes the index -- and the apron
  # used to go nowhere at all: no write, no refusal, and no `Playthrough::Drift`
  # row either, because the reach resolved. Half a sentence vanished and nothing
  # counted it.
  #
  # Said as a note rather than folded into `changed:` or `refused:`, because it
  # is neither: something did happen, and something else was left undone. The
  # note is added here rather than in each branch so every branch gets it,
  # including the ones that refuse.
  def overreach(report, intent)
    return report unless intent.named_more_than_one?

    report.with(note: Array(report.note) + [
      "also named: #{label(intent.also_named)} -- one line is one act, so this turn did not touch it. Type it on its own."
    ])
  end

  # MOVING, and with a model in the loop this is `Playthrough::Turn#move_to`
  # whole: the stub is realized, the arrival is written, the visit is stamped
  # and the playthrough moves only once both calls have landed. The prose that
  # arrival contains is not printed, and that is the only thing this branch does
  # differently from the browser.
  def move(destination, command, understood)
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
    scene.update!(typed: command, resolved_action: "move", acted_on: destination)
    classifier.agent.attribute_to!(scene)
    playthrough.prune_conversations!

    change("moved: #{label(from) || "nowhere"} -> #{destination.name} " \
           "(#{unwritten ? "written for the first time" : "already written"}, " \
           "arrival scene ##{scene.id}; its prose is not shown)", understood)
  end

  # The same move with no model available: the row moves and the room stays
  # unwritten. Said out loud, because a stub is the one thing the offline mode
  # reads differently from the real loop.
  def stand_in(from, destination, understood)
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

  # TALKING IS PROSE, and prose is the one thing this mode does not do. The
  # person it resolved to is named anyway: that the classifier found them is
  # worth seeing, and it is the half of the turn this mode can still check.
  def talk(character, understood)
    refuse("#{character.fullname} is here and the classifier resolved them, but talking is prose " \
           "and this mode writes none. Nothing changed. Play the browser game to speak to somebody.",
           understood: understood)
  end

  # A turn that resolved to no record. Told apart the way the loop tells them
  # apart, because they are different facts about the world.
  def nothing(intent, understood)
    reason =
      if intent.reached_for_nothing?
        "#{drift_reason(intent.action)} Nothing changed, and a Playthrough::Drift row was written."
      else
        "`#{intent.action}` does not move anything: it is answered in prose, and this mode writes none. Nothing changed."
      end

    refuse(reason, understood: understood)
  end

  # WHY THE REACH RESOLVED TO NOTHING, and it is two different facts told
  # apart: the set was empty, or the set had things in it and the command did
  # not land on one of them. It used to be one sentence for both, so "pickup
  # everything" in a room with three things on the floor was refused with
  # "Nothing of that name is lying here" -- directly above a read-out listing
  # all three. The command had named no name at all.
  #
  # Neither branch says what the player typed and neither repeats the lists:
  # the read-out below is where the records are printed, and a refusal that
  # guesses at the typing is how a wrong guess gets stated as a fact.
  def drift_reason(action)
    return empty_set_reason(action) if offered_for(action).empty?

    case action
    when :move then "That did not resolve to one of the ways out of here."
    when :talk then "That did not resolve to anybody who is here."
    when :take then "That did not resolve to anything lying here."
    when :drop then "That did not resolve to anything you are carrying."
    else "That resolved to nothing."
    end
  end

  def empty_set_reason(action)
    case action
    when :move then "There is no way out of here at all."
    when :talk then "There is nobody here to talk to."
    when :take then "There is nothing lying here to pick up."
    when :drop then "You are carrying nothing, so there is nothing to put down."
    else "That resolved to nothing."
    end
  end

  # The closed set the action reads against -- the same four the read-out
  # prints and the same four the classifier offers a model.
  def offered_for(action)
    case action
    when :move then classifier.exits_here
    when :talk then classifier.characters_here
    when :take then classifier.items_here
    when :drop then classifier.items_carried
    else []
    end
  end

  # --- resolving a typed name (no-model mode) --------------------------------

  # HOW A TYPED NAME BECOMES A RECORD when there is no model to read it. Exact
  # first, then an unambiguous prefix, then an unambiguous fragment -- so `take
  # daybook` finds the "Ward Office 12 daybook" and `go the` finds nothing
  # rather than guessing. Case and repeated spaces are ignored, because somebody
  # typing at a prompt is not a JSON enum.
  #
  # An exact match that hits two records takes the first, which is exactly what
  # `Playthrough::Classifier#find_item` does with two identical items in one
  # room: to a player typing the name they are the same thing, and `find` on an
  # id-ordered list makes which one stable.
  #
  # MATCHING USED TO RUN ONE WAY ONLY -- the record's name had to start with or
  # contain what was typed -- and both halves of that failed on ordinary
  # English. `drop the tide-slate` was refused underneath a refusal listing
  # "Assize tide-slate", because a leading article is fatal to a prefix and to a
  # fragment alike; `go to the Tide Post` was refused while offering "The Tide
  # Post", for the same reason one word earlier. So a typed name is read twice,
  # as typed and again with `LEADING_WORDS` taken off the front, and a fragment
  # is now looked for in both directions. It is the same shape as the fix the
  # classifier path got in #102: the player is not a JSON enum.
  #
  # Ambiguity found on the first reading is remembered rather than returned, so
  # the stripped reading still gets its turn -- and is only reported when
  # nothing else resolved. A refusal that says "matches more than one" when a
  # later reading would have found exactly one is the same defect wearing a
  # better message.
  def resolve(records, typed)
    ambiguous = nil

    readings_of(typed).each do |wanted|
      match = match_once(records, wanted)
      return match if match.found?

      ambiguous ||= match if match.ambiguous?
    end

    ambiguous || Match.new(record: nil, candidates: [])
  end

  # WHAT WAS TYPED, AND WHAT WAS TYPED WITHOUT THE WORDS THAT NAME NOTHING. In
  # that order, so a record actually called "The Tide Post" is still found by
  # its own name before anything is thrown away, and `go the` still resolves to
  # nothing rather than guessing.
  def readings_of(typed)
    wanted = normalize(typed)

    [ wanted, without_leading_words(wanted) ].uniq.reject(&:empty?)
  end

  # Never down to nothing: a player who typed only "the" typed a name this
  # grammar does not have, and the refusal for it is the one that lists what it
  # does have.
  def without_leading_words(wanted)
    words = wanted.split(" ")
    words.shift while words.many? && LEADING_WORDS.include?(words.first)

    words.join(" ")
  end

  # ONE READING OF THE TYPED NAME against the records, in the order a person
  # would try them.
  def match_once(records, wanted)
    exact = records.select { |record| names_of(record).any? { |name| normalize(name) == wanted } }
    return Match.new(record: exact.first, candidates: exact) if exact.any?

    HOW_A_NAME_MATCHES.each do |how|
      hits = records.select { |record| names_of(record).any? { |name| how.call(normalize(name), wanted) } }
      return Match.new(record: hits.first, candidates: hits) if hits.one?
      return Match.new(record: nil, candidates: hits) if hits.many?
    end

    Match.new(record: nil, candidates: [])
  end

  # THE NAMES A RECORD ANSWERS TO. A place and a thing have one; a person has
  # two, and both are in the closed enum `Playthrough::Classifier` offers a
  # model (`#cast_names`) -- so both have to be matchable here, or the offline
  # grammar would refuse a name the classifier accepts. A player types "Neb" as
  # readily as "Neb Halloran", which is the same reason
  # `Playthrough::Classifier#find_character` matches either.
  def names_of(record)
    return [ record.fullname, record.nickname ].compact_blank if record.respond_to?(:fullname)

    [ record.name ].compact_blank
  end

  def normalize(text)
    text.to_s.downcase.strip.gsub(/\s+/, " ")
  end


  # A refusal that says what would have worked. Ambiguity and absence are told
  # apart because they are different mistakes: one is a name that was too short,
  # the other a name for something that is not there.
  def cannot_find(kind, typed, match, records)
    return "#{typed.inspect} matches more than one #{kind}: #{names(match.candidates)}" if match.ambiguous?

    "there is no #{kind} called #{typed.inspect}. There is: #{names(records)}"
  end

  # As the player would have typed them -- `label` gives a person their
  # fullname, which is the name a refusal should offer back.
  def names(records)
    records.map { |record| label(record) }.presence&.join(", ") || "nothing"
  end

  # --- reports --------------------------------------------------------------

  def change(line, understood = nil)
    Report.new(command: nil, understood: understood, change: line, refusal: nil, note: nil, state: state)
  end

  def refuse(reason, note: nil, understood: nil)
    Report.new(command: nil, understood: understood, change: nil, refusal: reason, note: note, state: state)
  end

  # The loop that owns the writes. Built once; it holds nothing but the
  # playthrough, and no model call is made by building it.
  def turn
    @turn ||= Playthrough::Turn.new(playthrough)
  end
end
