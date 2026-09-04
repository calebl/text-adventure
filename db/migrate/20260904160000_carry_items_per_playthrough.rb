class CarryItemsPerPlaythrough < ActiveRecord::Migration[8.1]
  # WHAT THE PARTY IS CARRYING BELONGS TO THE PLAYTHROUGH, not to the story's
  # protagonist.
  #
  # `items.character_id` was the whole answer to "does the player have this",
  # and every playthrough of one story plays it as `story.protagonist` -- one
  # `Character` row. So one inventory was shared by every play of a world:
  # playthrough 17 opened holding what playthrough 16 had picked up, and
  # nothing on creation emptied the hands or put the things back.
  #
  # THIS IS THE POSITION SHAPE, and the argument is PR 109's word for word.
  # Where the player STANDS is `playthroughs.current_location_id` and not a
  # column on the protagonist, because two people playing one seeded world
  # stand in two rooms at once and a story-level column cannot hold both
  # answers. Two people playing one seeded world also carry two different sets
  # of things.
  #
  # SO AN ITEM IS IN EXACTLY ONE OF THREE PLACES, never two and never none:
  #
  #   location_id     lying in a room. Story-level and shared between
  #                   playthroughs, deliberately and unchanged -- the captain is
  #                   thinking about that separately.
  #   character_id    held by one of the world's OWN people. For the
  #                   protagonist this is the story's STARTING INVENTORY: world
  #                   data, written by the seed file, exported by the exporter,
  #                   and carried by nobody.
  #   playthrough_id  carried by the party of one playthrough. The only column
  #                   `take`, `drop` and the inventory read or write.
  #
  # NULLABLE, and all three stay nullable: which one holds the row IS the state.
  #
  # ON DELETE THE ITEM GOES WITH THE PLAYTHROUGH (`Playthrough has_many :items,
  # dependent: :destroy`). A carried row is that player's progress, like their
  # chats -- and a copy of the starting inventory has nowhere honest to land,
  # since dropping it into a shared room would leave two worlds' worth of
  # daybooks lying in one office.
  #
  # `rake game:backfill_inventory` attributes what an older database left on
  # the protagonist, out of the takes recorded on `scenes.resolved_action`, and
  # refuses to guess.
  def change
    add_reference :items, :playthrough, null: true, foreign_key: true

    # The closed set `drop` resolves against, and the one query
    # `Playthrough#carried` makes.
    add_index :items, [ :playthrough_id, :id ]
  end
end
