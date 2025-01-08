OpenRouter.configure do |config|
  config.access_token = Rails.application.credentials.open_router[:access_token]
end
