# One turn of the game: the player types something, the world answers, and the
# playthrough ends up wherever that left them.
#
# This is the loop, and it lives in `app/models` rather than in a controller or
# a rake task on purpose -- there is no `rake game:play` and there is not meant
# to be. The browser is the only front end, and its whole share of the loop is
# handing this class a string and a block to write chunks into.
#
# `move`, `talk`, `take` and `drop` are the four outcomes that do something
# particular, and each of them writes a record before any prose exists.
# Everything else -- `examine`, a move nobody can make, a `talk` with nobody to
# talk to, a `take` of something that is not here, a `drop` of something the
# player is not carrying, anything unclassifiable -- falls through to
# `Scene::Narrator`, which answers the raw command in prose. They are told apart
# so the classification is honest and so the branches that need to exist have
# somewhere to land.
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
    elsif intent.item
      # BOTH DIRECTIONS OF ONE SEAM. The item is the resolved record either way;
      # the action says which way it moves. Dispatching on the action here
      # rather than on two different fields keeps the branch on a record --
      # `intent.item` is what makes this branch reachable at all.
      move_item(intent, command, &block)
    else
      narrate(command, intent: intent, &block)
    end

    # WHAT THE PLAYER TYPED, filed under the turn it produced.
    #
    # Here rather than in each of the four branches, and for the same reason
    # the classifier is stamped here: this is the one place that has the
    # command AND the scene for every branch, so a branch added later cannot
    # forget to record it. `Scene#typed` is the durable answer -- it used to be
    # recoverable only by scraping the classifier's stored prompt, which the
    # conversation pruner eventually throws away (Chat::KEEP_TURNS), so the
    # player's own words disappeared from older turns.
    scene&.update!(typed: command)

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
  # A playthrough with no character cannot hold anything, so it narrates the
  # attempt instead. Nothing in the app creates one, but `Playthrough#character`
  # is optional and a world can be seeded without a protagonist.
  def take_item(item, command, &block)
    taker = playthrough.character
    return narrate(command, &block) if taker.nil?

    item.update!(character: taker, location: nil)

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

    item.update!(character: nil, location: here)

    Scene::Narrator.new(playthrough).narrate(command, fact: dropped_fact(item, here), &block)
  end

  # What the narrator is told, in the app's own words. Stated as done, because
  # it is: the row is already written by the time this is read.
  def taken_fact(item, taker)
    "#{taker.fullname} has picked up the #{item.name} and is now carrying it" \
      "#{" -- #{item.description}" if item.description.present?}."
  end

  def dropped_fact(item, here)
    "The #{item.name} is no longer carried: it is now lying in #{here.name}, " \
      "where it stays until somebody picks it up."
  end

  # Everything else. `Scene::Narrator` owns its own turn end to end: it streams,
  # it persists in an `ensure` so a closed tab does not lose the prose, and it
  # sets `current_scene` itself. Movement is the one thing it cannot do, which
  # is why it does not touch `current_location`.
  #
  # `intent` is what the classifier decided, when the caller has one. It used
  # to be dropped here: a `move` that resolved to no exit, a `talk` with nobody
  # to answer and an `examine` all reached the narrator as the bare command, so
  # the narrator walked the player through the door anyway and the next arrival
  # contradicted it. Now a reach that resolved to nothing is stated as a fact
  # (`#reach_fact`) and the intent label goes along for the narrator's one line
  # about what kind of turn this is.
  def narrate(command, intent: nil, &block)
    Scene::Narrator.new(playthrough).narrate(command, fact: reach_fact(intent), intent: intent&.action, &block)
  end

  # WHAT THE RECORDS SAY ABOUT A REACH THAT FOUND NOTHING, in the app's own
  # words, through the same `fact:` seam `take` and `drop` use for what they
  # did. The classifier resolved the command against the closed set of what
  # is actually here and nothing matched; that is a fact about the world, not
  # an opinion about the prose, and the narrator is told it rather than left
  # to guess. The lists themselves are already in the prompt
  # (`Playthrough::Moment`), so this only has to say which one came up empty
  # and that nothing moved.
  #
  # The cost is the case where the classifier was wrong -- a real exit it failed
  # to match -- and the narrator now denies a door that is there. That is a
  # worse turn than before; the turn where it narrated a move that never
  # happened was a worse GAME, because the records and the prose parted ways.
  # Either way `Playthrough::Drift` has the row.
  def reach_fact(intent)
    return nil unless intent&.reached_for_nothing?

    here = playthrough.current_location&.name || "where they are"

    case intent.action
    when :move
      "The player reached for a way out that does not exist here. The ways out are " \
        "exactly the ones listed above, and none of them is what they tried. They have not moved: " \
        "they are still in #{here}."
    when :talk
      "The player tried to speak to somebody who is not here. The only people present are " \
        "the ones listed above; nobody else answers."
    when :take
      "The player reached for something that is not lying here. Nothing was picked up, and " \
        "they are carrying exactly what is listed above."
    when :drop
      "The player tried to put down something they are not carrying. Nothing changed hands, and " \
        "they are carrying exactly what is listed above."
    end
  end

  def classifier
    @classifier ||= Playthrough::Classifier.new(playthrough)
  end
end
