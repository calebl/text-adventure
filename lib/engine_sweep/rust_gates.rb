# THE GATES THE RUST ENGINE PASSES BEFORE IT PLAYS ANYBODY'S GAME, over every
# sweep script, all offline. `bin/rails engine:rust_gates` runs them and CI's
# Rust job runs that; README.md ("The Rust engine") lists them.
#
# Each script is played once, by the Rust engine through its extension, in the
# shared-database mode (`EngineSweep::Parity::InProcess`). Then:
#
# 1. PARITY: every step's dump from the Rust walk equals its golden
#    (`test/engine_parity/`, or `goldens:`), and the engine played every step.
#    The goldens are the engine's own, written by its parity binary and
#    vendored here byte for byte (`EngineSweep::Vendored`), so what this checks
#    is that Ruby's reader of the rows the engine wrote (`EngineSweep::Dump`
#    over `Playthrough::Mechanics#state`) says what the engine's own reader
#    says. Two readers in two languages agreeing on one set of rows.
# 2. INVARIANTS: `EngineSweep::Invariants` holds over the database the Rust
#    engine wrote, against the world file as last loaded.
# 3. DOCTOR AND AUDIT: `Story::Doctor` and `Story::Audit` say exactly what the
#    script's checks file says (`<script>.checks.json` beside its golden).
#    Each file was first written from the Ruby reference loop, at the last
#    commit where that loop wrote the goldens and the Rust walk and the Ruby
#    walk were judged alike on every script; from there it changes only as a
#    reviewed diff, written by `bin/rails engine:checks`.
#
# The judges stay Ruby: nothing here asks the engine what it thinks it did.
module EngineSweep::RustGates
  Verdict = Data.define(:script, :problems) do
    def passed? = problems.empty?
  end

  def self.check(scripts = EngineSweep.scripts, goldens: EngineSweep::Parity::DIRECTORY)
    rust = EngineSweep::Parity::InProcess.new(:rust)
    scripts.map do |script|
      Dir.mktmpdir("rust-gates") do |directory|
        Verdict.new(script: script, problems: problems(script, rust, directory, goldens))
      end
    end
  end

  def self.problems(script, rust, directory, goldens)
    played = rust.play_in(directory, script)
    [
      EngineSweep::Parity.first_divergence(script, EngineSweep::Parity.golden(script, goldens), played.dumps),
      *invariants(script, rust, played),
      *compared(script, rust.on_file(played.file) { checks(script) }, frozen(script))
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

  # What the doctor and the audit said that the checks file does not, and
  # what the file says that they no longer do, per judge.
  def self.compared(script, now, kept)
    %w[doctor audit].filter_map do |judge|
      next if now.fetch(judge) == kept.fetch(judge)

      said = lines(now.fetch(judge))
      expected = lines(kept.fetch(judge))
      "#{script.name}: the #{judge} disagrees with #{checks_path(script).relative_path_from(Rails.root)}:\n  " \
        "said now:   #{(said - expected).inspect}\n  " \
        "not now:    #{(expected - said).inspect}"
    end
  end

  def self.lines(judged)
    judged.flat_map { |key, value| key == "headline" ? [ "headline: #{value}" ] : value.map { |entry| "#{key}: #{entry.to_json}" } }
  end

  def self.story(script) = Story.find_by!(title: "#{script.story}#{EngineSweep::Walk::TITLE_SUFFIX}")

  # BOTH JUDGES' WORDS ABOUT THE DATABASE THE BLOCK IS CONNECTED TO, as plain
  # JSON: what `rake game:doctor` prints, and what `rake game:audit` prints
  # with VERBOSE=1.
  def self.checks(script)
    doctor = Story::Doctor.new(story(script))
    audit = Story::Audit.new(story(script))
    JSON.parse({
      "doctor" => {
        "headline" => doctor.headline,
        "findings" => doctor.findings.map { |finding| [ finding.code, finding.severity, finding.message, finding.remedy ] }
      },
      "audit" => {
        "headline" => audit.headline,
        "flags" => audit.flags.map { |flag| [ flag.code, flag.scene&.id, flag.headline, flag.evidence ] },
        "unjudged" => audit.unjudged.map { |skipped| [ skipped.code, skipped.scene&.id, skipped.reason ] }
      }
    }.to_json)
  end

  def self.checks_path(script) = Rails.root.join(EngineSweep::Parity::DIRECTORY, "#{script.name}.checks.json")

  def self.frozen(script)
    path = checks_path(script)
    raise EngineSweep::InvalidScript, "#{script.name}: no checks file at #{path.relative_path_from(Rails.root)} -- run bin/rails engine:checks" unless path.exist?

    JSON.parse(path.read)
  end

  def self.render(script, checks) = "#{JSON.pretty_generate({ "script" => script.name, **checks })}\n"

  # Writes each script's checks file from the Rust walk.
  def self.write!(scripts = EngineSweep.scripts)
    rust = EngineSweep::Parity::InProcess.new(:rust)
    scripts.each do |script|
      Dir.mktmpdir("rust-gates") do |directory|
        played = rust.play_in(directory, script)
        checks_path(script).write(render(script, rust.on_file(played.file) { checks(script) }))
      end
    end
  end
end
