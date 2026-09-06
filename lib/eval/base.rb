# IS THE BASE WORLD USABLE, and if not, why not.
#
# `script/eval_base.rb` builds `tmp/eval/base.sqlite3` once and every run of a
# sweep is a byte-identical copy of it. Both the builder and `rake eval:run`
# used to ask `File.exist?` before deciding whether to build, and EXISTENCE IS
# THE WRONG QUESTION: a build that was interrupted -- ^C, a full disk, a killed
# runner -- leaves the file behind at zero bytes, and both guards then trust it.
# That happened for real while shipping `ta-take-drop-narration`: an empty base
# was copied to fifteen run databases and all fifteen died on `Could not find
# table 'stories'`, a long way from the cause and after a sweep's worth of
# waiting.
#
# WHAT IT ASKS INSTEAD is whether the file is the thing a run needs: it opens as
# a SQLite database, it carries the tables the run reads, and it holds every
# world `Eval::STORIES` names. Reading the CONTENT rather than the size is what
# makes the failure impossible rather than merely unlikely -- an interrupted
# build can also leave a file with a schema and no worlds in it (the builder
# aborts on a missing world AFTER the connection is open), and a size check
# would trust that one too. It is one connection and three small queries, paid
# once per sweep.
#
# IT ANSWERS A REASON RATHER THAN A BOOLEAN, so the rebuild it triggers can say
# what was wrong with the file it is replacing. A caller that only wants the
# decision asks `.usable?`.
#
# It NEVER deletes anything: `#unusable_reason` is a read, and the removal is
# `script/eval_base.rb`'s own `FileUtils.rm_f` on the path it was asked to
# build. Nothing here goes near `storage/development.sqlite3`.
module Eval
  module Base
    # WHAT A RUN READS BEFORE IT WRITES ANYTHING. `stories` is the table the
    # real failure named, and `models` IS the RubyLLM registry since the
    # `acts_as` migration -- nothing resolves a model without it, so a base with
    # one and not the other is no more usable than an empty one.
    REQUIRED_TABLES = %w[stories models].freeze

    # WHY THE BASE AT `path` CANNOT BE USED, or nil when it can.
    def self.unusable_reason(path)
      path = path.to_s
      return "it does not exist" unless File.exist?(path)
      return "it is empty (0 bytes)" if File.size(path).zero?

      database = begin
        SQLite3::Database.new(path, readonly: true)
      rescue SQLite3::Exception => e
        return "it is not a readable SQLite database (#{e.class})"
      end

      begin
        tables = database.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten
        missing = REQUIRED_TABLES - tables
        return "it has no #{missing.join(" or ")} table" if missing.any?

        titles = database.execute("SELECT title FROM stories").flatten
        absent = Eval::STORIES - titles
        return "it is missing the seeded world(s) #{absent.join(", ")}" if absent.any?

        nil
      rescue SQLite3::Exception => e
        "it could not be read (#{e.class}: #{e.message})"
      ensure
        database.close
      end
    end

    def self.usable?(path) = unusable_reason(path).nil?
  end
end
