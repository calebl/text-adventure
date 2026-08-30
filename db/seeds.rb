# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# RubyLLM's model registry lives in the `models` table since the v1.7 acts_as
# migration, and RubyLLM resolves model names out of that table rather than the
# gem's bundled models.json. An empty table resolves nothing -- there is no
# fallback -- so seeding it is not optional for a working app.
#
# Offline: reads the registry the gem ships with. No API key, no network.
if defined?(RubyLLM) && RubyLLM.config.model_registry_class.present?
  RubyLLM.models.load_from_json!
  Model.save_to_database
  puts "Loaded #{Model.count} models into the RubyLLM registry"
end
