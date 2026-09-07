# A STORY KEEPS THE WORLD IT WAS GENERATED WITH, so it can be played again from
# the beginning without being destroyed.
#
# The captain's request, 2026-09-07: *"I want to be able to 'reset' a game to
# it's initial state after generation so I can see how it performs from the
# beginning instead of only after a lot of locations have already been
# generated"* -- and, of the stories already in his database, *"I don't want to
# delete them. I want to be able to run them fresh as if they were new."* Offered
# a rewind of the same story or a fork from a snapshot, he chose the fork: the
# original story, every playthrough and every verdict on a turn stay exactly
# where they are, and `rake game:fork` loads the snapshot as a NEW story beside
# them.
#
#   stories.generation_snapshot   the `WorldSeed::Exporter` document for this
#                                 story as it stood the moment generation
#                                 finished, dumped to the same YAML a seed file
#                                 holds. NULL means no snapshot was taken, which
#                                 is every story generated before this column
#                                 and is what `Story::Snapshot::Derivation`
#                                 exists for.
#
# WHY A COLUMN AND NOT A FILE -- the argument in full is in `Story::Snapshot`'s
# header, which is the class that owns this column. In short: a snapshot has to
# survive `rake game:reseed`, has to be destroyed with its story, and must not be
# a checked-in artifact for a world that exists on one machine. A column is all
# three for free.
#
# NULLABLE, and it stays nullable: a story that predates this column has no
# snapshot and never will have one it did not derive, and `Story::Doctor` has
# nothing to report about that -- an absent snapshot is not a defect, it is a
# story generated before the feature. NO `bin/update` STEP for the same reason.
#
# NO INDEX. Nothing queries by it; it is read off one story row at a time, by id,
# on the one command that forks a story.
class AStoryRemembersHowItWasGenerated < ActiveRecord::Migration[8.1]
  def change
    add_column :stories, :generation_snapshot, :text
  end
end
