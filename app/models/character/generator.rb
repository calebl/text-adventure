class Character::Generator
  attr_reader :story, :character_generation_prompt

  ATTRACTIVENESS_VALUES = [ "very_attractive", "attractive", "average", "unattractive" ]
  BIRTH_PLACES = [ "large city", "small town", "cave", "remote wilderness", "isolated island", "floating city", "jungle", "desert", "mountain", "boat" ]
  RAISED_BY = [ "parents", "guardian", "siblings", "grandparents", "aunt/uncle", "neighbor", "teacher", "mentor", "pet", "wild aninmals", "self" ]

  def initialize(story)
    @story = story
    @character_generation_prompt = generation_prompt(story)
    @background_generation_prompt = background_generation_prompt
  end

  def generate
    Async do
      agent = BaseAgent.new.with_instructions(system_prompt)
      character = @story.characters.new

      begin
        response = agent.with_schema(Character::BaseSchema).ask(@character_generation_prompt)
        base_content = response.content

        character.fullname = sanitize_string(base_content["fullname"])
        character.nickname = sanitize_string(base_content["nickname"])
        character.age = base_content["age"].to_i
        character.sex = sanitize_string(base_content["sex"])
        character.race = sanitize_string(base_content["race"])

        background_response = agent.with_schema(Character::BackgroundSchema).ask(@background_generation_prompt)
        background_content = background_response.content

        character.personality = sanitize_string(background_content["personality"])
        character.appearance = sanitize_string(background_content["appearance"])
        character.likes = sanitize_string(background_content["likes"])
        character.dislikes = sanitize_string(background_content["dislikes"])
        character.fears = sanitize_string(background_content["fears"])
        character.backstory = sanitize_string(background_content["backstory"])

      rescue => e
        Rails.logger.error("Error generating character: #{e.message}")
      end
      character
    end.result
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
      physics: #{story.universe.physics}
      technology: #{story.universe.technology}
      weapons: #{story.universe.weapons}
      races: #{story.universe.races}
      civilizations: #{story.universe.civilizations}
      geographies: #{story.universe.geographies}
      history: #{story.universe.history}
      economics: #{story.universe.economics}
      politics: #{story.universe.politics}
      religion: #{story.universe.religion}

      ## Already Generated Characters
      DO NOT GENERATE THESE CHARACTERS AGAIN.
      #{story.characters.map { |character| character.slice(:fullname, :nickname, :age, :sex, :race, :personality).to_json }.join("\n")}
      END OF ALREADY GENERATED CHARACTERS

      ## Predetermined Character Details for the new character
      sex: #{Character.sexes.values.sample}
      age: #{rand(18..120)}
      attractiveness: #{ATTRACTIVENESS_VALUES.sample}

      ## Character Generation Instructions
      - The character should be consistent with the story's universe
      - The character should be consistent with the story's characters
      - The character should be consistent with the story's plot
      - The character details should be significantly different from the already generated characters

      You are a character generator for the above fictional story.
      Generate all of the character details for a new character that will be added to the story.

    PROMPT
  end

  def background_generation_prompt
    <<~PROMPT
      Generate a believable backstory for the character.

      This character was born in a #{BIRTH_PLACES.sample}. They were raised by #{RAISED_BY.sample}.

      ## Backstory
      The backstory should be a short, concise, and engaging story that is consistent with the character.
      The backstory should detail the character's life before the story, their motivations, and their goals.
      The backstory should be one paragraph. It should be written in third person, referencing the character by name.

    PROMPT
  end

  def sanitize_string(string)
    string.to_s.gsub(/\p{Emoji_Presentation}|\p{Emoji}\uFE0F?/, "").strip
  end
end
