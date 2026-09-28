# WHETHER A DUMPED SCHEMA FILE MAY BE PUT BACK, decided on its text and nothing
# else.
#
# THE PROBLEM IT IS FOR. A database built migration by migration keeps its
# columns in the order the migrations added them. Rails 8.1's schema dumper
# writes columns in database order and does not sort them, while the committed
# `db/schema.rb`, `db/queue_schema.rb` and `db/cable_schema.rb` are alphabetical,
# because a fresh database is loaded FROM them. So on the owner's machine every
# `bin/update` that ran a migration left all three files modified -- the same
# lines, only their positions moved -- and the next pull refused a dirty tree.
#
# So after it migrates, `bin/update` asks this about each file and writes the
# committed bytes back when the answer is yes. The answer is yes ONLY when:
#
#   - the file was clean before `bin/update` started. An edit that was already
#     there is somebody's, and is never this script's to overwrite;
#   - it is committed at HEAD, so there is something to put back;
#   - and the dump and the committed file are the same lines apart from their
#     order INSIDE a `create_table` block. Everything outside the blocks -- the
#     version line, `add_foreign_key`, the order of the tables themselves --
#     must match line for line.
#
# Anything else is left alone and said: a missing column, a changed default, or
# a newer version from a migration that is not committed yet is a real change,
# and hiding one would put a schema in the repo that the database does not have.
#
# THIS IS THE DECISION AND NOT THE ACT, for the reason `Update::SeedFiles`
# gives: a pure function over text, asserted without a checkout or a database
# (`Update::SchemaOrderTest`). `bin/update` reads git and writes the file.
#
# PLAIN RUBY, no Rails: `bin/update` reads this by `require` before the app is
# booted.
module Update
  class SchemaOrder
    # Every schema file a development `db:migrate` dumps. One that does not
    # exist in a checkout is skipped rather than reported.
    FILES = %w[db/schema.rb db/queue_schema.rb db/cable_schema.rb].freeze

    Outcome = Data.define(:path, :restore, :line) do
      def restore? = restore
    end

    # `committed` is the file at HEAD (nil when it is not tracked there),
    # `dumped` the file as the migration left it, `clean_before` whether it had
    # no uncommitted change before `bin/update` started.
    def self.decide(path:, clean_before:, committed:, dumped:)
      if !clean_before
        note = committed && dumped && column_order_only?(committed, dumped) ? " (as dumped now it differs only in column order)" : ""
        Outcome.new(path:, restore: false,
                    line: "#{path} had uncommitted changes before this run, so it was left alone#{note}.")
      elsif committed.nil?
        Outcome.new(path:, restore: false, line: "#{path} is not committed at HEAD; left alone.")
      elsif dumped.nil?
        Outcome.new(path:, restore: false, line: "#{path} is gone after migrating; left alone.")
      elsif dumped == committed
        Outcome.new(path:, restore: false, line: "#{path} matches the committed file.")
      elsif column_order_only?(committed, dumped)
        Outcome.new(path:, restore: true, line: "restored #{path} (column order only).")
      else
        Outcome.new(path:, restore: false,
                    line: "#{path} differs from the committed file by more than column order; " \
                          "left alone (`git diff #{path}`).")
      end
    end

    # What `--dry-run` says instead: no migration runs, so nothing is dumped.
    def self.dry_line(path:, clean_before:, migrating:)
      if !clean_before
        "#{path} has uncommitted changes, so it would be left alone."
      elsif migrating
        "#{path}: would be restored after migrating if the dump differs only in column order."
      else
        "#{path}: no migration to run, so nothing would be dumped."
      end
    end

    def self.column_order_only?(committed, dumped)
      canonical(committed) == canonical(dumped)
    end

    # The file with the body of every `create_table ... do |t|` block sorted and
    # everything else kept in place. A block with no matching `end` is kept in
    # its own order, so a file this cannot read is never forgiven anything.
    def self.canonical(text)
      out = []
      block = nil

      text.each_line(chomp: true) do |line|
        if block
          if line == block[:end]
            out.push(block[:head], *block[:body].sort, line)
            block = nil
          else
            block[:body] << line
          end
        elsif (match = line.match(/\A(\s*)create_table\b.*\bdo \|\w+\|\s*\z/))
          block = { head: line, end: "#{match[1]}end", body: [] }
        else
          out << line
        end
      end

      out.push(block[:head], *block[:body]) if block
      out
    end

    # `git status --porcelain -- <files>` output as the paths it names.
    def self.dirty_paths(output)
      output.to_s.lines.map { |line| line.chomp[3..].to_s.strip }.reject(&:empty?)
    end
  end
end
