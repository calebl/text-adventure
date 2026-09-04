# THE WORLD IS THE TEMPLATE AND THE PLAYTHROUGH OWNS THE INSTANCES.
#
# The captain's ruling of 2026-09-04, verbatim: *"each play through should have
# its own copy of items. If a location is generated with items in it, that
# should become the initial snapshot that any playthrough uses but what happens
# to the items after that should be managed by the playthrough."*
#
# `items.playthrough_id` arrived one PR earlier meaning ONE thing -- the party
# of that playthrough is carrying this. That closed half the defect: two people
# playing one seeded world no longer shared a pair of hands. It left the other
# half open and said so, in `lib/engine_sweep/scripts/the-unrecorded-hour-two-players.yml`
# and in the ROADMAP: a room one party emptied was empty for the other, because
# `items.location_id` was the world's and the world was shared.
#
# WHAT THIS MIGRATION CHANGES IS WHAT THAT COLUMN MEANS. It is now THE LAYER:
#
#   playthrough_id NULL   the world's own row -- a TEMPLATE. What a room or a
#                         person was seeded or generated with. Written by
#                         `WorldSeed::Loader` and `Item::Registry`, exported by
#                         `WorldSeed::Exporter`, counted by the caps, and never
#                         touched by anybody playing.
#   playthrough_id SET    that playthrough's own copy -- an INSTANCE. It carries
#                         a place of its own: `location_id` (lying in a room, in
#                         that game), `character_id` (in that person's hands, in
#                         that game), or NEITHER, which is the party's own hands.
#                         The only layer `take`, `drop`, `read`, the classifier's
#                         closed sets, the narrator and the mechanics read-out
#                         ever see.
#
# So the old three-place rule becomes a two-part rule, one part per layer, and
# `Item#in_exactly_one_place` says both. See that model's header for the trade
# that shape makes and the two shapes that were rejected.
#
# `template_id` IS THE DURABLE LINK, and it is what makes the split answerable
# rather than merely representable. It says which world row a copy is a copy OF,
# so `rake game:doctor` can tell this playthrough's ward stamp from a fresh
# thing of the same name, `Item::Snapshot` can copy a template exactly once per
# playthrough however many turns walk back through the room, and a template
# written into a room nobody has visited yet still reaches every game that
# walks in later.
#
# NOTHING MOVES HERE. Every row already in the table keeps its columns: a row
# lying in a room and a row in somebody's hands are already templates under the
# new reading, and PR 111's carried rows are already instances with the place
# the new reading gives them (neither -- the party's hands). What they lack is
# `template_id` and the instances the visited rooms are owed, and that is
# `rake game:backfill_items` (`Item::LayerBackfill`), offline and DRY_RUN-able.
class CopyTheWorldIntoEachPlaythrough < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :template_id, :integer, null: true
    add_index :items, :template_id
    # THE ONE QUESTION `Item::Snapshot` ASKS ON EVERY TURN: which of this
    # world's templates does this playthrough already hold a copy of? It runs
    # once per turn on the room the party is standing in, so it is the index
    # that keeps lazy instantiation free after the first visit.
    add_index :items, [ :playthrough_id, :template_id ]
  end
end
