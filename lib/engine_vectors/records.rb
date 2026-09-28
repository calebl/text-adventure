require "active_support/testing/time_helpers"

# THE ROWS A BUILDER READ, written down as a case's input.
#
# The builders of step three (a narration context, a ledger, a memory, a
# floor plan, a System One request) read many tables at once, so a case
# cannot name its inputs field by field the way a dice case does. Instead it
# builds its records, runs the builder, and writes down every row the
# database then holds: a second implementation loads those rows into the same
# schema and must give the same output.
#
# A dump is { table => [row, ...] }: tables in name order, only tables with
# rows, rows in id order (or in column order for a table with no id), every
# column present (but `RANDOM`'s, written as `FIXED`, and a reference into a
# `SKIPPED` table, written as null). A boolean is true/false, a time whole seconds since the
# Unix epoch (UTC), a JSON column its parsed value and a float a JSON number.
#
# THE CLOCK IS STOPPED AT `EngineVectors::World::START` while a case is built
# (`.frozen`), so `created_at` and `updated_at` never carry the wall clock; a
# row whose time matters to a builder sets it explicitly.
module EngineVectors::Records
  # Not records a builder reads: Rails' own bookkeeping, and RubyLLM's model
  # registry, which the seed step fills and the test database may not.
  SKIPPED = %w[schema_migrations ar_internal_metadata ruby_llm_models].freeze

  # Columns filled at random when a row is born and read by no builder: a
  # stage that builds its own playthrough cannot be told what to write, so
  # the dump writes this fixed value in their place.
  RANDOM = { "playthroughs" => %w[token] }.freeze
  FIXED = "engine-vectors".freeze

  # A column that points into a skipped table is written as null: the row it
  # names is not in the dump, and its id is whichever the registry happened
  # to hold when the test that filled it ran first, so it would make a case
  # depend on the order tests ran in.
  def self.unreachable(connection, table)
    connection.foreign_keys(table).select { |key| SKIPPED.include?(key.to_table) }.map(&:column)
  end

  def self.dump
    connection = ActiveRecord::Base.connection
    (connection.tables.sort - SKIPPED).each_with_object({}) do |table, dump|
      columns = connection.columns(table).sort_by(&:name)
      arel = Arel::Table.new(table)
      order = columns.any? { |column| column.name == "id" } ? [ arel[:id] ] : columns.map { |column| arel[column.name] }
      rows = connection.select_all(arel.project(Arel.star).order(*order)).to_a
      next if rows.empty?

      random = RANDOM.fetch(table, [])
      unreachable = unreachable(connection, table)
      dump[table] = rows.map do |row|
        columns.to_h do |column|
          next [ column.name, nil ] if unreachable.include?(column.name)

          [ column.name, random.include?(column.name) ? FIXED : value(column, row[column.name]) ]
        end
      end
    end
  end

  def self.value(column, raw)
    return nil if raw.nil?

    case column.type
    when :boolean then ActiveModel::Type::Boolean.new.cast(raw)
    when :datetime then ActiveRecord::Type::DateTime.new.cast(raw).to_i
    when :json then raw.is_a?(String) ? JSON.parse(raw) : raw
    else raw
    end
  end

  # RUNS THE BLOCK WITH THE CLOCK AT THE WORLD'S START and every id counter
  # at zero, inside a transaction that is rolled back, so a builder's rows and
  # their ids are the same in any database the export runs against. Stops if
  # a table already holds rows, which would make the dump somebody else's.
  def self.frozen(&block)
    EngineVectors.rolled_back do
      held = dump
      raise ArgumentError, "the database already holds rows in #{held.keys.join(", ")}" unless held.empty?

      connection = ActiveRecord::Base.connection
      sequences = connection.select_value("SELECT count(*) FROM sqlite_master WHERE name = 'sqlite_sequence'").to_i
      connection.execute("DELETE FROM sqlite_sequence") if sequences.positive?
      Clock.at(EngineVectors::World::START, &block)
    end
  end

  class Clock
    include ActiveSupport::Testing::TimeHelpers

    def self.at(time, &block) = new.travel_to(time, &block)
  end
end
