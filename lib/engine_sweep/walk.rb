# ONE SCRIPT PLAYED AGAINST ITS OWN COPY OF A SEEDED WORLD.
#
# THE COPY IS THE POINT. The world file is loaded under a title of this class's
# own, so a sweep cannot read, move or delete anything in the world somebody has
# been playing -- and the whole walk runs inside a transaction that is rolled
# back at the end, so a sweep leaves a database exactly as it found it. Run
# `rake game:sweep` against a half-played development database and both survive:
# the sweep sees a pristine world, the database keeps its game.
#
# It is also what makes the sweep repeatable. `WorldSeed::Loader` is idempotent
# on natural keys, so loading into a world that had been PLAYED would find the
# daybook wherever the last player left it and the exits somebody's turn had
# written -- a starting state that drifts with use is not a starting state.
#
# A SCRIPT MAY PLAY THE COPY MORE THAN ONCE. Steps carry a `player`, and each
# distinct one gets its own `Playthrough` of the same story -- which is what
# makes "two people playing one world carry two different sets of things"
# assertable offline. The rooms stay shared, because they are the world.
#
# NOTHING IS ISOLATED FROM THE ENGINE ITSELF. The walk is `Playthrough::Mechanics`
# with `model: false`, which is `Playthrough::Turn#stand_in!`, `#carry!` and
# `#put_down!` -- the same statements the browser moves the world with. A sweep
# with its own copy of the line that moves the player would be testing itself.
class EngineSweep::Walk
  # Appended to the world's title so the copy cannot collide with the real one.
  # A story is matched by title and by nothing else, which is what makes one
  # word enough to keep two worlds apart.
  TITLE_SUFFIX = " (engine sweep)"

  attr_reader :script

  def initialize(script)
    @script = script
  end

  # Returns an `EngineSweep::Result`. Raises only on a broken script or a model
  # call: a step whose expectation did not hold is a finding, not an exception,
  # because the point is to report every one of them at once.
  def play
    failures = []
    steps = 0

    # `requires_new` because this may be called from inside the suite's own
    # transaction, where a plain nested `transaction` shares its parent and
    # `ActiveRecord::Rollback` silently does nothing at all.
    ActiveRecord::Base.transaction(requires_new: true) do
      story = load_world!
      players = {}

      script.steps.each do |step|
        steps += 1
        mechanics = players[step.player] ||= Playthrough::Mechanics.new(playthrough_for(story), model: false)
        failures.concat(walk(mechanics, step))
      end

      failures.concat(EngineSweep::Invariants.new(story, seed: seed_document).check.map { |broken| broken.with(script: script) })

      raise ActiveRecord::Rollback
    end

    EngineSweep::Result.new(script: script, steps: steps, failures: failures)
  end

  private

  def walk(mechanics, step)
    before = Playthrough::Drift.count
    report = mechanics.run(step.typed)
    drifts = Playthrough::Drift.count - before

    step.expectation.check(report, drifts: drifts).map do |unmet|
      EngineSweep::Result::Failure.new(script: script, step: step, unmet: unmet, state: report.state.to_s)
    end
  end

  # The world file, with the title changed and nothing else. Parsed fresh on
  # every walk so two scripts against one world cannot share a mutated hash.
  def seed_document
    @seed_document ||= begin
      unless File.exist?(script.seed_file)
        raise EngineSweep::InvalidScript, "#{script.path}: there is no seeded world #{script.story.inspect} (#{script.seed_file})"
      end

      WorldSeed.parse(File.read(script.seed_file))
    end
  end

  def load_world!
    document = seed_document.deep_dup
    document["story"]["title"] = "#{script.story}#{TITLE_SUFFIX}"

    WorldSeed::Loader.new(document, source: script.seed_file).load!
  end

  # Where a player starts: the world's own opening arrival, in the world's
  # lowest-id realized room. The same two the browser hands a new playthrough --
  # see `PlaythroughsController#create` and `Helpers.mechanics_playthrough!`.
  #
  # ONE PER `player` NAMED IN THE SCRIPT, created the first time a step is typed
  # into it. A second playthrough of one world is the only way to sweep the
  # thing that made the inventory per-playthrough: what one party carries is not
  # what the other does, and a story-level column cannot say that.
  def playthrough_for(story)
    opening = story.locations.realized.order(:id).first
    raise EngineSweep::InvalidScript, "#{script.path}: #{script.story.inspect} has no realized room to stand in" if opening.nil?

    Playthrough.create!(story: story, character: story.protagonist,
                        current_location: opening, current_scene: story.opening_scene)
  end
end
