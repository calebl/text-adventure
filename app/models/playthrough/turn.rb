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

    # WHAT THE PLAYER TYPED, AND WHAT THE TURN DID WITH IT, filed under the turn
    # it produced.
    #
    # Here rather than in each of the four branches, and for the same reason
    # the classifier is stamped here: this is the one place that has the
    # command AND the scene for every branch, so a branch added later cannot
    # forget to record it. `Scene#typed` is the durable answer -- it used to be
    # recoverable only by scraping the classifier's stored prompt, which the
    # conversation pruner can still be asked to throw away (Chat::KEEP_TURNS),
    # so the player's own words disappeared from older turns.
    #
    # `resolved_action` and `acted_on` are the same argument taken one step
    # further. `typed` is what the player SAID; the records around it are what
    # the world IS afterwards. Neither is what the turn DID, and without that
    # a check reading a narration against the state before it has nothing to
    # read -- which is why the prose denying a resolved `take` was invisible to
    # every check in `Story::Audit`. See `#resolution_for`.
    #
    # AND WHO WAS IN THE ROOM, on every branch too, which is the third column
    # this one place now owns. `characters_scenes` used to be written by the
    # two branches that happened to have a cast in hand -- an arrival and a
    # talk -- so 184 of the 480 baseline turns of 2026-09-03 had no record of
    # who was present at all, and the one thing the records could say about
    # presence was said on 62% of turns. It is a DERIVED SNAPSHOT now: taken
    # from `Character.present_in` and never the source of it (see
    # `#cast_of`), so the direction the Tide Post defect ran in is reversed.
    scene&.update!(typed: command, characters: cast_of(scene), **resolution_for(intent))

    # THE CONVERSATIONS THIS TURN HAD, filed under the turn.
    #
    # The classifier is stamped here rather than in its own class because it
    # runs before the branch that produces the scene -- it is the one call every
    # turn makes and the only record of what the player actually typed on a turn
    # that was not a conversation. Every branch stamps its own; see
    # `BaseAgent#attribute_to!`.
    classifier.agent.attribute_to!(scene) if scene

    # And the retention cap is applied -- which by default does nothing at all,
    # because nothing is pruned unless `TA_CHAT_KEEP_TURNS` says so. Still called
    # on every turn so that setting it takes effect without a sweep.
    # See Playthrough#prune_conversations!.
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
    stand_in!(destination, scene: scene)

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
  #                       turn log shows. Its cast is stamped by `#play` from
  #                       the whereabouts records, along with `typed` and what
  #                       the turn did; this branch used to write the
  #                       protagonist and the person spoken to, because that
  #                       cast was the only thing keeping them in the room.
  #                       `Character.present_in` keeps them now.
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
  # A playthrough with no character has nobody to NAME as having picked the
  # thing up, so it narrates the attempt instead. Since the inventory moved to
  # `items.playthrough_id` the record itself no longer needs one -- the guard is
  # about the sentence handed to the narrator, and it stays because a fact that
  # says "somebody picked it up" is not a fact. Nothing in the app creates such
  # a playthrough, but `Playthrough#character` is optional and a world can be
  # seeded without a protagonist.
  def take_item(item, command, &block)
    taker = playthrough.character
    return narrate(command, &block) if taker.nil?

    carry!(item)

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

    put_down!(item)

    Scene::Narrator.new(playthrough).narrate(command, fact: dropped_fact(item, here), &block)
  end

  # THE THREE WRITES THAT MOVE THE WORLD, each one named rather than left inline
  # in the branch above it.
  #
  # They are named because `Playthrough::Mechanics` -- the mechanics-only mode,
  # which bypasses the classifier and the narrator and makes no model call at
  # all -- has to write the world through exactly these statements. A mode built
  # to test movement and possession on their own is worth nothing if it moves
  # the player with a second copy of the line that moves the player: it would
  # then be testing itself. So the line lives here, in the loop that owns it,
  # and both modes call it.
  #
  # Nothing else about these is new. They are the same updates, in the same
  # order relative to the prose, with the same guards in the callers.

  # `scene:` defaults to the one the playthrough is already on, so a caller with
  # no scene to hand -- which is every caller in mechanics mode, where a turn
  # produces no prose -- moves the player without wiping the turn log.
  def stand_in!(destination, scene: playthrough.current_scene)
    playthrough.update!(current_location: destination, current_scene: scene)
  end

  # INTO THE PARTY'S HANDS, which is `items.playthrough_id` and not the
  # protagonist's `character_id`. The protagonist is one row per story, so
  # writing the inventory there gave every playthrough of a world one shared
  # set of things: a new game opened holding what the last one had picked up.
  # `Item` is in exactly one of three places, so the other two are written nil.
  def carry!(item)
    item.update!(playthrough: playthrough, character: nil, location: nil)
  end

  def put_down!(item)
    item.update!(playthrough: nil, character: nil, location: playthrough.current_location)
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

  # WHAT THE TURN DID, in the two columns `Scene` keeps it in.
  #
  # The classifier's answer, with one correction: the two branches that resolve
  # a record and then cannot act on it. `take_item` narrates instead when the
  # playthrough has no protagonist to carry anything, and `drop_item` when it is
  # standing nowhere to put anything down in -- nothing in the app produces
  # either, and both are shapes a hand-made playthrough really has. The action
  # is still what the player was doing; the RECORD is dropped, because writing
  # one there would say a row moved that did not, and `Scene#took?` is the seam
  # a check trusts outright.
  #
  # Everything else is recorded exactly as it resolved, including a reach that
  # found nothing: an action with no record is the drift case, told apart here
  # the same way `Playthrough::Classifier::Intent` tells it apart.
  # WHO WAS IN THE ROOM WHEN THIS TURN HAPPENED, snapshotted onto the turn.
  #
  # A SNAPSHOT AND NOT THE RECORD. `Character.present_in` is where somebody is
  # NOW; this is where they were then, and the two are different questions that
  # a single column cannot answer. `Eval::Richness` asks whether a narration
  # named the person who was standing there, `Story::Audit#check_stillness`
  # asks whether anybody was in the room on a run of turns that changed
  # nothing, and both frozen corpora carry the answer beside the prose -- all
  # three read a past moment that the whereabouts column, which has no history,
  # cannot reconstruct. So the join table is KEPT, and only its direction
  # changed: it is written from the records rather than being the only place
  # the records ever lived.
  #
  # Read off `scene.location` rather than `playthrough.current_location`,
  # because on a move the two are the same room only after `#stand_in!` has
  # run, and the cast belongs to the room the scene is in either way.
  def cast_of(scene)
    here = scene.location || playthrough.current_location
    return [] if here.nil?

    Scene::Generator.characters_present(here)
  end

  def resolution_for(intent)
    acted_on =
      if (intent.take? && playthrough.character.nil?) || (intent.drop? && playthrough.current_location.nil?)
        nil
      else
        intent.subject
      end

    { resolved_action: intent.action.to_s, acted_on: acted_on }
  end

  def classifier
    @classifier ||= Playthrough::Classifier.new(playthrough)
  end
end
