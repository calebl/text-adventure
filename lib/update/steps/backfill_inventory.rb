# PR 111's post-update action: attribute what the protagonist is holding to the
# playthrough whose turn log took it, and give every existing game its own copy
# of the story's starting kit. `Item::InventoryBackfill` is the work and its
# header is the reasoning -- including the one outcome that moves a thing to a
# place no record named, which is stated in the output every time.
#
# IT RUNS AFTER `backfill_transitions` AND THE ORDER IS NOT A PREFERENCE:
# attribution reads `Scene#took?`, which needs both `resolved_action` and
# `acted_on`. Run first, every take in a pre-PR-105 database is invisible and
# every held item reads as unrecoverable -- which is the outcome that puts
# things down on the floor.
#
# IDEMPOTENT, and it is the only step in the registry where that took reading
# rather than assuming. Its candidates are the items the protagonist holds, and
# `starting` LEAVES THEM THERE -- so the same answers come back on every run for
# ever. What makes the second run quiet is `#playthroughs_without`, which
# reports the parties still owed a copy: once each has one, `starting` answers
# with an empty list and writes nothing. So `changed` asks what each answer
# would WRITE, not which answers came back.
class Update::Steps::BackfillInventory < Update::Step
  def self.key = :backfill_inventory
  def self.reason = "put the party's things in the party's hands, not on the story's protagonist row (PR 111)"

  def call
    lines = []
    notes = []
    changed = false

    stories.each do |story|
      answers = Item::InventoryBackfill.new(story).run(dry_run: dry_run)
      wrote = answers.select { |answer| writes?(answer) }
      changed ||= wrote.any?

      wrote.each { |answer| lines << "#{story.title}: #{describe(story, answer)}" }
      answers.select(&:ambiguous?).each do |answer|
        notes << "#{answer.item.name} is left alone: playthrough(s) " \
                 "#{answer.playthroughs.map { |play| "##{play.id}" }.join(" and ")} record taking it at the same " \
                 "moment, and an item is in one place"
      end
    end

    report(changed: changed, lines: lines, notes: notes)
  end

  private

  # WHETHER THIS ANSWER PUTS ANYTHING IN THE DATABASE, which is the same
  # question `Item::InventoryBackfill#apply!` branches on -- read it beside
  # this. `starting` writes only when a party is still owed a copy, and
  # `unrecoverable` only when there is a realized room to put the thing down in.
  def writes?(answer)
    case answer.outcome
    when :attributed then true
    when :starting then answer.playthroughs.any?
    when :unrecoverable then !answer.location.nil?
    else false
    end
  end

  def describe(story, answer)
    case answer.outcome
    when :attributed
      "#{answer.item.name} -> playthrough ##{answer.playthrough.id}, which recorded taking it"
    when :starting
      "#{answer.item.name} is the story's starting kit -- copied into #{answer.playthroughs.size} playthrough(s), " \
      "and left on #{story.protagonist.fullname}"
    when :unrecoverable
      "#{answer.item.name} PUT DOWN in #{answer.location.name}: no turn records taking it and no world file starts " \
      "the player with it, so it is left where the last party that could have held it stands"
    end
  end
end
