# `Playthrough::Grammar`: one typed line read without a model, against the
# closed sets of the room the playthrough stands in.
module EngineVectors::Grammar
  SOURCES = [ "app/models/playthrough/grammar.rb", "config/engine/playthrough/grammar.yml",
              "app/models/playthrough/classifier.rb", "app/models/playthrough/physical_action.rb",
              "app/models/item.rb" ].freeze
  NOTES = "Four kinds of case, told apart by the name's first word. `unslashed` is Grammar.unslashed " \
          "and Grammar.slashed? of one string. `word` is Grammar.word_for(action), null where there is " \
          "no one word. `line` stands in the room named `world` (a world in `worlds`; see " \
          "lib/engine_vectors/room.rb for its shape) and reads `typed`: claims is #claims?, " \
          "reading_first and parse the two readings, and engine_view and engine_view_offline " \
          "#engine_view_reading with model: true and model: false. A reading is {intent, refusal, " \
          "note, understood, wound, attempt, resolved_by} with nulls left out; an intent's records are " \
          "their ids and `physical` is the attempt's token; a note that is the whole help text is " \
          "written \"help\" and its lines are the `help` constant. `line_for` is #line_for of each of " \
          "the room's physical attempts, in the order the attempts are listed.".freeze

  # THE LINES THE MODEL TESTS READ, room by room, so each is a case.
  TESTED = {
    "office" => [
      "/frobnicate the stamp", "hello", "what about that key then", "wait", "north", "go to the supply closet",
      "take the ward stamp", "talk to Rowe", "drop the daybook", "read the ward stamp", "look at the sky",
      "stats", "vitals", "harm 5", "mend 2", "check strength", "help", "harm 3", "look",
      "/go to the supply closet", "/talk to Rowe", "/take the ward stamp", "/drop the daybook",
      "/inspect the ward stamp", "/read the ward stamp", "/take the daybook", "/drop the ward stamp", "/go to Rowe",
      "/take the crown", "/go to the supply closet and then back", "/take the ward stamp, then read it",
      "/attack Halkett Rowe", "/attack Rowe", "/hit halkett", "/strike Rowe", "/attack the bell", "/attack",
      "attack Halkett Rowe", "attack the problem", "/throw the daybook at Halkett Rowe", "/throw the ward stamp at Rowe",
      "/throw the daybook at the supply closet", "/hurl the daybook at Rowe", "/toss the daybook at Rowe", "/throw",
      "/throw the daybook", "/throw the tide-slate at Rowe", "/throw the ward stamp at the core",
      "/throw the daybook at the moon", "/throw the daybook at Rowe and take the stamp",
      "throw the daybook at Halkett Rowe", "throw the switch", "throw a party", "/throw the daybook at Rowe",
      "/go", "/talk", "/take", "/drop", "/inspect", "/anything at all"
    ],
    "office_register" => [ "/take the ward", "/take the ward stamp" ],
    "office_apron" => [ "/take the ward stamp and the apron", "/take the ward stamp and the copy-room apron",
                        "take the ward stamp and the apron" ],
    "office_tavern" => [ "move the supply closet shelf aside", "walk the supply closet perimeter", "leave the ward office",
                         "take a look at the ward stamp", "/go to The Bell and Anchor",
                         "/throw the daybook at the bell and anchor" ],
    "office_supply_room" => [ "/throw the daybook at the supply" ],
    "office_hat" => [ "/throw the flat hat at Rowe" ]
  }.freeze

  # THE ROOMS EVERY VERB IS SWEPT THROUGH, with every name the room answers to.
  SWEPT = %w[office physical empty castless nowhere].freeze

  UNSLASHED = [ "/take slate", "  /take slate  ", "take slate", "read the s/v ledger", "//take slate", "", "/",
                " / ", "/ go north", "\t/look\n", "go /north" ].freeze

  NUMBERS = [ "0", "1", "3", "12", "-2", "two", "05", "1 2" ].freeze
  ABILITIES = [ "strength", "dex", "w", "d", "s", "luck", "strength 2", "will x", "dexterity 0" ].freeze

  def self.constants_table
    { "worlds" => EngineVectors::Rooms::WORLDS.slice(*(TESTED.keys + SWEPT)).to_a, "help" => Playthrough::Grammar::HELP }
  end

  def self.cases
    unslashed + words + lines + line_fors
  end

  def self.unslashed
    UNSLASHED.map do |typed|
      EngineVectors.case_for("unslashed #{typed.inspect}", { "typed" => typed },
                             { "unslashed" => Playthrough::Grammar.unslashed(typed),
                               "slashed" => Playthrough::Grammar.slashed?(typed) })
    end
  end

  def self.words
    actions = (Playthrough::IntentSchema::INTENTS + Playthrough::Grammar::VERBS.values.map(&:to_s)).uniq
    actions.map do |action|
      EngineVectors.case_for("word #{action}", { "action" => action }, Playthrough::Grammar.word_for(action.to_sym))
    end
  end

  def self.lines
    (TESTED.keys | SWEPT).flat_map do |world|
      EngineVectors.rolled_back do
        room = EngineVectors::Rooms.build!(world)
        typed = (TESTED.fetch(world, []) + (SWEPT.include?(world) ? swept(room) : [])).uniq
        grammar = room.grammar
        typed.map { |line| EngineVectors.case_for("line #{world} #{line.inspect}", { "world" => world, "typed" => line }, read(grammar, line)) }
      end
    end
  end

  def self.read(grammar, line)
    {
      "claims" => grammar.claims?(line),
      "reading_first" => EngineVectors::Room.reading(grammar.reading_first(line)),
      "parse" => EngineVectors::Room.reading(grammar.parse(line)),
      "engine_view" => EngineVectors::Room.reading(grammar.engine_view_reading(line, model: true)),
      "engine_view_offline" => EngineVectors::Room.reading(grammar.engine_view_reading(line, model: false))
    }
  end

  # Every verb alone and before every name the room answers to, before a name
  # it does not, and each numeric and ability verb before the arguments it
  # parses; then every throw of every throwable thing at every aim, and every
  # physical attempt's own line and its halves swapped.
  def self.swept(room)
    classifier = room.classifier
    names = (classifier.exits_here.map(&:name) + classifier.characters_here.flat_map { |person| [ person.fullname, person.nickname ] } +
             classifier.items_here.map(&:name) + classifier.items_carried.map(&:name)).compact_blank.uniq
    arguments = [ "" ] + names + names.map { |name| "the #{name.downcase}" } + [ "the moon", "the" ]
    verbs = Playthrough::Grammar::VERBS.keys.flat_map do |verb|
      extra = case Playthrough::Grammar::VERBS.fetch(verb)
      when :harm, :mend then NUMBERS
      when :check then ABILITIES
      else []
      end
      (arguments + extra).map { |argument| "/#{verb} #{argument}".strip }
    end
    throwable = (classifier.items_carried + classifier.items_here).map(&:name) + [ "the moon" ]
    aims = classifier.characters_here.map(&:fullname) + classifier.exits_here.map(&:name) + [ "the moon" ]
    throws = throwable.product(aims).map { |thing, aim| "/throw #{thing} at #{aim}" }
    attempts = classifier.physical_actions.flat_map do |choice|
      [ "/#{choice.kind} #{choice.argument}", "/#{choice.kind} #{choice.argument.split(/ (?:with|to) /).reverse.join(" with ")}" ]
    end
    verbs + throws + attempts + [ "north", "the supply closet", "The Supply Closet", "/The Supply Closet", "/pick up the rag" ]
  end

  def self.line_fors
    %w[office physical].flat_map do |world|
      EngineVectors.rolled_back do
        room = EngineVectors::Rooms.build!(world)
        grammar = room.grammar
        room.classifier.physical_actions.each_with_index.map do |choice, index|
          EngineVectors.case_for("line_for #{world} #{index}", { "world" => world, "token" => choice.token },
                                 grammar.line_for(choice))
        end
      end
    end
  end
end
