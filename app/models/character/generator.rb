class Character::Generator
  include SanitizesGeneratedText

  attr_reader :story, :character_generation_prompt

  ATTRACTIVENESS_VALUES = [ "very_attractive", "attractive", "average", "unattractive" ]
  BIRTH_PLACES = [ "large city", "small town", "cave", "remote wilderness", "isolated island", "floating city", "jungle", "desert", "mountain", "boat" ]
  RAISED_BY = [ "parents", "guardian", "siblings", "grandparents", "aunt/uncle", "neighbor", "teacher", "mentor", "pet", "wild aninmals", "self" ]

  attr_reader :race, :age, :sex

  def initialize(story)
    @story = story
    # Race, age and sex are decided here rather than by the model. Race comes
    # from the universe's generated list so every character belongs to one of
    # its peoples; age and sex are rolled so repeated runs diverge. All three
    # are stated in the prompt, and none of them is in the schema -- asking for
    # a value the prompt just supplied is a decision bought twice.
    @race = story.universe.races.sample
    @age = rand(18..120)
    @sex = Character.sexes.values.sample
    @character_generation_prompt = generation_prompt(story)
  end

  # Raises if generation fails. Returning a half-built character instead just
  # pushes the failure downstream, where it looks like a bad model response.
  def generate
    agent = BaseAgent.new.with_instructions(system_prompt)
    character = @story.characters.new

    content = agent.with_schema(Character::Schema).ask(@character_generation_prompt).content

    character.fullname = sanitize_string(content["fullname"])
    character.nickname = sanitize_string(content["nickname"])
    character.personality = sanitize_string(content["personality"])
    character.appearance = sanitize_string(content["appearance"])
    character.likes = sanitize_string(content["likes"])
    character.dislikes = sanitize_string(content["dislikes"])
    character.fears = sanitize_string(content["fears"])
    character.backstory = sanitize_string(content["backstory"])

    character.race = race
    character.age = age
    character.sex = sex

    character
  end

  def system_prompt
    <<~PROMPT
      You are creative and imaginative while also being realistic. You pay attention to detail and you are able to generate characters that are consistent with realistic human behavior.

      DO NOT INCLUDE EMOJIS IN YOUR RESPONSE.
    PROMPT
  end

  def generation_prompt(story)
    <<~PROMPT

      ## Story Details:
      title: #{story.title}
      genre: #{story.genre}
      preface: #{story.preface}
      summary: #{story.summary}

      ## Universe Details
      #{story.universe.prompt_details}

      ## Already Generated Characters
      DO NOT GENERATE THESE CHARACTERS AGAIN.
      #{story.characters.map { |character| character.slice(:fullname, :nickname, :age, :sex, :personality).merge(race: character.race&.name).to_json }.join("\n")}
      END OF ALREADY GENERATED CHARACTERS

      ## Predetermined Character Details for the new character
      sex: #{sex}
      age: #{age}
      attractiveness: #{ATTRACTIVENESS_VALUES.sample}
      race: #{race&.name} -- #{race&.description}
      born in a: #{BIRTH_PLACES.sample}
      raised by: #{RAISED_BY.sample}

      ## Character Generation Instructions
      - The character is a #{race&.name}. Write them as one, and do not assign
        them a different race
      - Respect the stated length of each field
      - The character should be consistent with the story's universe
      - The character should be consistent with the story's characters
      - The character should be consistent with the story's plot
      - The character details should be significantly different from the already generated characters
      - The backstory covers their life before the story, their motivations and
        their goals. Write it in third person, referencing the character by name,
        and keep it consistent with where they were born and who raised them

      You are a character generator for the above fictional story.
      Generate all of the character details for a new character that will be added to the story.

    PROMPT
  end
end
