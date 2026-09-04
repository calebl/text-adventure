# WHAT ONE SCRIPT DID, and every expectation of it that did not hold.
#
# A FAILURE HAS TO BE READABLE FROM A CI LOG AND NOWHERE ELSE. Whoever reads it
# has no database, no console and no world in front of them, so the message
# carries all four things they would otherwise go looking for: which script,
# which step, WHAT WAS TYPED, and the expectation that failed with both sides of
# it. The engine's own read-out of the room comes with it, because the next
# question after "carrying: expected nothing, got the daybook" is always "what
# did the room look like".
class EngineSweep::Result
  Failure = Data.define(:script, :step, :unmet, :state) do
    def to_s
      [
        "#{script.name}: #{step.label} typed #{step.typed.inspect}",
        "  expected #{unmet.key}: #{unmet.expected}",
        "  the records say:      #{unmet.actual}",
        step.why.present? ? "  the step is for: #{step.why}" : nil,
        state.to_s.lines.map { |line| "  #{line.chomp}" }
      ].flatten.compact.join("\n")
    end
  end

  # An invariant is a failure with no step behind it: it is about the world
  # after the walk rather than about one line of it.
  Broken = Data.define(:script, :invariant, :detail) do
    def to_s = "#{"#{script.name}: " if script}the walk broke #{invariant} -- #{detail}"
  end

  attr_reader :script, :steps, :failures

  def initialize(script:, steps:, failures:)
    @script = script
    @steps = steps
    @failures = failures
  end

  def passed? = failures.empty?

  # One line per script, which is what a green run prints and all it prints.
  def line
    format("  %-6s %-28s %2d step(s), %s", passed? ? "ok" : "FAILED", script.name, steps,
           passed? ? "#{script.story} intact" : "#{failures.size} expectation(s) unmet")
  end

  def report = failures.map(&:to_s).join("\n\n")
end
