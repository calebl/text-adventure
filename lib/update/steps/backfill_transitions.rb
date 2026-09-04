# PR 105's post-update action: label the turns played before the columns that
# say what a turn did existed. `Scene::TransitionBackfill` is the whole of the
# work and its header is the reasoning; this is the registry's entry for it.
#
# IDEMPOTENT because `TransitionBackfill#unlabelled` selects on
# `resolved_action: nil`, and both outcomes that write set it -- `drifted`
# writes the action with a nil record, which IS what that turn was. Only
# `unrecoverable` writes nothing, and it writes nothing for ever: there is no
# stored answer to read, so it is reported as a note rather than counted as
# work still pending.
class Update::Steps::BackfillTransitions < Update::Step
  def self.key = :backfill_transitions
  def self.reason = "say what each old turn DID, from the classifier's own stored answer (PR 105)"

  def call
    lines = []
    total = Hash.new(0)

    stories.each do |story|
      counts = Scene::TransitionBackfill.new(story).run(dry_run: dry_run)
      counts.each { |outcome, count| total[outcome] += count }
      written = counts[:labelled] + counts[:drifted]
      next if written.zero?

      lines << format("%s: %d turn(s) labelled with an action and its record, %d recorded as drift",
                      story.title, counts[:labelled], counts[:drifted])
    end

    report(changed: (total[:labelled] + total[:drifted]).positive?, lines: lines, notes: notes_for(total))
  end

  private

  def notes_for(total)
    return [] if total[:unrecoverable].zero?

    [ "#{total[:unrecoverable]} turn(s) left blank: no stored classifier answer, or it named something " \
      "these records no longer have. A blank column is honest; a guess is not." ]
  end
end
