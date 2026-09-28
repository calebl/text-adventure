# One designated position (lowest labelled line id), rebuilt from the corpus.
# The request is the one the engine builds for that line in that room
# (`Playthrough::Requests`, `classifier`), including the physical tokens in its
# emitted schema. Those tokens contain temporary database IDs. Normalize only
# known token entries, to their complete named bindings, in the action list and
# schema; keep the typed line, other numbers and framing exact. Raw requests
# are retained by paid runs. This identity describes the staged scaffold, never
# byte equality between requests with different record IDs.
#
# `shape:` SELECTS WHICH REQUEST GETS CAPTURED, `:schema` BY DEFAULT -- every
# call site that predates the tool-call bench arm keeps asking for exactly what
# it always asked for. `:tool` and `:tools` capture the identical construction
# `Eval::Classifier::ToolAgent` sends on a live pass (`Eval::Classifier::ToolShapes`
# builds both, out of the engine's schema and the room's closed sets), so
# `rake eval:classifier_digest` can prove a tool arm's request moves when a
# tool's parameters do -- the gap the report's §5 named: a request identity
# keyed on `schema` alone goes BLANK for a shape whose closed set lives in
# `tools` instead.
module Eval::Classifier::Version
  extend self

  # The request a shape sends, from the engine's schema'd request and the
  # room's closed sets (`Playthrough::Requests`, `classifier` and `room`).
  def request_for(built, room, shape: :schema)
    case shape
    when :tool
      tools = Eval::Classifier::ToolShapes.single(built.fetch("schema"))
      Eval::RequestIdentity.request(built.fetch("system"), built.fetch("user"), nil,
                                    tools: tool_payloads(tools[:tools]), tool_choice: tools[:choice])
    when :tools
      tools = Eval::Classifier::ToolShapes.per_intent(room)
      Eval::RequestIdentity.request(built.fetch("system"), built.fetch("user"), nil,
                                    tools: tool_payloads(tools[:tools]), tool_choice: tools[:choice])
    else
      { system: built.fetch("system"), user: built.fetch("user"), schema: built.fetch("schema") }
    end
  end

  def tool_payloads(tools)
    tools.map { |tool| { name: tool.name, description: tool.description, parameters: tool.params_schema } }
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
      playthrough = stages.fetch(line.position).playthrough
      rows = Playthrough::Requests.rows
      built = Playthrough::Requests.build(:classifier, rows: rows, playthrough: playthrough.id, line: line.typed)
      room = Playthrough::Requests.build(:room, rows: rows, playthrough: playthrough.id)
      request = normalize(request_for(built, room, shape: shape), room.fetch("physical"))
    end
    { line.id => request }
  end

  # `choices` are the room's physical attempts as the engine lists them, each
  # with its token, its kind and the names it binds.
  def normalize(request, choices)
    tokens = choices.to_h do |choice|
      [ choice.fetch("token"), "use:#{choice.fetch("kind")}:#{JSON.generate(choice.fetch("binding"))}" ]
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
