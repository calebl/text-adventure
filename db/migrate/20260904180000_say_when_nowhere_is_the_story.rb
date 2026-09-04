class SayWhenNowhereIsTheStory < ActiveRecord::Migration[8.1]
  # NOWHERE ON PURPOSE, told apart from nowhere by accident.
  #
  # `characters.location_id` is nullable because nowhere is a real state, and
  # `rake game:doctor` reports every character in it: a person
  # `Character.present_in` never offers is a person nobody can speak to in any
  # room, which is the defect the column was added for. But one of the three
  # checked-in worlds MEANS it. `the-unrecorded-hour.yml` gives Perrin Lasco no
  # `location` because the premise of that world is that he has been removed
  # from it, and the doctor reported him on every single run -- a warning about
  # the story working exactly as written, which is the kind of warning that
  # teaches a person to stop reading warnings.
  #
  # So the file gets a word for it (`characters[].absent: true`) and the record
  # gets this column. NOT DERIVED FROM THE FILE AT RUN TIME: only three stories
  # in the database have a checked-in file at all, and a doctor that answered
  # "is this deliberate" by reading YAML would have no answer for a generated
  # world and would be reading the disk on every finding. The marker is a fact
  # about the person, so it lives on the person.
  #
  # `null: false, default: false` because the honest default is the one every
  # existing row deserves: an unmarked nowhere character is exactly the
  # accidental case the doctor should keep reporting. `rake game:repair` writes
  # the marker for a seeded world whose file already says `absent: true` --
  # derivable from a checked-in file, so it is a `safe` repair.
  #
  # WHAT READS IT: `Story::Doctor#characters_nowhere` (skips them),
  # `Character::Registry` (never places them), `WorldSeed::Exporter` (writes the
  # key back). WHAT CLEARS IT: `Character#move_to!` with a room -- bringing
  # Perrin back is the story's business, and a person standing in a room is not
  # absent from the world.
  def change
    add_column :characters, :deliberately_absent, :boolean, null: false, default: false
  end
end
