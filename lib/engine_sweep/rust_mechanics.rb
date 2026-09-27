# THE OFFLINE WALK'S TYPED STEPS, PLAYED BY THE RUST ENGINE.
#
# `EngineSweep::Conversation` is `Playthrough::Mechanics` with `model: false`,
# which is how a walk plays a typed line on Ruby. This answers the same four
# questions a walk asks of it -- `#run`, `#with_choice`, `#read` and `#state` --
# and plays each line through `Playthrough::RustEngine.play` instead: the
# engine's own no-model turn, on its own connection, in one transaction of its
# own. So it plays only on a database committed between steps
# (`EngineSweep::Parity::InProcess`), never inside the walk's rolled-back
# transaction.
#
# THE RECORDS ARE READ BY RUBY. The engine answers what it understood, what
# changed, what it refused and what it noted; everything else a dump holds is
# `Playthrough::Mechanics#state` over the rows the engine wrote, so a
# divergence is Ruby failing to read the world Rust left, not two engines
# describing their own.
#
# A browser step never comes here: `EngineSweep::BrowserTurn` plays it through
# `Playthrough::Session`, which is the switch itself.
class EngineSweep::RustMechanics
  # The engine answered with an error on a typed step.
  class Failed < StandardError; end

  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  def with_choice(choice)
    @choice = choice
    yield
  ensure
    @choice = nil
  end

  def run(line)
    answer = Playthrough::RustEngine.play(playthrough, line, decision: @choice)
    if (error = answer["error"])
      raise Failed, "the Rust engine failed on #{line.inspect}: #{error.fetch("kind")}: #{error.fetch("message")}"
    end

    report = answer.fetch("report")
    Playthrough::Mechanics::Report.new(
      command: line, understood: report["understood"], change: report["change"], refusal: report["refusal"],
      note: report["note"].presence, resolved_by: report["resolved_by"], state: state
    )
  end

  def read(note: nil) = ruby.read(note: note)

  def state = ruby.state

  private

  def ruby = Playthrough::Mechanics.new(playthrough.reload, model: false)
end
