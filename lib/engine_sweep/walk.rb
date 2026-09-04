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
      games = {}
      engines = {}

      script.steps.each do |step|
        steps += 1
        game = games[step.player] ||= playthrough_for(story)

        if step.reseed?
          note = reseed!(step.renames)
          # EVERY CACHED ENGINE IS READING STALE ROWS after a load: the loader
          # has put items back where the file says they belong and may have
          # renamed a room the player is standing in. Dropping them costs
          # nothing (a `Playthrough::Mechanics` memoises only its classifier,
          # which memoises nothing it reads) and reading the records afterwards
          # is the whole point of the step.
          engines.clear
          games.each_value(&:reload)
          failures.concat(check(engines[step.player] ||= engine_for(game), step, note: note))
        else
          failures.concat(walk(engines[step.player] ||= engine_for(game), step))
        end
      end

      # AGAINST THE FILE AS LAST LOADED, not as first read: a `reseed:` step may
      # name a version of the file that renames a room, and comparing a
      # deliberate rename against the original would read as an invented
      # doorway and a lost room -- which is exactly what these invariants are
      # for catching when nobody asked for it.
      failures.concat(EngineSweep::Invariants.new(story, seed: @loaded).check.map { |broken| broken.with(script: script) })

      raise ActiveRecord::Rollback
    end

    EngineSweep::Result.new(script: script, steps: steps, failures: failures)
  end

  private

  def walk(mechanics, step)
    before = Playthrough::Drift.count
    report = mechanics.run(step.typed)
    drifts = Playthrough::Drift.count - before

    failures(step, report, drifts: drifts)
  end

  # THE RECORDS AFTER A RE-SEED, WITH NOTHING ELSE HAVING HAPPENED.
  # `Playthrough::Mechanics#read` is the read-out the console prints before the
  # first command -- fresh state, nothing changed, nothing refused -- so every
  # expectation on a `reseed:` step is a statement about what the load did to
  # the world, and `changed: false` is true of it by construction.
  def check(mechanics, step, note:)
    failures(step, mechanics.read(note: note), drifts: 0)
  end

  def failures(step, report, drifts:)
    step.expectation.check(report, drifts: drifts).map do |unmet|
      EngineSweep::Result::Failure.new(script: script, step: step, unmet: unmet, state: report.state.to_s)
    end
  end

  def engine_for(game) = Playthrough::Mechanics.new(game, model: false)

  # The same `WorldSeed::Loader` call `bin/rails db:seed` makes, over the copy
  # this walk has been playing. What it reconciled and what it warned about
  # become the step's note, so a script can pin the reconciliation itself --
  # a doorway left where the world put it, a room recognized under a new name --
  # and not only the records it left behind.
  def reseed!(renames)
    loader = WorldSeed::Loader.new(sweep_document(renames), source: script.seed_file)
    loader.load!

    [ "re-seeded from #{File.basename(script.seed_file)}",
      *loader.reconciled.map { |line| "reconciled: #{line}" },
      *loader.warnings.map { |line| "WARNING: #{line}" } ].join("\n")
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
    WorldSeed::Loader.new(sweep_document, source: script.seed_file).load!
  end

  # The file's document with the title changed and whatever the step renames,
  # freshly duplicated on every call -- a loader assigns into what it is given,
  # and a re-seed step loads the document a second time. Kept as `@loaded` so
  # the invariants are checked against the version that was last loaded.
  def sweep_document(renames = {})
    @loaded = seed_document.deep_dup
    @loaded["story"]["title"] = "#{script.story}#{TITLE_SUFFIX}"
    rename!(@loaded, renames)
    @loaded
  end

  # A DIFFERENT VERSION OF THE FILE, and only in the names. Locations are
  # renamed wherever a name is a natural key -- the row, both ends of every
  # connection, the opening arrival's room and any cast placement -- because a
  # file with a room renamed in one of those places and not the others is a
  # file `WorldSeed::Loader#validate!` refuses, and a script that produced one
  # would be testing the validation rather than the re-seed.
  def rename!(document, renames)
    locations = renames["locations"] || {}
    items = renames["items"] || {}
    return if locations.empty? && items.empty?

    name = ->(value) { locations.fetch(value, value) }

    Array(document["locations"]).each { |row| row["name"] = name.call(row["name"]) }
    Array(document["connections"]).each { |row| row["between"] = Array(row["between"]).map { |value| name.call(value) } }
    document["opening_scene"]["location"] = name.call(document["opening_scene"]["location"]) if document["opening_scene"]
    Array(document["characters"]).each { |row| row["location"] = name.call(row["location"]) if row["location"].present? }

    (Array(document["locations"]) + Array(document["characters"])).each do |owner|
      Array(owner["items"]).each { |row| row["name"] = items.fetch(row["name"], row["name"]) }
    end
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
