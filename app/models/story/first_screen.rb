# EVERYTHING A GENERATED WORLD NEEDS BEFORE ANYBODY CAN PLAY IT, in the one
# order they have to happen in. `rake game:new` runs this the moment the
# universe and the story are saved, and it is the whole of what the task does
# between persisting the pair and printing them out.
#
# THE CAPTAIN'S RULING, 2026-09-05: *"the generation task should create the
# protagonist along with any characters that are in the opening scene."*
#
# WHAT WAS WRONG. `rake game:new` made no characters at all -- not one, and
# nothing anywhere set `is_protagonist`. It generated a universe, a story, the
# opening room and the opening arrival, and stopped, so a generated world was
# played by NOBODY: the arrival was narrated with an empty cast and the
# playthrough opened with `character_id` nil. `Story #7 (The Iron Gate
# Descends)` is the one that made this a task, with two turns that narrated
# picking things up that were never picked up. The rake task said so itself in
# a comment above the arrival and treated it as the seed file's problem to fix.
# It is not: a seed file is how a world is EDITED, not the only way to get a
# cast.
#
# FOUR THINGS, AND THE ORDER IS THE POINT:
#
#   1. THE PROTAGONIST, because `Scene::Generator#characters_present` reads
#      `Story#protagonist` and the arrival prompt marks them *"the player, the
#      one arriving"*. Written before the room is realized, so the room's own
#      description is written by a model that has been told this world already
#      has that person in it (`Location::Generator#known_names_note`).
#   2. THE ARC, which says where the story is GOING -- `Quest::Generator`, one
#      call, the captain's Call 3 of 2026-09-06. It creates no rows but its own:
#      every beat names a place, a person or a thing and every target is NULL,
#      because the arc states what the world must contain and the registries
#      decide when it does.
#   3. THE OPENING ROOM, realized exactly as every other room is -- cast
#      included. The captain's ruling of 2026-09-05: *"the opening room should
#      not guarantee at least one person. The protagonist can start by
#      themselves."* So the realization keeps the ordinary "sometimes nobody"
#      answer and `#cast` may legitimately come back empty; `rake game:new`'s
#      closing lines say so out loud when it does.
#   4. THE OPENING ARRIVAL, last, so its `## Who Is Here` block carries both --
#      which is the whole reason the order is written down here rather than
#      left to a caller.
#
# WHY THE ARC IS SECOND AND NOT LAST, which is the one ordering decision this
# slice added and the one worth defending. The opening room is the first thing
# any generated world realizes, and it is the only room every player of that
# world starts in -- so it is the room it costs most to have written without
# knowing where the story is going. An arc written after it would have missed
# exactly that one. Nothing downstream depends on the ORDER of steps 1 and 2;
# what depends on it is step 3.
#
# AND IT IS THE ONE STEP OF THE FOUR A WORLD CAN BE BORN WITHOUT. The other
# three raise: a world with no protagonist, no room or no arrival is not a world
# anybody can play. `Quest::Generator#generate!` answers nil on a failed call
# and this carries on, because a world with no arc is exactly what every world
# in this repository was before the arc existed -- playable, exportable, and
# reported by `rake game:doctor` (`story_without_a_conclusion`) rather than
# broken.
#
# WHAT IT COSTS: FIVE model calls -- one `Character::Generator` for the
# protagonist, one `Quest::Generator` for the arc, two for the room
# (`Location::Generator` asks for the detail and then the exits) and one
# `Scene::Generator` for the arrival. The opening room's people ride on the
# realization call the room was already paying for, and the arc costs nothing
# per room and nothing per turn -- its beats are record predicates.
#
# IT IS THE PAID PATH, so nothing in CI runs it against a real model.
# `Story::FirstScreenTest` drives the whole sequence with the agent stubbed,
# which is what makes the order above something a test can hold.
class Story::FirstScreen
  attr_reader :story, :protagonist, :quest, :location, :scene

  # `reporter:` is how a caller says "print what you are doing": it is called
  # with a label and the work as a block, which is exactly `Helpers.timed`'s
  # shape in `lib/tasks/game.rake`. Left out, the steps run silently, which is
  # what a test wants.
  def initialize(story, reporter: nil)
    @story = story
    @reporter = reporter || ->(_label, &work) { work.call }
  end

  # The four things, in the one order they work in. Returns self, because
  # every one of them is worth reading afterwards and a caller that only wants
  # the scene can ask for it.
  def build!
    create_protagonist!
    write_the_arc!
    realize_opening!
    narrate_opening!

    self
  end

  # WHO IS STANDING IN THE OPENING ROOM, out of the records and never out of
  # what a call answered -- `Character::Registry` is what decides which of the
  # proposed people were actually written, so reading its answer back is the
  # only honest way to say who is there. IT MAY BE EMPTY, on the ruling in the
  # header, and the caller is expected to say so rather than to fix it.
  #
  # The protagonist is NOT in it and must not be: the party is derived from
  # where the playthrough is (`Character#location`'s note), so a generated
  # protagonist is nowhere exactly as all three seeded ones are.
  def cast
    return [] if location.nil?

    Character.present_in(location).to_a
  end

  private

  # THE PLAYER, and `Character::Generator` was always meant to be how a
  # generated world gets one -- its own comment says *"`rake game:new` builds
  # the protagonist with it"*. Nothing called it, and nothing anywhere set
  # `is_protagonist`, so the comment described an intention rather than a code
  # path. This is the code path.
  #
  # The body is call C1's rather than a generated person's: level 3 on a d8,
  # 18 hit points, the same numbers the three seed files hand-write. See
  # `Character::StatBlock.for_a_protagonist`.
  def create_protagonist!
    @protagonist = step("Generating the protagonist") { story.create_character(protagonist: true) }
  end

  # WHERE THE STORY IS GOING, as records -- and nil is a legal answer. See the
  # header: this is the one step of the four whose failure leaves a world that
  # still works.
  def write_the_arc!
    @quest = step("Generating the story's arc") { Quest::Generator.new(story).generate! }
  end

  def realize_opening!
    @location = step("Generating opening location") { Location::Generator.opening(story) }
  end

  def narrate_opening!
    @scene = step("Narrating the opening arrival") { Scene::Generator.opening(story) }
  end

  def step(label, &work)
    @reporter.call(label, &work)
  end
end
