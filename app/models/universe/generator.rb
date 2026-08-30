class Universe::Generator
  include SanitizesGeneratedText

  # Seeds handed to the model so repeated runs with the same premise still
  # diverge, in the spirit of Character::Generator's predetermined details.
  TONES = [ "hopeful", "bleak", "uneasy", "wondrous", "decaying", "feverish", "austere", "lush" ]
  ERAS = [ "on the edge of collapse", "in a long uneasy peace", "generations after a great war", "at the height of its power", "in the first years of a new order", "amid a slow forgotten decline" ]

  attr_reader :premise, :tone, :era

  def initialize(premise: nil)
    @premise = premise.presence
    @tone = TONES.sample
    @era = ERAS.sample
  end

  # Raises if generation fails -- see Character::Generator#generate.
  def generate
    agent = BaseAgent.new.with_instructions(system_prompt)
    universe = Universe.new

    physical = agent.with_schema(Universe::PhysicalSchema).ask(physical_prompt).content

    universe.physics = sanitize_string(physical["physics"])
    universe.technology = sanitize_string(physical["technology"])
    universe.weapons = sanitize_string(physical["weapons"])
    universe.geographies = sanitize_string(physical["geographies"])

    societal = agent.with_schema(Universe::SocietalSchema).ask(societal_prompt).content

    Array(societal["races"]).each do |race|
      universe.races.new(
        name: sanitize_string(race["name"]),
        description: sanitize_string(race["description"])
      )
    end

    universe.civilizations = sanitize_string(societal["civilizations"])
    universe.history = sanitize_string(societal["history"])
    universe.economics = sanitize_string(societal["economics"])
    universe.politics = sanitize_string(societal["politics"])
    universe.religion = sanitize_string(societal["religion"])

    universe
  end

  def system_prompt
    <<~PROMPT
      You are a worldbuilder. You invent settings that are internally consistent,
      specific, and grounded -- concrete names, concrete consequences, no vague
      gestures at grandeur. Every rule you establish is one a story could later
      be constrained by.

      DO NOT INCLUDE EMOJIS IN YOUR RESPONSE.
    PROMPT
  end

  def physical_prompt
    <<~PROMPT
      Invent the physical foundations of a new fictional universe.

      ## Premise
      #{premise || "Your choice. Pick something specific rather than generic fantasy."}

      ## Predetermined Details
      tone: #{tone}
      the world is currently: #{era}

      ## Instructions
      - Establish rules that constrain what characters can and cannot do
      - Be specific: name things, give numbers, state limits
      - Respect the stated length of each field
    PROMPT
  end

  def societal_prompt
    <<~PROMPT
      Now describe the peoples and societies of the universe you just established.

      ## Instructions
      - Stay consistent with the physics, technology, weapons and geography above
      - Give the factions reasons to be in conflict with one another
      - Be specific: name peoples, places and powers
      - Every character in this story will be one of the races you list, so make
        them distinct enough that it matters which one a character belongs to
      - Respect the stated length of each field
    PROMPT
  end
end
