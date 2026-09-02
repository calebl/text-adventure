source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.0"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :development, :test do
  # Load `.env` for `bin/rails` and `rake`. It was only ever a transitive
  # dependency (via kamal), so `.env` did NOT auto-load and a key put there was
  # silently ignored -- which, before BaseAgent stopped rotating past a 401,
  # meant a local model answered instead. `.envrc` / direnv still works; this
  # makes the other half of what the docs imply true too.
  gem "dotenv-rails"

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Factory Bot for test data
  gem "factory_bot_rails"
end

group :test do
  # Minitest 6 extracted minitest/mock into its own gem
  gem "minitest-mock"
end



gem "ruby_llm"
# Must stay below 1.0: that release is a deprecation shim forwarding to the
# renamed `schematist` gem, and taking it silently pins ruby_llm to 1.8.2.
# ruby_llm's own `~> 0` already rules it out; this restates the bound rather
# than establishing it. See AGENTS.md -> *Never let `ruby_llm-schema`
# resolve to 1.x*, and `.github/dependabot.yml` for why the weekly 1.0.0 PR
# is not silenced with an `ignore` rule.
gem "ruby_llm-schema", "~> 0.2"

gem "open_router", "~> 0.3.3"

gem "async", "~> 2.27"

# Hotwire, zero build step. `propshaft` serves digested assets with no
# compilation, `importmap-rails` maps bare module names to those assets in the
# browser's own module loader, and `turbo-rails` is what a background job
# broadcasts a finished turn over. Deliberately NO jsbundling/cssbundling,
# esbuild, Vite or `package.json`: if something here appears to need one, that
# is a reason to reconsider the something.
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
