# WHETHER A THING BREAKS WHEN IT COMES DOWN ON A FLOOR, as a key the engine
# rolls against: `Item::FRAGILITIES`, the rows of `fragility` in the Rust
# engine's `data/physics.yml`.
#
# NOT NULL WITH A DEFAULT, on `items.bulk`'s precedent and for its reason:
# `sturdy` never breaks, so every row already written plays exactly as it did,
# and NO `bin/update` STEP IS NEEDED. A playthrough's copy inherits it through
# `Item::Snapshot#copy!` like every other column that is not a place.
class AddFragilityToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :fragility, :string, null: false, default: "sturdy"
  end
end
