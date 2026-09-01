# One turn of the game: the player types something, the world answers, and the
# playthrough ends up wherever that left them.
#
# This is the loop, and it lives in `app/models` rather than in a controller or
# a rake task on purpose -- there is no `rake game:play` and there is not meant
# to be. The browser is the only front end, and its whole share of the loop is
# handing this class a string and a block to write chunks into.
#
# `move` and `talk` are the two outcomes that do something particular.
# Everything else -- `examine`, `take`, a move nobody can make, a `talk` with
# nobody to talk to, anything unclassifiable -- falls through to
# `Scene::Narrator`, which answers the raw command in prose. They are told
# apart so the classification is honest and so the branches that need to exist
# have somewhere to land, not because they all behave differently yet.
class Playthrough::Turn
  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # Plays `command` and returns the Scene it produced, or nil if it produced
  # none. Chunks of prose are yielded as they become available: `Scene::Narrator`
  # streams token by token, and a schema'd generator yields its finished
  # paragraph in one piece, because a schema'd call cannot stream (see the
  # comment on `Scene::Narrator`).
  def play(command, &block)
    # THE WORLD MOVES FIRST, and it moves whether or not anybody was watching.
    # Every boundary the story's clock has passed since the last turn is applied
    # here, in Ruby, before the player's command is even read -- so the exits
    # the classifier resolves against are tonight's exits and not last night's.
    # One `SELECT MAX` and one row per mechanic when nothing is due, which is
    # almost every turn; zero tokens either way. See WorldMechanic.
    playthrough.story.catch_up_world!

    intent = classifier.classify(command)

    scene = if intent.destination
      move_to(intent.destination, &block)
    elsif intent.speaker
      talk_to(intent.speaker, command, &block)
    else
      narrate(command, &block)
    end

    # THE CONVERSATIONS THIS TURN HAD, filed under the turn.
    #
    # The classifier is stamped here rather than in its own class because it
    # runs before the branch that produces the scene -- it is the one call every
    # turn makes and the only record of what the player actually typed on a turn
    # that was not a conversation. Every branch stamps its own; see
    # `BaseAgent#attribute_to!`.
    classifier.agent.attribute_to!(scene) if scene

    # And the audit trail older than the last few dozen turns goes, because this
    # is a SQLite file on a laptop. See Playthrough#prune_conversations!.
    playthrough.prune_conversations!

    scene
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

    scene = Scene::Generator.new(
      destination, previous_scene: playthrough.current_scene, playthrough: playthrough
    ).generate!
    playthrough.update!(current_location: destination, current_scene: scene)

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
  #                       turn log shows. `scene.characters` is the protagonist
  #                       and whoever they spoke to, so the next turn in this
  #                       room still knows that person is standing in it.
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
      characters: [ playthrough.story.protagonist, character ].compact.uniq,
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

  # Everything else. `Scene::Narrator` owns its own turn end to end: it streams,
  # it persists in an `ensure` so a closed tab does not lose the prose, and it
  # sets `current_scene` itself. Movement is the one thing it cannot do, which
  # is why it does not touch `current_location`.
  def narrate(command, &block)
    Scene::Narrator.new(playthrough).narrate(command, &block)
  end

  def classifier
    @classifier ||= Playthrough::Classifier.new(playthrough)
  end
end
