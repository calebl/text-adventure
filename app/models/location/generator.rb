# Realizes a location: fills in the description and lore the player reads, then
# creates the stub locations the exits lead to. Those stubs are the whole point
# -- when the narrator says three doors lead out, all three have to be real
# records before the player picks one, but only the one they walk through is
# ever written in full.
#
# Generation happens once per place. A realized location is returned untouched,
# which is what makes walking back into a room give you the room you left.
class Location::Generator
  include SanitizesGeneratedText

  attr_reader :location, :story

  # `location` is a stub -- a Location with a name and a teaser but no
  # description or lore. It may be unsaved; realizing it persists it.
  #
  # `playthrough` is only what the conversation gets filed under (see Chat).
  # Realizing a room is the most expensive thing a move does -- two calls and
  # ~670 output tokens -- so a turn's cost is wrong without it, and the
  # world-building path that has no playthrough simply leaves it out.
  def initialize(location, playthrough: nil)
    @location = location
    @playthrough = playthrough
    @story = location.story
  end

  # Realizes the story's opening location. Story::Generator already created it
  # as a stub from the same call that wrote the preface, so there is nothing to
  # name here -- only to write out in full.
  def self.opening(story)
    location = story.opening_location
    raise ArgumentError, "story ##{story.id} has no opening location to realize" if location.nil?

    new(location).realize!
  end

  # Description and lore, then the stub exits leading out -- saved in that
  # order. The description used to be held unsaved until the exits call
  # returned, so an exits failure threw away the more expensive of the two
  # calls along with the cheaper one.
  #
  # A failure after the description lands leaves a realized room with no way
  # out. `realize!` returns an already-realized location untouched, which is
  # the "generate once per place" guarantee, so recovering from that means
  # calling #write_exits! directly rather than realizing the room again.
  def realize!
    return location if location.realized?

    write_detail!
    write_exits!

    location
  end

  # What the player reads on arrival, persisted immediately.
  def write_detail!
    detail = ask(Location::DetailSchema, detail_prompt)

    location.description = sanitize_string(detail["description"])
    location.lore = sanitize_string(detail["lore"])
    location.detail_level = :realized
    location.save!

    location
  end

  # The ways out, as stub neighbours plus connection rows in both directions,
  # in one transaction so a room never keeps some of its exits and not others.
  #
  # THE FLOOR is the second pass. A room with no way out at all is worse than a
  # room with one it should not have, so if every way out the model named was a
  # written room this cannot open a door into (see #connect_exit!), they are
  # taken anyway rather than sealing the player in. Only reachable for a room
  # that was not realized by being walked into -- an arrival already has its
  # way back, so the first pass can never leave it with nothing.
  def write_exits!
    exits = Array(ask(Location::ExitsSchema, exits_prompt)["exits"])

    Location.transaction do
      exits.each { |attributes| connect_exit!(attributes) }
      exits.each { |attributes| connect_exit!(attributes, into_written: true) } unless location.exits.exists?
    end

    location
  end

  # ONE conversation for both calls, and that is why persistence is per agent
  # rather than per call: the exits call is asked in the context of the
  # description the same model just wrote, so the two exchanges are one
  # conversation and the stored row is what was actually sent.
  def agent
    @agent ||= BaseAgent.new(purpose: "location", playthrough: @playthrough).with_instructions(system_prompt)
  end

  def system_prompt
    <<~PROMPT
      You build the rooms of a text adventure one at a time. You write places a
      player can stand in and walk out of: concrete, specific, and consistent
      with the world they belong to. Every exit you name is somewhere the player
      could actually go.

      DO NOT INCLUDE EMOJIS IN YOUR RESPONSE.
    PROMPT
  end

  def detail_prompt
    <<~PROMPT
      #{story_context}

      ## The Place
      name: #{location.name}
      teaser: #{location.teaser}

      ## Instructions
      Write this place out in full.
      - The description is what the player reads on arrival. Address them as "you"
      - Describe what is here now, not the history -- the history is the lore
      - Stay consistent with the universe and with the teaser above
      - Respect the stated length of each field
    PROMPT
  end

  def exits_prompt
    <<~PROMPT
      Now list the ways out of #{location.name}.

      ## Places That Already Exist In This Story
      Reuse a name from this list when an exit leads somewhere already known.
      Only invent a name when the exit leads somewhere genuinely new.
      A place marked (already written) has had its own ways out written down
      already, so naming it here would open a door it does not have: leave it
      out and name somewhere new instead.
      #{known_location_names.presence || "None yet."}

      ## Instructions
      - Each exit is somewhere the player can reach directly from #{location.name}
      - One way out is a complete answer. A dead end, a cell, the bottom of a
        shaft: if the only way out is back the place the player came from, list
        that place and nothing else. Never invent a passage to reach a second
      - When there is more than one, give the player a reason to prefer one
        over another
      - Do not list #{location.name} itself
      - Distance and travel method must be consistent with the description you
        just wrote, and must be true in both directions -- the way back is the
        same edge
      - Respect the stated length of each field
    PROMPT
  end

  private

  def ask(schema, prompt)
    agent.with_schema(schema).ask(prompt).content
  end

  def story_context
    <<~CONTEXT
      ## Universe Details
      #{story.universe.prompt_details(:place)}

      ## Story Details
      title: #{story.title}
      genre: #{story.genre}
      preface: #{story.preface}
      summary: #{story.summary}
    CONTEXT
  end

  # The places the model may reuse a name from, with the written ones marked.
  # A room that has been written has already said what its ways out are, so
  # naming it here is asking for a door it does not have; the engine refuses
  # that edge in #connect_exit! either way, and saying so up front is what
  # stops the model spending an exit on one.
  def known_location_names
    story.locations.where.not(id: location.id).order(:id).map { |place| known_location_line(place) }.join("\n")
  end

  def known_location_line(place)
    return place.name unless place.realized? && !connected?(place)

    "#{place.name} (already written -- do not open a new way into it)"
  end

  # An exit becomes a stub neighbour plus a connection in both directions.
  # Reusing an existing location by name is what stops realizing A -> stub B,
  # then realizing B, from creating a second A alongside the first.
  #
  # A REUSED NAME THAT IS ALREADY WRITTEN IS NOT A NEW EXIT. Realizing this
  # room would otherwise add a way out to a room whose description has already
  # been written and already said what its ways out are: a supply closet whose
  # prose reads "there is no other door" grew a second one the moment the
  # hallway next to it was realized and the model reused the closet's name. The
  # edge is dropped in BOTH directions, because it is one edge.
  #
  # What decides is the connection and not the detail level, so the two cases
  # that have to stay legal do: the way back, written when this room was still
  # a stub, and a written place the player can already reach from here. Only an
  # edge that did not exist before is refused. `into_written:` is the floor in
  # #write_exits! asking for that refusal to be lifted.
  def connect_exit!(attributes, into_written: false)
    name = sanitize_string(attributes["name"])
    return if name.blank? || name.casecmp?(location.name.to_s)

    existing = find_location(name)
    return if existing&.realized? && !into_written && !connected?(existing)

    neighbour = existing || create_stub!(name, sanitize_string(attributes["teaser"]))

    connect!(location, neighbour, attributes)
    connect!(neighbour, location, attributes)
  end

  def find_location(name)
    story.locations.where("LOWER(name) = ?", name.downcase).first
  end

  def create_stub!(name, teaser)
    story.locations.create!(name: name, teaser: teaser, detail_level: :stub)
  end

  # Whether the player can already get between here and there, either way
  # round. Both rows are written together, so one direction is enough to know
  # the edge exists -- the second check is only so a half-written pair does not
  # read as a new door.
  def connected?(neighbour)
    LocationConnection.exists?(location: location, connected_location: neighbour) ||
      LocationConnection.exists?(location: neighbour, connected_location: location)
  end

  # Connections are directional rows, so both directions are written: the
  # player has to be able to walk back the way they came, and the return trip
  # exists before the far side is ever realized. Both rows carry the same
  # values, which is only correct because LocationConnection's enums are
  # direction-neutral; `time_to_travel` is derived there, not copied here.
  def connect!(from, to, attributes)
    return if LocationConnection.exists?(location: from, connected_location: to)

    LocationConnection.create!(
      location: from,
      connected_location: to,
      distance: sanitize_string(attributes["distance"]),
      travel_method: sanitize_string(attributes["travel_method"])
    )
  end
end
