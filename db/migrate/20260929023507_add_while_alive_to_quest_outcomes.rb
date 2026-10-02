# THE TWO NUMBERS `while_alive` TAKES: which beat of the arc, and whose life.
# `Quest::Outcome::CONDITIONS` has the rule and `Playthrough::Arc#satisfies?`
# reads it; what belongs here is why the columns have the shape they have.
#
# `step_position` IS A POSITION AND NOT A STEP ID, because a position is what a
# world file says (`beat: 3`) and what `WorldSeed::Loader` re-asserts a step
# under -- and a foreign key onto `quest_steps` would refuse the loader
# trimming a step an ending still named, halfway through a load.
#
# `character_id` IS THE WORLD'S ROW, the person a seed file names by
# `fullname` (`alive: Marek Sollen`). Whether they are alive is one game's
# question and is read off that game's own blows and tolls, never off this
# column. NO FOREIGN KEY, for `quest_steps.target_id`'s reason: the story's
# characters and its quests go in one `Story#destroy!`, and the order Rails
# destroys them in is not a constraint this column should add.
#
# NULL ON EVERY ROW THAT EXISTS, AND NOTHING IS BACKFILLED: no ending written
# before today takes either number, and a new parameter ships inert. The one
# world that means this rule says so in its own file, and `bin/update`
# re-seeds a world file that moved (`Update::SeedFiles`).
class AddWhileAliveToQuestOutcomes < ActiveRecord::Migration[8.1]
  def change
    add_column :quest_outcomes, :step_position, :integer
    add_reference :quest_outcomes, :character, foreign_key: false
  end
end
