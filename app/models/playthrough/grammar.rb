# THE FIXED GRAMMAR: ONE TYPED LINE READ WITHOUT A MODEL.
#
# A closed verb table, a name matched against the closed sets the actions
# already read, and a `Playthrough::Classifier::Intent` at the end of it -- the
# same `Intent` the classifier answers with, so everything downstream is one
# path and not two. It makes NO model call and writes NOTHING.
#
# WHY IT IS A CLASS OF ITS OWN, since 2026-09-04. It was the private half of
# `Playthrough::Mechanics` -- the offline fallback for `model: false`, a mode
# nobody plays -- and it is now ALSO the first reader of a line typed in the
# browser. The captain's ruling of 2026-09-04, evening:
#
#   *"support a slash prefix autocomplete in the text box, and resolve those and
#   verb-prefixed lines offline then fallback to the model."*
#
# So `Playthrough::Turn#play` and `Playthrough::Mechanics#run` both hand a line
# here first and both fall back to `Playthrough::Classifier` when it does not
# resolve. Two callers reading one line two ways is exactly what a second copy
# of a grammar would produce, and there is one copy: this file.
#
# WHAT IT CLAIMS, AND WHAT IT LEAVES ALONE (`#reading_first`): A LINE BEGINNING
# WITH A SLASH, AND NOTHING ELSE. The captain's ruling of 2026-09-05 --
# ***"I think we should only auto accept the slash commands"*** -- after he
# objected that *"a line beginning with `move`"* should not always be a move.
# Everything a player types without one reaches `Playthrough::Classifier`
# untouched, which is the whole of what the model is bought for. See
# `MEANS_SOMETHING_ELSE` for the four measured wrong answers a leading verb
# alone produced.
#
# THE SLASH IS INPUT SYNTAX AND IS STRIPPED BEFORE THE LINE IS READ. `/take
# slate` and `take slate` are the same line to everything below `#parse`, and
# `Scene#typed` records the line without it -- so the frozen corpora,
# `Story::Audit` and the classifier prompt all go on seeing ordinary English.
# What the slash buys is the browser's autocomplete (`Playthrough::SlashMenu`)
# and a player saying out loud "read this as a command".
#
# `#parse` HAS NO SUCH RULE and answers every line handed to it: `model: false`
# has no classifier to defer to, so `rake game:sweep` and
# `Eval::Classifier::Offline` are unchanged by any of this.
#
# WHAT IT WILL NOT DO IS GUESS. Exact first, then an unambiguous prefix, then an
# unambiguous fragment read both ways round; an ambiguous name, an unknown verb
# and a name that lands on nothing all come back as a REFUSAL and never as a
# record. Whether that refusal is shown to the player is the caller's business:
# `Playthrough::Mechanics` prints it, and `Playthrough::Turn` does not -- there,
# a line the grammar could not resolve is a line the classifier gets, exactly as
# it did before any of this existed. See `Playthrough::Turn#read_line`.
class Playthrough::Grammar
  # THE VERB TABLE. A closed table rather than anything clever: this is the part
  # of the input path nobody should have to wonder about.
  #
  # Everything that only reads goes to `:look`, because a read-out is always the
  # whole engine view. `inventory`, `exits`, `items` and `who` are in the table
  # so that typing the obvious word gets the records rather than a refusal, not
  # because each prints a different thing.
  VERBS = {
    "look" => :look, "l" => :look, "where" => :look, "state" => :look,
    "inventory" => :look, "inv" => :look, "i" => :look,
    "exits" => :look, "items" => :look, "who" => :look,
    "go" => :go, "move" => :go, "walk" => :go, "enter" => :go,
    "take" => :take, "get" => :take, "grab" => :take, "pick up" => :take,
    "drop" => :drop, "put down" => :drop, "leave" => :drop,
    # TALKING IS PROSE AND `Playthrough::Mechanics` WRITES NONE, so a `talk`
    # there resolves a person and then refuses -- which is the whole point of
    # it. Who is standing here is `Character.present_in`, a record, so whether a
    # `talk` RESOLVES is an engine question that can be answered with no model
    # at all, and answering it offline is what lets `rake game:sweep`
    # regression-test presence. In the browser the same resolution goes straight
    # to `InteractionAgent`, and the prose is written as it always was.
    "talk" => :talk, "speak" => :talk, "ask" => :talk,
    "read" => :read, "examine" => :read, "x" => :read, "look at" => :read,
    # THE ENGINE-VIEW COMMANDS FOR A BODY. `vitals` only reads, so it goes to
    # `:look` with everything else that does; `harm` and `mend` are the two
    # writers `Playthrough::Turn` owns, reached from here the way `go` reaches
    # `#stand_in!`. They take a number rather than a name, which is the one
    # shape no other verb in this table has -- see `#read_wound`.
    "vitals" => :look, "hp" => :look, "condition" => :look,
    "harm" => :harm, "hurt" => :harm, "damage" => :harm,
    "mend" => :mend, "heal" => :mend,
    # THE THREE ABILITIES, AND THE ONE THING A GAME DOES WITH THEM. `stats` and
    # `abilities` only read, so they go to `:look`; `check` throws a d20 and
    # writes NOTHING AT ALL, which makes it the first verb in this table that
    # changes the world in no way and is still worth typing -- the whole point
    # of it is that the roll it prints is the roll the engine would make.
    "stats" => :look, "abilities" => :look,
    "check" => :check,
    "help" => :help
  }.freeze

  # THE VERBS THE ENGINE ANSWERS ITSELF, and the whole of why they are a list
  # rather than a branch.
  #
  # Everything else typed with a model available goes to
  # `Playthrough::Classifier`. These do not, because they are not things a
  # player does in the fiction: they are the engine's own instruments,
  # `Playthrough::IntentSchema::INTENTS` has no word for any of them, and
  # sending `harm 5` or `check strength` to a closed enum of six intents would
  # spend a model call to be told it was `other`.
  #
  # THEY ARE `Playthrough::Mechanics`'S ALONE. The browser has no engine view --
  # nothing there claims an unslashed line at all, so a player who types `stats`
  # at the fiction reaches the classifier exactly as they always did.
  ENGINE_VIEW = %w[vitals hp condition stats abilities check harm hurt damage mend heal help].freeze

  # THE FIVE VERBS THAT RESOLVE A RECORD, in the word this grammar's own help
  # calls each of them by, mapped to the action it produces.
  #
  # It is the list `Playthrough::SlashMenu` offers the player after a `/`, so the
  # box cannot complete to a word the grammar does not read. It is NOT what a
  # line is claimed on -- since the captain's ruling of 2026-09-05 the slash is
  # the whole of that, and every synonym in `VERBS` works behind one. `other` is
  # not here and never will be: it carries no record, so there is nothing for a
  # closed set to complete.
  RESOLVING = { "go" => :move, "talk" => :talk, "take" => :take, "drop" => :drop, "read" => :examine }.freeze

  # WHY A VERB ALONE DOES NOT CLAIM A LINE, and it is the captain's ruling of
  # 2026-09-05. He objected first:
  #
  #   *"i'm not sure that a line beginning with `move` should always go to the
  #   move action in the classifier. For instance, a player might type: `move
  #   the lamp off the desk`"*
  #
  # and then ruled: ***"I think we should only auto accept the slash commands."***
  #
  # He was right, and it was worse than his example. `VERBS` is a COMMAND
  # vocabulary -- `move` is a synonym for `go` in it, `leave` for `drop` -- which
  # is correct for a mode where the player has read `help` and there is no model
  # behind it, and wrong as a claim on a line typed at the fiction. Measured on a
  # room with a `The Supply Closet` exit and a `Ward Office 12 daybook` in hand,
  # four ordinary English lines were answered on a real record:
  #
  #   move the supply closet shelf aside  ->  move -> The Supply Closet
  #   walk the supply closet perimeter    ->  move -> The Supply Closet
  #   leave the ward office               ->  drop -> Ward Office 12 daybook
  #   take a look at the brass lamp       ->  take -> brass lamp
  #
  # The first two WALK THE PLAYER somewhere they were only describing, which is
  # the one thing a closed set was supposed to make impossible; the third puts
  # down what they are carrying; the fourth takes what they meant to read. Each
  # would have been a silently wrong turn, and none of the four is exotic English.
  #
  # SO THE SLASH IS THE WHOLE OF THE CLAIM. It is the player saying "read this as
  # a command", and nothing else says it: a leading verb is a coincidence of
  # English, and a guess about which of two meanings it had is exactly what
  # `Playthrough::Classifier` is bought for. That also makes the shortcut OPT-IN
  # AND VISIBLE -- what the box completes on is what goes offline, and a player
  # who never types `/` never leaves the path they are on today.

  # WHICH READER ANSWERED THE LINE, and the closed list `scenes.resolved_by`
  # holds. One list, in the class that owns the two readers a line can go
  # through, so nothing has to keep a second copy of it in agreement.
  #
  #   grammar       this class resolved it, offline, for no model call
  #   model         `Playthrough::Classifier` resolved it
  #   engine_view   one of `ENGINE_VIEW`, answered by the engine itself. No
  #                 `Scene` is ever written on that path -- `harm`, `check` and
  #                 the read-outs are `Playthrough::Mechanics`'s own -- so the
  #                 value exists for the mode's report and for
  #                 `EngineSweep::Expectation`, and a scene carrying it would be
  #                 a defect `rake game:doctor` would have to name.
  PATHS = %w[grammar model engine_view].freeze

  # The marker a player types to say "read this as a command". One character,
  # taken off the front and nowhere else.
  SLASH = "/"

  # A WORD THAT JOINS TWO ACTS, and the one thing that makes this grammar hand a
  # line it COULD answer to the model anyway.
  #
  # THE PROBLEM IT SOLVES, measured rather than imagined. This grammar has no
  # `also_named` -- nothing in a fixed verb table produces one -- so a line
  # naming two things out of one closed set resolves the FIRST and plays it,
  # where `Playthrough::Classifier` sees both and the line is REFUSED (the
  # captain's ruling of 2026-09-04: one line, one act). On `Eval::Classifier`'s
  # 300 labelled lines that was the whole cost of reading offline first: 6 lines
  # answered wrongly, and ALL SIX were the two-names-in-one-set shape.
  #
  # So a resolved reading whose line still carries a joining word once the
  # matched name is taken out of it is NOT taken as an answer. It goes to the
  # classifier, which has the field that can see the second name, refuses the
  # line and writes the `Playthrough::Overreach` row -- so the ruling and the
  # counter both survive, and neither had to be reproduced here.
  #
  # MEASURED BOTH WAYS: it catches 6 of 6 wrong answers and costs 4 of 63 right
  # ones, which then cost one classifier call each and come back the same. The
  # name itself is cut out first, so a room really called "The Bell and Anchor"
  # is not a second act.
  #
  # IT APPLIES TO `#reading_first` AND NOT TO `#parse`, deliberately: this is a
  # rule about DEFERRING to a model, and `model: false` has none to defer to --
  # `rake game:sweep` and `Eval::Classifier::Offline` must still get an answer,
  # and the offline floor stays byte-identical because of it.
  JOINING_WORDS = /(?<![[:alnum:]])(?:and|then)(?![[:alnum:]])|,/i

  # What a line the grammar will not answer says, on the one consumer that has
  # no model behind it to hear about it. Never shown in the browser: there the
  # line simply goes to the classifier.
  MORE_THAN_ONE_ACT = "that line joins two things together, and reading it is the model's job".freeze

  # What `help` prints, and what an unknown word is refused with. Written out
  # rather than derived from `VERBS` because the aliases matter less than the
  # shape of a command does.
  HELP = [
    "go <exit>        move into one of the ways out (also: move, walk, enter)",
    "take <item>      pick up something lying here (also: get, grab, pick up)",
    "drop <item>      put down something you are carrying (also: put down, leave)",
    "talk <person>    resolve somebody standing here (also: speak, ask). The",
    "                 talking itself is prose, so this mode names them and stops",
    "read <item>      what is written on something, out of the records (also:",
    "                 examine, x, look at). Only a thing marked readable has",
    "                 words; this mode prints them and never writes them",
    "look             the engine's whole view of where you are (also: where,",
    "                 inventory, exits, items, who, state, vitals)",
    "stats            the player's level, hit die and three abilities, out of",
    "                 the world's own records (also: abilities)",
    "check <ability> [penalty]",
    "                 throw one d20 against strength, dexterity or will and",
    "                 print what it came up: d20-under the score, with the",
    "                 penalty taken off the TARGET. It writes nothing, and at a",
    "                 target of zero or less it says so instead of rolling",
    "harm <n>         take n hit points off the player, through",
    "                 Playthrough::Turn#harm!. Zero is death and death ends the",
    "                 playthrough (also: hurt, damage)",
    "mend <n>         put n back, up to the maximum. It never raises the dead",
    "                 (also: heal)",
    "help             this list",
    "",
    "A leading / is optional and is stripped: `/take slate` and `take slate` are",
    "the same line. A name is matched against the records: exactly first, then as",
    "an unambiguous prefix, then as an unambiguous fragment -- and a fragment is",
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

  # HOW ONE TYPED LINE WAS READ, whichever reader read it. `intent` is a
  # `Playthrough::Classifier::Intent` either way -- this grammar builds one
  # rather than inventing a second vocabulary -- so every dispatch downstream is
  # one path and not two, which is the whole reason the fallback is
  # trustworthy. A reading with no intent and no refusal is a command that only
  # reads.
  #
  # `wound` is the one reading that is not an `Intent` and cannot be: `harm 5`
  # names a NUMBER where every intent in the closed enum names a record, so
  # there is nothing for `Playthrough::Classifier::Intent` to hold. It is
  # `[:harm | :mend, n]` and `Playthrough::Mechanics#wound` is what acts on it.
  # `attempt` is the third reading that is not an `Intent`, for the same reason:
  # `check strength 2` names an ABILITY and a NUMBER. It is `[ability, penalty]`
  # and `Playthrough::Mechanics#attempt` acts on it.
  #
  # `resolved_by` is WHICH READER ANSWERED, one of `PATHS`, and it is on the
  # reading rather than worked out by each caller because the caller that most
  # needs it -- `Playthrough::Turn`, writing `scenes.resolved_by` -- is the one
  # furthest from the decision.
  Reading = Data.define(:intent, :refusal, :note, :understood, :wound, :attempt, :resolved_by) do
    def initialize(intent: nil, refusal: nil, note: nil, understood: nil, wound: nil, attempt: nil,
                   resolved_by: nil, **rest) = super

    # WHETHER THIS READING IS ONE A CALLER CAN ACT ON WITHOUT A MODEL: a record
    # was named and found. It is the ONE question `Playthrough::Turn` asks of
    # the grammar, and it is deliberately narrow -- a refusal is not an answer
    # here, because the grammar refuses for exactly the reasons the classifier
    # exists to get right (an ambiguous name, a name it could not place, a verb
    # it does not have). See `Playthrough::Turn#read_line`.
    def resolved? = !intent.nil? && !intent.subject.nil?
  end

  # A typed name against the records it could have meant. `record` is what the
  # command acts on; `candidates` is what to say when it is nil.
  Match = Data.define(:record, :candidates) do
    def found? = !record.nil?
    def ambiguous? = record.nil? && candidates.any?
  end

  # THE LINE WITHOUT ITS SLASH. One place, because the router, the parser and
  # the classifier prompt all have to agree about what the line says.
  def self.unslashed(command)
    text = command.to_s.strip

    text.start_with?(SLASH) ? text.delete_prefix(SLASH).strip : text
  end

  def self.slashed?(command) = command.to_s.strip.start_with?(SLASH)

  # HOW A LINE WAS READ, in one line, for a person -- printed by
  # `rake game:mechanics` above every report and stored as
  # `Playthrough::Mechanics::Report#understood`.
  #
  # THE SECOND NAME IS PART OF THE READING and is said here too, because since
  # the ruling of 2026-09-04 a line that named two things is refused -- and
  # `understood: take -> Perrin's private index` printed alone above that
  # refusal reads as though the index had been taken. What the engine understood
  # is both names; what it did is nothing. This grammar never produces one, so
  # nothing offline changes.
  def self.describe(intent)
    reading = "#{intent.action} -> #{label(intent.subject) || "nothing"}"
    reading += " (and #{label(intent.also_named)})" if intent.named_more_than_one?

    reading
  end

  # The name a record answers to, out of the class that owns the closed sets a
  # typed name is matched against. One definition, so the read-out, the refusals
  # and the counter rows cannot name the same person three ways.
  def self.label(record) = Playthrough::Classifier.label_for(record)

  attr_reader :playthrough

  # `classifier:` is the four closed-set readers and nothing else -- building
  # one makes no model call, and `#classify` is the only method on it that talks
  # to a model. It is passed in rather than always built so that a caller
  # already holding one (`Playthrough::Mechanics`) reads the same lists this
  # does: the set a model is offered is the set a typed name is matched
  # against, and sharing it is what stops the two ways in drifting apart about
  # what is reachable from here.
  def initialize(playthrough, classifier: nil)
    @playthrough = playthrough
    @classifier = classifier
  end

  def classifier = @classifier ||= Playthrough::Classifier.new(playthrough)

  # THE GRAMMAR'S ANSWER TO A LINE THE BROWSER SHOULD READ OFFLINE FIRST, or
  # NIL for a line it does not claim at all.
  #
  # Nil rather than an empty reading, and that is the whole seam: nil means
  # "this is not mine, hand it to the model", which is what an ordinary sentence
  # gets and what keeps this change from narrowing the game to a verb list.
  def reading_first(command)
    return nil unless claims?(command)

    reading = parse(command)
    return reading unless reading.resolved?
    return reading.with(intent: nil, understood: nil, refusal: MORE_THAN_ONE_ACT) if joins_two_acts?(command, reading.intent.subject)

    reading
  end

  # WHETHER THE LINE STILL JOINS SOMETHING ON, once the name it resolved to is
  # taken out of it. See `JOINING_WORDS` for why this exists and what it was
  # measured at. Every name the record answers to is removed, because the player
  # may have typed either one.
  def joins_two_acts?(command, subject)
    rest = normalize(self.class.unslashed(command))
    names_of(subject).each { |name| rest = rest.gsub(normalize(name), " ") }

    rest.match?(JOINING_WORDS)
  end

  # WHETHER THIS LINE IS ONE THE FIXED GRAMMAR READS FIRST, AND IT IS THE SLASH
  # AND NOTHING ELSE -- the captain's ruling of 2026-09-05, *"I think we should
  # only auto accept the slash commands."* See `MEANS_SOMETHING_ELSE` above for
  # the four measured wrong answers a leading verb alone produced.
  #
  # A line with no slash is not claimed at all, whatever it begins with, and
  # reaches `Playthrough::Classifier` exactly as it did before any of this. A
  # line WITH one is claimed whether or not the grammar can read it: `/frobnicate
  # the stamp` is claimed, refused here, and falls through -- the slash says how
  # to read the line, not that the line is readable.
  def claims?(command) = self.class.slashed?(command)

  # THE NO-MODEL PATH, and the one entry point for reading a line without a
  # model. Longest verb first so `pick up` is not read as `pick`, and the verb
  # has to be the whole line or be followed by a space -- otherwise `lease the
  # room` would parse as `l` and lose four words.
  #
  # A leading slash is taken off first, so `/take slate` is `take slate` here
  # and everywhere below. That is what gives `model: false` and every
  # `rake game:sweep` script the slash path for nothing.
  #
  # A line that matches no verb at all gets one more chance against the exit
  # names, which is what makes a bare `north` work in a world whose exits are
  # named that way. It is tried last and only on an unambiguous match, so it can
  # never shadow a verb.
  def parse(command)
    text = normalize_line(self.class.unslashed(command))
    return Reading.new if text.empty?

    verb = verb_for(text)
    argument = verb ? text[verb.length..].to_s.strip : text
    path = verb && ENGINE_VIEW.include?(verb) ? "engine_view" : "grammar"

    reading = case verb && VERBS.fetch(verb)
    when :look then Reading.new
    when :help then Reading.new(note: HELP)
    when :go then read_move(argument)
    when :take then read_take(argument)
    when :drop then read_drop(argument)
    when :talk then read_talk(argument)
    when :read then read_reading(argument)
    when :harm then read_wound(argument, :harm)
    when :mend then read_wound(argument, :mend)
    when :check then read_check(argument)
    else resolve(classifier.exits_here, text).found? ? read_move(text) : unknown(text)
    end

    reading.with(resolved_by: path)
  end

  # ONE OF THE ENGINE-VIEW COMMANDS, READ BY THIS GRAMMAR whichever mode is
  # running. Nil for anything else, which is what sends the line on.
  # `Playthrough::Mechanics` is the only caller: the browser has no engine view.
  def engine_view_reading(command, model:)
    text = normalize_line(self.class.unslashed(command))
    verb = verb_for(text)
    return nil unless verb && ENGINE_VIEW.include?(verb)
    return nil if in_the_fiction?(verb, text, model: model)

    parse(text)
  end

  # `check` IS THE ONE WORD IN `ENGINE_VIEW` A PLAYER PLAUSIBLY MEANS IN THE
  # FICTION. Nobody types `vitals` or `mend 3` at a story; *"check the ledger"*
  # is ordinary English, and swallowing it here would have made the instrument
  # cost the mode a verb. So with a model available, `check` is the engine's own
  # only when the next word is one of the three abilities -- otherwise the line
  # goes to `Playthrough::Classifier` like any other. With no model there is
  # nothing to hand it to, so this grammar answers and refuses.
  def in_the_fiction?(verb, text, model:)
    return false unless model && VERBS.fetch(verb) == :check

    resolve_ability(text[verb.length..].to_s.strip.split(/\s+/).first).nil?
  end

  def verb_for(text)
    downcased = text.downcase

    VERBS.keys.sort_by { |verb| -verb.length }
         .find { |verb| downcased == verb || downcased.start_with?("#{verb} ") }
  end

  # THE CLOSED SET AN ACTION READS AGAINST, one hop through the class that owns
  # it -- so this grammar and the model are offered the same lists.
  def offered_for(action) = classifier.offered_for(action)

  private

  def normalize_line(text) = text.to_s.strip.gsub(/\s+/, " ")

  # --- reading the command --------------------------------------------------

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

  # READING SOMETHING, against BOTH item sets at once -- what is lying here and
  # what is in the player's hands. The same closed set
  # `Playthrough::Classifier#build_intent` resolves an `examine` against, in the
  # same order, so this grammar and the classifier cannot disagree about which
  # note `read the note` meant. Nothing is moved either way.
  def read_reading(argument)
    readable = classifier.items_here + classifier.items_carried
    return Reading.new(refusal: "read what? Here and in your hands: #{names(readable)}") if argument.blank?

    match = resolve(readable, argument)
    return Reading.new(refusal: cannot_find("thing here or in your hands", argument, match, readable)) unless match.found?

    intent(:examine, item: match.record)
  end

  # A NUMBER OF HIT POINTS, which is the one argument in this grammar that is
  # not a name. It is read strictly -- digits and nothing else, and greater than
  # zero -- because a number is the whole of what the command means and a
  # tolerant reading of `harm a lot` would have to invent one.
  #
  # Zero is refused rather than accepted as a no-op: somebody who typed it meant
  # something, and quietly doing nothing is the answer that teaches nothing.
  def read_wound(argument, kind)
    unless argument.to_s.strip.match?(/\A[1-9][0-9]*\z/)
      return Reading.new(refusal: "#{kind} how much? `#{kind} <n>` takes a whole number of hit points " \
                                  "greater than zero, and #{argument.presence.inspect} is not one")
    end

    amount = argument.to_i
    Reading.new(wound: [ kind, amount ], understood: "#{kind} -> #{amount} hit point#{"s" unless amount == 1}")
  end

  # AN ABILITY AND AN OPTIONAL PENALTY, which is the other argument shape in this
  # grammar that is not a name off a closed set of records -- `Character::ABILITIES`
  # IS the closed set, and it is three words long and lives in code rather than
  # in the database.
  #
  # The ability is matched exactly or as an unambiguous prefix (`check dex`),
  # which is the first two of `HOW_A_NAME_MATCHES` and deliberately not the
  # third: a fragment match over a three-word list would let `check ill` mean
  # `will`, and there is no record here for a player to have been reading a name
  # off.
  #
  # The penalty is read strictly -- digits, and zero IS allowed, because zero is
  # what the command means without one and typing it is not a mistake. That is
  # the opposite of `#read_wound`'s rule, and for the opposite reason: `harm 0`
  # asks for a change and would make none, while `check strength 0` asks for a
  # roll and gets exactly the roll it asked for.
  def read_check(argument)
    words = argument.to_s.strip.split(/\s+/)
    if words.empty?
      return Reading.new(refusal: "check what? `check <ability> [penalty]`, and an ability is: " \
                                  "#{Character::ABILITIES.join(", ")}")
    end

    ability = resolve_ability(words.first)
    unless ability
      return Reading.new(refusal: "#{words.first.inspect} is not one of the three abilities. There is: " \
                                  "#{Character::ABILITIES.join(", ")}")
    end

    penalty = words[1]
    if penalty && !penalty.match?(/\A[0-9]+\z/)
      return Reading.new(refusal: "a penalty is a whole number of points taken off the target, and " \
                                  "#{penalty.inspect} is not one")
    end

    Reading.new(attempt: [ ability, penalty.to_i ],
                understood: "check -> #{ability}#{" (penalty #{penalty.to_i})" if penalty.to_i.positive?}")
  end

  # One of the three, exactly or as an unambiguous prefix. Nil for anything else,
  # which is a refusal rather than a guess.
  def resolve_ability(typed)
    typed = typed.to_s.downcase
    return typed.to_sym if Character::ABILITIES.include?(typed.to_sym)

    matches = Character::ABILITIES.select { |ability| ability.to_s.start_with?(typed) }
    matches.one? ? matches.first : nil
  end

  # This grammar's answer, in the classifier's own vocabulary.
  def intent(action, **resolved)
    built = Playthrough::Classifier::Intent.new(action: action, **resolved)
    Reading.new(intent: built, understood: self.class.describe(built))
  end

  # A word that is not in the table. The grammar comes with the refusal rather
  # than a suggestion to type `help`: with no model behind it there is nothing
  # here to guess what was meant, so the honest answer is the whole of what this
  # grammar understands. In the browser this refusal is never shown -- the line
  # goes to the classifier instead.
  def unknown(text)
    Reading.new(
      refusal: "I do not understand #{text.to_s.split.first.inspect}. The no-model grammar is fixed:",
      note: HELP
    )
  end

  # --- resolving a typed name -----------------------------------------------

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
  # model (`#cast_names`) -- so both have to be matchable here, or this grammar
  # would refuse a name the classifier accepts. A player types "Neb" as readily
  # as "Neb Halloran", which is the same reason
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
    records.map { |record| self.class.label(record) }.presence&.join(", ") || "nothing"
  end
end
