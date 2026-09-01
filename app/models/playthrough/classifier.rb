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
class Playthrough::Classifier
  # What one line of player input turned out to be.
  #
  # `destination` and `speaker` are RECORDS, and at most one of them is ever
  # set. A classification the loop cannot act on -- "go north" in a room with
  # no northward exit, "talk to the ghost" with nobody here -- leaves both nil
  # and keeps `action`, so the loop narrates the attempt instead of pretending
  # it worked. Being unable to do a thing is part of the game; silently doing a
  # different thing is not.
  Intent = Data.define(:action, :destination, :speaker) do
    def move? = action == :move
    def talk? = action == :talk
  end

  INSTRUCTIONS = <<~PROMPT.freeze
    You read one line of a text adventure player's input and say what they were
    trying to do. You do not narrate, you do not answer the player, and you do
    not decide whether they succeed.

    Pick the intent that fits best:
      move    - they are going somewhere else
      talk    - they are speaking to someone who is here
      examine - they are looking at something more closely
      take    - they are picking something up
      other   - anything else

    Then pick what they aimed it at from the lists you are given, copied
    exactly: a way out for `move`, a person for `talk`. If the intent is
    neither of those, or they named a place or a person that is not on those
    lists, answer `nothing`. Do not answer with a place they cannot reach from
    here or a person who is not here.
  PROMPT

  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # Returns an Intent. Raises rather than guessing when the call fails, for the
  # same reason every generator here raises: a swallowed failure reads
  # downstream as the player typing something the game did not understand.
  def classify(command)
    exits = exits_here
    cast = characters_here

    answer = agent
      .with_schema(Playthrough::IntentSchema.for(exit_names(exits) + cast_names(cast)))
      .ask(command_prompt(command, exits, cast))
      .content

    build_intent(answer["intent"], answer["target"], exits, cast)
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
  def characters_here
    location = playthrough.current_location
    return [] if location.nil?

    Scene::Generator.characters_present(location) - [ playthrough.story.protagonist ].compact
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
    @agent ||= BaseAgent.new(purpose: "classifier", playthrough: playthrough).with_instructions(INSTRUCTIONS)
  end

  def command_prompt(command, exits, cast)
    <<~PROMPT
      ## Where The Player Is
      #{playthrough.current_location&.name || "Nowhere in particular."}

      ## Ways Out
      #{exit_list(exits)}

      ## Who Is Here
      #{cast_list(cast)}

      ## The Player Types
      #{command}
    PROMPT
  end

  private

  # Only ever one of the two, and only when the name resolved. `examine`,
  # `take` and `other` carry no target today -- they all fall through to
  # `Scene::Narrator`, which answers the raw command anyway -- so resolving one
  # would be building a seam with nothing on the other side of it.
  def build_intent(intent, target, exits, cast)
    action = Playthrough::IntentSchema::INTENTS.include?(intent) ? intent.to_sym : :other
    name = target.to_s

    case action
    when :move then Intent.new(action: action, destination: find_exit(exits, name), speaker: nil)
    when :talk then Intent.new(action: action, destination: nil, speaker: find_character(cast, name))
    else Intent.new(action: action, destination: nil, speaker: nil)
    end
  end

  def find_exit(exits, name)
    exits.find { |location| location.name.to_s.casecmp?(name) }
  end

  # Either name resolves, because both are in the enum: a player types "talk to
  # Maren" as readily as they type the full name, and forcing the model to
  # translate one into the other is a step it can get wrong for no reason.
  def find_character(cast, name)
    cast.find { |character| character.fullname.to_s.casecmp?(name) || character.nickname.to_s.casecmp?(name) }
  end

  def exit_names(exits)
    exits.map(&:name)
  end

  def cast_names(cast)
    cast.flat_map { |character| [ character.fullname, character.nickname ] }
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

    " (#{connection.distance}, #{connection.travel_method})"
  end

  def cast_list(cast)
    lines = cast.map { |character| "- #{character.fullname}#{" (#{character.nickname})" if character.nickname.present?}" }

    lines.join("\n").presence || "Nobody. There is no one here to talk to."
  end
end
