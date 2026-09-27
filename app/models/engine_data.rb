# THE ONE HOME OF EVERY FIXED PROMPT TEXT AND CLOSED TABLE THE ENGINE READS.
#
# The words a model is handed and the tables a die is weighted with live in
# `config/engine/*.yml`, one file per owning class, so that any engine reading
# this game's rules reads the same bytes this one does. A prompt with two homes
# is a prompt that drifts, and the drift would be invisible: the digests that
# prove a request unchanged (`rake eval:prompt_digest`, `eval:classifier_digest`,
# `eval:realization_digest`) can only watch one of them.
#
# WHAT IS HERE AND WHAT IS NOT. A text that is the same on every call moves
# here; a template that interleaves records with prose stays in the builder
# that fills it in, because its shape is code. A static text that needs one
# value takes it as a `%{name}` placeholder, filled with `format` by its owner.
#
# THE OWNING CLASS STILL NAMES THE VALUE. `Scene::Narrator::INSTRUCTIONS` is
# still the constant everything reads; only its literal moved. The comment
# explaining why a sentence says what it says stays beside that constant, which
# is where the person changing it is standing.
#
# LOADING FAILS LOUDLY. A missing file, a file that is not YAML, and a file whose
# shape is not the one declared in `SCHEMAS` all raise `EngineData::Error` when
# the owning class is loaded -- never a nil prompt sent to a model. Every value is
# read once per process and frozen.
module EngineData
  class Error < StandardError; end

  ROOT = Rails.root.join("config/engine")

  # A HASH WITH ANY STRING KEYS, every value of one shape -- as against a Hash
  # literal in a schema, which is a record with exactly those keys.
  Map = Data.define(:value)
  # A VALUE OF ONE SHAPE, OR NOTHING.
  Maybe = Data.define(:value)

  def self.map(value) = Map.new(value)
  def self.maybe(value) = Maybe.new(value)

  CRITERIA = map(String)

  # EVERY FILE AND ITS SHAPE. A file on disk with no entry here, or an entry
  # with no file, is an error `EngineDataTest` reports.
  SCHEMAS = {
    "character" => { "hit_dice" => [ Integer ] },
    "character/desires" => { "system_prompt" => String, "more_than_one" => String },
    "character/generator" => { "system_prompt" => String, "protagonist_section" => String },
    "item/inscriber" => { "instructions" => String },
    "location/generator" => { "nobody_here" => String, "system_prompt" => String, "parameters_instructions" => String },
    "location/parameters" => {
      "no_inside" => String, "one_room" => String, "flat" => String, "no_hazard" => String,
      "inside" => map(maybe([ Integer ])),
      "rooms_a_band_promises" => map(Integer),
      "storeys_above" => map(Integer),
      "storeys_below" => map(Integer),
      "danger" => map([ String ]),
      "gradient" => map(Integer),
      "hazard_die" => Integer,
      "hazard_share" => Integer
    },
    "playthrough/classifier" => { "instructions" => String },
    "playthrough/classifier/request" => {
      "intent_instructions" => String, "intent_criteria" => CRITERIA,
      "target_instructions" => String,
      "targets" => map({ "premise" => String, "nothing" => String }),
      "also_named_instructions" => String, "also_named_nothing" => String,
      "named_more_than_one_instructions" => String, "named_more_than_one_criteria" => CRITERIA,
      "target_present_instructions" => String, "target_present_criteria" => CRITERIA
    },
    "playthrough/grammar" => { "verbs" => map(String) },
    "playthrough/volition/weights" => { "shapes" => [ String ], "base" => Integer, "table" => map(map(Integer)) },
    "quest/generator" => { "system_prompt" => String },
    "scene/ending" => { "instructions" => String },
    "scene/generator" => { "system_prompt" => String, "arrival_returning" => String, "arrival_first" => String },
    "scene/narrator" => { "instructions" => String, "doing" => map(String) },
    "story/generator" => { "system_prompt" => String },
    "universe/generator" => { "system_prompt" => String, "societal_prompt" => String }
  }.freeze

  @loaded = {}
  @lock = Mutex.new

  # ONE FILE, parsed, checked against its schema and deep-frozen. Memoized.
  def self.fetch(name)
    @lock.synchronize { @loaded[name] ||= load(name) }
  end

  def self.load(name, root: ROOT)
    schema = SCHEMAS.fetch(name) { raise Error, "#{name}: no schema declared in EngineData::SCHEMAS" }
    path = Pathname(root).join("#{name}.yml")
    raise Error, "#{name}: #{path} is missing" unless path.file?

    data = begin
      YAML.safe_load_file(path, aliases: false)
    rescue Psych::Exception => e
      raise Error, "#{name}: #{path} is not valid YAML: #{e.message}"
    end
    check!(data, schema, name)
    deep_freeze(data)
  end

  def self.check!(value, spec, where)
    case spec
    when Maybe
      check!(value, spec.value, where) unless value.nil?
    when Map
      raise Error, "#{where}: expected a mapping, got #{value.class}" unless value.is_a?(Hash)

      value.each do |key, inner|
        raise Error, "#{where}: key #{key.inspect} is not a string" unless key.is_a?(String)

        check!(inner, spec.value, "#{where}.#{key}")
      end
    when Hash
      raise Error, "#{where}: expected a mapping, got #{value.class}" unless value.is_a?(Hash)
      unless value.keys.sort == spec.keys.sort
        raise Error, "#{where}: keys #{value.keys.sort.inspect} are not #{spec.keys.sort.inspect}"
      end

      spec.each { |key, inner| check!(value[key], inner, "#{where}.#{key}") }
    when Array
      raise Error, "#{where}: expected a list, got #{value.class}" unless value.is_a?(Array)

      value.each_with_index { |inner, index| check!(inner, spec.first, "#{where}[#{index}]") }
    else
      raise Error, "#{where}: expected #{spec}, got #{value.inspect}" unless value.is_a?(spec)
    end
  end

  def self.deep_freeze(value)
    case value
    when Hash then value.each_value { |inner| deep_freeze(inner) }
    when Array then value.each { |inner| deep_freeze(inner) }
    end
    value.freeze
  end

  private_class_method :load, :check!, :deep_freeze
end
