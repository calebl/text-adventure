# Removes a story and everything that belongs only to it.
#
# THE DANGEROUS ONE, so it is built to be read before it is run: `#manifest`
# counts what will go, by type, and nothing is destroyed until a caller has
# repeated the story's own title back. A story is minutes of model calls and it
# is not recoverable, so a mistyped id must not be able to take one.
#
# WHAT "BELONGS ONLY TO IT" MEANS, and it is not obvious from the associations:
#
#   * The story cascades to its characters (and their items and interactions),
#     its locations (and their scenes), its playthroughs, its world mechanics
#     and their events. `dependent:` is already right for all of that, and
#     StoryDeletionTest pins it by counting every table before and after.
#   * Connections are join rows on `location_connections`, cleared by the two
#     HABTM declarations on Location -- one for each end of the edge, which is
#     why both are declared.
#   * THE UNIVERSE IS NOT THE STORY'S. `Universe has_many :stories`, so a
#     universe can outlive this one; it is destroyed only when this was the last
#     story in it, and then its races go with it. That check is the difference
#     between cleaning up and destroying a world the captain still wanted.
class Story::Deletion
  class NotConfirmed < StandardError; end

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # What the caller has to type back before anything is destroyed. The title
  # rather than the id: an id typo is exactly the mistake this is guarding
  # against, so the confirmation has to be something only the right story says.
  def confirmation
    story.title
  end

  def confirmed?(input)
    input.to_s.strip.casecmp?(confirmation.to_s.strip)
  end

  # Everything that goes, counted by type and in the order it is destroyed.
  # Zero counts are kept: "0 playthroughs" is information too.
  def manifest
    {
      "characters" => characters.count,
      # Both places an item can be: held by one of the story's characters, or
      # lying in one of its locations (Item). The second half arrived with
      # app-owned `take` and would otherwise go uncounted.
      "items" => Item.where(character: characters).or(Item.where(location: locations)).count,
      "interactions" => Interaction.where(character: characters).count,
      "locations" => locations.count,
      # One row per DIRECTION, which is what is actually deleted: an edge is
      # two rows (see LocationConnection), so this is twice the edge count.
      "connection rows" => connections.count,
      "scenes" => story.scenes.count,
      "playthroughs" => story.playthroughs.count,
      "world mechanics" => story.world_mechanics.count,
      "world events" => story.world_events.count
    }
  end

  # The other stories built on the same universe. Non-empty means the universe
  # stays, and saying so is half the point of the manifest.
  def universe_stories
    story.universe.stories.where.not(id: story.id)
  end

  def universe_shared? = universe_stories.exists?

  # One line about the universe: destroyed with the story, or kept and why.
  def universe_disposition
    universe = story.universe

    if universe_shared?
      titles = universe_stories.order(:id).pluck(:title)
      "universe ##{universe.id} KEPT: #{titles.size} other stor#{titles.one? ? "y" : "ies"} use it (#{titles.join(", ")})"
    else
      "universe ##{universe.id} and its #{universe.races.count} race(s): destroyed, nothing else uses them"
    end
  end

  # Destroys the story, and the universe if this was the last story in it.
  #
  # One transaction over both, so a universe that refuses to go (a race still
  # holding characters -- `Race has_many :characters, dependent: :restrict_with_error`)
  # leaves the story intact rather than half a world behind.
  def destroy!(confirm:)
    unless confirmed?(confirm)
      raise NotConfirmed, "expected the story's title (#{confirmation.inspect}) to confirm, got #{confirm.to_s.strip.inspect}"
    end

    removed = manifest
    universe_id = story.universe_id
    take_universe = !universe_shared?

    ActiveRecord::Base.transaction do
      story.destroy!
      # Re-read rather than destroying the instance already in hand. Its `races`
      # association can be loaded and stale -- anything that created a race
      # after the universe was first read is not in it -- and destroying the
      # universe then leaves the races it did not know about pointing at a row
      # that is gone. SQLite enforces the foreign key, so that is a raise rather
      # than an orphan, but only because the constraint is there to catch it.
      Universe.find(universe_id).destroy! if take_universe
    end

    removed
  end

  private

  def characters = story.characters

  def locations = story.locations

  # Both ends: the join rows are cleared by Location's two HABTM declarations,
  # and counting only one direction would under-report by half.
  def connections
    LocationConnection.where(location: locations).or(LocationConnection.where(connected_location: locations))
  end
end
