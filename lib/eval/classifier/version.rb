# One designated position (lowest labelled line id), rebuilt from the corpus.
# Capture Classifier#classify at its actual ask boundary, including the physical
# tokens in its emitted schema. Those tokens contain temporary database IDs.
# Normalize only known token entries, to their complete named bindings, in the
# action list and schema; keep the typed line, other numbers and framing exact.
# Raw requests are retained by paid runs. This identity describes the staged
# scaffold, never byte equality between requests with different record IDs.
#
# `shape:` SELECTS WHICH REQUEST GETS CAPTURED, `:schema` BY DEFAULT -- every
# call site that predates the tool-call bench arm keeps asking for exactly what
# it always asked for. `:tool` and `:tools` capture the identical construction
# `Eval::Classifier::ToolAgent` sends on a live pass (`Eval::Classifier::ToolShapes`
# builds both), so `rake eval:classifier_digest` can prove a tool arm's request
# moves when a tool's parameters do -- the gap the report's §5 named: a
# request identity keyed on `schema` alone goes BLANK for a shape whose closed
# set lives in `tools` instead.
module Eval::Classifier::Version
  extend self

  class CaptureAgent
    def initialize(instructions, shape: :schema, classifier: nil)
      @instructions = instructions
      @shape = shape
      @classifier = classifier
    end

    def with_schema(schema)
      @schema = schema
      self
    end

    def ask(prompt, **)
      throw :classifier_request, request_for(prompt)
    end

    private

    def request_for(prompt)
      case @shape
      when :tool
        built = Eval::Classifier::ToolShapes.single(@schema)
        Eval::RequestIdentity.request(@instructions, prompt, nil,
                                       tools: tool_payloads(built[:tools]), tool_choice: built[:choice])
      when :tools
        built = Eval::Classifier::ToolShapes.per_intent(@classifier)
        Eval::RequestIdentity.request(@instructions, prompt, nil,
                                       tools: tool_payloads(built[:tools]), tool_choice: built[:choice])
      else
        Eval::RequestIdentity.request(@instructions, prompt, @schema)
      end
    end

    def tool_payloads(tools)
      tools.map { |tool| { name: tool.name, description: tool.description, parameters: tool.params_schema } }
    end
  end

  def offline(corpus = Eval::Classifier.corpus, shape: :schema)
    identity(requests(corpus, shape: shape))
  end

  def offline_details(corpus = Eval::Classifier.corpus, shape: :schema)
    sent = requests(corpus, shape: shape)
    { request_identity: identity(sent),
      instructions_digest: Eval::Prompt::Version.digest(sent.values.map { |request| request[:system] }),
      prompt_digest: Eval::Prompt::Version.digest(sent.values.map { |request| request[:user] }) }
  end

  def identity(requests)
    Eval::RequestIdentity.of(requests).merge("version" => 2, "scope" => "known_physical_token_bindings")
  end

  def requests(corpus = Eval::Classifier.corpus, shape: :schema)
    line = corpus.lines.min_by(&:id)
    request = nil
    Eval::Classifier::Stage.open([ corpus.position(line.position) ]) do |stages|
      classifier = stages.fetch(line.position).classifier
      request = normalize(capture(classifier, line.typed, shape: shape), classifier.physical_actions)
    end
    { line.id => request }
  end

  def capture(classifier, typed, shape: :schema)
    agent = classifier.agent
    # Keep a test's provider double unconsumed too; capture only replaces the
    # terminal agent, while classify still assembles its actual enum and text.
    classifier.instance_variable_set(:@agent,
      CaptureAgent.new(agent.instructions || Playthrough::Classifier::INSTRUCTIONS, shape: shape, classifier: classifier))
    EngineSweep.without_a_model do
      catch(:classifier_request) { classifier.classify(typed) }
    end
  ensure
    classifier.instance_variable_set(:@agent, agent)
  end

  def normalize(request, choices)
    tokens = choices.to_h do |choice|
      binding = [ choice.item&.name, choice.recipient&.fullname,
                  choice.connection && [ choice.connection.location.name, choice.connection.connected_location.name ],
                  choice.tool&.name ]
      [ choice.token, "use:#{choice.kind}:#{JSON.generate(binding)}" ]
    end
    raise ArgumentError, "Ambiguous named physical bindings" unless tokens.values.uniq.size == tokens.size

    # Replace list keys only. A player quoting a literal token is input, and
    # must remain distinguishable from the app offering that same token.
    prefix, heading, rest = request.fetch(:user).partition("## Physical Actions (token: one attempt)\n")
    actions, player_heading, typed = rest.partition("## The Player Types\n")
    normalized_actions = actions.lines.map do |line|
      token = line.split(": ", 2).first
      tokens.key?(token) ? line.sub(token, tokens.fetch(token)) : line
    end.join
    user = prefix + heading + normalized_actions + player_heading + typed
    normalized = request.merge(user: user)
    normalized = normalized.merge(schema: normalize_schema(request[:schema], tokens)) if request.key?(:schema)
    normalized = normalized.merge(tools: normalize_tools(request[:tools], tokens)) if request.key?(:tools)
    normalized
  end

  def normalize_tools(tools, tokens)
    tools.map { |tool| tool.merge(parameters: normalize_schema(tool[:parameters], tokens)) }
  end

  def normalize_schema(value, tokens)
    case value
    when Hash
      value.to_h do |key, part|
        [ key, key.to_s == "enum" ? part.map { |entry| tokens.fetch(entry, entry) } : normalize_schema(part, tokens) ]
      end
    when Array then value.map { |part| normalize_schema(part, tokens) }
    else value
    end
  end
end
