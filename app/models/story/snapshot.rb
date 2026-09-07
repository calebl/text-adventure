# THE WORLD A STORY WAS GENERATED WITH, kept so the story can be played again
# from the beginning without anybody destroying it.
#
# The captain's request, 2026-09-07: *"I want to be able to 'reset' a game to
# it's initial state after generation so I can see how it performs from the
# beginning instead of only after a lot of locations have already been
# generated."* And about the stories already in his database: *"I don't want to
# delete them. I want to be able to run them fresh as if they were new."*
#
# HE CHOSE A FORK OVER A REWIND, offered both: *"for the story reset, I want to
# fork."* So nothing here ever writes to a story that exists -- `Story::Fork`
# loads this snapshot as a NEW story beside the old one, and the original's
# playthroughs, scenes and `Playthrough::Feedback` rows are not read, not
# copied and not touched. A verdict REFERENCES the exact `Scene` it judged
# (see that model's header), so a rewind would have deleted the evidence the
# scoreboard's agreement figures are computed from. That is the whole reason
# the shape is a fork.
#
# WHAT IS IN IT is `WorldSeed::Exporter`'s document, unchanged and unwrapped:
# the whole world graph plus the one opening scene, no playthroughs, no visits,
# no events. That exporter already draws exactly the world-vs-progress line
# this needs, so there is no second exporter here and there must not be one --
# a snapshot that disagreed with a seed file about what a world is would be a
# second format to keep loading.
#
# == WHERE IT LIVES, AND WHAT WAS REJECTED
#
# `stories.generation_snapshot`, a text column on the story's own row. Four
# constraints decided it, and a column is the only shape that meets all four
# without machinery:
#
#   IT MUST NOT LIVE UNDER db/seeds/worlds. `bin/rails db:seed` and
#   `rake game:reseed` load EVERY file in that directory, so a snapshot dropped
#   there would be seeded as a world of its own on the next pull -- and one
#   keyed by the same title as its original would re-assert itself OVER the
#   story it was taken from, which is precisely the row this feature exists not
#   to touch.
#
#   IT MUST SURVIVE `rake game:reseed`. A column does: `WorldSeed::Loader`
#   writes `story_document`'s five keys and nothing else, so re-asserting a
#   checked-in file over a story leaves its snapshot exactly as it was.
#
#   IT MUST BE DESTROYED WITH THE STORY. A column on the row is, by the row
#   going. `Story::Deletion#manifest` says so rather than counting it, because
#   it is not a table.
#
#   IT MUST NOT BE A CHECKED-IN FILE FOR A WORLD ON ONE MACHINE. The captain's
#   generated stories exist in his development database and nowhere else;
#   committing a snapshot of one would put a private world in the repository
#   and make `git status` dirty every time he generated another.
#
# REJECTED: a file under the gitignored `storage/`. It meets all four, and it
# was the alternative offered. It loses on the fourth constraint's neighbour --
# a file is a second thing to keep in step with a row, and `rake game:delete`
# would have to learn to unlink it, which is a deletion path that can fail
# halfway and leave a snapshot for a story that is gone. It also cannot be read
# from a console or a test without a path, and `db:prepare` on a fresh clone
# would produce a database whose stories claim snapshots that are not there.
#
# REJECTED: a `story_snapshots` table with a row per capture. It buys a history
# of snapshots, and nothing asked for one: a story is generated once, so there
# is one generation-time state and re-capturing it would be re-capturing a world
# somebody has played. A table would also need its own factory, its own test
# file and its own line in the deletion manifest to hold one string.
#
# == A STORY THAT PREDATES THE COLUMN
#
# Has no snapshot, and never will have one that was taken at the time -- there
# was nothing to take it. `Story::Snapshot::Derivation` reconstructs one from
# the records, best effort and with its uncertainty stated out loud. An absent
# snapshot is NOT a defect: `Story::Doctor` reports nothing about it, because a
# story generated before this column is not broken.
class Story::Snapshot
  # A snapshot that could not be taken, and the sentence saying why. Raised
  # rather than returned nil: every caller of `.capture!` is a command that has
  # just built or been handed a world, and a snapshot silently not written is a
  # fork that silently cannot happen weeks later.
  class NotSnapshottable < StandardError; end

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # Takes the snapshot and writes it to the column. Called by `rake game:new`
  # the moment `Story::FirstScreen#build!` returns, and by
  # `rake game:snapshot` for a story that predates the column.
  #
  # `document:` is how the derivation hands over a reconstructed world instead
  # of the story as it stands now. Left out, the story is exported as it is,
  # which is only right at generation time.
  def self.capture!(story, document: nil)
    new(story).capture!(document: document)
  end

  # The stored document, or nil. Parsed on every call rather than memoized on
  # the story: a snapshot is read once, by one command.
  def self.for(story)
    new(story).document
  end

  def capture!(document: nil)
    document ||= WorldSeed::Exporter.new(story).document

    # REFUSED RATHER THAN STORED. A file with no `opening_scene` is one
    # `WorldSeed::Loader` will not load (`#validate!`), so storing one would
    # write a snapshot whose only use fails at the point it is used, weeks
    # later, with no way left to tell what went wrong.
    if document["opening_scene"].blank?
      raise NotSnapshottable, "#{story.title.inspect} has no opening arrival, so its snapshot would not load. " \
                              "`rake game:doctor` reports it; repair it and snapshot again."
    end

    story.update!(generation_snapshot: WorldSeed.dump(document))
    document
  end

  # The stored world, or nil when this story predates the column. Malformed
  # YAML reads as nil for `WorldSeed.checked_in_document`'s reason: the reader
  # asking "is there a snapshot" must not be the thing that raises on a broken
  # one -- `Story::Fork` says so in a sentence instead.
  def document
    yaml = story.generation_snapshot
    return nil if yaml.blank?

    WorldSeed.parse(yaml)
  rescue StandardError
    nil
  end
end
