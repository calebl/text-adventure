# THE GOLDEN VECTORS: see `lib/engine_vectors.rb` and docs/engine-vectors.md.
namespace :engine do
  desc "Write the engine's golden vectors (inputs and Ruby's outputs) to test/engine_vectors/. Offline; writes no database."
  task vectors: :environment do
    EngineVectors.in_memory_database { EngineVectors.write! }
    puts "Wrote #{EngineVectors::PORTIONS.size} files to #{EngineVectors::DIRECTORY}/."
  end
end

# THE PARITY GOLDENS: see `EngineSweep::Parity` and docs/engine-parity.md.
namespace :engine do
  desc "Write every sweep script's per-step state dump to test/engine_parity/. Offline; rolls back what it plays."
  task parity: :environment do
    EngineSweep::Parity.write!
    puts "Wrote #{EngineSweep.scripts.size} files to #{EngineSweep::Parity::DIRECTORY}/."
  end

  desc "Play every sweep script through ENGINE=<command> and name each script's first divergence from the goldens. SCRIPT=<name> for one; ENGINE_DATABASE=1 for one call per step on a database prepared here"
  task parity_diff: :environment do
    command = ENV["ENGINE"].presence or abort "Which engine? ENGINE=<command>, handed a script path, printing one dump per line."
    scripts = EngineSweep.scripts
    scripts = scripts.select { |script| script.name == ENV["SCRIPT"] } if ENV["SCRIPT"].present?
    divergences = EngineSweep::Parity.diff(EngineSweep::Parity::Command.new(command, shared_database: ENV["ENGINE_DATABASE"].present?), scripts: scripts)
    abort "#{divergences.join("\n\n")}\n\nDIVERGED: #{divergences.size} of #{scripts.size} script(s)." if divergences.any?

    puts "AGREED: #{scripts.size} script(s), step for step."
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

  desc "Play every sweep script through the Rust engine and check the gates: the goldens, the invariants, and the doctor and audit against a twin played by the Ruby reference loop. SCRIPT=<name> for one. Offline; plays on scratch copies"
  task rust_gates: :environment do
    abort "The extension is not built (#{Playthrough::RustEngine.load_error}); run bin/rails engine:build." if Playthrough::RustEngine.extension.nil?
    abort "A provider key is set; the gates run with neither OPENROUTER_API_KEY nor TYPESAFE_API_KEY." if EngineSweep::Parity::WITHHELD.any? { |key| ENV[key].present? }

    scripts = EngineSweep.scripts
    scripts = scripts.select { |script| script.name == ENV["SCRIPT"] } if ENV["SCRIPT"].present?
    verdicts = EngineSweep::RustGates.check(scripts)
    failed = verdicts.reject(&:passed?)
    failed.each { |verdict| puts verdict.problems.join("\n"), "" }
    abort "FAILED: #{failed.size} of #{scripts.size} script(s)." if failed.any?

    puts "PASSED: #{scripts.size} script(s) on the Rust engine: every step matches its golden, " \
         "the invariants hold, and the doctor and audit agree with the twin the Ruby reference played."
  end
end
