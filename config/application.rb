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

    # THE HOSTED MODE SERVES THE ENGINE API AND NOTHING ELSE. With
    # `TA_HOSTED_API_ONLY=1`, config/routes.rb draws only `/api/v1`, the model
    # relay's two routes under `/relay/openrouter` and `/up`:
    # the browser play page has no login, and debug, map, lab and machinery are
    # windows into every game, so none of them may be reachable from a hosted
    # instance. Action Cable is not mounted either -- it only ever carried the
    # play page. Where the instance listens is the operator's configuration
    # (bind it to a loopback address), never something this app assumes.
    config.x.hosted_api_only = ENV["TA_HOSTED_API_ONLY"] == "1"
    config.action_cable.mount_path = nil if config.x.hosted_api_only
  end
end
