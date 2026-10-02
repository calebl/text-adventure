# THE DESTINATION AS IT IS IN ONE GAME, before the party's location is moved.
#
# A Location's description is durable world prose, so it may still describe a
# person this game killed or a thing it carried away. These readers are the
# authoritative live state beside that description. They deliberately take a
# destination: the engine's moment reads current_location, which is still the
# room the player is leaving while an arrival is being written.
#
# Reading this object changes nothing. The move snapshots the room and pays
# its hazards first; the generator freezes the pending tolls here and records
# only those IDs as presented after a complete arrival has been written.
class Scene::ArrivalContext
  include ActionView::Helpers::DateHelper

  attr_reader :playthrough, :location, :at

  # `at` is when the party walks in, which is what how long ago a body was
  # killed is measured to.
  def initialize(playthrough, location:, at: nil)
    @playthrough = playthrough
    @location = location
    @at = at
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
    parts << "Dead here: #{dead_names}. They cannot speak or act." if dead.any?
    parts << "Lying here: #{item_names(floor)}."
    parts << "You are carrying: #{item_names(carried)}."
    parts.concat(tolls.map(&:fact))
    parts
  end

  private

  # The dead, each with the blow that killed them where one did: the room's
  # durable description may still have them standing, and nothing else on the
  # way in says how they came to lie there. The engine's `moment::killed_by`.
  def dead_names
    killed = dead.map { |body| killed_by(body) }
    return names(dead) if killed.none?

    dead.zip(killed).map { |body, clause| clause ? "#{body.fullname}, #{clause}" : body.fullname }.join("; ")
  end

  def killed_by(body)
    blow = playthrough.blows.where(target: body, hp_after: 0).order(:sequence, :id).last
    return unless blow

    killer = blow.attacker.fullname
    return "killed by #{killer}" unless at && blow.story_timestamp

    "killed by #{killer} #{distance_of_time_in_words(at - blow.story_timestamp)} ago"
  end

  def names(people) = people.map(&:fullname).join(", ")
  def item_names(items) = items.map(&:name).join(", ").presence || "nothing"
end
