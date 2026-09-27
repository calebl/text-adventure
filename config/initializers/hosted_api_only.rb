# See lib/middleware/hosted_api_only.rb and `config.x.hosted_api_only` in
# config/application.rb. First in the stack, so nothing behind it -- static
# files included -- answers a path the hosted mode does not serve.
if Rails.configuration.x.hosted_api_only
  require Rails.root.join("lib/middleware/hosted_api_only")

  Rails.application.config.middleware.insert_before 0, HostedApiOnly
end
