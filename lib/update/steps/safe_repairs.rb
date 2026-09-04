# THE HALF OF `rake game:repair` THAT COSTS NOTHING, over every story.
#
# `Story::Repair`'s whole point is the line between a repair that writes a value
# already on record somewhere else and one that asks a model to invent world
# data; `generate: false` is the cheap side of that line and it is what this
# runs. NEVER THE OTHER SIDE. It is passed explicitly rather than left to the
# default so that a reader of this file can see which it is, and
# `Update::RegistryTest` asserts no step in the registry ever asks for a model.
#
# A FAILED REPAIR DOES NOT STOP THE RUN, deliberately, and this is the one place
# the registry's "a failure stops everything" rule is bent. `Story::Repair#apply!`
# already catches per finding, on its own reasoning: a run is over several
# findings and the ones after a failure are still worth attempting. Turning its
# caught failure back into a raise here would also skip the doctor, which is the
# one thing that would have told the captain what state he is now in. So it is
# reported as a line and a note, and the doctor at the end of the run reports
# the finding it failed to fix.
class Update::Steps::SafeRepairs < Update::Step
  def self.key = :safe_repairs
  def self.reason = "fix what is derivable from records already on file -- no model call, ever"

  def call
    lines = []
    notes = []
    changed = false

    stories.each do |story|
      repair = Story::Repair.new(story, generate: false)
      plan = repair.plan

      if plan.any?
        changed = true
        lines.concat(dry_run? ? planned(story, plan) : applied(story, repair, notes))
      end

      notes.concat(by_hand(story, repair))
    end

    report(changed: changed, lines: lines, notes: notes)
  end

  private

  def planned(story, plan)
    plan.map { |finding| "#{story.title}: would fix #{finding.message}" }
  end

  def applied(story, repair, notes)
    repair.apply!.map do |result|
      notes << "#{story.title}: a safe repair FAILED -- run `rake 'game:repair[#{story.id}]'` for the detail" unless result.repaired?
      "#{story.title}: #{result.repaired? ? "ok" : "FAILED"} #{result.message}"
    end
  end

  # What is left that this will not touch: the findings that need a model call
  # (offered, never taken) and the ones with no honest answer at all. Read
  # AFTER `#apply!`, which drops the memoised doctor, so these are the findings
  # that survived the run rather than the ones it started with.
  def by_hand(story, repair)
    repair.deferred.map { |finding| "#{story.title}: #{finding.message} -- needs a model call: GENERATE=1 rake 'game:repair[#{story.id}]'" } +
      repair.manual.map { |finding| "#{story.title}: #{finding.message} -- by hand; nothing can honestly derive this" }
  end
end
