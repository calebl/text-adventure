# `Eval::RequestIdentity` and the schema serialization under it: the 16-hex
# digest a prompt or classifier set is identified by, and RubyLLM's
# `to_json_schema` output that half of every structured request is.
module EngineVectors::RequestIdentity
  SOURCES = [ "lib/eval/request_identity.rb", "lib/eval/classifier/version.rb", "lib/eval/prompt/request_version.rb",
              "app/models/playthrough/intent_schema.rb", "app/models/interaction/schema.rb",
              "app/models/location/detail_schema.rb", "app/models/location/exits_schema.rb",
              "app/models/location/place_schema.rb", "app/models/location/kind.rb" ].freeze
  NOTES = "Two kinds of case. A `schema` case names a RubyLLM::Schema (`schema`, a class name; `for` and " \
          "`args` when it is built by that class method from those arguments) and its output is " \
          "schema.new.to_json_schema, keys in the order RubyLLM writes them. An `identity` case holds " \
          "`requests` (a map of request id => {system, user, schema}, schema being a to_json_schema output " \
          "or null) and its output is {canonical, digest}: `canonical` is the requests with every object's " \
          "keys sorted, written by Ruby's JSON.generate (no spaces, non-ASCII written as itself, \"/\" not " \
          "escaped), and `digest` the first 16 hex characters of its SHA-256. The `classifier set` and " \
          "`prompt set` cases are the designated requests `rake eval:classifier_digest` and " \
          "`rake eval:prompt_digest` identify today (the classifier's physical tokens already replaced by " \
          "their named bindings); `identity` is the whole object each task prints.".freeze

  STATIC = %w[Scene::Schema Story::Schema Character::Schema Character::DesireWriter::Schema Interaction::Schema
              Location::PlaceSchema Location::DetailSchema Location::ExitsSchema Item::InscriptionSchema
              Quest::Schema Universe::PhysicalSchema Universe::SocietalSchema].freeze

  TARGETS = [ [], [ "The Supply Closet" ], [ "The Supply Closet", " ward stamp ", "", "ward stamp", "Perrin Lasco" ],
              [ "Ward Office 12 daybook", "the \"red\" door", "café — back room" ] ].freeze
  ACTIONS = [ [ "none" ], [ "none", "use:give:9", "move:12" ] ].freeze

  # Small requests that reach each rule of the canonical form on their own.
  EDGES = {
    "empty" => {},
    "nested order" => { "b" => { "z" => 1, "a" => [ { "y" => nil, "x" => true } ] }, "a" => { "system" => "s", "user" => "u", "schema" => nil } },
    "escapes" => { "one" => { "system" => "line\nbreak \"quoted\" back\\slash </tag> tab\t", "user" => "café — naïve ☃ \u0001", "schema" => nil } }
  }.freeze

  def self.constants_table = { "request_identity_version" => Eval::RequestIdentity::VERSION }

  def self.cases
    schemas + edges + sets
  end

  def self.schemas
    static = STATIC.map { |name| schema_case(name, name.constantize) }
    built = TARGETS.map { |targets| schema_case("Playthrough::IntentSchema", Playthrough::IntentSchema.for(targets), "for", targets) } +
            ACTIONS.map { |choices| schema_case("Interaction::Schema", Interaction::Schema.with_actions(choices), "with_actions", choices) } +
            (0..Location::Population::MOST).map { |wanted| schema_case("Location::DetailSchema", Location::DetailSchema.for_people(wanted), "for_people", [ wanted ]) }
    static + built
  end

  def self.schema_case(name, schema, built_by = nil, args = nil)
    input = { "schema" => name }
    input.merge!("for" => built_by, "args" => args) if built_by
    EngineVectors.case_for("schema #{name}#{" #{built_by} #{JSON.generate(args)}" if built_by}", input, plain(schema.new.to_json_schema))
  end

  def self.edges
    EDGES.map { |name, requests| identity_case("edge #{name}", requests) }
  end

  def self.sets
    classifier = plain(Eval::Classifier::Version.requests)
    prompt = plain(Eval::Prompt::RequestVersion.requests)
    [ identity_case("classifier set", classifier, Eval::Classifier::Version.identity(classifier)),
      identity_case("prompt set", prompt, Eval::RequestIdentity.of(prompt)) ]
  end

  def self.identity_case(name, requests, identity = nil)
    canonical = JSON.generate(Eval::RequestIdentity.canonical(requests))
    output = { "canonical" => canonical, "digest" => Eval::RequestIdentity.of(requests).fetch("digest") }
    output["identity"] = identity if identity
    EngineVectors.case_for(name, { "requests" => requests }, output)
  end

  # Symbol keys and whatever else a request holds, as the JSON it is sent as.
  def self.plain(value) = JSON.parse(JSON.generate(value))
end
