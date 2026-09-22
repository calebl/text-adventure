# THE TWO TOOL-CALL SHAPES OF THE CLASSIFIER'S CLOSED SET, BUILT FOR THE BENCH
# ONLY. Nothing here is reachable from a live turn: `Playthrough::Classifier`
# still asks `Playthrough::IntentSchema.for` through `response_format`, exactly
# as it always has. This module exists so `Eval::Classifier::Bench` can measure
# what a forced tool call would cost and catch, next to that same schema arm,
# in the same pass -- see `data/ta-tool-calls-scout/report.md`, sections 4-5.
#
# SHAPE B (`+tool`) wraps `Playthrough::IntentSchema.for(targets)` -- the
# IDENTICAL closed set the app sends today -- in one `RubyLLM::Tool`, with
# `tool_choice` naming it. Nothing about the schema changes; only the envelope
# it crosses the wire in does. It is the control: if this arm does not read
# like the schema arm, the harness is what is wrong.
#
# SHAPE C (`+tools`) builds one tool PER INTENT -- `move`, `talk`, `examine`,
# `take`, `drop`, `attack`, `use`, `other` -- each carrying only that intent's
# own closed set as `target`/`also_named`, taken VERBATIM off
# `Playthrough::IntentSchema.for` (the field descriptions are never rewritten;
# only which enum answers are on offer narrows, and `intent` itself is dropped
# because which tool was called already answers it). Picking the tool IS
# picking the intent, so a target belonging to a different action's list
# cannot cross the wire at all -- the property the report's Version B measured
# on an ordinary chat model, with no System One key.
#
# THE TOOLS EXECUTE NOTHING. Each requires approval, which makes RubyLLM stop
# after the provider's tool call instead of executing it and buying a second
# generation. `ToolAgent` reads those arguments into the same response shape
# `Playthrough::Classifier#ask_the_model` already consumes. A shape C tool has
# no `intent` field of its own, so the agent writes the called tool's name into
# the answer -- the one place this bench tells the engine anything the provider
# did not.
module Eval::Classifier::ToolShapes
  extend self

  SINGLE_NAME = "player_intent".freeze
  SINGLE_DESCRIPTION = "Record what one typed line was aimed at.".freeze

  # Shape B: one tool, the identical schema, forced by name.
  def single(schema)
    tool = build_tool(SINGLE_NAME, SINGLE_DESCRIPTION, schema, inject_intent: false)
    { tools: [ tool ], choice: tool.name.to_sym }
  end

  # Shape C: one tool per intent, each with only its own target set, and the
  # model forced to pick one of them. `classifier` is asked for the SAME
  # closed sets `Playthrough::Classifier#ask_the_model` already builds
  # (`#exits_here`, `#characters_here`, `#items_here`, `#items_carried`,
  # `#physical_actions` -- all public readers), so this reaches no private
  # method and reimplements no resolution rule, only the naming of a target.
  def per_intent(classifier)
    tools = Playthrough::IntentSchema::INTENTS.map { |intent| intent_tool(intent, classifier) }
    { tools: tools, choice: :required }
  end

  private

  def intent_tool(intent, classifier)
    choices = target_names(intent, classifier)
    build_tool(intent, "Record a #{intent}, aimed at one of the things offered for it.",
               per_intent_schema(choices), inject_intent: true)
  end

  # THE FOUR CLOSED SETS `Playthrough::Classifier#build_intent` ALREADY
  # RESOLVES AGAINST, reproduced here as names rather than reached through
  # `.send` on a private method: this is bench request construction, not the
  # engine, and the engine's own copy of this table never changes underneath
  # it. `other` carries no target and never will -- see `IntentSchema`'s header.
  def target_names(intent, classifier)
    case intent.to_sym
    when :move then classifier.exits_here.map(&:name)
    when :talk, :attack
      classifier.characters_here.flat_map { |character| [ character.fullname, character.nickname ] }
    when :take then classifier.items_here.map(&:name)
    when :drop then classifier.items_carried.map(&:name)
    when :examine then (classifier.items_here + classifier.items_carried).map(&:name)
    when :use then classifier.physical_actions.map(&:token)
    else []
    end
  end

  # `target`/`also_named`, VERBATIM OFF `Playthrough::IntentSchema.for` -- built
  # from the real factory so the field descriptions and the `nothing` value are
  # never retyped by hand, then `intent` is dropped, because which tool was
  # called already answers it.
  def per_intent_schema(choices)
    full = Playthrough::IntentSchema.for(choices).new.to_json_schema.fetch(:schema)
    full.merge(properties: full.fetch(:properties).except(:intent),
               required: full.fetch(:required) - [ :intent ])
  end

  def build_tool(tool_name, tool_description, schema, inject_intent:)
    label = tool_name.to_s
    Class.new(RubyLLM::Tool) do
      description tool_description
      parameters(schema)
      requires_approval
      define_method(:name) { label }
      define_method(:params_schema) { parameters_schema }
      define_method(:execute) do |**args|
        content = args.transform_keys(&:to_s)
        content["intent"] = label if inject_intent
        content
      end
    end.new
  end
end
