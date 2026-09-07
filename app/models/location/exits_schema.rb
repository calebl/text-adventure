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
      # WHETHER THIS PLACE HAS AN INSIDE, and it is HERE rather than on a call of
      # its own because this is the one moment in the app that names a place that
      # does not exist yet -- the captain's Call 7 of 2026-09-06, that the
      # location generator decides it, and his Call 2 of 2026-09-07, that it
      # rides on a call already being made. `Location::Parameters` is the band
      # each label names in paces; the engine rolls the footprint inside it and
      # `Location#place?` starts answering true with no new column.
      #
      # OPTIONAL, AND THE QUIETEST OPTION IS FIRST. An absent pick is a legal
      # answer and means `no inside`, which is what a stretch of road, a
      # clearing and a bridge all are -- so there is no separate question of
      # which stubs get asked (his Call 3). What it costs is that a world can
      # quietly stop having buildings in it by nobody answering, which is why
      # `Eval::Realization::Scorer` measures `inside_declined` and prints
      # `insides_given` beside the two rates that would otherwise reward it.
      string :inside,
             description: "NO INSIDE for almost everything you name. Anything else here makes the game " \
                          "build a whole floor plan of rooms there and send the player walking through " \
                          "them, so answer otherwise ONLY for a place that is a BUILDING somebody goes in " \
                          "at a door: an inn, a keep, a counting house, a warren. NO INSIDE for a road, a " \
                          "shore, a clearing, a bridge, a square, a cave mouth, a stair, a courtyard -- " \
                          "and for a room, an office or a hall, which are already somewhere you stand. " \
                          "When it really is a building, pick the size it would really be.",
             enum: Location::Parameters::INSIDE.keys, required: false
    end
  end
end
