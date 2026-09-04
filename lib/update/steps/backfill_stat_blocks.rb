# THE POST-UPDATE ACTION FOR `ta-character-stats`: roll a body for everybody who
# was written before `characters.level` and `characters.hit_die` existed.
# `Character::StatBackfill` is the work and its header is the reasoning --
# including why this is the one backfill in the app that decides rather than
# recovers.
#
# IDEMPOTENT because its candidates are the rows with no stat block: a person it
# rolls for drops out of the set on the next run, and it never touches somebody
# who already has one. There are no refusals to report, so it has no notes: a
# roll cannot be ambiguous.
#
# OFFLINE: `Roll` is integer arithmetic. No model call, no key, no network.
#
# IT RUNS BEFORE THE REPAIRS, like every other backfill, and for the same
# reason: `Story::Repair`'s `character_without_a_stat_block` and
# `protagonist_without_vitals` both act on findings this removes, so repairing
# first spends the findings and then this reports them again.
class Update::Steps::BackfillStatBlocks < Update::Step
  def self.key = :backfill_stat_blocks
  def self.reason = "give the world's people a body, so the engine has numbers to work from (ta-character-stats)"

  def call
    lines = []

    stories.each do |story|
      answers = Character::StatBackfill.new(story).run(dry_run: dry_run)
      lines << "#{story.title}: #{summarise(answers)}" if answers.any?
    end

    report(changed: lines.any?, lines: lines)
  end

  private

  # The first few by name and a count for the rest: a story with thirty
  # characters is one line, not thirty.
  def summarise(answers)
    shown = answers.first(3).map(&:to_s).join("; ")

    "rolled #{answers.size} stat block#{"s" unless answers.one?} -- #{shown}#{"; ..." if answers.size > 3}"
  end
end
