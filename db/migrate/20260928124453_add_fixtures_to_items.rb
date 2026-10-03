# WHAT STANDS IN A ROOM, AND WHAT LIES ON IT, AS FOUR COLUMNS ON `items`.
# `Item::Kit` owns the tables a room is furnished from and `Item`'s header the
# rules; what belongs here is why the columns have the shape they have.
#
# ONE TABLE, NOT A SECOND ONE, on the argument `Item`'s header makes against
# `item_instances`: the caps, the doctor, the exporter, the audit and
# `Item.in_story` would all fork the day there were two. A desk is a thing in a
# room that does not move, so it is a row here, copied per playthrough like the
# ward stamp on it.
#
#   tier      `portable` or `fixture`. NOT NULL WITH A DEFAULT, on `bulk`'s
#             precedent and for its reason: every row already written is a
#             portable thing, so it plays exactly as it did and `bin/update`
#             gains no step.
#   holds     on a fixture only: `nothing`, `top`, `hollow` or `closed`. Nil on
#             every portable row, which is every row already written.
#   within_id the fixture this row lies on or in, and `how` which of the two.
#             Both or neither. A row with one still carries its `location_id`:
#             the room is its place and the fixture a refinement of it, so the
#             one-place rule is untouched. NO FOREIGN KEY, on `template_id`'s
#             precedent: `Item`'s association clears both columns before a
#             fixture is destroyed, and `rake game:doctor` reports a row that
#             raw SQL left pointing at nothing.
#   kit_key   which kit entry wrote the row, nil for everything else: the
#             writer's own things, seeded things and every row already written.
#             It is what the caps read to count only the writer's things.
class AddFixturesToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :tier, :string, null: false, default: "portable"
    add_column :items, :holds, :string
    add_column :items, :within_id, :integer
    add_column :items, :how, :string
    add_column :items, :kit_key, :string
    add_index :items, :within_id
  end
end
