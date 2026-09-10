# Run after rake ruby_llm:load_models in the isolated scratch database.
arm = Eval::Classifier::Arm.parse(BaseAgent::REMOTE_MODEL_IDS.first)
reps = Eval::Noise::MIN_RUNS
puts JSON.pretty_generate(
  model: arm.id, reps: reps, price: arm.price.to_h,
  main: Eval::Prompt.estimate(cases: Eval::Prompt.corpus.cases, reps: reps, models: [ arm ]),
  classifier: Eval::Classifier.estimate(lines: Eval::Classifier.corpus.size, reps: reps, models: [ arm ]),
  ending: Eval::Prompt.estimate(cases: Eval::Prompt.corpus("ending").cases, reps: reps, models: [ arm ]),
  model_bounds: Model.find_by!(model_id: arm.model).attributes.slice("context_window", "max_output_tokens"),
  retries: RubyLLM.config.max_retries
)
