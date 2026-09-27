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
