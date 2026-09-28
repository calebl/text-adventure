# GOLDEN VECTORS: THE ENGINE'S PURE RULES, WRITTEN DOWN AS INPUTS AND ANSWERS.
#
# Every file under `DIRECTORY` holds one portion of the engine -- the dice, a
# box's geometry, an interior's layout, the reading of a typed line -- as a
# list of cases, each a set of named inputs and the exact output this Ruby
# code gives for them. A second implementation of the same rules (a port to
# another language) is tested by reading these files and reproducing every
# output. So the files are a contract, and `docs/engine-vectors.md` says how
# to use and change them.
#
# THE FILES ARE GENERATED, NEVER HAND-EDITED. `rake engine:vectors` writes
# them and `test/lib/engine_vectors_test.rb` regenerates them in memory and
# compares, so any change to the Ruby behaviour shows up as a vector diff in
# the same PR that made it.
#
# EXCEPT THE PORTIONS THE ENGINE OWNS (`ENGINE_OWNED`): rules no Ruby code
# runs any more but the Ruby turn loop, which no player plays. Their files
# are the engine's, blessed there as a reviewed diff and vendored here byte
# for byte at the pinned commit (`EngineSweep::Vendored`), so this module
# neither writes nor regenerates them; a builder stays where the Ruby
# reference loop still runs its rule, so that loop can still be asked what it
# would have answered. A portion joins the list only once nothing but that
# loop runs its Ruby code:
# `world_mechanic` is not on it, because the debug view reads a mechanic's
# boundaries (`Playthrough::Debug`).
#
# OFFLINE AND WRITING NOTHING. No portion makes a model call. The portions
# that need rows (an interior, a shuffle, a deadline's anchor) build them with
# explicit ids inside a transaction that is always rolled back, so the answer
# does not depend on what else the database holds. The rake task goes further
# and runs against a fresh in-memory database loaded from `db/schema.rb`, so it
# never opens a database file at all.
#
# DETERMINISTIC BYTE FOR BYTE. Inputs come from plain arithmetic over fixed
# lists, every seed is an integer, and nothing reads the wall clock or a
# salted hash. Running the task twice gives identical files.
#
# THE FORMAT, VERSION `FORMAT_VERSION`. Each file is one JSON object:
#
#   format    always "engine-vectors"
#   version   `FORMAT_VERSION`; bumped when the shape of a file changes
#   portion   the file's name without `.json`
#   sources   the Ruby files whose behaviour the cases record
#   notes     how to read this portion's inputs and outputs
#   constants the tables the portion reads, where a port needs them verbatim
#             (a table is a list of [key, value] pairs, so key order is kept)
#   cases     one object per line: { "name", "input", "output" }
#
# A seed that can pass 2**53 is written as a decimal string; a System One
# reading is a JSON number between 0 and 1; every other number is a JSON
# integer. A time is whole seconds since the Unix epoch, UTC. The portions
# that pin a builder reading many tables take `records`, the rows the
# database held (`EngineVectors::Records`), or `records_of`, the name of the
# case whose rows they share.
module EngineVectors
  FORMAT = "engine-vectors".freeze
  FORMAT_VERSION = 1
  DIRECTORY = "test/engine_vectors".freeze

  PORTIONS = {
    "roll" => "EngineVectors::Dice",
    "stat_block" => "EngineVectors::StatBlock",
    "spot" => "EngineVectors::Spots",
    "placement" => "EngineVectors::Placements",
    "population" => "EngineVectors::Population",
    "danger" => "EngineVectors::Danger",
    "parameters" => "EngineVectors::Parameters",
    "box" => "EngineVectors::Boxes",
    "interior" => "EngineVectors::Interior",
    "shuffle_connections" => "EngineVectors::Shuffle",
    "world_mechanic" => "EngineVectors::Boundaries",
    "deadline" => "EngineVectors::Deadline",
    "cast" => "EngineVectors::Cast",
    "grammar_corpus" => "EngineVectors::GrammarCorpus",
    "classifier_intent" => "EngineVectors::ClassifierIntent",
    "cascade" => "EngineVectors::Cascade",
    "refusal" => "EngineVectors::Refusal",
    "classifier_request" => "EngineVectors::ClassifierRequest",
    "moment" => "EngineVectors::Moment",
    "volition_request" => "EngineVectors::VolitionRequest",
    "ledger" => "EngineVectors::Ledger",
    "memory" => "EngineVectors::Memory",
    "plan" => "EngineVectors::Plan",
    "request_identity" => "EngineVectors::RequestIdentity",
    "kept_requests" => "EngineVectors::KeptRequests"
  }.freeze

  # The portions whose files are the engine's (its `vectors/ENGINE_OWNED`).
  # `physics` never had a Ruby builder: falls were written in the engine.
  # `grammar` and `slash_menu` have none any more: the play box's menu and the
  # grammar's slash words and use lines are read off the engine now
  # (`Playthrough::RustEngine.glance`).
  ENGINE_OWNED = %w[shuffle_connections physics grammar grammar_corpus slash_menu classifier_intent refusal].freeze

  # EVERY PORTION'S FILE CONTENTS that this module writes, keyed by file
  # name: all but the engine's own. Needs a database with the current schema
  # for the portions that build rows; nothing is kept.
  def self.files
    PORTIONS.except(*ENGINE_OWNED).to_h { |portion, builder| [ "#{portion}.json", render(document(portion, builder.constantize)) ] }
  end

  # A portion whose tables and cases come out of one piece of work answers
  # `.contents` as [constants, cases] instead of the two separately.
  def self.document(portion, builder)
    constants, cases = builder.respond_to?(:contents) ? builder.contents : [ builder.constants_table, builder.cases ]
    {
      "format" => FORMAT,
      "version" => FORMAT_VERSION,
      "portion" => portion,
      "sources" => builder::SOURCES,
      "notes" => builder::NOTES,
      "constants" => constants,
      "cases" => cases
    }
  end

  # ONE CASE PER LINE, so a behaviour change reads as the lines it changed.
  def self.render(document)
    cases = document.fetch("cases")
    lines = [ "{" ]
    document.except("cases").each { |key, value| lines << "  #{JSON.generate(key)}: #{JSON.generate(value)}," }
    lines << '  "cases": ['
    cases.each_with_index do |one, index|
      lines << "    #{JSON.generate(one)}#{"," unless index == cases.size - 1}"
    end
    lines << "  ]"
    lines << "}"
    "#{lines.join("\n")}\n"
  end

  def self.write!(root = Rails.root)
    directory = root.join(DIRECTORY)
    FileUtils.mkdir_p(directory)
    files.each { |name, body| File.write(directory.join(name), body) }
  end

  # RUNS THE BLOCK AGAINST A FRESH IN-MEMORY DATABASE, then puts the app's own
  # connection back. What the rake task uses, so it never touches a file.
  def self.in_memory_database
    config = ActiveRecord::Base.connection_db_config
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Schema.verbose = false
    load Rails.root.join("db/schema.rb").to_s
    yield
  ensure
    ActiveRecord::Base.establish_connection(config)
  end

  # A CASE THAT NEEDS ROWS builds them in here, and they never outlive it.
  def self.rolled_back
    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      result = yield
      raise ActiveRecord::Rollback
    end
    result
  end

  def self.case_for(name, input, output) = { "name" => name, "input" => input, "output" => output }

  # A table as [key, value] pairs, so a reader in any language keeps its order.
  def self.pairs(hash) = hash.map { |key, value| [ key, plain(value) ] }

  def self.plain(value)
    case value
    when Range then [ value.min, value.max ]
    when Hash then pairs(value)
    when Array then value.map { |item| plain(item) }
    else value
    end
  end
end
