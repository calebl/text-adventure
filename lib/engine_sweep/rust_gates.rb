# THE GATES THE RUST ENGINE PASSES BEFORE IT PLAYS ANYBODY'S GAME, over every
# sweep script, all offline. `bin/rails engine:rust_gates` runs them and CI's
# Rust job runs that; README.md ("The Rust engine") lists them.
#
# Each script is played twice in this process, in the shared-database mode
# (`EngineSweep::Parity::InProcess`): once by the Rust engine through its
# extension, and once by the Ruby engine, its twin, on a copy of its own. Then:
#
# 1. PARITY: every step's dump from the Rust walk equals the committed golden
#    (`test/engine_parity/`), and the engine played every step.
# 2. INVARIANTS: `EngineSweep::Invariants` holds over the database the Rust
#    engine wrote, against the world file as last loaded -- the same whole-world
#    checks `rake game:sweep` makes of a Ruby walk.
# 3. DOCTOR AND AUDIT: `Story::Doctor` and `Story::Audit` say the same things
#    about the Rust-written database as about its Ruby-played twin. Both
#    walks pin the same ids, so a finding names the same rows in both.
#
# The judges stay Ruby: nothing here asks the engine what it thinks it did.
module EngineSweep::RustGates
  Verdict = Data.define(:script, :problems) do
    def passed? = problems.empty?
  end

  def self.check(scripts = EngineSweep.scripts)
    rust = EngineSweep::Parity::InProcess.new(:rust)
    ruby = EngineSweep::Parity::InProcess.new(:ruby)
    scripts.map do |script|
      Dir.mktmpdir("rust-gates") do |directory|
        Verdict.new(script: script, problems: problems(script, rust, ruby, directory))
      end
    end
  end

  def self.problems(script, rust, ruby, directory)
    played = rust.play_in(directory, script)
    twin = ruby.play_in(directory, script)
    [
      EngineSweep::Parity.first_divergence(script, EngineSweep::Parity.golden(script), played.dumps),
      *invariants(script, rust, played),
      *compared("doctor", rust.on_file(played.file) { doctor(script) }, ruby.on_file(twin.file) { doctor(script) }),
      *compared("audit", rust.on_file(played.file) { audit(script) }, ruby.on_file(twin.file) { audit(script) })
    ].compact
  rescue EngineSweep::InvalidScript, EngineSweep::ModelCalled, EngineSweep::RustMechanics::Failed,
         Playthrough::RustEngine::EngineError => e
    [ "#{script.name}: #{e.message}" ]
  end

  def self.invariants(script, engine, played)
    engine.on_file(played.file) do
      EngineSweep::Invariants.new(story(script), seed: played.walk.loaded).check.map do |broken|
        "#{script.name}: #{broken}"
      end
    end
  end

  def self.compared(what, rust, ruby)
    return [] if rust == ruby

    [ "#{what} disagrees:\n  rust: #{(rust - ruby).inspect}\n  ruby: #{(ruby - rust).inspect}" ]
  end

  def self.story(script) = Story.find_by!(title: "#{script.story}#{EngineSweep::Walk::TITLE_SUFFIX}")

  # What the doctor says, as the rake task prints it.
  def self.doctor(script)
    doctor = Story::Doctor.new(story(script))
    [ doctor.headline, *doctor.findings.map { |finding| [ finding.code, finding.severity, finding.message, finding.remedy ].inspect } ]
  end

  # What the audit says, as the rake task prints it with VERBOSE=1.
  def self.audit(script)
    audit = Story::Audit.new(story(script))
    flags = audit.flags.map { |flag| [ flag.code, flag.scene&.id, flag.headline, flag.evidence ].inspect }
    unjudged = audit.unjudged.map { |skipped| [ skipped.code, skipped.scene&.id, skipped.reason ].inspect }
    [ audit.headline, *flags, *unjudged ]
  end
end
