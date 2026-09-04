# The post-update action for the captain's ruling of 2026-09-04: split what is
# one shared set of items into the world's own rows and each playthrough's own
# copies. `Item::LayerBackfill` is the work and its header is the reasoning --
# including the one outcome that hands a game something it did not have before,
# which is a room another player had emptied.
#
# IT RUNS AFTER `backfill_transitions` AND THE ORDER IS NOT A PREFERENCE:
# attribution reads `Scene#took?`, which needs both `resolved_action` and
# `acted_on`, and it reads `scenes.location_id` to know which room to put the
# world's own row back in. Run first, every take in a pre-PR-105 database is
# invisible, every row a player carried off reads as one of the world's own, and
# the rooms those things came out of stay empty for everybody.
#
# IDEMPOTENT, and this is where it is worth reading rather than assuming. The
# row phase re-derives the same answers on every run -- a row already linked to
# its template answers `template` and writes nothing, and `#put_the_world_s_row_back`
# finds the row it made last time rather than making a second one. The snapshot
# phase is idempotent by construction: `Item::Snapshot` guards per template, so
# a second run copies nothing. So `changed` asks what a run would WRITE, not
# which answers came back.
class Update::Steps::BackfillItems < Update::Step
  def self.key = :backfill_items
  def self.reason = "give every playthrough its own copy of the world's things, and put the world's own rows back"

  def call
    lines = []
    notes = []
    changed = false

    stories.each do |story|
      result = Item::LayerBackfill.new(story).run(dry_run: dry_run)

      attributed = result.answers.select(&:attributed?).select(&:writes?)
      snapshots = result.snapshots.reject { |snapshot| snapshot.copies.empty? }
      changed ||= attributed.any? || snapshots.any?

      attributed.each { |answer| lines << "#{story.title}: #{describe(answer)}" }
      snapshots.each { |snapshot| lines << "#{story.title}: #{describe_snapshot(snapshot)}" }

      result.answers.select(&:ambiguous?).each do |answer|
        notes << "#{answer.item.name} is left alone: playthrough(s) " \
                 "#{answer.playthroughs.map { |play| "##{play.id}" }.join(" and ")} record taking it at the same " \
                 "moment, and an item was in one place"
      end
      result.answers.select(&:unrecoverable?).each do |answer|
        notes << "#{answer.item.name} stays where it is in playthrough ##{answer.item.playthrough_id}'s game: " \
                 "nothing on record says which of the world's rows it is a copy of, and taking a thing out of " \
                 "somebody's hands to tidy the records is the one destructive thing this could do"
      end
    end

    report(changed: changed, lines: lines, notes: notes)
  end

  private

  def describe(answer)
    where = answer.location ? ", and the world's own row goes back to #{answer.location.name}" : ""
    "#{answer.item.name} -> playthrough ##{answer.playthrough.id}'s own copy#{where}"
  end

  def describe_snapshot(snapshot)
    "playthrough ##{snapshot.playthrough.id} takes its own copy of #{snapshot.copies.size} thing(s) across " \
    "#{snapshot.rooms.size} room(s) it has been in: #{snapshot.copies.map(&:name).join(", ")}"
  end
end
