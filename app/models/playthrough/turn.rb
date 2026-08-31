# One turn of the game: the player types something, the world answers, and the
# playthrough ends up wherever that left them.
#
# This is the loop, and it lives in `app/models` rather than in a controller or
# a rake task on purpose -- there is no `rake game:play` and there is not meant
# to be. The browser is the only front end, and its whole share of the loop is
# handing this class a string and a block to write chunks into.
#
# `move` is the interesting outcome. Everything else -- `examine`, `take`, a
# `talk` with nobody to talk to, anything unclassifiable -- falls through to
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
    intent = classifier.classify(command)

    if intent.destination
      move_to(intent.destination, &block)
    else
      narrate(command, &block)
    end
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
    Location::Generator.new(destination).realize!

    scene = Scene::Generator.new(destination, previous_scene: playthrough.current_scene).generate!
    playthrough.update!(current_location: destination, current_scene: scene)

    block&.call(scene.description)
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
