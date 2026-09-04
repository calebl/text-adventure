# WHAT A CHECKOUT HAS TO DO AFTER IT PULLS, WRITTEN DOWN ONCE.
#
# THE PROBLEM THIS EXISTS FOR. A story is written once and then sits in the
# database while features land around it (`AGENTS.md` -> *When a world outlives
# the schema*), so every PR that adds a column also adds a sentence to its own
# body: run this backfill, then that repair, then the doctor. Five of them
# landed in one week (PRs 105, 109, 110, 111, 113) and the captain was left
# reading five PR bodies to work out what his own database still needed. A
# sentence in a merged PR body is not a place a checkout can look things up.
#
# So the list lives HERE, in the repo, in dependency order, and `bin/update`
# runs it. A PR that needs a post-update action adds a step to `REGISTRY`
# instead of a paragraph to its description; the paragraph is gone by the time
# it matters and the step is not.
#
# ADDING A STEP -- the whole of it:
#
#   1. Write `lib/update/steps/<your_step>.rb`, a subclass of `Update::Step`.
#      Three declarations (`key`, `reason`, and `run` returning a Report) and
#      nothing else; `Update::Step`'s header has the contract and
#      `Update::Steps::BackfillWhereabouts` is the shortest example.
#   2. Add the class to `REGISTRY` below, in the position it must run in.
#      Order is the file's order and nothing else infers it.
#   3. Say in the PR body that you did. No hand list.
#
# THE THREE RULES A STEP MUST KEEP, because the whole thing is worthless if a
# captain cannot run it twice:
#
#   IDEMPOTENT     running it on an already-updated database writes nothing and
#                  reports nothing to do. Every backfill in this app already
#                  claims this (they act only on rows with the blank column);
#                  a step that cannot claim it does not belong here.
#   QUIET WHEN IT
#   HAS NOTHING    a step with no work reports one line. A run against an
#                  up-to-date database should be readable in one screen, or the
#                  captain stops reading it, and then it may as well not exist.
#   OFFLINE        no model call, no network, no key. This runs on the captain's
#                  primary development database, unattended, at whatever hour he
#                  pulled -- see `Update::Step.model_calls?` for the gate the
#                  one hypothetical exception has to pass, and note that no step
#                  uses it and none is expected to.
#
# WHAT IS DELIBERATELY NOT HERE: `bin/rails db:migrate` and `bundle install`.
# Those are `bin/update`'s own business and always run; a migration is not a
# step in a list, it is the schema the steps read.
module Update
  # Anything wrong enough to stop the run. `Update::Runner` names the step.
  class StepFailed < StandardError; end

  # THE STEPS, IN THE ORDER THEY RUN. Order is dependency order and it is
  # asserted by `Update::RegistryTest`, not inferred at run time:
  #
  #   transitions before items      `Item::LayerBackfill` reads `Scene#took?`,
  #                                 which needs BOTH `resolved_action` and
  #                                 `acted_on` -- exactly what the transition
  #                                 backfill writes -- and `scenes.location_id`
  #                                 to know which room to put the world's own
  #                                 row back in. Run the other way round, every
  #                                 take is invisible, every row a player
  #                                 carried off reads as one of the world's own,
  #                                 and the rooms stay empty for everybody.
  #   backfills before repairs      `Story::Repair`'s safe remedies act on
  #                                 findings the backfills remove
  #                                 (`protagonist_holds_a_taken_item` and
  #                                 `playthrough_missing_a_copy` are literally
  #                                 two pieces of the item backfill's work).
  #                                 Repairing first spends the findings and then
  #                                 the backfill reports them again.
  #   doctor last                   it reports and never writes, so it is the
  #                                 summary of everything above it.
  REGISTRY = [
    Update::Steps::BackfillTransitions,
    Update::Steps::BackfillWhereabouts,
    Update::Steps::BackfillItems,
    Update::Steps::SafeRepairs,
    Update::Steps::Doctor
  ].freeze
end
