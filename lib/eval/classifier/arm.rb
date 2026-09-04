# ONE MODEL, NAMED EXPLICITLY, AND NOTHING BEHIND IT.
#
# THE CAPTAIN'S INSTRUCTION OF 2026-09-04: *"Give the bench an explicit arm
# selector so a run can name exactly which models it measures (remote or local)
# instead of inheriting the rotation; do not change the app's default rotation
# or the TA_LOCAL_MODELS default."*
#
# So an arm is a `BaseAgent` model option, built from a spec a person can type,
# and `#pinned` replaces `BaseAgent.default_model_options` for the length of one
# pass -- the same seam `EngineSweep.without_a_model` uses on `BaseAgent.new`,
# and for the same reason: `BaseAgent` is the one gate every model call in this
# app goes through, so standing in front of it is the whole of "measure exactly
# this model". Nothing in `app/` changes, `REMOTE_MODEL_IDS` is untouched, and
# `TA_LOCAL_MODELS` still defaults to off.
#
# THE ROTATION IS OFF BY CONSTRUCTION, and that is the point rather than a side
# effect. `BaseAgent#ask` retries only while `attempts < @model_options.count`,
# so a rotation of ONE never retries: a failed call is a failed line, attributed
# to the model that failed it. Three things follow, all of them wanted in a
# measurement:
#
#   * NO CROSS-CONTAMINATION. The earlier remote baseline pinned with
#     `OPENROUTER_MODEL` and left the rotation behind it, and one run had
#     `minimax/minimax-m3` fail 223 of 1,200 calls -- so `mistralai/mistral-medium-3.1`
#     answered them and the board had to say the arm was impure. With an arm of
#     one that cannot happen.
#   * CLEAN LATENCY. A retried call's wall clock is the failed attempt PLUS the
#     one that worked, and attributing that to the model as its speed would be
#     a lie in the direction that flatters nobody.
#   * FLAKINESS IS A FAILURE COUNT, not a retry count. There are no retries to
#     count; what there is instead is the error, by class, which says WHY --
#     strictly more than a number would. See `Eval::Classifier::Bench::Pass#failures_by_class`.
#
# SPECS. `mistralai/mistral-medium-3.1` is OpenRouter, because that is what
# every remote id in this app looks like. `ollama:qwen3:8b` names the provider
# first -- one colon-separated prefix, because an ollama tag has a colon in it
# and the provider has to be told apart from the tag. `assume_model_exists` is
# set for a local model for the same reason `BaseAgent::LOCAL_MODEL_OPTIONS`
# sets it: an ollama model is in neither registry and saving the chat would
# otherwise raise `RubyLLM::ModelNotFoundError` before anything is asked.
class Eval::Classifier::Arm
  PROVIDERS = %i[openrouter ollama].freeze

  class UnknownProvider < StandardError; end

  attr_reader :provider, :model

  # `"ollama:qwen3:8b"` -> ollama, `qwen3:8b`. Anything with no known provider
  # prefix is OpenRouter, which is what the app's own ids are.
  def self.parse(spec)
    text = spec.to_s.strip
    prefix, rest = text.split(":", 2)

    return new(provider: prefix.to_sym, model: rest) if rest.present? && PROVIDERS.include?(prefix.to_sym)

    new(provider: :openrouter, model: text)
  end

  # Accepts specs OR arms, so a caller that already has arms does not have to
  # remember which it is holding.
  def self.all(specs) = Array(specs).map { |spec| spec.is_a?(self) ? spec : parse(spec) }

  def initialize(provider:, model:)
    unless PROVIDERS.include?(provider.to_sym)
      raise UnknownProvider, "#{provider.inspect} is not one of #{PROVIDERS.inspect}"
    end
    raise UnknownProvider, "an arm needs a model" if model.to_s.strip.empty?

    @provider = provider.to_sym
    @model = model.to_s.strip
  end

  # THE NAME A SET RECORDS AND A BOARD PRINTS. A local model keeps its provider
  # in the label, because `qwen3:8b` and a hosted model of the same name would
  # otherwise be one row in a cross-model table.
  def id = local? ? "#{provider}:#{model}" : model

  def local? = provider == :ollama

  def to_s = id

  def model_options
    { provider: provider, model: model, assume_model_exists: true }
  end

  def ==(other) = other.is_a?(self.class) && other.provider == provider && other.model == model
  alias eql? ==
  def hash = [ provider, model ].hash

  # WHAT IT COSTS PER CALL. A local model costs nothing -- it is the captain's
  # own hardware and his own electricity -- and saying "unpriced" for it would
  # read as "we do not know". Priced off the registry for a hosted one, the same
  # way `Eval::Cost` prices a sweep.
  def price = local? ? Eval::Cost::UNKNOWN : Eval::Cost.price(model)

  def free? = local?

  # HOW LONG A LOCAL MODEL IS ASKED TO STAY IN MEMORY. Ollama unloads a model
  # after about five minutes idle by default and may evict one when another is
  # loaded, so a 300-line pass that paused would pay the load cost again in the
  # middle of its own latency figures.
  #
  # ASKED OF THE DAEMON DIRECTLY AND NOT THROUGH THE APP, which is the whole
  # reason this is clean. `RubyLLM::Chat#with_params` exists and `keep_alive` is
  # an ollama request field, but `BaseAgent` does not expose `with_params` and
  # reaching through `agent.chat` to set a provider-specific parameter would be
  # the instrument reconfiguring the app's own call. The daemon's `/api/generate`
  # takes `keep_alive` on its own account, so one out-of-band request pins the
  # model resident and every call the app then makes is an ordinary call. Best
  # effort: a daemon that refuses it leaves the run relying on contiguous calls
  # staying inside the idle window, which is what `#residency` reports.
  KEEP_ALIVE = "45m".freeze

  RESIDENCY_TIMEOUT = 20

  # Pins the model in memory for `KEEP_ALIVE` and says whether it worked. Only
  # ever called for a local arm; a hosted provider has nothing to keep.
  def keep_resident!
    return :not_local unless local?

    uri = URI.parse(RubyLLM.config.ollama_api_base.to_s.sub(%r{/v1/?\z}, "") + "/api/generate")
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: RESIDENCY_TIMEOUT,
                                                   read_timeout: RESIDENCY_TIMEOUT) do |http|
      http.post(uri.path, { model: model, keep_alive: KEEP_ALIVE }.to_json,
                "Content-Type" => "application/json")
    end

    response.is_a?(Net::HTTPSuccess) ? :resident : :refused
  rescue StandardError
    :unreachable
  end

  # REPLACES THE ROTATION FOR THE LENGTH OF THE BLOCK, and puts it back in an
  # `ensure` including when the block raises -- a failed pass must not leave a
  # poisoned `BaseAgent` behind for the rest of a process.
  def pinned
    original = BaseAgent.method(:default_model_options)
    options = [ model_options ]

    BaseAgent.singleton_class.send(:define_method, :default_model_options) { options }
    yield self
  ensure
    BaseAgent.singleton_class.send(:define_method, :default_model_options, original)
  end
end
