# RECORD FIDELITY ONLY. No regex pretends to infer a race, an identity or a
# plausible world from prose. Names of new places and quest targets are free
# text in today's schemas, not picks from a list. Character race is the engine's
# pick; only that stored attribute can honestly be compared with universe races.
# Every check has its own denominator. A missing historical fact is unavailable,
# and an unanswered call is a failure, never a clean answer.
class Eval::Genesis::Scorer
  CHECKS = {
    required_fields: "required fields absent or empty, including nested objects",
    outside_schema: "an answer supplies a field the emitted schema does not offer",
    schema_shape: "wrong type, enum, length or array bounds in the emitted schema",
    engine_owned: "character answer sets an engine-owned attribute, or admission changes the engine pick",
    race_outside_universe: "admitted character race is outside the fixed universe list",
    name_taken: "character answer repeats a name in the prompt's cast",
    retry_not_distinct: "the retry repeats its fixed conflicting name",
    quest_bounds: "step or conclusion count outside the engine bounds",
    quest_default: "the answer does not choose exactly one default conclusion",
    quest_labels: "conclusions collapse to duplicate engine labels",
    quest_admission: "the engine rejects the arc or loses steps or conclusions"
  }.freeze
  ENGINE_FIELDS = (%w[stats hit_points max_hit_points hp level hit_die hostile hostility race age sex] +
                   Character::ABILITIES.map(&:to_s)).freeze

  attr_reader :rows
  def initialize(rows) = @rows = rows
  def judgeable_for(code) = rows.count { |row| !judge(code.to_sym, row).nil? }
  def flagged_for(code) = rows.select { |row| judge(code.to_sym, row) == true }
  def rate(code)
    count = judgeable_for(code)
    flagged_for(code).size.fdiv(count) if count.positive?
  end

  def judge(code, row)
    answer, facts, after = row.values_at("answer", "facts", "after")
    return nil unless row.key?("answer")
    facts ||= {}
    unless %i[required_fields outside_schema schema_shape].include?(code)
      return nil unless answer.is_a?(Hash)
    end
    case code
    when :required_fields, :outside_schema, :schema_shape
      schema = row.dig("request", "schema", "schema")
      return nil unless schema

      violations(schema, answer).include?(code)
    when :engine_owned
      return nil unless facts.key?("body")
      return true if (answer.keys & ENGINE_FIELDS).any?
      return nil unless after&.key?("body")

      # The constructor exposes enum KEYS; the prompt states stored labels.
      # Read the engine's mapping rather than calling that spelling a changed
      # pick. The request digest already detects changed labels in the prompt.
      sex = Character.sexes.fetch(after["sex"], after["sex"])
      sex != facts["sex"] || %w[body race age hostile].any? { |key| after[key] != facts[key] }
    when :race_outside_universe
      return nil unless facts.key?("races") && after&.key?("race")

      !facts["races"].include?(after["race"])
    when :name_taken
      return nil unless facts.key?("taken_names") && answer["fullname"].is_a?(String)

      facts["taken_names"].any? { |name| name.casecmp?(answer["fullname"].strip) }
    when :retry_not_distinct
      return nil unless facts.key?("retry_name") && answer["fullname"].is_a?(String)

      facts["retry_name"].casecmp?(answer["fullname"].strip)
    when :quest_bounds
      return nil unless facts.key?("step_bounds") && facts.key?("outcome_bounds")

      { "steps" => "step_bounds", "outcomes" => "outcome_bounds" }.any? do |field, bounds|
        !answer[field].is_a?(Array) || !Range.new(*facts[bounds]).cover?(answer[field].size)
      end
    when :quest_default, :quest_labels
      return nil unless facts.key?("outcome_bounds") && answer["outcomes"].is_a?(Array)
      outcomes = answer["outcomes"]
      return true unless outcomes.all? { |outcome| outcome.is_a?(Hash) }
      return outcomes.count { |outcome| outcome["is_default"] == true } != 1 if code == :quest_default

      names = outcomes.map { |outcome| outcome["name"].to_s.parameterize }
      names.uniq.size != names.size || names.any?(&:blank?)
    when :quest_admission
      return nil unless facts.key?("step_bounds") && after&.key?("admitted")

      !after["admitted"] || Array(after["steps"]).size != Array(answer["steps"]).size ||
        Array(after["outcomes"]).size != Array(answer["outcomes"]).size ||
        Array(after["outcomes"]).count { |outcome| outcome["is_default"] } != 1 ||
        Array(after["steps"]).any? { |step| step["target_id"].present? }
    else raise ArgumentError, "unknown genesis check #{code}"
    end
  end

  # A deliberately small recursive reader of the schema constructs these
  # producers emit. Required booleans may be false: Rails blank? would flag
  # every alternative ending as missing.
  def violations(schema, value)
    found = []
    type = schema["type"]
    valid_type = case type
    when "object" then value.is_a?(Hash)
    when "array" then value.is_a?(Array)
    when "string" then value.is_a?(String)
    when "boolean" then [ true, false ].include?(value)
    when "integer" then value.is_a?(Integer)
    when "number" then value.is_a?(Numeric)
    else false
    end
    return [ :schema_shape ] unless valid_type
    found << :schema_shape if schema["enum"] && !schema["enum"].include?(value)
    case type
    when "object"
      properties = schema.fetch("properties", {})
      found << :outside_schema if (value.keys - properties.keys).any?
      required = schema.fetch("required", []).map(&:to_s)
      found << :required_fields if required.any? { |key| !value.key?(key) || empty?(value[key]) }
      properties.each { |key, child| found.concat(violations(child, value[key])) if value.key?(key) }
    when "array"
      found << :schema_shape if value.size < schema.fetch("minItems", 0) || value.size > schema.fetch("maxItems", Float::INFINITY)
      value.each { |child| found.concat(violations(schema.fetch("items"), child)) }
    when "string"
      found << :schema_shape if value.length > schema.fetch("maxLength", Float::INFINITY) || value.length < schema.fetch("minLength", 0)
    end
    found.uniq
  end

  def empty?(value) = value.nil? || (value.is_a?(String) ? value.strip.empty? : value.respond_to?(:empty?) && value.empty?)
end
