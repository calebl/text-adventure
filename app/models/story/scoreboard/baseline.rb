# WHAT THE NUMBERS WERE LAST TIME, so a change can be judged as *these numbers
# moved* rather than as *this reads nicer to me*.
#
# One checked-in JSON file, one entry per corpus. It is in git on purpose and
# that is the whole mechanism: the diff of a baseline is the record of whether
# a prompt change, a model change or a bug fix actually did anything, and it
# survives in the history next to the change that claimed it.
#
# IT IS REWRITTEN ONLY WHEN ASKED (`SAVE=1 rake game:score`). A scoreboard that
# re-baselined itself on every run would always report no movement, which is
# the failure mode of every dashboard that has ever been ignored.
#
# A NOTE ON THE `database` ENTRY. It is a snapshot of one machine's stories, so
# it means nothing to anybody else -- and that is fine, because the person it
# means something to is the one playing. The `corpus` entry is the portable
# half: the same passages on every machine, so its baseline is a real
# regression line and `Story::AuditPrecisionTest` pins the flags behind it
# independently.
class Story::Scoreboard::Baseline
  PATH = "db/eval_baseline.json".freeze

  class << self
    def path = Rails.root.join(PATH)

    # Everything on file, or an empty hash. A missing file is the normal state
    # of a fresh checkout of a fork and is not an error.
    def all
      return {} unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError => error
      Rails.logger.warn("#{PATH} is not readable JSON, ignoring it: #{error.message}")
      {}
    end

    def read(corpus) = all[corpus.to_s]

    # Writes one corpus's snapshot and leaves the others alone, so scoring one
    # corpus never silently discards the other's line.
    def write(corpus, snapshot)
      merged = all.merge(corpus.to_s => snapshot)
      File.write(path, "#{JSON.pretty_generate(merged.sort.to_h)}\n")
      merged[corpus.to_s]
    end
  end
end
