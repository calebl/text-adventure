# THE GAME WITH THE PROSE TAKEN OUT: move, take, drop, and read the records
# back. No model call, no API key, no network, and no narration at all.
#
# WHY IT EXISTS. Every turn of the real loop runs two model calls -- the
# classifier that decides what was typed, and the narrator or generator that
# writes what the player reads -- and a turn that goes wrong could have gone
# wrong in either of them or in the engine underneath. Testing movement and
# possession therefore meant testing them alongside prose quality, with the
# prose in the way. This mode removes both calls and leaves the engine:
#
#   the classifier  is replaced by a fixed grammar (`VERBS`) and a name
#                   resolver (`#resolve`), against the SAME closed sets
#                   `Playthrough::Classifier` builds -- its `exits_here`,
#                   `characters_here`, `items_here` and `items_carried` are
#                   called directly here, so the two modes can never disagree
#                   about what is reachable, present or holdable. Building a
#                   classifier makes no model call; only `#classify` does, and
#                   this class never calls it.
#   the narrator    is replaced by nothing. What comes back is the engine's own
#                   view of the world, straight off the records, plus one line
#                   saying what just changed.
#
# WHAT IT WRITES is `playthroughs.current_location_id` and `items.character_id`
# / `items.location_id`, through `Playthrough::Turn#stand_in!`, `#carry!` and
# `#put_down!` -- the same three statements the narrated loop moves the world
# with. That is the whole point: a mechanics mode with its own copy of the line
# that moves the player would be testing itself. It writes no `Scene`, so it
# costs no story time and leaves the turn log alone.
#
# WHAT IT DOES NOT DO is realize a stub. Walking into an unwritten room in the
# real loop calls `Location::Generator`, which is a model call; here the
# playthrough simply moves into the stub and the read-out says the room has
# never been written. That is honest -- the row and the graph are real, the
# prose is what is missing -- and it is the one place the narrated loop would
# have reached for a model.
class Playthrough::Mechanics
  # THE WHOLE GRAMMAR. A closed table rather than anything clever: what is being
  # tested is the engine, so the parser in front of it has to be the part nobody
  # has to wonder about. Two-word verbs are matched before their one-word
  # prefixes -- see `#verb_for`.
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
    "help" => :help
  }.freeze

  # What `help` prints, and what an unknown word is refused with. Written out
  # rather than derived from `VERBS` because the aliases matter less than the
  # shape of a command does.
  GRAMMAR = [
    "go <exit>        move into one of the ways out (also: move, walk, enter)",
    "take <item>      pick up something lying here (also: get, grab, pick up)",
    "drop <item>      put down something you are carrying (also: put down, leave)",
    "look             the engine's whole view of where you are (also: where,",
    "                 inventory, exits, items, who, state)",
    "help             this list",
    "",
    "A name is matched against the records: exactly first, then as an",
    "unambiguous prefix, then as an unambiguous fragment. Case and extra spaces",
    "do not matter. Nothing here calls a model."
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

  # ONE COMMAND AND WHAT IT DID. `change` is the one-line diff of the write --
  # nil when the command only read -- and `refusal` is why nothing happened.
  # Never both. `state` is always there, because the reason to type anything in
  # this mode is to see the records afterwards.
  Report = Data.define(:command, :change, :refusal, :note, :state) do
    def refused? = refusal.present?
    def changed? = change.present?

    def to_s
      lines = []
      lines << "  changed:  #{change}" if changed?
      lines << "  refused:  #{refusal}" if refused?
      lines.concat(note.map { |line| "  #{line}" }) if note.present?
      lines << state.to_s
      lines.join("\n")
    end
  end

  # A typed name against the records it could have meant. `record` is what the
  # command acts on; `candidates` is what to say when it is nil.
  Match = Data.define(:record, :candidates) do
    def found? = !record.nil?
    def ambiguous? = record.nil? && candidates.any?
  end

  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # Runs one typed line and returns a Report. Never raises on bad input: an
  # unknown word, an unknown name and an ambiguous name are all refusals with
  # the valid options in them, because the point of the mode is to be able to
  # tell a rejected command from a broken engine at a glance.
  def run(command)
    verb, argument = parse(command)

    report =
      case verb
      when nil, :look then read
      when :help then read(note: GRAMMAR)
      when :go then go(argument)
      when :take then take(argument)
      when :drop then drop(argument)
      else unknown(argument)
      end

    report.with(command: command)
  end

  # The read-out with nothing changed. What the console prints before the first
  # command, and what every read verb produces.
  def read(note: nil)
    Report.new(command: nil, change: nil, refusal: nil, note: note, state: state)
  end

  # THE ENGINE'S VIEW, out of the same four readers `Playthrough::Classifier`
  # offers a model. Rebuilt on every call: `sets` holds a classifier, and a
  # classifier memoizes nothing it reads.
  def state
    State.new(
      location: playthrough.current_location,
      exits: sets.exits_here,
      items_here: sets.items_here,
      carried: sets.items_carried,
      present: sets.characters_here
    )
  end

  private

  def go(argument)
    return refuse("go where? The ways out are: #{names(sets.exits_here)}") if argument.blank?

    match = resolve(sets.exits_here, argument)
    return refuse(cannot_find("way out", argument, match, sets.exits_here)) unless match.found?

    from = playthrough.current_location
    turn.stand_in!(match.record)

    change("moved: #{from&.name || "nowhere"} -> #{match.record.name}#{unwritten(match.record)}")
  end

  def take(argument)
    return refuse("this playthrough has no protagonist, so nobody can carry anything") if playthrough.character.nil?
    return refuse("take what? Lying here: #{names(sets.items_here)}") if argument.blank?

    match = resolve(sets.items_here, argument)
    return refuse(cannot_find("thing lying here", argument, match, sets.items_here)) unless match.found?

    item = match.record
    was = item.location
    turn.carry!(item)

    change("took: #{item.name} (was lying in #{was&.name || "nowhere"}, now carried by #{playthrough.character.fullname})")
  end

  def drop(argument)
    return refuse("this playthrough is standing nowhere, so there is no room to put anything down in") if playthrough.current_location.nil?
    return refuse("drop what? Carrying: #{names(sets.items_carried)}") if argument.blank?

    match = resolve(sets.items_carried, argument)
    return refuse(cannot_find("thing you are carrying", argument, match, sets.items_carried)) unless match.found?

    item = match.record
    was = item.character
    turn.put_down!(item)

    change("dropped: #{item.name} (was carried by #{was&.fullname || "nobody"}, now lying in #{playthrough.current_location.name})")
  end

  # THE PARSER. Longest verb first so `pick up` is not read as `pick`, and the
  # verb has to be the whole line or be followed by a space -- otherwise
  # `lease the room` would parse as `l` and lose four words.
  #
  # A line that matches no verb at all gets one more chance against the exit
  # names, which is what makes a bare `north` work in a world whose exits are
  # named that way. It is tried last and only on an unambiguous match, so it
  # can never shadow a verb.
  def parse(command)
    text = command.to_s.strip.gsub(/\s+/, " ")
    return [ nil, nil ] if text.empty?

    verb = verb_for(text)
    return [ VERBS.fetch(verb), text[verb.length..].to_s.strip ] if verb
    return [ :go, text ] if resolve(sets.exits_here, text).found?

    [ :unknown, text ]
  end

  def verb_for(text)
    downcased = text.downcase

    VERBS.keys.sort_by { |verb| -verb.length }
         .find { |verb| downcased == verb || downcased.start_with?("#{verb} ") }
  end

  # HOW A TYPED NAME BECOMES A RECORD, and the whole of what this mode has where
  # the real loop has a model. Exact first, then an unambiguous prefix, then an
  # unambiguous fragment -- so `take daybook` finds the "Ward Office 12 daybook"
  # and `go the` finds nothing rather than guessing. Case and repeated spaces
  # are ignored, because somebody typing at a prompt is not a JSON enum.
  #
  # An exact match that hits two records takes the first, which is exactly what
  # `Playthrough::Classifier#find_item` does with two identical items in one
  # room: to a player typing the name they are the same thing, and `find` on an
  # id-ordered list makes which one stable.
  def resolve(records, typed)
    wanted = normalize(typed)
    return Match.new(record: nil, candidates: []) if wanted.empty?

    exact = records.select { |record| normalize(record.name) == wanted }
    return Match.new(record: exact.first, candidates: exact) if exact.any?

    [ :start_with?, :include? ].each do |how|
      hits = records.select { |record| normalize(record.name).public_send(how, wanted) }
      return Match.new(record: hits.first, candidates: hits) if hits.one?
      return Match.new(record: nil, candidates: hits) if hits.many?
    end

    Match.new(record: nil, candidates: [])
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

  def names(records)
    records.map(&:name).presence&.join(", ") || "nothing"
  end

  # Said out loud on arrival, because a stub is the one thing this mode reads
  # differently from the narrated loop: there, walking in writes the room.
  def unwritten(location)
    return "" unless location.stub?

    " (a stub -- nobody has written this room; the narrated game realizes it on arrival)"
  end

  def change(line)
    Report.new(command: nil, change: line, refusal: nil, note: nil, state: state)
  end

  def refuse(reason)
    Report.new(command: nil, change: nil, refusal: reason, note: nil, state: state)
  end

  # A word that is not in the table. The grammar comes with the refusal rather
  # than a suggestion to type `help`: there is no model here to guess what was
  # meant, so the honest answer is the whole of what this mode understands.
  def unknown(text)
    Report.new(
      command: nil,
      change: nil,
      refusal: "I do not understand #{text.to_s.split.first.inspect}. This mode has a fixed grammar and no model to guess with:",
      note: GRAMMAR,
      state: state
    )
  end

  # The loop that owns the three writes. Built once; it holds nothing but the
  # playthrough, and no model call is made by building it.
  def turn
    @turn ||= Playthrough::Turn.new(playthrough)
  end

  # The classifier, for its four closed-set readers and nothing else. It is the
  # inverse of the resolver above -- the list a model is offered is the list a
  # typed name is matched against -- and sharing it is what stops the two modes
  # drifting apart about what is reachable from here. `#classify` is the only
  # method on it that talks to a model, and this class never calls it.
  def sets
    @sets ||= Playthrough::Classifier.new(playthrough)
  end
end
