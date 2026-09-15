# One designated position (lowest labelled line id), rebuilt from the corpus.
# Capture Classifier#classify at its actual ask boundary, including the physical
# tokens in its emitted schema. Those tokens contain temporary database IDs.
# Normalize only known token entries, to their complete named bindings, in the
# action list and schema; keep the typed line, other numbers and framing exact.
# Raw requests are retained by paid runs. This identity describes the staged
# scaffold, never byte equality between requests with different record IDs.
module Eval::Classifier::Version
  extend self

  class CaptureAgent
    def initialize(instructions) = @instructions = instructions

    def with_schema(schema)
      @schema = schema
      self
    end

    def ask(prompt, **)
      throw :classifier_request, Eval::RequestIdentity.request(@instructions, prompt, @schema)
    end
  end

  def offline(corpus = Eval::Classifier.corpus)
    identity(requests(corpus))
  end

  def offline_details(corpus = Eval::Classifier.corpus)
    sent = requests(corpus)
    { request_identity: identity(sent),
      instructions_digest: Eval::Prompt::Version.digest(sent.values.map { |request| request[:system] }),
      prompt_digest: Eval::Prompt::Version.digest(sent.values.map { |request| request[:user] }) }
  end

  def identity(requests)
    Eval::RequestIdentity.of(requests).merge("version" => 2, "scope" => "known_physical_token_bindings")
  end

  def requests(corpus = Eval::Classifier.corpus)
    line = corpus.lines.min_by(&:id)
    request = nil
    Eval::Classifier::Stage.open([ corpus.position(line.position) ]) do |stages|
      classifier = stages.fetch(line.position).classifier
      request = normalize(capture(classifier, line.typed), classifier.physical_actions)
    end
    { line.id => request }
  end

  def capture(classifier, typed)
    agent = classifier.agent
    # Keep a test's provider double unconsumed too; capture only replaces the
    # terminal agent, while classify still assembles its actual enum and text.
    classifier.instance_variable_set(:@agent, CaptureAgent.new(agent.instructions || Playthrough::Classifier::INSTRUCTIONS))
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
    request.merge(user: user, schema: normalize_schema(request[:schema], tokens))
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
