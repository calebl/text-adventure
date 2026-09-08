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
# WHY IT IS NOT A `Stage`. A corpus case's identity is a room in a checked-in
# world file, and `Stage#wind_back!` FINDS that room; a kind the captain typed is
# in no world file, so there is nothing to find. That is the one mechanical thing
# between a scored sample and a corpus case, and closing it -- teaching `Stage` to
# CREATE the room from a `teaser:` on the case -- is the promotion step, filed
# apart from this. Until then the staging a typed kind needs lives here, and it
# reuses `Stage`'s world load, `Stage::Standing`'s readers and `Bench#build`'s
# orchestration unchanged rather than reimplementing any of them.
#
# ONE SAMPLE PER TRANSACTION, deliberately: the development database has one
# writer, so a lab draw and a long rake task cannot both be inside a transaction
# at once. Scoping it to a single draw is what keeps the lab usable while
# something else is running.
class Lab::Realization::Runner
  class Unrunnable < StandardError; end

  # WHAT THE LAB CALLS ITS COPIES, beside `Eval::Realization::Stage::LABEL`'s
  # "realization bench". Its own word so a title that somehow escaped a rollback
  # says which instrument made it.
  LABEL = "realization lab".freeze

  # THE SHAPE ON THE AD-HOC CASE. `shape` is what a board groups by, and a lab
  # draw is not one of the corpus's shapes -- naming it `lab` keeps a stored row
  # that ever reached a board legible instead of masquerading as a corpus case.
  SHAPE = "lab".freeze

  # THE WAY IN'S OWN LABEL, when a kind names the neighbour it was reached from.
  # `LocationConnection` derives `time_to_travel` from these two and refuses free
  # text, so they come from its tables. A short walk on foot is the quietest
  # possible way in: it is the doorway's label and nothing in a realization
  # prompt reads it, so a lab that offered a picker would be offering a knob with
  # nothing behind it.
  DISTANCE = "a short walk".freeze
  TRAVEL_METHOD = "walking".freeze

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

  # Draws one sample and returns it, persisted. Raises `Unrunnable` when the
  # world has no file or the kind names a way back the world does not have --
  # both of which are a person's mistake and want a sentence rather than a stack
  # trace.
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
  def read!
    kase = ad_hoc_case
    reading = nil

    Eval::Concurrency.rolled_back do
      story = Eval::Realization::Stage.load_world!(kind.world, title: title_for(kase))
      stub = stand_up!(story)
      open_the_way_in!(story, stub)

      standing = Eval::Realization::Stage::Standing.new(
        kase: kase, story: story, location: stub, generator: Location::Generator.new(stub)
      )

      arm.pinned { reading = bench.build(kase, standing, arm, 1) }
    end

    reading
  end

  # A CASE THE CORPUS DOES NOT HOLD, built to carry the two things `Bench#build`
  # reads off one: the id a stored row is labelled with, and the labels that
  # decide which checks may be judged on it.
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
  def ad_hoc_case
    Eval::Realization::Corpus::Case.new(
      id: "lab-kind-#{kind.id}", story: kind.world, room: kind.name,
      reached_from: kind.reached_from.presence, danger: kind.danger.presence,
      expects_new_ground: true, shape: SHAPE,
      why: "typed in the realization lab as #{kind.name.inspect}"
    )
  end

  def title_for(kase) = Eval::Realization::Stage.title_for(kase, label: LABEL)

  # THE STUB, THROUGH THE APP'S OWN CONSTRUCTOR FOR A ROOM BEING BORN. It rolls
  # the danger (`Location::Danger.for_a_new_room`), rolls the footprint inside
  # the `inside` band, keeps the population word and binds the story's arc if it
  # was waiting for a place by this name -- all of which a stub written here by
  # hand would have to remember to do.
  #
  # THE DECLARED DANGER IS APPLIED AFTER, which is `Eval::Realization::Stage#wind_back!`'s
  # own order and its reason: the roll is what a new room gets, and a case (or a
  # kind) that overrides it is reaching a shape the die rarely produces -- a
  # `dangerous` room, which is where the monstrous half of the cast prompt becomes
  # judgeable at all.
  def stand_up!(story)
    stub = Location::Generator.create_stub!(story, name: kind.name, teaser: kind.teaser,
                                            inside: kind.inside.presence,
                                            population: kind.population.presence)
    stub.update!(danger: kind.danger) if kind.danger.present?
    stub
  end

  # THE WAY BACK, IF THE KIND NAMED ONE. Both rows, because an exit is written in
  # both directions and a realization prompt's dead-end sentence is about the
  # place the player CAME FROM specifically -- `Eval::Realization::Scorer#correct_dead_end?`
  # cannot tell a way back from any other neighbour without it.
  #
  # A KIND WITH NO WAY BACK IS AN OPENING ROOM and is a legitimate draw: the
  # story's first room has no neighbour to have been named by, and it is realized
  # like every other room.
  def open_the_way_in!(story, stub)
    name = kind.reached_from.presence
    return if name.nil?

    other = story.locations.find_by(name: name)
    if other.nil?
      raise Unrunnable, "#{kind.world} has no place called #{name.inspect}, so that cannot be the " \
                        "way this kind was reached"
    end

    attributes = { distance: DISTANCE, travel_method: TRAVEL_METHOD }
    LocationConnection.create!(location: other, connected_location: stub, **attributes)
    LocationConnection.create!(location: stub, connected_location: other, **attributes)
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
