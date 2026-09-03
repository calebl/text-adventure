# The ways out of a location. Each exit becomes a stub Location plus a
# LocationConnection, so the entries have to be individually addressable rather
# than a paragraph of prose -- the player has to be able to walk into one.
#
# A single exit is a legitimate answer. Exits are written in both directions, so
# a room realized from its neighbour already has its way back before this call
# runs, and naming that neighbour again is a no-op -- which is what makes a dead
# end honest at one exit rather than two. The floor is 1 and not 0 because the
# opening location has no neighbour to have been named by: an empty array there
# is a sealed room with no way out and no second chance to ask.
#
# `distance` and `travel_method` are enums drawn from LocationConnection's
# tables rather than free text, and `time_to_travel` is not asked for at all:
# it follows from the other two. Three free-text fields per exit, up to four
# exits, was twelve prose decisions per room, and the two failure modes that
# produced are documented on LocationConnection.
class Location::ExitsSchema < RubyLLM::Schema
  # HOW MANY WAYS OUT OF ONE ROOM, IN TOTAL AND NOT PER CALL.
  #
  # `max_items` below bounds ONE ANSWER, which is not the same thing and used to
  # be mistaken for it. A room's edges also arrive from outside this call --
  # seeded by a world file, or written when a neighbour was realized and named
  # this place -- and none of those are counted by a schema. Larkspur Quarter
  # rooftops was seeded with two, was walked into, and came back with five:
  # more connected than any other room in the database, and its own description
  # named none of them.
  #
  # So the total is enforced where the total is known, in
  # `Location::Generator#write_exits!`, which asks for at most what is left and
  # stops writing at this number however many the model named. A room already
  # at the cap is not asked at all -- no call, no tokens.
  MAX_EXITS = 4

  array :exits,
        description: "The places a player can reach directly from here.",
        min_items: 1,
        max_items: MAX_EXITS do
    object do
      string :name, description: "The name of the place this exit leads to, as a player would refer to it. 1 to 4 words, no article.", max_length: 60
      string :teaser, description: "A one-line glimpse of what lies that way, enough to make the player choose it. Exactly one sentence.", max_length: 160
      string :distance, description: "How far it is. Pick the closest of these; the exact wording does not matter.", enum: LocationConnection::DISTANCES.keys
      string :travel_method, description: "How the player covers that ground. Pick the closest of these. It must read correctly in both directions, because the way back is the same edge.", enum: LocationConnection::TRAVEL_METHODS.keys
    end
  end
end
