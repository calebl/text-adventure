# WHERE THE STORY IS GOING, AS ROWS -- the arc, its beats and its endings.
#
# THE CAPTAIN'S SENTENCE THIS IS FOR, 2026-09-06: *"My overall next goal is to
# get The Iron Gate Descends to be playable in a reasonable way, both from the
# location generation and the story perspectives."* Story 7's prince existed in
# the preface, in the summary and in four fields of its universe, and in ZERO
# ROWS -- so nothing in the app could ask where he was, and the generator gave
# the deepest room of his dungeon two ways out and both led back up. Nothing
# noticed: the doctor called the story healthy and the sweep asserted nine
# things, none of them about whether the story could reach its own end.
#
# THE WHOLE IDEA IS IN ONE SENTENCE: **the arc states what the world must
# contain; the world's own registries decide when it does.** A step names a
# place, a person or a thing (`Quest::Step#target_name`) and is UNBOUND until a
# row with that name exists, at which point the registry that wrote the row
# binds it. So an arc can be generated at world creation -- when there is one
# room and no cast -- without the arc creating anything, which is the direction
# report's anti-railroad rule kept in substance.
#
# AND IT CHECKS, IT NEVER GATES. Nothing here stops a player going anywhere,
# refuses a line, or writes a `Location`. `Playthrough::Arc` reads records after
# a turn the engine played and writes a beat when one is true. The one thing the
# ENGINE may place is a target the model declined to place, on a deadline, and
# that is `Quest::Deadline` -- the captain's Call 2 of 2026-09-06, taken through
# the ordinary `Location::Generator.create_stub!` path so the room is
# indistinguishable from one a model named.
#
# --- the three tables, and why there are three ------------------------------
#
#   quests            the arc. Belongs to the STORY: two people playing one
#                     world walk the same arc.
#   quest_steps       its beats, in order. `target_name` is the name it waits
#                     for; `target` is the row it resolved to.
#   quest_outcomes    its endings, SEVERAL of them, one marked `is_default`.
#
# WHY OUTCOMES ARE ROWS AND NOT A COLUMN. The direction report decided
# `Story#conclusion`, one sentence, and the captain's note of 2026-09-06
# retired it: *"multiple endings to a quest must be possible."* A world is still
# BORN with one -- `Quest::Generator` writes a default and `#conclusion` reads
# it back, so the decided name survives -- but nothing may assume it is the only
# one. A column beside these rows would be a second record that could disagree
# with them, which is the shape this codebase writes headers to prevent.
#
# AND WHICH BEAT AND WHICH ENDING ONE GAME REACHED IS PER PLAYTHROUGH
# (`Playthrough::Beat`, `Playthrough::Ending`) -- the `Item` layer split applied
# to progress. `quest_steps.reached_at` would be wrong on a two-player world
# exactly the way a shared inventory was.
#
# --- what belongs to the world and what belongs to a game -------------------
#
# NOTHING A PLAYER TYPES MAY WRITE A ROW IN ANY OF THE THREE TABLES.
# `EngineSweep::Invariants#quest_unmoved` asserts it over every walk, and it is
# the same statement `stat_blocks_unmoved` and `cast_unmoved` make: the arc is
# the world's, exactly as a stat block is. A beat is per-game and IS written by
# a walk, which is why it is a different table.
#
# --- status, and why failure is not the opposite of completable -------------
#
# The captain chose *"always completable"* (Call 1, 2026-09-06) AND *"a failed
# quest gets stored as an event"*. Those are not in conflict and the difference
# is which record they are about:
#
#   ALWAYS COMPLETABLE is a property of the WORLD -- the target exists and is
#   reachable from the opening room. `Story::Doctor`'s
#   `quest_target_unreachable` is fatal about it.
#
#   FAILURE is an outcome of the PLAYTHROUGH -- this player died, or ran out of
#   story, before the ending. `Playthrough::Arc` writes it to `world_events`.
#
# `status` is therefore the WORLD's answer and has two values. `open` is every
# arc a generated world is born with. `doomed` is a seed file saying, on
# purpose, that this world does not let you finish -- an AUTHORED tragedy, which
# Call 1 leaves available while refusing an emergent one. There is no `finished`
# status, and that is the point: a quest is finished for a PLAYER
# (`Playthrough::Ending`), never for the world.
class Quest < ApplicationRecord
  # THE FOUR THINGS A BEAT CAN BE, and it is a FIXED TABLE rather than a rule
  # language -- the direction report's §12, *"a general rule language, predicate
  # DSL, or condition evaluator"* is explicitly not being built. Every one of
  # them is something `Playthrough::Turn` already does, so there is no trigger
  # the loop cannot reach and nothing to forbid.
  #
  # The predicates themselves are `Playthrough::Arc`'s, because each of them is
  # a question about ONE GAME and this class is the world's.
  TRIGGERS = %w[reach_location speak_to hold_item time_passed].freeze

  # WHAT THE WORLD SAYS ABOUT ITS OWN ARC. See the header: two values, and
  # neither of them means "somebody finished it".
  STATUSES = %w[open doomed].freeze

  # WHICH PATH WROTE IT. A world file, or `Quest::Generator` at `rake game:new`
  # -- recorded because the two are judged differently: a generated arc's steps
  # are legitimately unbound on a brand-new world and a seeded one's are not,
  # and `Story::Doctor` has to be able to tell them apart without guessing.
  ORIGINS = %w[seeded generated].freeze

  belongs_to :story
  # A SIDE QUEST IS A CHILD, which is the whole of the main-versus-side
  # distinction the direction report asked for. Nothing generates one yet --
  # side quests are DISCOVERED, out of a call that is already happening, and
  # never at world creation when there is one room and no cast.
  belongs_to :parent_quest, class_name: "Quest", optional: true
  has_many :child_quests, class_name: "Quest", foreign_key: :parent_quest_id,
                          dependent: :destroy, inverse_of: :parent_quest
  has_many :steps, -> { order(:position) }, class_name: "Quest::Step",
                   dependent: :destroy, inverse_of: :quest
  has_many :outcomes, -> { order(:id) }, class_name: "Quest::Outcome",
                      dependent: :destroy, inverse_of: :quest

  validates :title, presence: true, uniqueness: { scope: :story_id }
  validates :premise, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :origin, inclusion: { in: ORIGINS }
  validate :parent_belongs_to_the_story
  validate :single_main_arc_per_story

  # THE MAIN ARC. One per story, and `#single_main_arc_per_story` is what makes
  # "the" honest rather than "whichever came back first" -- the defect
  # `Scene#next_scenes` documents, one table over.
  scope :main, -> { where(parent_quest_id: nil) }
  scope :side, -> { where.not(parent_quest_id: nil) }
  scope :open_arcs, -> { where(status: "open") }

  def self.main_arc(story) = story.quests.main.order(:id).first

  def main? = parent_quest_id.nil?

  def doomed? = status == "doomed"

  def generated? = origin == "generated"

  # THE ENDING THE WORLD WAS BORN WITH. Every quest has one -- `Story::Doctor`
  # reports a quest that does not (`quest_without_an_outcome`), because an arc
  # with no outcome is an arc nothing can ever finish, which is the fourth of
  # the captain's five properties.
  #
  # FIRST BY ID AMONG THE DEFAULTS rather than "the default", because nothing in
  # the schema can stop a file marking two: the honest answer to a file that
  # did is the first one and a doctor finding, not a load that raises halfway
  # through a world.
  def default_outcome = outcomes.detect(&:is_default?) || outcomes.first

  # THE SENTENCE THE WORLD WAS BUILT TOWARD -- the direction report's decided
  # `Story#conclusion`, read off the default outcome row rather than out of a
  # column of its own. See the header: the name survives his ruling, the column
  # does not.
  def conclusion = default_outcome&.summary

  # THE NEXT BEAT NOBODY HAS REACHED, IN THIS GAME. It is the one thing the
  # narrator is ever told about the arc (the captain's Call 4 of 2026-09-06:
  # *the next open step's summary only, one line*) and the one thing the
  # generator's prompt block names.
  #
  # PER PLAYTHROUGH AND NOT PER QUEST, for the reason the beat rows are: two
  # players are on different steps of one arc.
  #
  # BY POSITION, and steps may legitimately be reached OUT of order -- so this
  # is the lowest-numbered step this game has not reached rather than the one
  # after the last it did.
  def next_step_for(playthrough)
    reached = Playthrough::Beat.where(playthrough: playthrough, quest_step: steps).pluck(:quest_step_id)

    steps.reject { |step| reached.include?(step.id) }.min_by(&:position)
  end

  # WHETHER THIS GAME HAS WALKED THE WHOLE ARC. Every step reached, which is
  # what makes the ending due -- see `Playthrough::Arc#run!`.
  def finished_by?(playthrough)
    steps.any? && next_step_for(playthrough).nil?
  end

  # THE STEPS THE WORLD HAS NOT GROWN A TARGET FOR YET. Expected on a
  # brand-new generated world and a defect on an old one, which is the
  # difference `Story::Doctor` reads `origin` to tell.
  def unbound_steps = steps.reject(&:bound?)

  private

  def parent_belongs_to_the_story
    return if parent_quest.nil? || story.nil?
    return if parent_quest.story_id == story_id

    errors.add(:parent_quest, "must belong to the same story")
  end

  # ONE MAIN ARC PER STORY. `Quest.main_arc` says "the" main arc and a second
  # one would make that a lie the same way a second opening `Scene` would --
  # see `Scene#single_opening_scene_per_story`, which this is a copy of and
  # deliberately so.
  def single_main_arc_per_story
    return unless main?
    return if story.nil?

    others = Quest.main.where(story_id: story_id)
    others = others.where.not(id: id) if persisted?
    return unless others.exists?

    errors.add(:parent_quest, "is the main arc, and this story already has one")
  end
end
