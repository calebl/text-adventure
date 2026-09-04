# THE ENGINE, WALKED BY A SCRIPT, WITH NOBODY AT THE KEYBOARD.
#
# WHY IT EXISTS. Five engine defects were found in one evening of play -- an
# invented door into a room that was already written, a two-noun line that acted
# on one noun and said nothing about the other, "take everything" counted as
# drift, one person counted as two, an exit cap that bounded one answer instead
# of one room. Every one of them was found by a person typing, and every one of
# them is now guarded by a unit test written afterwards. Nothing walks the
# engine end to end unless somebody sits down and does it.
#
# So: stored scripts of typed lines, played through `Playthrough::Mechanics` in
# its no-model mode, with expectations asserted against THE RECORDS after each
# line. Where the player stands, what leads out of there and whether it is
# written yet, what is lying here, what is being carried, and what was refused.
# Not a word of prose is read, because no prose is written.
#
# WHAT MAKES IT DIFFERENT FROM `rake eval:run`, which also plays a script
# against a seeded world:
#
#   eval:run     the whole loop, models and all. It measures NARRATION against
#                the records, costs money, is noisy enough to need a rank test,
#                and never runs in CI. See EVALUATION.md.
#   game:sweep   the engine underneath, and nothing above it. Deterministic to
#                the row, free, offline, and it runs in `bin/rails test`. It
#                asserts rather than measures: a run passes or it fails.
#
# THREE THINGS MAKE IT DETERMINISTIC, and they are worth stating because a
# sweep that wandered would be worse than none:
#
#   1. NO MODEL, guarded rather than intended. `EngineSweep.without_a_model`
#      replaces `BaseAgent.new` for the length of the run, so a call made from
#      anywhere in the engine raises `EngineSweep::ModelCalled` instead of
#      reaching a provider. `BaseAgent` is the one gate every call in this app
#      goes through, which is what makes one seam enough.
#   2. ITS OWN COPY OF THE WORLD. The seed file is loaded under a title of this
#      module's own (`EngineSweep::Walk::TITLE_SUFFIX`), so a sweep never reads,
#      writes or deletes the world somebody has been playing -- and the whole
#      walk runs inside a transaction that is rolled back, so it leaves nothing
#      at all. Run it against a database mid-game and both are unharmed.
#   3. THE WORLD DOES NOT MOVE UNDERNEATH IT. `WorldMechanic` runs on the
#      story's clock, and the clock is `MAX(scenes.story_timestamp)` -- which
#      only advances when a Scene is written, and no-model mode writes none. So
#      The Lunar Cartographer's nightly shuffle is not suppressed here; it
#      simply never comes due. Nothing had to be switched off to get repeatable
#      exits, which is the kind of determinism worth having.
#
# WHAT IT CANNOT SEE, stated plainly rather than left to be discovered. With the
# classifier switched off, a defect that lives in how a MODEL read the line is
# out of reach: `Playthrough::Overreach`, the `also_named` half of a two-noun
# line, and one person answered under two names are all classifier-path
# behaviour and stay pinned by `Playthrough::ClassifierTest`. What the sweep
# holds of those turns is the half the fixed grammar can still answer for -- see
# the script comments, which say so turn by turn.
#
# THE REFUSALS OF 2026-09-04 ARE THE WORKED EXAMPLE OF THAT LINE.
# `Playthrough::Refusal` is one author read by both modes, so what a script can
# assert is whether a line is refused and whether anything moved -- which is
# the whole of the ruling as the engine sees it. What it cannot assert is the
# classifier answer that triggers two of the three shapes.
# `one-act-per-line.yml` walks what is reachable and names, shape by shape,
# what is not and where that half is pinned instead.
module EngineSweep
  # Raised when anything under a sweep tries to build an agent. Not rescued
  # anywhere: a sweep that quietly made a model call would be a different
  # instrument with the same name.
  class ModelCalled < StandardError; end

  # A script that does not parse, or asks for an expectation that does not
  # exist. Loud, because a fixture typo that read as "no expectation" would
  # make a script pass by saying nothing.
  class InvalidScript < StandardError; end

  DIRECTORY = Rails.root.join("lib/engine_sweep/scripts")

  # Every stored script, in a stable order.
  def self.scripts = Dir.glob(DIRECTORY.join("*.yml")).sort.map { |path| Script.load(path) }

  # Plays them all and returns one Result each. Ordinary Ruby objects rather
  # than assertions, so the rake task and the test can each say what they need
  # to about the same run.
  def self.run(scripts = self.scripts)
    without_a_model { scripts.map { |script| Walk.new(script).play } }
  end

  # THE GUARD. `BaseAgent.new` is where every model call in this app begins, so
  # standing in front of it is the whole of "no network, no key, no spend" --
  # and it fails the sweep rather than silently answering, because a fake answer
  # would make the sweep measure the fake.
  #
  # The original method is put back in an `ensure`, including when a script
  # raises, so a failing sweep does not leave a poisoned class behind for the
  # rest of a test run.
  def self.without_a_model
    original = BaseAgent.method(:new)

    BaseAgent.singleton_class.send(:define_method, :new) do |*_args, **options, &_block|
      raise ModelCalled, "a sweep asked for a model (BaseAgent.new#{options.any? ? " #{options.inspect}" : ""}); " \
                         "the engine sweep is offline by definition"
    end

    yield
  ensure
    BaseAgent.singleton_class.send(:define_method, :new, original)
  end
end
