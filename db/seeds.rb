# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Persist RubyLLM's bundled model registry in `ruby_llm_models`. RubyLLM 2 can
# resolve from its bundled registry when this table is empty, but application
# pricing and evaluation read the persisted rows directly.
#
# Offline: reads the registry the gem ships with. No API key, no network.
if defined?(RubyLLM)
  RubyLLM.models.load_from_json
  RubyLLM::ActiveRecord::Model.save_to_database
  puts "Loaded #{Model.count} models into the RubyLLM registry"
end

# The checked-in playable worlds under db/seeds/worlds. Offline and idempotent:
# plain YAML in, database rows out, matched on natural keys so a second run
# updates rather than duplicates. See lib/world_seed.rb.
WorldSeed::Loader.load_all
