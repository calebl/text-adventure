# The branch bench's protocol over the speech corpus: one pending moment a
# case, staged in a rolled-back transaction, and the narrator's request the
# engine builds from it. Only what stages the moment differs.
class Eval::Prompt::Speech::Bench < Eval::Prompt::Branches::Bench
  private

  def capture = Eval::Prompt::Speech.capture(corpus)
  def identity(captured) = Eval::Prompt::Speech.identity(captured)
  def stage(kase, game) = Eval::Prompt::Speech::Stage.new(kase, game).prepare
end
