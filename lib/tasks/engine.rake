# THE GOLDEN VECTORS: see `lib/engine_vectors.rb` and docs/engine-vectors.md.
namespace :engine do
  desc "Write the engine's golden vectors (inputs and Ruby's outputs) to test/engine_vectors/. Offline; writes no database."
  task vectors: :environment do
    EngineVectors.in_memory_database { EngineVectors.write! }
    puts "Wrote #{EngineVectors::PORTIONS.size} files to #{EngineVectors::DIRECTORY}/."
  end
end
