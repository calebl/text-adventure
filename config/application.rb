require_relative "boot"

require "rails/all"

# require "active_graph/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TextAdventure
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # `middleware` is ignored because it is required by an initializer rather
    # than autoloaded: a middleware object outlives a reload, so a class the
    # autoloader can unload underneath it is the one thing it must not be.
    config.autoload_lib(ignore: %w[assets tasks middleware])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Full middleware stack: the browser interface needs cookies, session and flash.
    # `load_defaults 8.0` already supplies the CookieStore, so nothing else is needed.
    # This also makes the generators produce views again, which is wanted.
    config.api_only = false
  end
end
