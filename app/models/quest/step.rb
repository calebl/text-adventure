# ONE BEAT OF AN ARC, AND THE TWO STATES IT HAS.
#
#   UNBOUND -- the step names something (`target_name`) that does not exist in
#              the world yet. `target` is nil.
#   BOUND   -- a row with that name exists, `target` points at it, and
#              `bound_at` says when on the story clock that happened.
#
# THAT DISTINCTION IS THE LOAD-BEARING IDEA IN THE WHOLE ARC. The direction
# report wrote a single `trigger_ref` -- *"location / character / item /
# minutes"* -- which assumes the target already exists. In a hand-seeded world it
# does. IN A GENERATED WORLD IT CANNOT: at `rake game:new` there is one room and
# no cast, so an arc written then can only name things. Two columns instead of
# one is what lets the arc be generated at world creation WITHOUT the arc
# creating rows.
#
# WHO BINDS ONE, AND IT IS NEVER THIS CLASS. Binding is a SIDE EFFECT OF
# ADMISSION: the three registries that are already the only writers of their
# kind of row -- `Location::Generator#create_stub!` for a place,
# `Character::Registry#admit!` for a person, `Item::Registry#admit!` for a thing
# -- call `Quest::Binder.bind!` with the row they just wrote, and a step
# waiting for that name takes it. No new writer anywhere, which is what keeps
# the arc from being a second way for rows to come into existence.
#
# A PLACE IS BOUND AS THE PLACE AND READ AS THE ROOM YOU STAND IN. A
# `reach_location` step names a building -- *Blackfang Warren* -- and nobody
# ever stands in a building: once its inside is laid out, every doorway onto it
# lives on its entry room (the captain's Call 5 of 2026-09-07, *a laid-out place
# is never an endpoint*). So `target` holds the row the arc actually named,
# which is what the world was asked for and what the file re-asserts, and
# `#target_room` resolves it through `Location::Interior.way_in` -- the one rule
# in the app for that question, applied at READ time exactly as
# `Location::Generator#connect_exit!` applies it.
#
# RESOLVED LATE AND NOT AT BINDING, which is the whole reason it is a method
# rather than a column. A place is born as a stub with a footprint and its
# inside is laid out later, when somebody first walks in -- so a step bound at
# creation time would have taken the container, and the beat could never have
# fired afterwards. Reading it late means the answer is right before the layout
# and after it, with nothing to migrate in between.
#
# --- what a target may be ---------------------------------------------------
#
# THE POLYMORPHIC COLUMN IS NARROW ON PURPOSE. `trigger_kind` decides what class
# `target` may hold and `#target_class` is the one table for it, so a step
# cannot be bound to a row of the wrong kind by anything that happens to have
# one in hand. `time_passed` has no target at all -- the clock already exists,
# so there is nothing for the world to grow.
#
# --- what is deliberately NOT here ------------------------------------------
#
# NO `reached_at`. A beat is reached by a PLAYER and two players of one world
# reach it at different moments -- `Playthrough::Beat` is the row, on the same
# reasoning `Item`'s layer split is under. A column here would be one player's
# progress stored on the world.
#
# NO PREDICATE. Whether a step is reached is a question about one game, so it is
# `Playthrough::Arc`'s and not this class's. What lives here is what the world
# says the step IS.
class Quest::Step < ApplicationRecord
  # WHAT MAY BE BOUND TO EACH KIND OF TRIGGER. The whole of the polymorphic
  # column's discipline, in one table: `reach_location` takes a `Location` and
  # nothing else, and `time_passed` takes nothing at all.
  TARGET_CLASSES = {
    "reach_location" => "Location",
    "speak_to" => "Character",
    "hold_item" => "Item",
    "time_passed" => nil
  }.freeze

  belongs_to :quest
  belongs_to :target, polymorphic: true, optional: true

  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :quest_id }
  validates :summary, presence: true
  validates :trigger_kind, inclusion: { in: Quest::TRIGGERS }
  # MINUTES IS THE ONE NUMBER A STEP CARRIES, and it is the one kind of trigger
  # that has nothing for the world to grow. Required for `time_passed` and
  # refused for everything else, so a step cannot half-mean two triggers.
  validates :minutes, presence: true, numericality: { only_integer: true, greater_than: 0 },
                      if: :time_passed?
  validates :minutes, absence: true, unless: :time_passed?
  # AND `target_name` IS THE OTHER THREE'S. A step with neither is a step
  # nothing could ever satisfy.
  validates :target_name, presence: true, unless: :time_passed?
  validate :target_is_the_right_kind_of_row

  scope :bound, -> { where.not(target_id: nil) }
  scope :unbound, -> { where(target_id: nil) }

  def bound? = target_id.present?

  def unbound? = !bound?

  def time_passed? = trigger_kind == "time_passed"

  def reach_location? = trigger_kind == "reach_location"

  def speak_to? = trigger_kind == "speak_to"

  def hold_item? = trigger_kind == "hold_item"

  # WHETHER THE WORLD HAS TO GROW SOMETHING FOR THIS STEP AT ALL. False for
  # `time_passed`, which is the only trigger the clock satisfies on its own --
  # so it is also the only kind `Quest::Deadline` never has to place.
  def wants_a_row? = !time_passed?

  def target_class = TARGET_CLASSES[trigger_kind]

  # THE ROW A NAME HAS TO BE, FOR THIS STEP TO TAKE IT. Nil is the ordinary
  # answer for a candidate of the wrong kind, and a `time_passed` step never
  # takes one.
  def takes?(record)
    return false unless wants_a_row? && unbound?
    return false if record.nil? || target_class.nil?
    return false unless record.is_a?(target_class.constantize)

    WorldSeed.natural_key(name_of(record)) == WorldSeed.natural_key(target_name.to_s)
  end

  # WHERE THE PARTY HAS TO BE STANDING FOR THIS STEP, which is a ROOM and never
  # a building -- see the header. Nil for every step that is not about a place.
  #
  # THE ONE READER OF "WHICH ROOM DOES THIS STEP MEAN", so `Playthrough::Arc`'s
  # predicate, `Story::Doctor`'s reachability walk and the read-outs cannot come
  # to three answers. A stub place with no rooms yet is handed straight back,
  # which is correct: the doorway onto it IS the way in, waiting.
  def target_room
    return nil unless reach_location? && target.is_a?(Location)

    Location::Interior.way_in(target)
  end

  # BINDING, WRITTEN ONCE. `at:` is story time, for `Playthrough#end!`'s reason:
  # a world re-derived from a backup must not date its arc to whenever the
  # backup was opened.
  #
  # Idempotent: a step that is already bound keeps the row and the moment it
  # was bound at, so nothing can quietly re-point an arc.
  def bind!(record, at:)
    return self if bound?

    update!(target: record, bound_at: at)
    self
  end

  # LETTING GO OF A ROW THAT WENT AWAY, which is the one honest repair for a
  # bound target somebody deleted: unbind it and let the world grow it again
  # (`Story::Doctor`'s `quest_target_missing`, remedy `safe`). It does NOT
  # forget `target_name`, because that is the arc's own statement of what the
  # world must contain and deleting a row does not retract it.
  def unbind!
    update!(target: nil, bound_at: nil)
    self
  end

  # WHAT THE NARRATOR IS TOLD, and the whole of it: one line, the captain's
  # Call 4 of 2026-09-06. Never the conclusion -- telling a model the ending
  # invites it to write toward an ending the engine has not recorded, which is
  # the railroad by the back door.
  def to_s = summary.to_s

  private

  def name_of(record) = record.is_a?(Character) ? record.fullname : record.name

  def target_is_the_right_kind_of_row
    return if target.nil?

    if target_class.nil?
      errors.add(:target, "is not something a #{trigger_kind} step waits for")
      return
    end

    return if target.is_a?(target_class.constantize)

    errors.add(:target, "must be a #{target_class}, and this is a #{target.class}")
  end
end
