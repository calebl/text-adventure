# A SECOND COPY OF A WORLD AT ITS BEGINNING, made so the first one can be
# played again from the start without being touched.
#
# The captain's ruling, 2026-09-07, offered a rewind of the same story and a
# fork from a generation-time snapshot: *"for the story reset, I want to
# fork."* `Story::Snapshot` carries what the choice cost and bought; this is
# the half that runs.
#
# NOTHING HERE READS OR WRITES A PLAYTHROUGH, A SCENE OR A `Playthrough::Feedback`.
# The document goes in, `WorldSeed::Loader` writes a new story out, and the
# original's rows are not in either path -- which is the guarantee the whole
# shape exists for, and `Story::ForkTest` counts all three before and after to
# hold it.
#
# == THE TITLE, AND WHY IT CANNOT BE THE ORIGINAL'S
#
# `WorldSeed::Loader` keys a story on its TITLE. Handing it a document titled
# like a story that exists would not create a second story: it would re-assert
# the document OVER the first one, renaming its rooms and putting its people
# back where the snapshot has them, in a world somebody has 47 verdicts about.
# That is the one thing this feature must not do, so the title is changed
# BEFORE the loader ever sees the document, and `#title` refuses to answer with
# a name that is already taken.
#
# The default is `"<title> (fork 1)"`, counting up until nothing answers to it,
# so forking the same story four times gives four stories rather than one
# overwritten three times. `title:` overrides it and is checked the same way.
#
# == THE UNIVERSE IS COPIED, NOT SHARED
#
# Deliberately, and it is what `WorldSeed::Loader` does on its own: it reads
# `existing_story&.universe`, so a document whose title matches nothing builds a
# new `Universe` with its own races. Sharing was the alternative and it is
# refused for two reasons.
#
# A `Race` belongs to a universe and `Character` belongs to a race, so a shared
# universe means the fork's people point at the ORIGINAL's race rows. Every one
# of those rows is then something a re-seed or a hand edit of one story can
# change under the other -- and `monstrous` is not decoration: it decides which
# pool `Location::Danger` draws a dangerous room's people from, so a race
# re-marked in one world would change who is born in the other.
#
# And `Story::Deletion` keeps a universe alive for as long as any story uses it.
# A shared universe would make `rake game:delete` on the fork leave the races
# behind, and on the ORIGINAL leave a universe the captain no longer has a story
# for. A copy costs one row per race and makes both deletions mean what they
# say.
class Story::Fork
  class Refused < StandardError; end

  # How many titles to try before giving up, so a database that somehow holds
  # every name cannot spin. Far past any real number of forks; it exists so the
  # loop has a floor rather than because anybody will reach it.
  MAX_TITLES = 999

  attr_reader :story

  def initialize(story, title: nil)
    @story = story
    @requested_title = title.presence
  end

  # THE WORLD THIS FORK WOULD BE, retitled. The stored snapshot when the story
  # has one; otherwise `Story::Snapshot::Derivation`'s best-effort reading of
  # the records, which is what makes this work on a story generated before
  # snapshots existed.
  def document
    @document ||= source_document.merge(
      "story" => source_document.fetch("story").merge("title" => title)
    )
  end

  # WHERE THE WORLD CAME FROM, in a phrase, for the command to print: a person
  # forking a story has to know whether they are getting what was generated or
  # what could be read back out of the records.
  def source
    snapshot? ? "the snapshot taken when the story was generated" : "a best-effort derivation from the records"
  end

  def snapshot? = stored_document.present?

  # The derivation, or nil when the story carries a real snapshot and there is
  # nothing to derive. `rake game:fork` prints its notes and its manifest.
  def derivation
    return nil if snapshot?

    @derivation ||= Story::Snapshot::Derivation.new(story)
  end

  # Everything standing between this story and a fork, one sentence each, empty
  # when there is nothing. A refusal is reported and the command stops: the
  # brief this was built to is that a derivation which cannot be made with
  # confidence says so rather than guessing.
  def refusals
    return [] if snapshot?

    derivation.refusals
  end

  def refused? = refusals.any?

  # The name the copy gets. Unique when it is answered at all -- see the header.
  def title
    @title ||= begin
      if @requested_title
        taken!(@requested_title) if Story.exists?(title: @requested_title)
        @requested_title
      else
        available_title
      end
    end
  end

  # Writes the fork and returns the new Story. One transaction, which is
  # `WorldSeed::Loader#load!`'s own.
  def create!
    raise Refused, refusals.join(" ") if refused?

    loader = WorldSeed::Loader.new(document, source: "fork of story ##{story.id}")
    begin
      forked = loader.load!
    rescue WorldSeed::Loader::InvalidWorld => e
      # THE DERIVATION PRODUCED A WORLD THAT WILL NOT LOAD, said as a refusal
      # rather than as a stack trace. It is the loader's own sentence, because
      # the loader is the one thing that knows what a world has to be, and
      # nothing here should paraphrase it. `#load!` is one transaction, so
      # nothing was written.
      raise Refused, "the generation-time world read out of these records does not load: #{e.message} " \
                     "Nothing was written, and #{story.title.inspect} is untouched."
    end
    @warnings = loader.warnings + loader.reconciled

    # A snapshot of its own, so the fork can be forked. It is the document that
    # was just loaded rather than a fresh export of what came out of it: the
    # two should be identical, and if they ever are not, the world the fork was
    # asked for is the one the file said.
    Story::Snapshot.capture!(forked, document: document)

    forked
  end

  # What the loader had to say about writing the fork. Empty for a fork into a
  # story that did not exist, which is every fork -- kept because a title
  # collision the check above somehow let through would show up here and
  # nowhere else.
  def warnings = @warnings || []

  private

  def stored_document
    return @stored_document if defined?(@stored_document)

    @stored_document = Story::Snapshot.for(story)
  end

  def source_document
    @source_document ||= stored_document || derivation.document
  end

  def available_title
    1.upto(MAX_TITLES) do |number|
      candidate = "#{story.title} (fork #{number})"
      return candidate unless Story.exists?(title: candidate)
    end

    taken!("#{story.title} (fork N)")
  end

  def taken!(candidate)
    raise Refused, "a story called #{candidate.inspect} already exists, and loading a world over a story that " \
                   "exists REWRITES it rather than making a second one. Pass TITLE= a name nothing answers to."
  end
end
