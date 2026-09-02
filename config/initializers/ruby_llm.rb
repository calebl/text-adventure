RubyLLM.configure do |config|
  config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
  config.default_model = "mistralai/mistral-medium-3.1"

  config.ollama_api_base = "http://127.0.0.1:11434/v1"

  # RubyLLM defaults to 120s. Local models generating several paragraphs of
  # schema-constrained output routinely run past that on CPU, and the resulting
  # Net::ReadTimeout looks exactly like a broken model. Generous here; hosted
  # models return long before it matters.
  config.request_timeout = ENV.fetch("LLM_REQUEST_TIMEOUT", 600).to_i

  # The association-based Rails API, added in RubyLLM 1.7. The legacy `acts_as`
  # API still works but warns at boot and is removed in RubyLLM 2.0.
  #
  # Under this API the `models` table IS the model registry -- RubyLLM resolves
  # model names out of it and does not fall back to the registry the gem ships
  # with, so an empty table resolves nothing. `bin/rails db:seed` fills it, or
  # `bin/rails ruby_llm:load_models` directly. Both read the bundled registry
  # offline; neither needs an API key.
  config.use_new_acts_as = true
end
