# A COMMAND ENGINE FOR THE SHARED-DATABASE CONTRACT, made of the Rust engine's
# extension.
#
# docs/engine-parity.md has a command engine that is handed one typed step at a
# time, `--database <file> --player <name> <script>` with `ENGINE_STEP=<n>`, on
# a database the runner prepared. This is that engine, answering each step by
# playing it on the Rust engine with `EngineSweep::Walk#play_step` on the file
# it was handed -- so every script passing through it proves the runner's half
# of the contract (the preparation, the re-seeds, the notices) matches the
# walk the goldens were written from. The engine's own parity binary is the
# other engine of this shape; its repository plays it through the runner.
#
# Two ways in: `bin/rails runner test/support/per_step_engine.rb <arguments>`
# as a real subprocess, and `PerStepEngine.launch` in-process, with
# `Open3.capture2`'s signature, for a test that plays every script without
# booting the app once per step.
module PerStepEngine
  Status = Data.define(:code) do
    def success? = code.zero?
    def to_s = "exit #{code}"
  end

  def self.launch(environment, *arguments)
    step = Integer(environment.fetch("ENGINE_STEP"))
    [ play(arguments, step), Status.new(0) ]
  rescue StandardError => e
    warn "#{e.class}: #{e.message}"
    [ "", Status.new(1) ]
  end

  def self.play(arguments, step_index)
    database = arguments[arguments.index("--database") + 1]
    script = EngineSweep::Script.load(arguments.last)
    step = script.steps.find { |candidate| candidate.index == step_index }
    raise EngineSweep::InvalidScript, "#{script.name} has no step #{step_index}" if step.nil? || step.reseed?

    dump = EngineSweep::Parity.on_database(database) do
      EngineSweep.without_a_model do
        Playthrough::RustEngine.using(:rust) { EngineSweep::Walk.new(script, engine: :rust).play_step(step).to_h }
      end
    end
    # The notices are the runner's to render, not an engine's.
    "#{dump.merge("shown" => nil).to_json}\n"
  end
end

if $PROGRAM_NAME == __FILE__
  abort "a provider key reached the engine" if EngineSweep::Parity::WITHHELD.any? { |key| ENV.key?(key) }
  $stdout.write(PerStepEngine.play(ARGV, Integer(ENV.fetch("ENGINE_STEP"))))
end
