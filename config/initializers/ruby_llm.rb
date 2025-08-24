RubyLLM.configure do |config|
  config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
  config.default_model = "mistralai/mistral-medium-3.1"

  config.ollama_api_base = "http://127.0.0.1:11434/v1"
end
