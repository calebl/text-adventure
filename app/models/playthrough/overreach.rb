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
# WHAT THE TURN DOES NOW, AND WHAT THIS COUNT STILL MEANS. The captain's ruling
# of 2026-09-04, in his words: *"If someone tries to do two things or more at a
# time, we should refuse and prompt the player to pick only 1 thing."* So the
# line is refused WHOLE -- the index is not taken either, nothing is written,
# and `Playthrough::Refusal` asks the player to pick one. The row is written
# exactly as before, from exactly the same place
# (`Playthrough::Classifier#record_overreach`), because the ruling changed what
# the turn DOES and not what is measured.
#
# READ `acted` AS WHAT THE LINE RESOLVED TO, then, and not as what was done to
# it. On a refused turn nothing was done to either name; the two columns are the
# pair the line reached for, and which of them the loop would have picked.
#
# STILL NOT A DEFECT, and `Story::Audit` still files it under LIMITS on its own:
# nothing here is wrong. What the count is for is how often people type two acts
# on one line -- a question about how people actually type, which is not
# answerable by opinion -- and it is now also the measure of how often the
# refusal fires.
#
# NOT PRUNED with the conversations (`Playthrough#prune_conversations!`), for
# the same reason drift is not: a measurement that expires cannot be watched
# over time.
class Playthrough::Overreach < ApplicationRecord
  # The intents that resolve against a closed set, and so the only ones that can
  # name two things out of one.
  #
  # NO LONGER THE SAME LIST AS `Playthrough::Drift`'s, and the difference is
  # `examine`. It used to be an alias of it, on the reasoning that `examine` and
  # `other` resolve to no record at all -- true until `ta-item-inscriptions`,
  # after which a look resolves a record out of both item sets at once
  # (`Playthrough::Classifier#build_intent`). So "read the note and the index"
  # names two things the records have and asks for two acts, and since the
  # ruling of 2026-09-04 it is refused like any other such line. Without the
  # value here the row would have failed its own validation and been logged
  # away, so the refusal would have fired uncounted.
  #
  # A LOOK CAN OVERREACH AND IT CANNOT DRIFT, which is why only this list gained
  # it: an `examine` that landed on nothing is not reaching for a record it can
  # miss -- "look at the sky" is a look at the sky -- and it stays narrated. See
  # `Playthrough::Refusal` for the boundary written out.
  #
  # `attack` ARRIVED HERE FOR FREE IN COMBAT SLICE 8, because it arrived in
  # `Playthrough::Drift::ACTIONS` and this list is that one plus `examine`. That
  # is the right answer and not an accident of the derivation: "hit Neb and then
  # Grenn" names two people out of one closed set and asks for two acts, which is
  # the shape this table exists to count, and a value missing here would have
  # failed the row's own validation and logged the refusal away uncounted -- the
  # exact failure `examine` was added to fix.
  #
  # **RE-READ THE BASELINE ACROSS SLICE 8.** A shape of line that could not
  # produce a row before this counter can now; see `Playthrough::Drift::ACTIONS`.
  ACTIONS = (Playthrough::Drift::ACTIONS + %w[examine]).freeze

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
  # broken game. It logs and returns nil -- and since the ruling that means the
  # player still gets their refusal, unmeasured.
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
