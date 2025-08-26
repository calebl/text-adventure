class InteractionAgent
  attr_reader :character_instructions, :narrator_instructions
  def initialize(character)
    @character = character

    @character_chat = RubyLLM::Chat.new(
      provider: :openrouter,
      model: "cognitivecomputations/dolphin-mixtral-8x22b", # a thinking model probably
      assume_model_exists: true
    ).with_schema(Interaction::Schema)

    @character_instructions = @character.interaction_instructions

    @character_chat.with_instructions(@character_instructions)

    self
  end

  def narrator_instructions(user_input, character_response)
    <<~NARRATOR_PROMPT
      The user input is: #{user_input}
      #{@character.fullname}'s internal and external thoughts and feelings are:
      pre_thought: #{character_response["pre_thought"]}
      pre_feeling: #{character_response["pre_feeling"]}
      action: #{character_response["action"]}
      post_thought: #{character_response["post_thought"]}
      post_feeling: #{character_response["post_feeling"]}

      The interaction should be written in the second person, from the perspective of the user. Refer to the user as "you".
      Refer to the character by their first name or nickname.

      The response should be concise and to the point. Have #{@character.fullname} (the character) act according to their personality
      and their thoughts and feelings. Do not be too verbose. Do not respond with details of the character's
      backstory. Only use the information provided in the character's backstory to understand their personality.
      Do not make up information about the character that is contradictory to their backstory.

      Use pronouns according to the character's gender. #{@character.fullname} is a #{@character.sex}.
      If the character is male, use he/him/his. If the character is female, use she/her/her.
      If the character is non-binary, use they/them/their.

      The response should be 1 paragraph.


      ## Example input:
      The user input is: "What are you doing??"
      The character's internal and external thoughts and feelings are:
      pre_thought: Is the user asking a me a question? I think so. I should probably answer.
      pre_feeling: surprised, nervous
      action: The character says, "Huh?"
      post_thought: Why did I just make that noise?
      post_feeling: anxious, embarrassed

      ## Example output:
      The person turns to you, her eyes wide. It seems like you startled her.
      "Huh?" she says.
      Immediately, she shuts her eyes, apparently embarrassed by her reaction.

    NARRATOR_PROMPT
  end

  def ask(user_input)
    interaction_prompt = <<~INTERACTION_PROMPT
      What is your reaction when
      The user input is: #{user_input}

    INTERACTION_PROMPT

    response = @character_chat.ask(user_input)

    character_response = response.content

    Rails.logger.debug { "Character response: #{character_response}" }

    @narrator_instructions = narrator_instructions(user_input, character_response)

    narrator = RubyLLM::Chat.new(
      provider: :openrouter,
      model: "cognitivecomputations/dolphin-mixtral-8x22b", # a thinking model probably
      assume_model_exists: true
    )
    narration = narrator.ask(@narrator_instructions)

    narration.content
  end
end
