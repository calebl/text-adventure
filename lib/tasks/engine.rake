# THE GOLDEN VECTORS: see `lib/engine_vectors.rb` and docs/engine-vectors.md.
namespace :engine do
  desc "Write the golden vectors whose rules Ruby still runs (inputs and Ruby's outputs) to test/engine_vectors/; the engine's own portions are vendored from it. Offline; writes no database."
  task vectors: :environment do
    written = EngineVectors.in_memory_database { EngineVectors.write! }
    puts "Wrote #{written.size} files to #{EngineVectors::DIRECTORY}/, and left the engine's own " \
         "(#{EngineVectors::ENGINE_OWNED.join(", ")}) as vendored."
  end
end

# THE PARITY GOLDENS: see `EngineSweep::Parity` and docs/engine-parity.md. The
# goldens are the engine's own; these tasks write them into a checkout of it
# (GOLDENS=<engine>/parity/goldens) and compare an engine with them.
namespace :engine do
  desc "Write every sweep script's per-step state dump, played on the Rust engine through its extension, to test/engine_parity/ or GOLDENS=<dir>. SCRIPT=<name> for one; ENGINE=<command> (with ENGINE_DATABASE=1 for one call per step) plays through that engine instead. Offline; plays on scratch copies"
  task parity: :environment do
    scripts = EngineSweep.scripts
    scripts = scripts.select { |script| script.name == ENV["SCRIPT"] } if ENV["SCRIPT"].present?
    directory = ENV["GOLDENS"].presence || EngineSweep::Parity::DIRECTORY
    engine = if ENV["ENGINE"].present?
      EngineSweep::Parity::Command.new(ENV["ENGINE"], shared_database: ENV["ENGINE_DATABASE"].present?)
    else
      abort "The extension is not built (#{Playthrough::RustEngine.load_error}); run bin/rails engine:build." if Playthrough::RustEngine.extension.nil?

      EngineSweep::Parity::InProcess.new(:rust)
    end
    EngineSweep::Parity.write!(engine, scripts, directory: directory)
    puts "Wrote #{scripts.size} file(s) to #{directory}/ from #{engine.name}."
  end

  desc "Play every sweep script through ENGINE=<command> and name each script's first divergence from the goldens (test/engine_parity/, or GOLDENS=<dir>). SCRIPT=<name> for one; ENGINE_DATABASE=1 for one call per step on a database prepared here"
  task parity_diff: :environment do
    command = ENV["ENGINE"].presence or abort "Which engine? ENGINE=<command>, handed a script path, printing one dump per line."
    scripts = EngineSweep.scripts
    scripts = scripts.select { |script| script.name == ENV["SCRIPT"] } if ENV["SCRIPT"].present?
    divergences = EngineSweep::Parity.diff(EngineSweep::Parity::Command.new(command, shared_database: ENV["ENGINE_DATABASE"].present?),
                                           scripts: scripts, goldens: ENV["GOLDENS"].presence || EngineSweep::Parity::DIRECTORY)
    abort "#{divergences.join("\n\n")}\n\nDIVERGED: #{divergences.size} of #{scripts.size} script(s)." if divergences.any?

    puts "AGREED: #{scripts.size} script(s), step for step."
  end

  desc "Write what the doctor and the audit say after each sweep script, walked on the Rust engine, to test/engine_parity/<script>.checks.json. SCRIPT=<name> for one. Offline; plays on scratch copies"
  task checks: :environment do
    abort "The extension is not built (#{Playthrough::RustEngine.load_error}); run bin/rails engine:build." if Playthrough::RustEngine.extension.nil?

    scripts = EngineSweep.scripts
    scripts = scripts.select { |script| script.name == ENV["SCRIPT"] } if ENV["SCRIPT"].present?
    EngineSweep::RustGates.write!(scripts)
    puts "Wrote #{scripts.size} checks file(s) to #{EngineSweep::Parity::DIRECTORY}/."
  end

  desc "Check that the goldens, the sweep scripts and the engine's own vector portions here are the pinned engine commit's, byte for byte (or ENGINE_SOURCE=<checkout>'s). Offline once the extension's build has fetched the engine"
  task vendored: :environment do
    source = EngineSweep::Vendored.source
    problems = EngineSweep::Vendored.problems(source)
    abort "#{problems.join("\n")}\n\nNOT VENDORED: #{problems.size} file(s) differ from #{source}." if problems.any?

    puts "VENDORED: the goldens, the scripts and the engine's own vector portions are #{source}'s, byte for byte."
  end
end

# THE RUST ENGINE, which plays every turn: see `Playthrough::RustEngine` and README.md ("The Rust engine").
namespace :engine do
  desc "Build the Rust engine's extension into ext/renderedstep/build/, which every turn is played through (needs a Rust toolchain). ENGINE_SOURCE=<checkout> builds against a local copy of the engine instead of the pinned commit"
  task :build do
    crate = File.expand_path("../../ext/renderedstep", __dir__)
    arguments = %w[cargo build --release --locked]
    if ENV["ENGINE_SOURCE"].present?
      source = File.expand_path(ENV["ENGINE_SOURCE"])
      arguments = %w[cargo build --release] +
                  [ "--config", "patch.'https://github.com/renderedstep/engine'.renderedstep-engine.path=#{source.inspect}" ]
    end
    system(*arguments, chdir: crate, exception: true)

    library = Dir[File.join(crate, "target/release/{lib,}renderedstep_native.{so,dylib,dll}")].first or
      abort "cargo built no library in #{crate}/target/release"
    FileUtils.mkdir_p(File.join(crate, "build"))
    built = File.join(crate, "build", "renderedstep_native.#{RbConfig::CONFIG.fetch("DLEXT")}")
    FileUtils.cp(library, built)
    puts "Built #{built}. Restart the app to play on it."
  end

  desc "Run the engine's own golden-vector tests, the kept-set request equality among them, against this checkout's test/engine_vectors/, at the commit the extension is pinned to (or ENGINE_SOURCE=<checkout>). Offline; needs a Rust toolchain"
  task :kept_requests do
    root = File.expand_path("../..", __dir__)
    crate = File.join(root, "ext/renderedstep")
    Dir.mktmpdir("engine-source") do |directory|
      source = File.join(directory, "engine")
      if ENV["ENGINE_SOURCE"].present?
        FileUtils.cp_r(File.expand_path(ENV["ENGINE_SOURCE"]), source)
        FileUtils.rm_rf(File.join(source, "target"))
      else
        rev = File.read(File.join(crate, "Cargo.toml"))[/renderedstep-engine = \{ git = "[^"]+", rev = "(\h{40})" \}/, 1] or
          abort "ext/renderedstep/Cargo.toml pins no engine commit"
        system("git", "clone", "--quiet", "https://github.com/renderedstep/engine", source, exception: true)
        system("git", "-C", source, "checkout", "--quiet", rev, exception: true)
      end
      FileUtils.cp(Dir[File.join(root, "test/engine_vectors/*.json")], File.join(source, "vectors"))
      environment = { "OPENROUTER_API_KEY" => nil, "TYPESAFE_API_KEY" => nil,
                      "CARGO_TARGET_DIR" => File.join(crate, "target/engine-vectors") }
      system(environment, "cargo", "test", "--locked", "--test", "vectors", chdir: source, exception: true)
    end
    puts "The engine reproduces every golden vector and every kept request this checkout exports."
  end

  desc "Play every sweep script through the Rust engine and check the gates: the goldens (test/engine_parity/, or GOLDENS=<dir>), the invariants, and the doctor and audit against each script's checks file. SCRIPT=<name> for one. Offline; plays on scratch copies"
  task rust_gates: :environment do
    abort "The extension is not built (#{Playthrough::RustEngine.load_error}); run bin/rails engine:build." if Playthrough::RustEngine.extension.nil?
    abort "A provider key is set; the gates run with neither OPENROUTER_API_KEY nor TYPESAFE_API_KEY." if EngineSweep::Parity::WITHHELD.any? { |key| ENV[key].present? }

    scripts = EngineSweep.scripts
    scripts = scripts.select { |script| script.name == ENV["SCRIPT"] } if ENV["SCRIPT"].present?
    goldens = ENV["GOLDENS"].presence || EngineSweep::Parity::DIRECTORY
    verdicts = EngineSweep::RustGates.check(scripts, goldens: goldens)
    failed = verdicts.reject(&:passed?)
    failed.each { |verdict| puts verdict.problems.join("\n"), "" }
    abort "FAILED: #{failed.size} of #{scripts.size} script(s)." if failed.any?

    puts "PASSED: #{scripts.size} script(s) on the Rust engine: every step matches its golden in #{goldens}/, " \
         "the invariants hold, and the doctor and audit say what each script's checks file says."
  end
end
