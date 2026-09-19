# A `BaseAgent` WHOSE `#with_schema` BECOMES A FORCED TOOL CALL, FOR THE BENCH
# ONLY. `Playthrough::Classifier` never constructs one of these and never will
# -- `Eval::Classifier::Bench` substitutes it for `Playthrough::Classifier
# #agent` the same way `Eval::Classifier::Version::CaptureAgent` already
# stands in for an offline capture, and puts the ordinary agent back when the
# read is done. Everything else -- rotation, rewind-on-failure, message
# attribution, `Chat` persistence -- is inherited unchanged, because those are
# facts about a `BaseAgent` call and not about which envelope carries the
# closed set.
#
# `#with_schema` IS OVERRIDDEN RATHER THAN LEFT ALONE, and that is the whole
# seam: the union schema `Playthrough::Classifier#ask_the_model` builds is
# exactly right for shape B (the identical closed set, wrapped in one tool) and
# the wrong shape entirely for shape C, which needs the four SEPARATE closed
# sets `Eval::Classifier::ToolShapes#target_names` reads off `classifier`
# instead. Either way `BaseAgent`'s own `@schema` ivar is never set, so
# `#build_chat`'s inherited `with_schema` call never fires and no
# `response_format` is ever attached next to the tools -- and the inherited
# schema verification never runs either, which is why this class carries its
# own.
class Eval::Classifier::ToolAgent < BaseAgent
  def initialize(shape:, classifier: nil, **kwargs)
    @shape = shape.to_sym
    @classifier = classifier
    super(**kwargs)
  end

  def with_schema(schema)
    @intent_schema = schema
    self
  end

  private

  def build_chat
    conversation = super
    built = @shape == :tool ? Eval::Classifier::ToolShapes.single(@intent_schema) :
                               Eval::Classifier::ToolShapes.per_intent(@classifier)
    # SHAPE B REQUIRES ALL THREE FIELDS, exactly as the schema call does; SHAPE
    # C'S TOOLS NEVER CARRY `intent` OF THEIR OWN -- it is injected by
    # `ToolShapes#build_tool` from the tool's own name, which cannot be missing
    # -- so only `target`/`also_named` are checked there.
    @required_keys = @shape == :tool ? %w[intent target also_named] : %w[target also_named]
    conversation.with_tools(*built[:tools], choice: built[:choice])
    conversation
  end

  # THE SAME TWO RULES `BaseAgent#verify_schema_honored!` CHECKS -- a `Hash`,
  # and no required field missing -- read off the tool's own required keys
  # instead of `@schema.required_properties`. A model that answered no tool
  # call at all comes back as something other than a `Hash` (RubyLLM's own
  # response, not a `Tool::Halt`), which raises here exactly as an un-schema'd
  # answer does on the schema path.
  def verify_schema_honored!(response)
    return if @intent_schema.nil?

    content = response.content
    unless content.is_a?(Hash)
      raise SchemaIgnoredError, "#{current_model[:model]} ignored the tool call and returned #{content.class}"
    end

    missing = (@required_keys || []).reject { |key| content[key].present? || content[key] == false }
    return if missing.empty?

    raise SchemaIgnoredError, "#{current_model[:model]} omitted tool fields: #{missing.join(', ')}"
  end

  # BOTH GUARD UNSCHEMA'D, PROSE CALLS -- `Scene::Narrator`'s shape, not this
  # one. A tool-shaped classifier call is closed exactly as the schema call is,
  # so it skips these the same way the schema path already does (`@schema`
  # present there); running a prose-refusal detector against a tool-call `Hash`
  # would not be measuring the classifier, and every kept schema baseline never
  # exercises them on a `classify` call either.
  def verify_not_refused!(response) = nil
  def verify_no_crisis_response!(response) = nil
end
