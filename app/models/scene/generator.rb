# Narrates arriving somewhere and keeps the moment as a Scene.
#
# NOT `Scene::Narrator`, and the difference is the point. The narrator answers
# what the player TYPED: it streams unschema'd prose because a player is
# watching it land a token at a time, and that is the one documented exception
# to the structured-output rule. This narrates walking INTO a place, which is
# not a turn -- it is the record of a moment in the world, written the way
# every other record here is written:
#
#   * schema'd, one call, two fields. The description is what the player reads;
#     the summary is what the rest of the game remembers (see Scene::Schema).
#     Streaming would buy back one field and cost the other, and it would make
#     this class a copy of the narrator with a different prompt.
#   * it does not stream, and on the path that calls it that costs almost
#     nothing: arriving somewhere new means realizing the location first, which
#     is two unstreamed calls and ~670 output tokens. Streaming the ~120 tokens
#     that follow them is not what the player is waiting on.
#
# Arrival reads differently the second time. `Location#last_protagonist_visit`
# is the whole mechanism: a location the protagonist has never stood in gets
# narrated as discovery, and one they have gets narrated as coming back, with
# how long they were gone stated in the prompt. Walking into a room you left an
# hour ago should not read like finding it.
class Scene::Generator
  include SanitizesGeneratedText
  include ActionView::Helpers::DateHelper

  attr_reader :location, :previous_scene, :story

  # `previous_scene` is the scene the player is coming from -- the linked-list
  # link, not the last scene in this location. It is optional because the
  # story's opening arrival has nothing before it.
  #
  # `opening` marks the one arrival that belongs to the world: see .opening.
  #
  # `playthrough` is only ever what the conversation gets FILED UNDER -- nothing
  # about the arrival depends on it, which is why it is optional and why the
  # world-building path (.opening, `rake game:new`) leaves it out. See Chat.
  def initialize(location, previous_scene: nil, opening: false, playthrough: nil)
    @location = location
    @previous_scene = previous_scene
    @opening = opening
    @playthrough = playthrough
    @story = location.story
  end

  # The story's opening arrival, narrated once at WORLD-BUILDING time.
  #
  # Every other room the player walks into is narrated the moment they walk in.
  # The opening room is the one they never walk into -- they are simply standing
  # in it -- so until this existed the first thing a new player read was the
  # room's own description standing in for an arrival nobody wrote.
  #
  # Generating it here rather than at playthrough-start is the point of the
  # whole exercise. `rake game:new` pays for it once (~1,302 in / ~200 out, the
  # same as any arrival), WorldSeed::Exporter writes it into the seed file where
  # it can be hand-authored -- it is the most important prose in the game -- and
  # WorldSeed::Loader loads it with the world. A player starting a story pays no
  # model call at all and reads real narrated prose immediately.
  #
  # It is marked `is_opening`, which is what makes it world rather than
  # progress: it is exported, it is shared by every playthrough of the story,
  # and it deliberately does NOT stamp `last_protagonist_visit` (see Scene).
  def self.opening(story)
    location = story.opening_location
    raise ArgumentError, "#{story.title.inspect} has no location to open in" if location.nil?

    new(location, opening: true).generate!
  end

  # Raises rather than returning a half-made scene: a generator that swallows a
  # failure turns a bad API key into "the AI wrote garbage" downstream. A stub
  # raises for the same reason -- it has no description and no lore, so there is
  # nothing to arrive in. Realize it first (`Location::Generator#realize!`,
  # which no-ops on an already realized location).
  def generate!
    raise ArgumentError, "cannot narrate arriving in #{location.name.inspect}: it is still a stub" unless location.realized?

    # Read BEFORE the scene is created. `Scene#mark_location_visit` is an
    # after_create that stamps `last_protagonist_visit` with THIS arrival's own
    # story time, so by the time the record exists every arrival looks like a
    # return that happened zero minutes ago.
    returning = location.last_protagonist_visit.present?
    at = story_timestamp
    elapsed = location.time_since_last_visit(at)
    cast = characters_present

    answer = agent.with_schema(Scene::Schema).ask(arrival_prompt(returning, elapsed, cast)).content

    scene = Scene.create!(
      story: story,
      location: location,
      previous_scene: previous_scene,
      characters: cast,
      description: sanitize_string(answer["description"]),
      summary: sanitize_string(answer["summary"]),
      is_opening: opening?,
      story_timestamp: at
    )

    # The turn the exchange above belongs to only exists now, so the messages
    # are stamped with it here rather than by the caller. See BaseAgent#attribute_to!.
    agent.attribute_to!(scene)
    scene
  end

  # WHEN IN THE STORY THIS ARRIVAL HAPPENS, and the one place the game turns a
  # journey into elapsed story time.
  #
  # The opening arrival IS the moment the story starts, and `start_time` is
  # already the world's fixed in-story clock -- so it is read from the world
  # rather than from the wall clock, and the seed file does not have to carry a
  # timestamp that would only ever restate it.
  #
  # Every other arrival is the previous scene plus how long the walk took, which
  # `LocationConnection` already answers from its fixed tables. So the story's
  # clock advances by the world's own distances, and `#time_since_last_visit`
  # -- the value that becomes "you were last here about an hour ago" in the
  # prompt -- is measured in the fiction rather than against whenever the player
  # happened to have a browser open. That is the wall-clock defect, fixed in the
  # single place the ROADMAP asks for it.
  def story_timestamp
    return story.start_time if opening?
    return story.clock if previous_scene.nil?

    previous_scene.story_timestamp + journey_minutes.minutes
  end

  # How long the walk in took. Nil `previous_scene` never reaches here, and a
  # move with no edge should not either -- `Playthrough::Classifier` resolves a
  # destination out of the room's real exits -- so the fallback is for a caller
  # that placed the player somewhere by hand. It borrows the shortest distance
  # there is rather than zero, because two scenes at the same story instant
  # would make "how long since you were here" answer nothing at all.
  def journey_minutes
    edge = LocationConnection.find_by(location: previous_scene.location, connected_location: location)
    return LocationConnection::DISTANCES.fetch("adjacent") if edge.nil?

    LocationConnection.travel_minutes(edge.distance, edge.travel_method) ||
      LocationConnection::DISTANCES.fetch("adjacent")
  end

  def opening?
    @opening
  end

  # Who the game knows is standing here, decided from records rather than asked
  # for. Three sources, and each is something the app can actually answer:
  #
  #   the protagonist  -- they are the one arriving
  #   companions       -- they travel with the protagonist, so they are wherever
  #                       the protagonist is
  #   holdovers        -- whoever was in the last scene played in this location.
  #                       The world persists, and so do the people in it: the
  #                       innkeeper you left behind the counter is still there.
  #
  # Nothing here invents a character. There is no column saying where anyone
  # stands, so a location nobody has visited and no companion follows you into
  # is empty, which is honest. Populating it is `ta-narrator-memory`'s job --
  # the narrator creating characters by tool call -- and this method is the one
  # place it has to add them.
  def characters_present
    ([ story.protagonist ] + companions + holdovers).compact.uniq
  end

  # The same answer without building an arrival. `Playthrough::Classifier` needs
  # to know who the player can speak to, and that has to be the same list the
  # arrival narration introduced them to -- a classifier that worked it out
  # separately would sooner or later refuse to talk to someone the game had
  # just put in the room.
  def self.characters_present(location)
    new(location).characters_present
  end

  def agent
    @agent ||= BaseAgent.new(purpose: "arrival", playthrough: @playthrough).with_instructions(system_prompt)
  end

  def system_prompt
    <<~PROMPT
      You narrate a text adventure. You write the moment a player walks into a
      place: what reaches them first, in the second person and the present
      tense. You never break character, never offer a numbered menu, and never
      mention that you are a narrator.

      DO NOT INCLUDE EMOJIS IN YOUR RESPONSE.
    PROMPT
  end

  def arrival_prompt(returning, elapsed, cast)
    <<~PROMPT
      ## Universe Details
      #{story.universe.prompt_details(:scene)}
      ## Story Details
      title: #{story.title}
      genre: #{story.genre}
      summary: #{story.summary}

      ## The Place
      name: #{location.name}
      description: #{location.description}
      lore: #{location.lore}
      ways out: #{exit_names}

      ## Who Is Here
      #{cast_list(cast)}

      ## Just Before This
      #{lead_in}

      ## Instructions
      #{arrival_instructions(returning, elapsed)}
      - Address the player as "you", in the present tense
      - One paragraph. Do not re-describe the place item by item -- the
        description above is already what is here, and your job is the moment
        of coming into it
      - Anyone listed above is here; write them as already present, not as
        arriving. Do not add a person who is not on that list
      - Do not name a way out that is not on the list above
      - Respect the stated length of each field
    PROMPT
  end

  private

  # The two shapes this generator exists to tell apart.
  def arrival_instructions(returning, elapsed)
    if returning
      <<~PROMPT.strip
        - The player has stood here before. They were last here #{distance_of_time_in_words(elapsed)} ago
        - Narrate coming back, not finding. They already know what this place
          is, so write recognition: what has changed while they were gone, or
          what pointedly has not. Do not introduce it to them again
      PROMPT
    else
      <<~PROMPT.strip
        - The player has never been here. This is the first time they have set
          foot in it
        - Narrate discovery: what catches them first on the way in, before they
          have made sense of the rest
      PROMPT
    end
  end

  # Name, nickname and race -- the same ~15-token line `Character::Generator`
  # uses for its cast list. The narration needs to know who to mention, not who
  # they are; a character's full sheet belongs to a conversation with them.
  def cast_list(cast)
    lines = cast.map { |character| "#{character.fullname} (#{character.nickname}), #{character.race&.name}" }

    lines.join("\n").presence || "Nobody but the player."
  end

  def exit_names
    location.exits.pluck(:name).join(", ").presence || "None written yet."
  end

  # The link backwards, told as one line. The previous scene's summary is
  # preferred over its description for exactly the reason the summary is
  # written: it is the same moment in a fraction of the tokens.
  def lead_in
    return "Nothing. This is where the story opens." if previous_scene.nil?

    from = previous_scene.location
    coming_from = from && from != location ? "The player has come from #{from.name}. " : ""

    "#{coming_from}#{previous_scene.summary.presence || previous_scene.description}"
  end

  def companions
    story.characters.where(is_companion: true).to_a
  end

  # Whoever was here when the player last left. Ordered by story time rather
  # than by id so a scene backdated into the story's past does not win.
  #
  # The join is what makes this survive the game loop. Only an arrival records
  # a cast; a turn spent examining something writes a `Scene::Narrator` scene
  # with nobody in it. Reading the plain latest scene therefore emptied the
  # room after any turn that was not an arrival, so the innkeeper vanished
  # because the player looked at the fireplace on the way out. The last scene
  # that recorded anyone is the last thing the game actually knows.
  def holdovers
    last_scene_here = location.scenes.joins(:characters)
                              .order(story_timestamp: :desc, id: :desc).first

    last_scene_here ? last_scene_here.characters.to_a : []
  end
end
