class Story::Generator
  include SanitizesGeneratedText

  attr_reader :universe, :premise

  def initialize(universe, premise: nil)
    @universe = universe
    @premise = premise.presence
  end

  # Returns an unsaved Story with its opening Location attached as a stub, so
  # saving the universe persists the whole opening in one go. The stub is built
  # here rather than asked for separately because the same call already wrote
  # the preface that describes it -- see Story::Schema.
  #
  # Raises if generation fails -- see Character::Generator#generate.
  def generate
    agent = BaseAgent.new.with_instructions(system_prompt)
    content = agent.with_schema(Story::Schema).ask(generation_prompt).content

    story = universe.stories.new(
      title: sanitize_string(content["title"]),
      genre: sanitize_string(content["genre"]),
      preface: sanitize_string(content["preface"]),
      summary: sanitize_string(content["summary"]),
      start_time: Time.current
    )

    story.locations.new(
      name: sanitize_string(content["opening_location_name"]),
      teaser: sanitize_string(content["opening_location_teaser"]),
      detail_level: :stub
    )

    story
  end

  def system_prompt
    <<~PROMPT
      You open text adventures. You drop the player into a specific moment with
      something already in motion -- a door already open, a body already cold, a
      ship already sinking. You never open with a character waking up, and you
      never explain the world in the abstract.

      DO NOT INCLUDE EMOJIS IN YOUR RESPONSE.
    PROMPT
  end

  def generation_prompt
    <<~PROMPT
      ## Universe Details
      #{universe.prompt_details}

      ## Premise
      #{premise || "Your choice, drawn from the tensions already present in the universe above."}

      ## Instructions
      Open a text adventure set in the universe above.
      - Set the opening somewhere concrete that the player can immediately look around and walk out of
      - Give the player an immediate reason to move
      - The preface is the first thing the player reads. Address them as "you". Do not list their options; describe the room and let them ask.
      - Name that opening place the way a player would refer to it, not the way a cartographer would
      - Leave the ending open. You are starting a story, not outlining one.
    PROMPT
  end
end
