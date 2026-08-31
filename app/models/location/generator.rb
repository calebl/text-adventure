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
  def initialize(location)
    @location = location
    @story = location.story
  end

  # The story's opening location. There is no stub to realize yet, so the model
  # names the place from the story's own preface first, on the same
  # conversation that then describes it.
  def self.opening(story)
    generator = new(story.locations.new)
    generator.name_from_story!
    generator.realize!
  end

  # Description, lore and the stub exits leading out, in one transaction so a
  # location is never left half-realized with some of its exits missing.
  def realize!
    return location if location.realized?

    detail = ask(Location::DetailSchema, detail_prompt)
    location.description = sanitize_string(detail["description"])
    location.lore = sanitize_string(detail["lore"])
    location.detail_level = :realized

    exits = Array(ask(Location::ExitsSchema, exits_prompt)["exits"])

    Location.transaction do
      location.save!
      exits.each { |attributes| connect_exit!(attributes) }
    end

    location
  end

  # Names the opening location from the story. Only used by .opening -- every
  # other location arrives already named, as a stub created by its neighbour.
  def name_from_story!
    content = ask(Location::OpeningSchema, opening_prompt)

    location.name = sanitize_string(content["name"])
    location.teaser = sanitize_string(content["teaser"])
    location
  end

  def agent
    @agent ||= BaseAgent.new.with_instructions(system_prompt)
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

  def opening_prompt
    <<~PROMPT
      #{story_context}

      ## Instructions
      Name the place this story opens in. It is the room the preface above
      describes -- do not invent a different one.
      - Name it the way a player would refer to it, not the way a cartographer would
      - Respect the stated length of each field
    PROMPT
  end

  def detail_prompt
    <<~PROMPT
      #{story_context}

      ## The Place
      name: #{location.name}
      teaser: #{location.teaser}
      #{parent_context}

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
      #{known_location_names.presence || "None yet."}

      ## Instructions
      - Each exit is somewhere the player can reach directly from #{location.name}
      - Give the player a reason to prefer one over another
      - Do not list #{location.name} itself
      - Distances and travel times must be consistent with the description you just wrote
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
      #{story.universe.prompt_details}

      ## Story Details
      title: #{story.title}
      genre: #{story.genre}
      preface: #{story.preface}
      summary: #{story.summary}
    CONTEXT
  end

  def parent_context
    return "" if location.parent_location.nil?

    "contained within: #{location.parent_location.name}"
  end

  def known_location_names
    story.locations.where.not(id: location.id).pluck(:name).join("\n")
  end

  # An exit becomes a stub neighbour plus a connection in both directions.
  # Reusing an existing location by name is what stops realizing A -> stub B,
  # then realizing B, from creating a second A alongside the first.
  def connect_exit!(attributes)
    name = sanitize_string(attributes["name"])
    return if name.blank? || name.casecmp?(location.name.to_s)

    neighbour = find_or_create_stub(name, sanitize_string(attributes["teaser"]))

    connect!(location, neighbour, attributes)
    connect!(neighbour, location, attributes)
  end

  def find_or_create_stub(name, teaser)
    existing = story.locations.where("LOWER(name) = ?", name.downcase).first
    return existing if existing

    story.locations.create!(name: name, teaser: teaser, detail_level: :stub)
  end

  # Connections are directional rows, so both directions are written: the
  # player has to be able to walk back the way they came, and the return trip
  # exists before the far side is ever realized.
  def connect!(from, to, attributes)
    return if LocationConnection.exists?(location: from, connected_location: to)

    LocationConnection.create!(
      location: from,
      connected_location: to,
      distance: sanitize_string(attributes["distance"]),
      time_to_travel: sanitize_string(attributes["time_to_travel"]),
      travel_method: sanitize_string(attributes["travel_method"])
    )
  end
end
