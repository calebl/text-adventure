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

  # A THINKING MODEL ANSWERING THE CLASSIFIER, WITH THE THINKING OFF.
  #
  # Measured on this machine, warm, `qwen3:4b`, the app's own prompt shape and
  # the app's own client -- RubyLLM reaches ollama through its OPENAI-COMPATIBLE
  # endpoint (`config.ollama_api_base` ends in `/v1`), which is the whole reason
  # this constant says what it says:
  #
  #   nothing asked                            100.2s   a `reasoning` field comes back beside the answer
  #   think: false                             100.7s   IGNORED -- an ollama-native field, and /v1 is not it
  #   chat_template_kwargs enable_thinking     100.0s   IGNORED
  #   reasoning_effort: "low"                  100.2s   honoured, and low is not none
  #   reasoning_effort: "none"                   2.1s   no reasoning field, same correct answer
  #
  # So it is `reasoning_effort`, a STANDARD OpenAI field, and not ollama's own
  # `think`. The 23 content tokens are the same either way; what the 98 seconds
  # buy is a reasoning block the schema never constrained, because the schema
  # constrains the content and the thinking happens in front of it. A 48x
  # difference on the one call a player waits for, and the field reaches the
  # daemon through `BaseAgent.default_provider_params` -- the seam that exists
  # for exactly this and is empty in every shipped path.
  #
  # (The native `/api/chat` endpoint with `format:` and `think: false` answers
  # the same call in 1.95s, measured. The app does not speak it, so neither does
  # the bench: an instrument that reached past the app's own client would be
  # measuring a different client.)
  #
  # ASKED FOR EXPLICITLY, NEVER INFERRED. An arm carries it because a spec said
  # `+nothink`, so a run that does not ask measures the model the way the app
  # would really use it -- which is the 100-second figure, and IS the finding.
  # Two arms of one model with different thinking are two rows on the board,
  # which is the comparison the captain asked for.
  NO_THINKING = { reasoning_effort: "none" }.freeze

  # The suffix that asks for it. A `+` because it modifies the arm rather than
  # naming part of the model, and an ollama tag can hold neither.
  NOTHINK_SUFFIX = "+nothink".freeze

  # THE REQUEST SHAPE AXIS, added for the tool-call bench arm (the maintainer's
  # decision on the investigation at `data/ta-tool-calls-scout/report.md`):
  # every existing arm measures `:schema`, `Playthrough::Classifier`'s own
  # `response_format` call, unchanged. `:tool` (the report's shape B / Version
  # A) wraps the identical closed set in ONE forced `RubyLLM::Tool` -- the
  # control, which should read like the schema arm or the harness is wrong.
  # `:tools` (shape C / Version B) is one tool per intent, each carrying only
  # its own target set, `tool_choice: "required"` -- the shape whose whole
  # claim is driving an out-of-list target to zero. Neither shape is ever
  # reached by a live turn: `Eval::Classifier::ToolShapes` and
  # `Eval::Classifier::ToolAgent` build them only for a bench pass.
  SHAPES = %i[schema tool tools].freeze

  TOOL_SUFFIX = "+tool".freeze
  TOOLS_SUFFIX = "+tools".freeze

  # THE SYSTEM ONE TRANSPORT AXIS, beside the request-shape axis: a cascade
  # measurement can pin which Jev transport answered, so TypeSafe direct and
  # OpenRouter Decisions are comparable like for like. `:ambient` (no suffix)
  # leaves the live preference alone -- TypeSafe when its key is present,
  # otherwise OpenRouter. Neither suffix is ever reached by a live turn; only
  # the bench constructs a pinned `SystemOneAgent`.
  SYSTEM_ONE_TRANSPORTS = %i[ambient typesafe_direct openrouter_decisions].freeze

  TYPESAFE_DIRECT_SUFFIX = "+typesafe-direct".freeze
  OPENROUTER_DECISIONS_SUFFIX = "+openrouter-decisions".freeze

  attr_reader :provider, :model, :provider_params, :shape, :system_one_transport

  # `"ollama:qwen3:8b"` -> ollama, `qwen3:8b`. Anything with no known provider
  # prefix is OpenRouter, which is what the app's own ids are.
  # `"ollama:qwen3:8b+nothink"` asks for `NO_THINKING` as well.
  # `"mistralai/mistral-medium-3.1+tool"` / `"+tools"` asks for a tool shape --
  # read off the end BEFORE `+nothink`, so a spec may carry both (`+tools`
  # checked first: the two suffixes never collide, since `"...+tools"` does not
  # end with the five characters of `"+tool"`).
  # `"mistralai/mistral-medium-3.1+openrouter-decisions"` pins the cascade's
  # Jev transport the same way; transport suffixes are read before shape ones.
  def self.parse(spec)
    text = spec.to_s.strip
    nothink = text.end_with?(NOTHINK_SUFFIX)
    text = text.delete_suffix(NOTHINK_SUFFIX) if nothink
    params = nothink ? NO_THINKING : {}

    system_one_transport = :ambient
    if text.end_with?(OPENROUTER_DECISIONS_SUFFIX)
      system_one_transport = :openrouter_decisions
      text = text.delete_suffix(OPENROUTER_DECISIONS_SUFFIX)
    elsif text.end_with?(TYPESAFE_DIRECT_SUFFIX)
      system_one_transport = :typesafe_direct
      text = text.delete_suffix(TYPESAFE_DIRECT_SUFFIX)
    end

    shape = :schema
    if text.end_with?(TOOLS_SUFFIX)
      shape = :tools
      text = text.delete_suffix(TOOLS_SUFFIX)
    elsif text.end_with?(TOOL_SUFFIX)
      shape = :tool
      text = text.delete_suffix(TOOL_SUFFIX)
    end

    prefix, rest = text.split(":", 2)

    if rest.present? && PROVIDERS.include?(prefix.to_sym)
      return new(provider: prefix.to_sym, model: rest, provider_params: params, shape: shape,
                 system_one_transport: system_one_transport)
    end

    new(provider: :openrouter, model: text, provider_params: params, shape: shape,
        system_one_transport: system_one_transport)
  end

  # Accepts specs OR arms, so a caller that already has arms does not have to
  # remember which it is holding.
  def self.all(specs) = Array(specs).map { |spec| spec.is_a?(self) ? spec : parse(spec) }

  def initialize(provider:, model:, provider_params: {}, shape: :schema, system_one_transport: :ambient)
    unless PROVIDERS.include?(provider.to_sym)
      raise UnknownProvider, "#{provider.inspect} is not one of #{PROVIDERS.inspect}"
    end
    raise UnknownProvider, "an arm needs a model" if model.to_s.strip.empty?
    unless SHAPES.include?(shape.to_sym)
      raise UnknownProvider, "#{shape.inspect} is not one of #{SHAPES.inspect}"
    end
    unless SYSTEM_ONE_TRANSPORTS.include?(system_one_transport.to_sym)
      raise UnknownProvider, "#{system_one_transport.inspect} is not one of #{SYSTEM_ONE_TRANSPORTS.inspect}"
    end

    @provider = provider.to_sym
    @model = model.to_s.strip
    @provider_params = provider_params.to_h
    @shape = shape.to_sym
    @system_one_transport = system_one_transport.to_sym
    if @provider_params.any? && !local?
      raise UnknownProvider, "provider params are only for a local arm; #{id} is hosted, and changing " \
                             "the shape of a remote request is not what the seam is for"
    end
  end

  # THE NAME A SET RECORDS AND A BOARD PRINTS. A local model keeps its provider
  # in the label, because `qwen3:8b` and a hosted model of the same name would
  # otherwise be one row in a cross-model table -- an arm with the thinking off
  # keeps that in the label too, and a tool-shaped arm keeps its suffix, all for
  # the same reason: each is a different measurement of the same model.
  def id = [ local? ? "#{provider}:#{model}" : model, shape_suffix, system_one_suffix,
             thinking_off? ? NOTHINK_SUFFIX : nil ]
             .compact.join

  def shape_suffix
    case shape
    when :tool then TOOL_SUFFIX
    when :tools then TOOLS_SUFFIX
    end
  end

  def system_one_suffix
    case system_one_transport
    when :typesafe_direct then TYPESAFE_DIRECT_SUFFIX
    when :openrouter_decisions then OPENROUTER_DECISIONS_SUFFIX
    end
  end

  def thinking_off? = provider_params == NO_THINKING

  def shape_schema? = shape == :schema
  def shape_tool? = shape == :tool
  def shape_tools? = shape == :tools

  # Whether this arm pins a System One transport rather than leaving the live
  # preference alone. A pinned arm implies a cascade measurement.
  def pins_system_one_transport? = system_one_transport != :ambient

  def local? = provider == :ollama

  def to_s = id

  def model_options
    { provider: provider, model: model, assume_model_exists: true }
  end

  # The credential variable this arm's System One transport needs, or nil when
  # the arm does not pin one (ambient cascade still needs whichever key the
  # environment will actually use).
  def system_one_credential_variable
    case system_one_transport
    when :typesafe_direct then SystemOneAgent::TYPESAFE_API_KEY_VARIABLE
    when :openrouter_decisions then SystemOneAgent::OPENROUTER_API_KEY_VARIABLE
    end
  end

  def ==(other)
    other.is_a?(self.class) && other.provider == provider && other.model == model &&
      other.provider_params == provider_params && other.shape == shape &&
      other.system_one_transport == system_one_transport
  end
  alias eql? ==
  def hash = [ provider, model, provider_params, shape, system_one_transport ].hash

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
    was_options = BaseAgent.method(:default_model_options)
    was_params = BaseAgent.method(:default_provider_params)
    options = [ model_options ]
    params = provider_params

    BaseAgent.singleton_class.send(:define_method, :default_model_options) { options }
    BaseAgent.singleton_class.send(:define_method, :default_provider_params) { params }
    yield self
  ensure
    BaseAgent.singleton_class.send(:define_method, :default_model_options, was_options)
    BaseAgent.singleton_class.send(:define_method, :default_provider_params, was_params)
  end
end
