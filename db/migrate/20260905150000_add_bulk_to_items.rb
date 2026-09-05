# A THING CAN BE THROWN, AND HOW HARD IT IS TO THROW IS A PROPERTY OF THE THING.
#
# The captain's request, answered in `data/ta-combat-scout` §13: *"I want players
# to be able to pick up items and throw them based on a strength check."* The
# strength is `characters.strength`, which landed with the abilities; this is the
# other half of the arithmetic, and it is ONE column.
#
#   items.bulk   a key into `Item::BULK`, whose value is the PENALTY taken off
#                the thrower's strength -- light 0, handy 2, heavy 5, and
#                `immovable` nil, which is not a hard throw but not a throw at
#                all. A closed-set key and not a number on the row, which is
#                `locations.danger`'s shape and `LocationConnection::DISTANCES`'
#                before it, for their reason: the labels are what somebody
#                writing a world reads and the numbers are what the engine
#                rolls, and a free number is a field something outside the
#                engine can fill in wrongly. `Item::THROWN_DAMAGE` is the second
#                table on the same key -- what a hit costs, d4 / d6 / d8 by bulk
#                -- rather than a second column.
#
# NOT NULL WITH A DEFAULT, which is `items.readable`'s shape and
# `locations.danger`'s, and it is why NO `bin/update` STEP IS NEEDED: every row
# already written is `handy`, and handy is true of almost everything in the three
# seeded worlds -- a daybook, a lamp, a bottle. There is no "nobody has decided
# yet" state for the doctor to report, so the column is not nullable the way
# `characters.hit_die` is.
#
# A PLAYTHROUGH'S OWN COPY INHERITS IT FOR NOTHING: `Item::Snapshot#copy!` is
# `attributes.except(*Item::NOT_COPIED)` and where a thing is is the whole of
# that exception list, so the next column added to `items` comes along by itself.
# The three seeded items this PR re-bulks reach a game already in progress
# through `Item::TemplateRefresh`, which is the other side of the same line.
#
# NO INDEX. Nothing queries by bulk: it is read off the row the classifier or
# the grammar already resolved, once, on the one turn somebody throws something.
class AddBulkToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :bulk, :string, default: "handy", null: false
  end
end
