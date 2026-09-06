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
# THREE THINGS, AND THE ORDER IS THE POINT:
#
#   1. THE PROTAGONIST, because `Scene::Generator#characters_present` reads
#      `Story#protagonist` and the arrival prompt marks them *"the player, the
#      one arriving"*. Written before the room is realized, so the room's own
#      description is written by a model that has been told this world already
#      has that person in it (`Location::Generator#known_names_note`).
#   2. THE OPENING ROOM, realized exactly as every other room is -- cast
#      included. The captain's ruling of 2026-09-05: *"the opening room should
#      not guarantee at least one person. The protagonist can start by
#      themselves."* So the realization keeps the ordinary "sometimes nobody"
#      answer and `#cast` may legitimately come back empty; `rake game:new`'s
#      closing lines say so out loud when it does.
#   3. THE OPENING ARRIVAL, last, so its `## Who Is Here` block carries both --
#      which is the whole reason the order is written down here rather than
#      left to a caller.
#
# WHAT IT COSTS: four model calls -- one `Character::Generator` for the
# protagonist, two for the room (`Location::Generator` asks for the detail and
# then the exits) and one `Scene::Generator` for the arrival. Three of the four
# were already the task's; the protagonist is the new one, and the opening
# room's people ride on the realization call the room was already paying for.
#
# IT IS THE PAID PATH, so nothing in CI runs it against a real model.
# `Story::FirstScreenTest` drives the whole sequence with the agent stubbed,
# which is what makes the order above something a test can hold.
class Story::FirstScreen
  attr_reader :story, :protagonist, :location, :scene

  # `reporter:` is how a caller says "print what you are doing": it is called
  # with a label and the work as a block, which is exactly `Helpers.timed`'s
  # shape in `lib/tasks/game.rake`. Left out, the steps run silently, which is
  # what a test wants.
  def initialize(story, reporter: nil)
    @story = story
    @reporter = reporter || ->(_label, &work) { work.call }
  end

  # The three things, in the one order they work in. Returns self, because
  # every one of them is worth reading afterwards and a caller that only wants
  # the scene can ask for it.
  def build!
    create_protagonist!
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
