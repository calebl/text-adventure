# A WORLD CAN CONTAIN AN ENEMY, and the three columns that say so are all on
# the WORLD's side of the layer split -- the side `characters.hit_die` is on.
# Nothing fights yet: this is the shape a fight will read, written down first so
# that the slice which resolves one adds no schema at all.
#
#   races.monstrous      a universe's own bestiary is the monstrous half of its
#                        race list. The captain's ruling of 2026-09-04:
#                        *"a universe should be able to have monsters as well as
#                        characters"* -- and a `Race` is already exactly that
#                        catalogue, one per universe, with a description every
#                        prompt that reads a race already reads.
#   characters.hostile   whether this person attacks the party. A flag on the
#                        record rather than a subclass or a second table, which
#                        is `locations.mobile`'s own argument said one table
#                        over: *"a mobile location is an ordinary location in
#                        every other respect"*. A monster is an ordinary person
#                        in every respect but one.
#   locations.danger     how likely a room is to be born with the world's
#                        monsters in it instead of its peoples. A closed-set key
#                        into `Location::DANGERS`, which is
#                        `LocationConnection::DISTANCES`' shape and is chosen
#                        for that shape's reason: the labels are what a person
#                        writing a world reads and the numbers are what the
#                        engine rolls, and a free number is a field something
#                        outside the engine can fill in wrongly.
#
# NOT NULL WITH A DEFAULT, all three, which is `items.readable`'s shape -- and
# it is why no `bin/update` step is needed: an existing world has no monsters
# and no dangerous rooms, and the defaults say exactly that. Compare
# `characters.strength`, which is nullable because "nobody has rolled one" is a
# state the doctor reports; there is no such state here, because false and
# "safe" are the honest answer for every row already written.
#
# THE INDEX IS THE CLOSED SET A FIGHT READS. `Playthrough#foes_in(location)` is
# `Character.present_in(location).hostile`, asked once a turn for the life of
# every playthrough, so the pair is indexed together the way
# `(location_id, id)` already is for presence itself.
class AddMonstersToTheWorld < ActiveRecord::Migration[8.1]
  def change
    add_column :races, :monstrous, :boolean, default: false, null: false
    add_column :characters, :hostile, :boolean, default: false, null: false
    add_column :locations, :danger, :string, default: "safe", null: false

    add_index :characters, [ :location_id, :hostile ]
  end
end
