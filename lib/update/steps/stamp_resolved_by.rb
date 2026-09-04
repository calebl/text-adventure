# THIS PR'S POST-UPDATE ACTION: say which reader answered the turns already on
# disk.
#
# `scenes.resolved_by` landed with the captain's ruling of 2026-09-04, evening
# -- *"support a slash prefix autocomplete in the text box, and resolve those
# and verb-prefixed lines offline then fallback to the model."* -- narrowed the
# next day to slashed lines alone. Two readers answer lines that one reader used
# to, so every turn now records which one did.
#
# AND EVERY TURN WRITTEN BEFORE IT WAS ANSWERED BY THE CLASSIFIER, because there
# was nothing else in the app that could answer one. That is not a guess in the
# sense `rake game:backfill_transitions` refuses to make -- it is a fact about
# the code that wrote the row, the way `Item::LayerBackfill` reads the checked-in
# world file as authority for a question the turn log cannot answer. So this
# stamps `model` and stops there.
#
# WHAT IT WILL NOT TOUCH, and the guard is one column: a scene with no
# `resolved_action` at all. That is an opening arrival -- world data written
# before anybody played, with no typed line and no reader -- and it keeps nil for
# ever, which is the truth about it. `scenes.typed` is nil there too.
#
# IDEMPOTENT because its candidates are `resolved_by: nil`: a stamped row drops
# out of the set on the next run, and a new turn writes the column itself.
class Update::Steps::StampResolvedBy < Update::Step
  def self.key = :stamp_resolved_by
  def self.reason = "say which reader answered the turns already on disk -- every one of them the classifier (PR 121)"

  def call
    lines = []

    stories.each do |story|
      pending = candidates(story)
      next if pending.none?

      lines << "#{story.title}: #{pending.count} turn#{"s" unless pending.count == 1} stamped `model`"
      pending.update_all(resolved_by: "model") unless dry_run
    end

    report(changed: lines.any?, lines: lines)
  end

  private

  # A turn: something was typed and a reader read it. An opening arrival has no
  # `resolved_action`, so it is not one and is left alone.
  def candidates(story)
    story.scenes.where(resolved_by: nil).where.not(resolved_action: nil)
  end
end
