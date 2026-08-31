class Character::Generator
  include SanitizesGeneratedText

  # Raised when the model keeps returning a name another character in this
  # story already has. See #generate for why this raises rather than renaming.
  class DuplicateNameError < StandardError; end

  # Enough attempts that a one-off collision costs a short follow-up on the
  # same conversation, few enough that a story anchored on one name fails fast.
  MAX_NAME_ATTEMPTS = 3

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
  #
  # The cast list in the prompt asks the model not to reuse a name, but that is
  # an instruction, not a constraint -- so a collision is checked here and the
  # model is asked again on the SAME conversation, which costs a two-line
  # follow-up rather than a fresh 2,700-token prompt.
  #
  # After MAX_NAME_ATTEMPTS this raises rather than renaming the character in
  # code. Three independent samples landing on the same name means the story
  # itself is anchored on it, and a character silently renamed here would still
  # have a backstory that calls them by the old name. Callers already handle a
  # generator raising; a quietly wrong record is the harder failure to notice.
  def generate
    agent = BaseAgent.new.with_instructions(system_prompt)
    prompt = @character_generation_prompt
    taken = nil

    MAX_NAME_ATTEMPTS.times do
      character = build_from(agent.with_schema(Character::Schema).ask(prompt).content)

      return character unless name_taken?(character.fullname)

      taken = character.fullname
      prompt = retry_prompt(taken)
    end

    raise DuplicateNameError,
          "#{story.title.inspect} already has a character named #{taken.inspect}, " \
          "and #{MAX_NAME_ATTEMPTS} attempts did not produce a different name"
  end

  # Asked on the same conversation as the first attempt, so the model still has
  # the whole character it just wrote and only has to change the name.
  def retry_prompt(taken_name)
    <<~PROMPT
      The name #{taken_name.inspect} already belongs to another character in
      this story. Generate the character again with a different full name.
      Everything else about them can stay as you wrote it.
    PROMPT
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

      ## Characters This Story Already Has
      Do not reuse any of these names, and do not write this person again.
      #{existing_cast}

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

  private

  # Name, nickname and race -- enough to tell the model who is taken and who
  # this new person has to be different from. It used to carry each existing
  # character's full `personality` as JSON, which cost ~116 tokens per cast
  # member on every generation and grew for the life of the story; this is
  # ~15. The names in it are the model's cue; Character's uniqueness
  # validation and #generate's retry are what actually enforce them.
  def existing_cast
    lines = story.characters.includes(:race).map do |character|
      "#{character.fullname} (#{character.nickname}), #{character.race&.name}"
    end

    lines.join("\n").presence || "None yet."
  end

  def build_from(content)
    character = Character.new(story: story, race: race, age: age, sex: sex)

    character.fullname = sanitize_string(content["fullname"])
    character.nickname = sanitize_string(content["nickname"])
    character.personality = sanitize_string(content["personality"])
    character.appearance = sanitize_string(content["appearance"])
    character.likes = sanitize_string(content["likes"])
    character.dislikes = sanitize_string(content["dislikes"])
    character.fears = sanitize_string(content["fears"])
    character.backstory = sanitize_string(content["backstory"])

    character
  end

  # Asked of the database rather than the in-memory association, so an unsaved
  # character built on this story cannot collide with itself.
  def name_taken?(fullname)
    return false if fullname.blank? || story.id.nil?

    Character.where(story_id: story.id).where("LOWER(fullname) = ?", fullname.downcase).exists?
  end
end
