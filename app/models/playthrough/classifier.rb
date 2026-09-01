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
  # `item` carries both directions: what a `take` resolved to on the floor and
  # what a `drop` resolved to in the player's hands. Which way it moves is the
  # action's business, not the record's -- see `Playthrough::Turn`.
  Intent = Data.define(:action, :destination, :speaker, :item) do
    # Defaulted so a caller naming only what it resolved reads the way it
    # means -- `Intent.new(action: :other)` is a turn that reached for nothing.
    def initialize(destination: nil, speaker: nil, item: nil, **rest) = super

    def move? = action == :move
    def talk? = action == :talk
    def take? = action == :take
    def drop? = action == :drop

    # The record the loop acts on, whichever kind it turned out to be. There is
    # at most one, by construction.
    def subject = destination || speaker || item

    # THE DRIFT CASE. The player was reaching for something -- a way out, a
    # person, a thing to pick up -- and the closed set the app built had
    # nothing in it that matched. The turn still narrates, and the reach is
    # counted: see Playthrough::Drift.
    def reached_for_nothing?
      Playthrough::Drift::ACTIONS.include?(action.to_s) && subject.nil?
    end
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
      drop    - they are putting down, leaving or giving up something they carry
      other   - anything else

    Then pick what they aimed it at from the lists you are given, copied
    exactly: a way out for `move`, a person for `talk`, a thing lying here for
    `take`, a thing they are carrying for `drop`. If the intent is none of
    those, or they named a place, a person or a thing that is not on those
    lists, answer `nothing`. Do not answer with a place they cannot reach from
    here, a person who is not here, something that is not lying in this room, or
    something they are not carrying.
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
    items = items_here
    carried = items_carried

    answer = agent
      .with_schema(Playthrough::IntentSchema.for(
        exit_names(exits) + cast_names(cast) + item_names(items) + item_names(carried)
      ))
      .ask(command_prompt(command, exits, cast, items, carried))
      .content

    intent = build_intent(answer["intent"], answer["target"], exits, cast, items, carried)
    record_drift(command, intent, exits, cast, items, carried) if intent.reached_for_nothing?
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
  def characters_here
    location = playthrough.current_location
    return [] if location.nil?

    Scene::Generator.characters_present(location) - [ playthrough.story.protagonist ].compact
  end

  # WHAT THE PLAYER CAN PICK UP: the items the records say are lying in this
  # room, which is the whole of it. Not what anybody here is holding -- taking
  # something off a person is a different act, with somebody on the other side
  # of it who has an opinion, and no record says how that goes.
  #
  # An empty list is the normal case today and costs nothing: nothing in the
  # app creates an item, so only a seed file or a test puts one on the floor.
  # That is `ta-item-registry`'s job; this end of the seam is what makes it
  # worth building.
  def items_here
    location = playthrough.current_location
    return [] if location.nil?

    Item.lying_in(location).order(:id).to_a
  end

  # WHAT THE PLAYER IS CARRYING, which is the closed set `drop` resolves
  # against -- and it is a closed set for the same reason `take`'s is: putting
  # something down is a state change, so the app has to know which row moved.
  # A player cannot drop what the records do not say they hold, however
  # confidently a narration once said they picked it up.
  def items_carried
    character = playthrough.character
    return [] if character.nil?

    Item.for_character(character).order(:id).to_a
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

      ## The Player Types
      #{command}
    PROMPT
  end

  private

  # Only ever one of the two, and only when the name resolved. `examine`,
  # `take` and `other` carry no target today -- they all fall through to
  # `Scene::Narrator`, which answers the raw command anyway -- so resolving one
  # would be building a seam with nothing on the other side of it.
  def build_intent(intent, target, exits, cast, items = [], carried = [])
    action = Playthrough::IntentSchema::INTENTS.include?(intent) ? intent.to_sym : :other
    name = target.to_s

    case action
    when :move then Intent.new(action: action, destination: find_exit(exits, name))
    when :talk then Intent.new(action: action, speaker: find_character(cast, name))
    when :take then Intent.new(action: action, item: find_item(items, name))
    when :drop then Intent.new(action: action, item: find_item(carried, name))
    else Intent.new(action: action)
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

  # By name, out of the list that was offered. Two items in one room with the
  # same name are indistinguishable to a player typing the name, so the first
  # is as right an answer as there is -- and `find` on the ordered list makes
  # which one it is stable rather than whatever the database felt like.
  def find_item(items, name)
    items.find { |item| item.name.to_s.casecmp?(name) }
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

    " (#{connection.distance}, #{connection.travel_method})"
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
end
