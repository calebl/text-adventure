# HOW THE FROZEN CORPUS GROWS: THE CAPTAIN'S VERDICTS, LIFTED OUT OF HIS
# DATABASE AND WRITTEN DOWN WITH THE RECORDS AROUND THEM.
#
# `rake game:corpus` is this class. `Story::Scoreboard::Corpus` reads the file;
# this writes it, and it is the only thing that may.
#
# WHY IT EXISTS. The corpus was captured once, by hand, and the captain asked
# the obvious question of it on 2026-09-07: *"is there a way to update the
# evaluation corpus based on my feedback?"* There was not. He had gone on
# playing and gone on judging turns, and every verdict after the capture stayed
# on one machine where nothing can regression-test it. A corpus that cannot be
# refreshed measures the week it was taken in.
#
# WHAT IT TAKES, and it is narrower than the original hand capture on purpose.
# That capture took every stored `Scene` and `Interaction` from the two played
# worlds; this takes EVERY JUDGED TURN AND THE TURNS EITHER SIDE OF IT, walked
# along the playthrough's own `previous_scene` chain. The verdicts are what the
# corpus is for -- they are the only ground truth in this project -- and the
# neighbours are what stop it being all defect: a check has to tell the flagged
# turn from the one before it, not from the corpus having nothing clean in it.
# Taking whole worlds instead would grow the file with turns nobody has
# judged and slow every run of the pinned test for no measurement.
#
# THE HELD-OUT WORLD IS NOT CAPTURED. `Eval::HELD_OUT` is prose no check has
# ever seen, and `EVALUATION.md` states the rule this obeys: *do not add a
# held-out passage to a fixture.* Verdicts recorded on it are counted in the
# summary and skipped, so the exclusion is visible in the output rather than
# silent. If the held-out world is ever retired, this is the line to delete.
#
# THE FACTS BESIDE EACH PASSAGE COME FROM THE RECORDS AND NEVER FROM THE PROSE
# -- `Story::Audit#facts_for`, which is the checks' own readers. Nothing here
# reads a passage to work out where the player was or who was standing there;
# that would be the narrator grading its own homework, which the standing
# constraint in `AGENTS.md` forbids.
#
# WHAT A MERGE DOES, because this file is edited by hand as well as written:
#
#   a row already there   ONLY its verdict and its note are overwritten. He
#                         amends a judgement and the corpus must follow; the
#                         passage and the facts beside it are what was frozen
#                         and they stay frozen. This is narrower than it first
#                         looks reasonable to be, and the reason is measured:
#                         `Story::Audit#cast_recorded_by` answers "who was in
#                         the room" for a turn played before the snapshot
#                         existed by scanning the story, so a row's `present`
#                         can change because the captain played the SAME WORLD
#                         AGAIN in a different playthrough -- nothing about the
#                         captured turn changed at all. A regression line that
#                         moves for that reason is not one. A re-derivation that
#                         disagrees with a captured row is REPORTED by
#                         `rake game:corpus` and written by nobody but a person.
#   `expect`              NEVER WRITTEN by this task. It is the hand-signed
#                         list of flags a person read and defended, and a
#                         capture that filled it in would turn
#                         `Story::Scoreboard::CorpusTest` into a test that
#                         agrees with whatever the checks currently do. A new
#                         row arrives with `expect` empty, so the pinned test
#                         FAILS until somebody reads the flags it earned.
#   a row not there       appended, at the end, so the diff of a refresh is an
#                         append and the existing order never churns.
#   a row nothing         left exactly where it is. Nothing is ever removed:
#   captured              the corpus is a regression line, and a line that
#                         drops passages when a database changes is not one.
#   the `lab/` rows       untouchable, and they are why removal is not merely
#                         unwise. They come from `narration_corpus.json`, not
#                         from any database, and they are the hardest negative
#                         case the project has -- see the corpus header.
#
# IDENTITY IS THE SCENE, NOT THE LABEL. A row is matched on (story title, scene
# id, interaction id) so that renaming the label convention could never
# duplicate a passage, and a matched row KEEPS THE LABEL IT WAS CHECKED IN
# WITH, because `Story::Scoreboard::CorpusTest` and every baseline pin labels.
class Story::Scoreboard::Capture
  # THE STORY HALF OF A LABEL: the title's first word that is not an article,
  # downcased. `The Unrecorded Hour` is `unrecorded` and `The Lunar
  # Cartographer` is `lunar`, which is the convention the hand capture used and
  # this reproduces exactly -- a slug rule that renamed the rows already in the
  # file would look like 68 new passages.
  #
  # Two worlds whose titles start with the same word would collide, so a
  # collision takes the story id as well. Nothing on this machine collides
  # today; the branch is here because a corpus with two different passages
  # under one label is unreadable and undebuggable.
  ARTICLES = %w[the a an].freeze

  # A CAPTURED PASSAGE AND WHAT BECAME OF IT, for the task to print. `kind` is
  # `:added` or `:updated`; an unchanged row is neither and is not reported, so
  # a second run of an unchanged database prints nothing to do.
  Change = Data.define(:label, :kind, :verdict, :was)

  # A CAPTURED ROW THE RECORDS NO LONGER AGREE WITH, field by field. Reported
  # and never written -- see the header for the one way this happens today.
  Drift = Data.define(:label, :field, :captured, :now)

  Result = Data.define(:rows, :changes, :drifts, :labelled, :verdict_tally, :held_out_verdicts) do
    def added = changes.select { |change| change.kind == :added }
    def updated = changes.select { |change| change.kind == :updated }
    def changed? = changes.any?
  end

  attr_reader :path, :scope

  def initialize(path: Story::Scoreboard::Corpus::PATH, scope: Story.all)
    @path = path
    @scope = scope
  end

  def file = Rails.root.join(path)

  # Reads the database, merges into the file, and writes it unless asked not
  # to. The returned `Result` carries the merged rows either way, so `DRY_RUN=1`
  # reports exactly what a write would have done.
  def run(dry_run: false)
    result = merge

    File.write(file, "#{JSON.pretty_generate(result.rows)}\n") unless dry_run

    result
  end

  private

  def merge
    rows = existing.dup
    index = rows.each_with_index.to_h { |row, position| [ identity_of(row), position ] }
    changes = []
    drifts = []

    captured.each do |capture|
      position = index[capture.fetch("identity")]
      row = capture.except("identity")

      if position
        was = rows[position]
        drifts.concat(drifts_between(was, row))
        merged = was.merge("verdict" => row["verdict"], "note" => row["note"])
        next if merged == was

        rows[position] = merged
        changes << Change.new(label: was.fetch("label"), kind: :updated,
                              verdict: merged["verdict"], was: was["verdict"])
      else
        index[capture.fetch("identity")] = rows.size
        rows << row
        changes << Change.new(label: row.fetch("label"), kind: :added, verdict: row["verdict"], was: nil)
      end
    end

    Result.new(rows: rows, changes: changes, drifts: drifts,
               labelled: rows.count { |row| row["verdict"].present? },
               verdict_tally: rows.filter_map { |row| row["verdict"] }.tally,
               held_out_verdicts: held_out_verdicts)
  end

  # The passage and the facts, never the label, the verdict, the note or
  # `expect`: the first two belong to the records and the rest belong to the
  # file.
  FROZEN = %w[id story room typed protagonist moved still_run present text].freeze

  def drifts_between(was, row)
    FROZEN.filter_map do |field|
      next if was[field] == row[field]

      Drift.new(label: was.fetch("label"), field: field, captured: was[field], now: row[field])
    end
  end

  def existing
    return [] unless File.exist?(file)

    JSON.parse(File.read(file))
  end

  # A ROW IS THE SCENE IT WAS COPIED FROM. Anything whose label this cannot
  # read -- the `lab/` narrations, which came from no database at all -- is its
  # own identity and can therefore never be matched, updated or displaced by a
  # capture.
  def identity_of(row)
    match = row["label"].to_s.match(%r{\A[^/]+/scene-(\d+)(?:/action-(\d+))?\z})
    return row["label"] unless match

    [ row["story"], match[1].to_i, match[2]&.to_i ]
  end

  # Every passage this database offers, oldest story first and in chain order
  # inside each playthrough, so an appended block reads in the order it was
  # played.
  def captured
    @captured ||= judged_windows.flat_map { |story, scene| rows_for(story, scene) }.uniq { |row| row["identity"] }
  end

  # THE JUDGED TURNS AND THEIR NEIGHBOURS, as `[story, scene]` pairs.
  #
  # The window is walked on `Playthrough#scene_chain` rather than on story
  # time: story time interleaves every playthrough of a world, so "the turn
  # before" read off the clock can be a turn this player never saw.
  def judged_windows
    feedbacks.flat_map do |feedback|
      chain = chain_for(feedback.playthrough)
      at = chain.index { |scene| scene.id == feedback.scene_id }
      next [] if at.nil?

      chain[[ at - 1, 0 ].max..at + 1].map { |scene| [ feedback.playthrough.story, scene ] }
    end
  end

  def feedbacks
    @feedbacks ||= Playthrough::Feedback
                   .joins(playthrough: :story)
                   .where(playthroughs: { story_id: capturable_stories.map(&:id) })
                   .includes(:scene, playthrough: :story)
                   .in_story_order
                   .to_a
  end

  def stories = @stories ||= scope.order(:created_at, :id).to_a

  def capturable_stories
    @capturable_stories ||= stories.reject { |story| Eval.held_out?(story.title) }
  end

  # HOW MANY OF HIS VERDICTS THIS RUN THREW AWAY because they were recorded on
  # the held-out world. Printed rather than left implicit: an exclusion that
  # shrinks a corpus without saying so is the same failure `Story::Scoreboard`
  # prints `excluded` to avoid.
  def held_out_verdicts
    @held_out_verdicts ||= Playthrough::Feedback
                           .joins(:playthrough)
                           .where(playthroughs: { story_id: (stories - capturable_stories).map(&:id) })
                           .count
  end

  def chain_for(playthrough) = (@chains ||= {})[playthrough.id] ||= playthrough.scene_chain

  # One scene becomes a passage for its own narration and one more for every
  # `Interaction` written on it -- a character's reaction is prose the player
  # read too, and the hand capture carried them for that reason.
  def rows_for(story, scene)
    audit = audit_for(story)
    facts = audit.facts_for(scene)
    rows = []

    rows << scene_row(story, scene, facts) if scene.description.present?
    scene.interactions.order(:id).each do |interaction|
      rows << interaction_row(story, scene, interaction) if interaction.action.present?
    end
    rows
  end

  def scene_row(story, scene, facts)
    {
      "identity" => [ story.title, scene.id, nil ],
      "label" => "#{slug_for(story)}/scene-#{scene.id}",
      "id" => scene.id,
      "story" => story.title,
      "room" => scene.location&.name,
      "typed" => scene.typed,
      "protagonist" => facts.protagonist,
      "moved" => facts.moved,
      "still_run" => facts.still_run,
      "present" => facts.present,
      "verdict" => verdicts[scene.id]&.verdict,
      "note" => verdicts[scene.id]&.note,
      "text" => scene.description,
      "expect" => []
    }
  end

  # AN INTERACTION DECLARES NO PROTAGONIST AND HAS NO TURN BEFORE IT, and that
  # is a fact about the passage rather than a gap in the capture: it is a
  # character's own line, so there is nobody it could write in the third person
  # and no move it could contradict. `Story::Scoreboard::Corpus#judgeable_for`
  # reads exactly these nils and drops the row out of two denominators.
  def interaction_row(story, scene, interaction)
    {
      "identity" => [ story.title, scene.id, interaction.id ],
      "label" => "#{slug_for(story)}/scene-#{scene.id}/action-#{interaction.id}",
      "id" => scene.id,
      "story" => story.title,
      "room" => scene.location&.name,
      "typed" => scene.typed,
      "protagonist" => nil,
      "moved" => nil,
      "still_run" => 0,
      "present" => [],
      "verdict" => nil,
      "note" => nil,
      "text" => interaction.action,
      "expect" => []
    }
  end

  # THE VERDICT ON A SCENE, and a scene can carry more than one: a verdict is
  # per (playthrough, scene), and a world's opening arrival is shared by every
  # playthrough of it. The oldest wins, deterministically, because the corpus
  # holds one passage per scene and picking by anything less stable would
  # rewrite the file on a re-run.
  def verdicts
    @verdicts ||= feedbacks.sort_by(&:id).reverse.index_by(&:scene_id)
  end

  def audit_for(story) = (@audits ||= {})[story.id] ||= Story::Audit.new(story)

  def slug_for(story) = slugs.fetch(story.id)

  # Worked out for every story at once, in a fixed order, so which of two
  # colliding titles keeps the bare word does not depend on which was judged
  # first.
  def slugs
    @slugs ||= capturable_stories.each_with_object({}) do |story, taken|
      words = story.title.to_s.downcase.scan(/[a-z0-9]+/)
      head = words.find { |word| !ARTICLES.include?(word) } || "story"

      taken[story.id] = taken.value?(head) ? "#{head}-#{story.id}" : head
    end
  end
end
