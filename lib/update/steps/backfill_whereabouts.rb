# PR 109's post-update action: place the people a world had before
# `characters.location_id` existed, out of the cast of the last arrival that
# recorded them. `Character::WhereaboutsBackfill` is the work and its header is
# the reasoning.
#
# IDEMPOTENT because its candidates are `characters.nowhere` and only `placed`
# writes: somebody placed drops out of the set on the next run, and the two
# refusals stay nowhere for ever by design. So `changed` counts placements
# alone -- an ambiguous character is a permanent fact about the data (two rooms
# claimed them at one moment), not a job still to do.
class Update::Steps::BackfillWhereabouts < Update::Step
  def self.key = :backfill_whereabouts
  def self.reason = "put the world's people back in their rooms, from the arrival casts on disk (PR 109)"

  def call
    lines = []
    notes = []

    stories.each do |story|
      answers = Character::WhereaboutsBackfill.new(story).run(dry_run: dry_run)
      placed = answers.select(&:placed?)
      lines << "#{story.title}: #{summarise(placed)}" if placed.any?

      answers.select(&:ambiguous?).each do |answer|
        notes << "#{answer.character.fullname} is left nowhere: #{answer.rooms.join(" and ")} both recorded them " \
                 "at the same moment, and a person cannot be in two rooms"
      end
    end

    report(changed: lines.any?, lines: lines, notes: notes)
  end

  private

  def summarise(placed)
    placed.map { |answer| "#{answer.character.fullname} -> #{answer.location.name}" }.join(", ")
  end
end
