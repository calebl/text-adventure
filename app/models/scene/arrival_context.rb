# THE DESTINATION AS IT IS IN ONE GAME, before the party's location is moved.
#
# A Location's description is durable world prose, so it may still describe a
# person this game killed or a thing it carried away. These readers are the
# authoritative live state beside that description. They deliberately take a
# destination: Playthrough::Moment reads current_location, which is still the
# room the player is leaving while an arrival is being written.
#
# Reading this object changes nothing. The move snapshots the room and pays
# its hazards first; the generator freezes the pending tolls here and records
# only those IDs as presented after a complete arrival has been written.
class Scene::ArrivalContext
  attr_reader :playthrough, :location

  def initialize(playthrough, location:)
    @playthrough = playthrough
    @location = location
  end

  def living
    @living ||= playthrough.cast_on_arrival(location)
  end

  def dead
    @dead ||= playthrough.characters_located_in(location).select { |person| playthrough.vitals_for(person)&.dead? }
  end

  def floor
    @floor ||= playthrough.items_lying_in(location).to_a
  end

  def carried
    @carried ||= playthrough.carried.to_a
  end

  def tolls
    @tolls ||= playthrough.tolls.untold.chronological.includes(:character, :location, :location_connection).to_a
  end

  def toll_ids = tolls.map(&:id)

  # Engine words also serve a failed arrival: no provider is needed to tell
  # the player where they arrived, what remains here and what the crossing cost.
  def facts
    parts = []
    parts << "You are #{playthrough.condition.in_words}." if playthrough.condition
    others = living - [ playthrough.character ]
    parts << (others.any? ? "Also here: #{names(others)}. Nobody else is alive here." : "Nobody else is alive here.")
    parts.concat(others.filter_map do |person|
      condition = playthrough.vitals_for(person)
      "#{person.fullname} is #{condition.in_words}." if condition && !condition.unhurt?
    end)
    parts << "Dead here: #{names(dead)}. They cannot speak or act." if dead.any?
    parts << "Lying here: #{item_names(floor)}."
    parts << "You are carrying: #{item_names(carried)}."
    parts.concat(tolls.map { |toll| Playthrough::Moment.new(playthrough).one_toll(toll) })
    parts
  end

  private

  def names(people) = people.map(&:fullname).join(", ")
  def item_names(items) = items.map(&:name).join(", ").presence || "nothing"
end
