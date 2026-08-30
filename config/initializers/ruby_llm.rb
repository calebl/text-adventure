RubyLLM.configure do |config|
  config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
  config.default_model = "minimax/minimax-m3"

  config.ollama_api_base = "http://127.0.0.1:11434/v1"

  # RubyLLM defaults to 120s. Local models generating several paragraphs of
  # schema-constrained output routinely run past that on CPU, and the resulting
  # Net::ReadTimeout looks exactly like a broken model. Generous here; hosted
  # models return long before it matters.
  config.request_timeout = ENV.fetch("LLM_REQUEST_TIMEOUT", 600).to_i
end
