# ONE DRAW: A KIND STOOD UP IN A COPY OF ITS WORLD, REALIZED WHOLE, AND ROLLED
# BACK.
#
# THE ONLY THING IN THE LAB THAT SPENDS MONEY, and the only thing in the debug
# surface that spends money at all. `DebugController`, `MachineryController` and
# `MapController` each say in their header that they are OBSERVERS -- they read,
# and they do not classify, generate or catch the world up. This one generates.
# So: it is reached by a POST and never by a GET, and no page load may buy a
# call.
#
# NOTHING IS STOOD IN FOR. `Location::Generator#realize!` runs whole, in the
# order and the conversation the app makes its two calls in, against a stub
# created by `Location::Generator.create_stub!` -- the app's own one path for a
# room being born. The prompt is therefore the app's, character for character,
# and the lab's whole contribution is four PARAMETERS: a name, a teaser, an
# `inside` band and a danger. AGENTS.md's rule for a world, and here it is the
# difference between an instrument and a second prompt source.
#
# THE THREE GUARANTEES ARE `Eval::Realization::Stage`'S AND THEY ARE WHY THIS IS
# SAFE TO POINT AT ONE OF THE CAPTAIN'S UNIVERSES:
#
#   1. ITS OWN COPY OF THE WORLD, loaded from the seed file under a title of its
#      own and inside a transaction that is rolled back. His stories are never
#      read for the prompt, never moved and never written to. When the draw ends
#      there is no room, no cast and no story left behind -- the stored `row` on
#      the sample is the only thing that survives, and it survives complete.
#   2. NO MODEL CALL TO GET INTO POSITION. The whole of the setup is a seed load
#      and row surgery; the only calls are the two being watched.
#   3. THE WORLD DOES NOT MOVE UNDERNEATH IT. No `Scene` is written and no turn
#      is played, so `WorldMechanic` never runs -- which is why a kind can be
#      drawn in `The Lunar Cartographer`, the world the prompt bench has to
#      refuse.
#
# AND THE TITLE IS PUT BACK, always. `Location::Generator#story_context` states
# the story's TITLE in the detail prompt, so a draw staged on
# `The Iron Gate Descends (realization lab: kind 4)` would be measuring a prompt
# no player gets -- and inviting a model to write the words "realization lab"
# into a room's lore. `Eval::Realization::Stage.load_world!` is the one place
# that rename lives and this calls it rather than repeating it.
#
# THE STAGING IS `Stage`'S AND NO LONGER THIS FILE'S. A corpus case's identity
# used to be a room in a checked-in world file that `Stage#wind_back!` FOUND, so
# a kind the captain typed -- in no world file, with nothing to find -- needed
# its own copy of the standing-up here. `Stage` now CREATES the stub from a
# `teaser` on the case, which is the promotion step, so this file hands it an
# ad-hoc case and keeps nothing of its own but the case and the arm.
#
# THAT IS ONE SPELLING RATHER THAN TWO, and it is the spelling the promotion
# needs: a kind drawn here and the same kind promoted into
# `Eval::Realization::Corpus` stand the same stub up in the same order, so the
# corpus case really re-runs what the lab scored. Two copies of it would be two
# answers to what a typed stub is, which is exactly what this codebase refuses.
#
# ONE SAMPLE PER TRANSACTION, deliberately: the development database has one
# writer, so a lab draw and a long rake task cannot both be inside a transaction
# at once. Scoping it to a single draw is what keeps the lab usable while
# something else is running.
class Lab::Realization::Runner
  # WHAT THE LAB CALLS ITS COPIES, beside `Eval::Realization::Stage::LABEL`'s
  # "realization bench". Its own word so a title that somehow escaped a rollback
  # says which instrument made it.
  LABEL = "realization lab".freeze

  # THE SHAPE ON THE AD-HOC CASE. `shape` is what a board groups by, and a lab
  # draw is not one of the corpus's shapes -- naming it `lab` keeps a stored row
  # that ever reached a board legible instead of masquerading as a corpus case.
  SHAPE = "lab".freeze

  attr_reader :kind, :arm

  # THE MODEL, NAMED EXPLICITLY, WITH THE ROTATION OFF -- `Eval::Classifier::Arm`,
  # shared with all three benches rather than copied. The default is
  # `BaseAgent::REMOTE_MODEL_IDS.first`, which is what a player's rooms are
  # really written by, so a sample is a sample of the game and not of whatever
  # `OPENROUTER_MODEL` happened to be set to.
  def initialize(kind, arm: BaseAgent::REMOTE_MODEL_IDS.first)
    @kind = kind
    @arm = Eval::Classifier::Arm.all([ arm ]).first
  end

  # Draws one sample and returns it, persisted. Raises
  # `Eval::Realization::Stage::Unstageable` when the world has no file or the
  # kind names a way back the world does not have -- both of which are a person's
  # mistake and want a sentence rather than a stack trace, and both of which are
  # now the stage's own refusal rather than a second error class of this file's.
  def draw!
    reading = read!

    kind.samples.create!(row: reading.to_h.transform_keys(&:to_s))
  end

  private

  # THE CALL, INSIDE THE ROLLED-BACK COPY. Everything worth keeping is read out
  # into Ruby before the copy goes, because after that there is nothing left to
  # read -- and `Eval::Concurrency.rolled_back` and NOT
  # `ActiveRecord::Base.transaction`: read that module's header before changing
  # the line.
  #
  # `Stage.open` IS NOT USED, and the difference is the one thing this method
  # still owns: the arm has to be pinned around the call and the transaction has
  # to close after the reading is out. `.open` yields inside its own rollback and
  # would put the pinning inside it too, which is a fact about a run rather than
  # about a world. So the stage is built and stood up here, in a rollback of this
  # method's own -- everything about HOW it stands up is `Stage`'s.
  def read!
    kase = ad_hoc_case
    reading = nil

    Eval::Concurrency.rolled_back do
      standing = Eval::Realization::Stage.new(kase, label: LABEL).stand!

      arm.pinned { reading = bench.build(kase, standing, arm, 1) }
    end

    reading
  end

  # A CASE THE CORPUS DOES NOT HOLD, carrying the kind's own facts so
  # `Eval::Realization::Stage` CREATES the stub rather than looking for one --
  # `teaser` is the key that decides that, and it is the same key a promoted case
  # carries into the checked-in corpus.
  #
  # `expects_new_ground: true` because a kind he typed IS somewhere the story
  # points into -- he typed it to see it built -- so `no_new_ground` is judgeable
  # and a room whose every exit restated a place the world already had is
  # flagged. That is the one defect in this area with a measured figure behind it.
  #
  # `expects_inside` IS LEFT OUT, and deliberately. It is the corpus's hand label
  # for whether this stub's world plainly holds a building, which is a DIFFERENT
  # claim from the kind's own `expects_inside` expectation -- see
  # `Lab::Realization::Pick`'s header. Leaving it nil takes the sample out of both
  # inside checks' denominators, which is what a case with no label asks for.
  #
  # AND THE REST OF THE EXPECTATION IS NOT PUT ON IT EITHER. A kind's `expects_*`
  # columns are scored by `Lab::Realization::HitRate` off the sample's stored row,
  # offline and retroactively; putting them on the ad-hoc case as well would be a
  # second place a draw's expectation was written down, and the two could
  # disagree. The expectation reaches the corpus only through the promotion, which
  # is a person committing a file.
  def ad_hoc_case
    Eval::Realization::Corpus::Case.new(
      id: "lab-kind-#{kind.id}", story: kind.world, room: kind.name, teaser: kind.teaser,
      reached_from: kind.reached_from.presence, danger: kind.danger.presence,
      inside: kind.inside.presence, population: kind.population.presence,
      expects_new_ground: true, shape: SHAPE,
      why: "typed in the realization lab as #{kind.name.inspect}"
    )
  end

  # THE BENCH, FOR ITS ORCHESTRATION AND NOTHING ELSE. `#build` reads the facts
  # off the standing BEFORE the call (which is what rolls and memoizes the cast
  # the prompt then states), realizes, and reads the receipts off the `messages`
  # rows afterwards. A second implementation of what a realization WAS is exactly
  # what this codebase refuses, so the lab borrows that one.
  #
  # `corpus:` is the real corpus and is unused by `#build` -- it is `#run`'s
  # input. `io: nil` because a lab draw prints nothing.
  def bench = @bench ||= Eval::Realization::Bench.new(corpus: Eval::Realization.corpus, io: nil)
end
