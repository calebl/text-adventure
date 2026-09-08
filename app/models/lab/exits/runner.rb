# ONE DRAW: A VANTAGE STOOD UP IN A COPY OF ITS WORLD WITH SOME OF THAT WORLD
# TAKEN OFF THE BOOKS, REALIZED WHOLE, AND ROLLED BACK.
#
# IT IS `Lab::Realization::Runner` WITH THREE METHODS CHANGED, and that is the
# design rather than a shortcut. A sample of the exits pick IS a whole
# realization: `Location::Generator#agent` memoizes ONE conversation for both
# calls and the exits prompt says *"consistent with the description you just
# wrote"*, so there is no exits-only call to buy and no cheaper draw to make. The
# two labs therefore buy the identical thing and read it from opposite ends, and a
# second implementation of "what a lab draw is" is exactly what this codebase
# refuses -- the same argument that moved the staging out of the parent and into
# `Eval::Realization::Stage`.
#
# SO THE THREE GUARANTEES ARE STILL `Stage`'S, unchanged and inherited: its own
# copy of the world loaded from the seed file inside a transaction that is rolled
# back; no model call to get into position; and no `Scene` written, so the world
# does not move underneath it. His stories are never read for the prompt, never
# moved and never written to, and the stored `row` on the sample is the only
# thing that survives.
#
# WHAT IT CHANGES, AND EACH IS ONE OF THE CAPTAIN'S ANSWERS OF 2026-09-08:
#
#   `#label`         its own word, so a staging title that ever escaped a
#                    rollback says which instrument made it.
#   `#shape`         `exits` rather than `lab`, so a stored row that ever reached
#                    a board is legible instead of masquerading as the other
#                    lab's draw.
#   `#ad_hoc_case`   carries the vantage's `absent` list, which is Call 1 (a) and
#                    the reason this lab can measure anything at all.
#
# WHY `absent` IS THE WHOLE OF IT. `Lab::Exits`'s header has the finding in full:
# a vantage typed into a world that still holds unrealized stubs has its exits
# call name THOSE, correctly, and `Location::Generator#connect_exit!` discards the
# `inside` band for a place that already exists. Four bought draws opened zero new
# places and threw away every pick. `Stage#stand!` already destroys the named
# rooms before it stands the stub up, so the list is carried and nothing here
# performs surgery of its own.
#
# THE BAND AND THE POPULATION WORD ARE DELIBERATELY NOT PASSED. A vantage has no
# `inside` column -- `Lab::Exits::Vantage`'s header says why it is unreachable
# rather than refused -- so the stub is born with no extent, `Location#place?` is
# false, and `#write_exits!` asks the question this lab exists to watch. Passing
# either would cancel the measurement.
class Lab::Exits::Runner < Lab::Realization::Runner
  # WHAT THIS LAB CALLS ITS COPIES, beside `Lab::Realization::Runner::LABEL`'s
  # "realization lab" and `Eval::Realization::Stage::LABEL`'s "realization
  # bench".
  LABEL = "exits lab".freeze

  # THE SHAPE ON THE AD-HOC CASE. Not one of the corpus's shapes and not the
  # other lab's either: `Eval::Realization::Board` groups by it, so a row that
  # reached one says where it came from.
  SHAPE = "exits".freeze

  # THE SUBJECT'S OWN WORD FOR ITSELF. The parent calls it `kind` because that is
  # what it draws; this draws a vantage, and a reader of this file should not have
  # to translate. Same object either way.
  def vantage = kind

  def label = LABEL

  def shape = SHAPE

  private

  # A CASE THE CORPUS DOES NOT HOLD, carrying the vantage's own facts so
  # `Eval::Realization::Stage` CREATES the stub rather than looking for one --
  # `teaser` is the key that decides that, exactly as it is for the other lab and
  # for a promoted case.
  #
  # `absent:` IS THE ONE FIELD THE PARENT DOES NOT SET, and it is the point of the
  # subclass. A name this world does not have is refused by
  # `Stage#remove_the_absent!` with a sentence naming both, which the page shows
  # as a flash: a person's mistake, and it wants a sentence rather than a stack
  # trace.
  #
  # `expects_new_ground: true` because a vantage he typed IS somewhere the story
  # points into -- he typed it to see what lies beyond it -- so `no_new_ground` is
  # judgeable and a draw whose every exit restated a place the world already had
  # is flagged. On this lab that check is nearly the subject: an answer that
  # opened nothing is an answer whose every pick was discarded.
  #
  # `expects_inside` IS LEFT OUT. It is the corpus's hand label for whether this
  # stub's world plainly holds a building, which is a DIFFERENT claim from the
  # vantage's own quantifier -- one is about the world, the other about what the
  # answer should say. Leaving it nil takes the draw out of both of the scorer's
  # inside checks' denominators, which is what a case with no label asks for, and
  # keeps this lab's figures the only ones reading its own expectation.
  #
  # AND THE REST OF THE EXPECTATION IS NOT PUT ON IT EITHER, for the parent's
  # reason: `Lab::Exits::HitRate` scores it off the sample's stored row, offline
  # and retroactively, so putting it on the case as well would be a second place a
  # draw's expectation was written down and the two could disagree.
  def ad_hoc_case
    Eval::Realization::Corpus::Case.new(
      id: "lab-vantage-#{vantage.id}", story: vantage.world, room: vantage.name,
      teaser: vantage.teaser, reached_from: vantage.reached_from.presence,
      danger: vantage.danger.presence, absent: vantage.absent_names,
      expects_new_ground: true, shape: shape,
      why: "typed in the exits lab as #{vantage.name.inspect}"
    )
  end
end
