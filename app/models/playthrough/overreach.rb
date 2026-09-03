# ONE TURN ON WHICH THE PLAYER ASKED FOR MORE THAN A TURN CAN DO.
#
# "pickup the index and the apron" names two things the records really have,
# and a turn is one act: `Playthrough::Turn#play` branches once, writes once
# and narrates once. So the index was taken and the apron was not -- and until
# this table existed, the second half of that sentence left no trace anywhere.
# No write, no refusal, and no `Playthrough::Drift` row either.
#
# WHY IT IS NOT A DRIFT. Drift is a reach that found NOTHING: the player named
# a cellar door that does not exist, so the closed set answered nothing and the
# invention became observable. This is the opposite shape -- everything named
# exists, and the limit is the loop's rather than the world's. Adding the two
# together would produce a number that is neither, so nothing does.
#
# WHY IT IS NOT A DEFECT EITHER, and `Story::Audit` files it under LIMITS on
# its own for that reason: nothing here is wrong. The turn did what it could
# and `Playthrough::Mechanics` says out loud what it left. What the count is
# for is deciding whether one act per line is a limit worth lifting -- see the
# ROADMAP -- and that is a question about how people actually type, which is
# not answerable by opinion.
#
# NOT PRUNED with the conversations (`Playthrough#prune_conversations!`), for
# the same reason drift is not: a measurement that expires cannot be watched
# over time.
class Playthrough::Overreach < ApplicationRecord
  # The intents that resolve against a closed set, and so the only ones that
  # can name two things out of one. The same four as `Playthrough::Drift`, and
  # the same reason: `examine` and `other` resolve to no record at all.
  ACTIONS = Playthrough::Drift::ACTIONS

  belongs_to :playthrough
  belongs_to :scene, optional: true
  belongs_to :location, optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :command, presence: true
  validates :acted, presence: true
  validates :unacted, presence: true

  scope :in_story_order, -> { order(:story_timestamp, :id) }
  scope :for_action, ->(action) { where(action: action.to_s) }

  # WRITES THE ROW, and never raises into the turn -- same guarantee as
  # `Playthrough::Drift.record` and for the same reason. This is a measurement
  # taken alongside a turn the player is waiting on, so a validation it misses
  # must not be able to turn an ordinary "take the index and the apron" into a
  # broken game. It logs and returns nil.
  def self.record(playthrough:, action:, command:, acted:, unacted:, scene: nil, location: nil, story_timestamp: nil)
    create!(
      playthrough: playthrough,
      scene: scene,
      location: location,
      action: action.to_s,
      command: command.to_s,
      acted: acted.to_s,
      unacted: unacted.to_s,
      story_timestamp: story_timestamp
    )
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn("Playthrough::Overreach could not be recorded: #{error.class}: #{error.message}")
    nil
  end

  # How many of each, for a story or across the whole database.
  def self.tally(scope = all)
    scope.group(:action).count
  end

  # Every one in a story, whichever playthrough it came from. The world is what
  # was played; who was playing is a detail.
  def self.for_story(story)
    joins(:playthrough).where(playthroughs: { story_id: story.id })
  end
end
