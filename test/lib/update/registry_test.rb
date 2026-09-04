require "test_helper"

# THE LIST ITSELF. Every assertion here is a rule stated in `lib/update.rb`'s
# header, pinned so that the next PR to add a step cannot quietly break it --
# which is the whole point of having the list in the repo instead of in a PR
# body.
class Update::RegistryTest < ActiveSupport::TestCase
  test "every step declares a key and a reason, and is a step" do
    Update::REGISTRY.each do |step|
      assert_operator step, :<, Update::Step, "#{step} is in the registry but is not an Update::Step"
      assert_kind_of Symbol, step.key
      assert_predicate step.reason, :present?, "#{step} has no reason, so its output says nothing"
      assert_respond_to step.new, :call
    end
  end

  test "the keys are unique, because they are what ONLY= and the output name" do
    keys = Update::REGISTRY.map(&:key)

    assert_equal keys.uniq, keys
  end

  # NOT A PREFERENCE. `Item::LayerBackfill` reads `Scene#took?`, which needs both
  # columns `Scene::TransitionBackfill` writes, and `scenes.location_id` to know
  # which room to put one of the world's own rows back in; run the other way
  # round, every take in an older database is invisible, every row a player
  # carried off reads as one of the world's own, and the rooms those things came
  # out of stay empty for everybody.
  test "the transitions backfill runs before the item backfill" do
    assert_operator index_of(Update::Steps::BackfillTransitions), :<, index_of(Update::Steps::BackfillItems)
  end

  # `Story::Repair`'s safe remedies act on findings the backfills remove --
  # `protagonist_holds_a_taken_item` is literally one item of the item
  # backfill's work. Repairing first spends the findings and then the backfill
  # reports them again.
  test "every backfill runs before the repairs" do
    backfills = Update::REGISTRY.select { |step| step.key.to_s.start_with?("backfill_") }

    assert_predicate backfills, :any?
    backfills.each do |backfill|
      assert_operator index_of(backfill), :<, index_of(Update::Steps::SafeRepairs)
    end
  end

  test "the doctor is last, and reports rather than writes" do
    assert_equal Update::Steps::Doctor, Update::REGISTRY.last
    assert_predicate Update::Steps::Doctor, :reports_only?
  end

  # THE RULE THE WHOLE COMMAND STANDS ON. `bin/update` runs unattended after a
  # pull, against the captain's primary development database, so a step that
  # spends tokens because he pulled is the one failure that costs real money.
  # The gate exists (`Update::Step.model_calls?`, tested in
  # `Update::RunnerTest`); nothing is allowed through it.
  test "no step in the registry asks for a model call" do
    asking = Update::REGISTRY.select(&:model_calls?)

    assert_empty asking.map(&:key),
                 "a step wants a model call. That gate is opt-in for a reason -- see lib/update.rb's header."
  end

  test "only the doctor reports without writing, so nothing else can hide behind that flag" do
    assert_equal [ Update::Steps::Doctor ], Update::REGISTRY.select(&:reports_only?)
  end

  private

  def index_of(step) = Update::REGISTRY.index(step)
end
