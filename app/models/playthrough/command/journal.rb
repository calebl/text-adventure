# A turn's restart points, under its existing GameLock. Engine writes and their
# receipts share a short transaction; a model answer is remembered only AFTER
# the call returns. Never put a provider call inside #commit.
#
# The scope is thread-local because the turn calls several existing writers.
# It is installed only by Command#execute! and always removed, including on
# interruption. Offline mechanics and world generation have no journal.
class Playthrough::Command::Journal
  DATA_TYPES = %w[Playthrough::Classifier::Intent Playthrough::NpcAction::Result
                  Playthrough::Turn::Throw Character::Check Playthrough::Arc::Concluded].freeze
  RECORD_TYPES = %w[Scene Location Character Item Playthrough::Blow Playthrough::Toll
                    Playthrough::Ending Quest::Outcome].freeze

  def self.with(command)
    previous = Thread.current[:turn_journal]
    Thread.current[:turn_journal] = new(command)
    yield
  ensure
    Thread.current[:turn_journal] = previous
  end

  def self.commit(key, &block)
    current = Thread.current[:turn_journal]
    current ? current.step(key, atomic: true, &block) : yield
  end

  def self.remember(key, &block)
    current = Thread.current[:turn_journal]
    current ? current.step(key, atomic: false, &block) : yield
  end

  def self.saved?(key) = Thread.current[:turn_journal]&.saved?(key) || false
  def self.read(key) = Thread.current[:turn_journal]&.read(key)

  def initialize(command)
    @command = command
  end

  def saved?(key) = @command.journal.fetch("steps", {}).key?(key)
  def read(key) = decode(@command.journal.fetch("steps").fetch(key))

  def step(key, atomic:)
    return read(key) if saved?(key)

    if atomic
      @command.class.transaction { save(key, yield) }
    else
      value = yield
      @command.class.transaction { save(key, value) }
    end
  rescue Exception # Reload even after an interrupt rolled back a receipt.
    @command.reload
    raise
  end

  private

  def save(key, value)
    steps = @command.journal.fetch("steps", {}).merge(key => encode(value))
    @command.update!(journal: @command.journal.merge("steps" => steps))
    value
  end

  def encode(value)
    case value
    when NilClass, TrueClass, FalseClass, Numeric, String then value
    when Symbol then { "symbol" => value.to_s }
    when Array then { "array" => value.map { |entry| encode(entry) } }
    when Hash then { "hash" => value.map { |key, entry| [ encode(key), encode(entry) ] } }
    when Playthrough::Refusal
      { "refusal" => encode({ kind: value.kind, typed: value.typed, fact: value.fact, offer: value.offer }) }
    when ApplicationRecord
      raise ArgumentError, "Unsupported journal record: #{value.class}" unless RECORD_TYPES.include?(value.class.name)

      result = { "record" => value.class.name, "id" => value.id }
      if value.is_a?(Scene)
        result["tolls"] = value.narrated_toll_ids
        result["safety"] = value.safety_notice
        result["setup"] = Playthrough::SetupNotice.for(value.rendering_error).present?
      end
      result
    when Data
      raise ArgumentError, "Unsupported journal value: #{value.class}" unless DATA_TYPES.include?(value.class.name)

      { "data" => value.class.name, "fields" => encode(value.to_h) }
    else raise ArgumentError, "Unsupported journal value: #{value.class}"
    end
  end

  def decode(value)
    return value unless value.is_a?(Hash)

    return value.fetch("symbol").to_sym if value.key?("symbol")
    return value.fetch("array").map { |entry| decode(entry) } if value.key?("array")
    return value.fetch("hash").to_h { |key, entry| [ decode(key), decode(entry) ] } if value.key?("hash")
    return Playthrough::Refusal.new(**decode(value.fetch("refusal"))) if value.key?("refusal")
    if DATA_TYPES.include?(value["data"])
      return value.fetch("data").constantize.new(**decode(value.fetch("fields")))
    end
    raise ArgumentError, "Invalid journal record" unless RECORD_TYPES.include?(value["record"])

    row = value.fetch("record").constantize.find(value.fetch("id"))
    if row.is_a?(Scene)
      row.narrated_toll_ids = value["tolls"]
      row.safety_notice = value["safety"]
      row.rendering_error = BaseAgent::NoModelConfiguredError.new if value["setup"]
    end
    row
  end
end
