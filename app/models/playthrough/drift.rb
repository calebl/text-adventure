# ONE TURN ON WHICH THE PLAYER REACHED FOR SOMETHING THE RECORDS DO NOT HAVE.
#
# `Playthrough::Classifier` resolves a move against the room's real exits, a
# talk against the people the records place here, and a take against the items
# lying here -- all closed sets, so the model either names something that
# exists or names nothing. Nothing is the interesting answer: the player typed
# "go through the cellar door" and there is no cellar door. One row is written
# and the turn falls through to narration exactly as before.
#
# WHY THIS IS THE DRIFT COUNTER. Deterministic verification catches the misuse
# of things that exist; it cannot catch the invention of things that do not,
# because you cannot scan prose for a name you were never given. But an
# invented exit has a consequence, and the consequence IS observable: the next
# turn, the player walks at it, and the closed set answers nothing. So this
# measures narration drift BY ITS EFFECTS, at the moment the invention starts
# to matter, for zero tokens and no model call.
#
# It is not proof. A player who types "go north" in a room with named exits
# lands here too, and that is not the narrator's fault. So the row keeps the
# evidence rather than a verdict: what they typed, what was on offer, and
# `scene` -- the narration they had just finished reading, which is where an
# invented exit would have come from. `Story::Audit` reports these against the
# scene that preceded them and counts them separately from contradictions the
# records prove outright.
#
# NOT PRUNED with the conversations (`Playthrough#prune_conversations!`). A
# chat is an audit trail nothing reads back; this is the measurement, and a
# measurement that expires cannot be watched over time.
class Playthrough::Drift < ApplicationRecord
  # The intents that resolve against a closed set, and so the only ones that
  # can come back empty. `examine` and `other` carry no target at all -- they
  # are not reaching for a record, so they cannot miss one.
  #
  # `attack` JOINED THEM IN COMBAT SLICE 8, when it became the seventh word in
  # `Playthrough::IntentSchema::INTENTS`. It resolves against the people
  # standing here -- the same closed set a `talk` reads -- so "hit the ferryman"
  # in a room he is not in is a reach that found nothing, exactly as
  # "talk to the ferryman" is, and it is refused for the same reason
  # (`Playthrough::Refusal`). Before that slice the word reached this class only
  # through the fixed grammar, which refuses an unresolved attack in its own
  # words and builds no `Intent` at all, so no row could ever be written for it.
  #
  # **A BASELINE TAKEN BEFORE SLICE 8 AND ONE TAKEN AFTER ARE NOT THE SAME
  # DENOMINATOR**, and that is the thing to know before reading a movement in
  # this counter or in `Playthrough::Overreach` across it. A shape of line that
  # could not produce a row now can. Re-read both instruments' baselines rather
  # than comparing across the change: `rake game:score` and `Story::Audit`'s
  # `reached_for_nothing` / `named_more_than_one` rates both count these rows.
  ACTIONS = %w[move talk take drop attack].freeze

  belongs_to :playthrough
  belongs_to :scene, optional: true
  belongs_to :location, optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :command, presence: true

  scope :in_story_order, -> { order(:story_timestamp, :id) }
  scope :for_action, ->(action) { where(action: action.to_s) }
  scope :after_scene, ->(scene) { where(scene: scene) }

  # WRITES THE ROW, and never raises into the turn.
  #
  # A drift is a measurement taken alongside a turn the player is waiting on,
  # so it must not be able to fail that turn: a validation this misses, or a
  # playthrough deleted underneath it, would otherwise turn an ordinary
  # unresolved "go north" into a broken game. It logs and returns nil instead.
  def self.record(playthrough:, action:, command:, offered:, scene: nil, location: nil, story_timestamp: nil)
    create!(
      playthrough: playthrough,
      scene: scene,
      location: location,
      action: action.to_s,
      command: command.to_s,
      offered: Array(offered).join(", "),
      story_timestamp: story_timestamp
    )
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn("Playthrough::Drift could not be recorded: #{error.class}: #{error.message}")
    nil
  end

  # How many of each, for a story or across the whole database. The number the
  # whole class exists to produce.
  def self.tally(scope = all)
    scope.group(:action).count
  end

  # Every drift in a story, whichever playthrough it came from. The world is
  # what drifted; who was playing at the time is a detail.
  def self.for_story(story)
    joins(:playthrough).where(playthroughs: { story_id: story.id })
  end

  # What was on the table, as the list it was.
  def offered_names
    offered.to_s.split(",").map(&:strip).reject(&:empty?)
  end

  def nothing_was_offered? = offered_names.empty?
end
