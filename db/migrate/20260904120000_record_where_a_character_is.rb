class RecordWhereACharacterIs < ActiveRecord::Migration[8.1]
  # WHERE A CHARACTER IS, as one column on the character.
  #
  # `Character` belonged to a story and to the scenes it appeared in, and that
  # was the whole answer to "where is Ammon Brace". Whereabouts were therefore
  # whatever the last ARRIVAL scene's cast happened to say, and only an arrival
  # writes a cast at all -- 296 of the 480 baseline turns of 2026-09-03 have
  # one, and the other 184 have no record of who was in the room. So the cast
  # was regenerated from scratch on every arrival, and it quietly dropped the
  # people a world is about: arriving at The Tide Post recorded the protagonist
  # alone on all three runs checked, in a world whose premise is that Neb
  # Halloran is chained to that post.
  #
  # THIS IS THE `Item` SHAPE, chosen by the captain over making the scene cast
  # authoritative: one place at a time, owned by the app, written by the engine
  # and never by prose. `Character.present_in(location)` is then the closed set
  # `talk` resolves against, exactly as `Item.lying_in(location)` is the one
  # `take` resolves against.
  #
  # NULLABLE, and it stays nullable: "nowhere yet" is a real state. A seeded
  # character the file does not place, a character generated for a story before
  # this column existed, and a character whose room has been deleted are all
  # genuinely nowhere, and `rake game:doctor` reports each of them rather than
  # this migration inventing a room to put them in.
  #
  # ON DELETE THE COLUMN IS NULLED rather than the character destroyed
  # (`Location has_many :characters, dependent: :nullify`): a person outlives a
  # building. `rake game:backfill_whereabouts` places what the old arrival
  # casts can still answer for, and refuses to guess when they disagree.
  def change
    add_reference :characters, :location, null: true, foreign_key: true

    # The closed set `talk` resolves against, and the one query
    # `Character.present_in` makes.
    add_index :characters, [ :location_id, :id ]
  end
end
