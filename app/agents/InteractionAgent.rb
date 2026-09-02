# Talking to a character, in two passes.
#
# The first pass is the CHARACTER: it answers under `Interaction::Schema` with
# what they thought, felt and did on either side of responding. The second is a
# NARRATOR that turns that structured answer into second-person prose. Neither
# is useful without the other, and the hand-off between them is by string key,
# so `Interaction::Schema`'s field names are a hard contract with
# `#narrator_prompt`.
#
# Both passes go through `BaseAgent`, so both inherit its model fallback and
# the first inherits `verify_schema_honored!` -- a character sheet that came
# back as prose used to poison the narrator prompt with the word "pre_thought"
# rather than failing. This class used to build bare `RubyLLM::Chat` objects
# pinned to `cognitivecomputations/dolphin-mixtral-8x22b`, a model that resolves
# in neither the bundled registry nor the seeded `models` table.
#
# The narrator pass is UNSCHEMA'D and streams, which is the same documented
# exception `Scene::Narrator` carries and for the same reason: it is prose the
# player watches arrive, and a schema would have them watch JSON arrive
# instead. What the game keeps out of this turn -- the five fields of the
# character's reaction -- is structured; only the part a human reads is not.
class InteractionAgent
  # The talk path is a generated-string path like any other, and it used to be
  # the ONE that skipped this seam -- so PR #76's `max_length` truncation guard,
  # installed here precisely because it "can reach any max_length field in any
  # schema in the app", covered every field the app writes except the six a
  # conversation writes every turn. See #reaction_fields.
  #
  # The guard is applied through `BaseAgent#ask`'s `verify:` seam rather than to
  # the response it returns, so a truncated sheet is a failed call that rotates.
  # See #ask, and the truncation note in `BaseAgent`.
  include SanitizesGeneratedText

  # What one exchange produced. `reaction` is the character's five structured
  # fields, keyed exactly as `Interaction::Schema` names them so it can be
  # handed straight to `Interaction.create!`; `narration` is the prose.
  #
  # Both are returned because both are kept: the caller writes the `Scene` the
  # player reads from one and the `Interaction` the character felt from the
  # other. Returning only the prose is why nothing in this app had ever created
  # an `Interaction` row.
  Exchange = Data.define(:reaction, :narration)

  attr_reader :character, :playthrough, :character_instructions, :narrator_instructions

  # `playthrough` is what makes the character pass a CONVERSATION rather than a
  # series of unrelated questions -- see #character_agent. It is optional so
  # that anything holding only a character still works, and such a caller simply
  # gets a character with no memory, which is what every caller got before.
  def initialize(character, playthrough: nil)
    @character = character
    @playthrough = playthrough
    @character_instructions = character.interaction_instructions
  end

  # Asks the character, then narrates their answer.
  #
  # A block is streamed the narration and nothing else -- not the structured
  # pass in front of it -- and it is yielded TEXT rather than the chunk objects
  # RubyLLM hands back, which is the same block contract `Scene::Narrator#narrate`
  # offers. The game loop forwards one block to both, so they have to agree.
  def ask(user_input, &block)
    # THE SANITIZER RUNS INSIDE `BaseAgent#ask`, NOT AFTER IT, and that is the
    # whole of what `verify:` is for. `#reaction_fields` is where a field cut off
    # at its cap is rejected; called out here, on the returned response, it
    # raised past the rotation, so a model that truncates cost the player the
    # turn while a model that ignored the schema got a second try. Handed in, the
    # raise happens inside the attempt loop: the attempt is rewound out of the
    # character's durable conversation and the next model is asked. See the
    # truncation note in `BaseAgent`.
    #
    # The lambda keeps what the SURVIVING attempt produced -- a rotated-away
    # attempt's fields are overwritten by the retry's, and a call that never
    # succeeds raises rather than returning -- so `fields` is only ever read
    # after an attempt that passed the check.
    fields = nil
    reaction = character_agent.ask(
      character_prompt(user_input),
      verify: ->(content) { fields = reaction_fields(content) }
    ).content
    Rails.logger.debug { "Character response: #{reaction}" }

    # AND BEFORE THE NARRATOR PASS, deliberately: the check above has already
    # run by the time `#ask` returns. The narrator's whole job is to write fluent
    # prose over whatever it is handed, so a fragment that gets this far is a
    # fragment no reader can ever see. Failing first costs one wasted call
    # instead of two and a turn the player has already read.
    @narrator_instructions = narrator_prompt(user_input, reaction)
    narration = narrator_agent.ask(@narrator_instructions) do |chunk|
      part = chunk.content.to_s
      block.call(part) if block && !part.empty?
    end.content

    Exchange.new(reaction: fields, narration: narration.to_s)
  end

  # THE ONE CONVERSATION IN THE APP THAT IS PICKED UP AGAIN. Every other agent
  # here is stateless by design -- it rebuilds its context from records on each
  # call -- but a person who cannot remember the sentence you said a moment ago
  # is not somebody you are talking to. `Chat.conversation_with` finds the chat
  # this playthrough already has with this character, so the exchange continues
  # across turns and across a server restart.
  #
  # It is BOUNDED, and that is not optional: RubyLLM replays every persisted
  # message, `character_instructions` already inlines the whole universe, and the
  # local models run in a 4,096-token window. `Chat#prune_history!` trims the
  # replay to `Chat::HISTORY_EXCHANGES` when the conversation is picked up. What
  # falls off is not forgotten -- `Interaction` keeps every exchange in full.
  def character_agent
    @character_agent ||= BaseAgent.new(
      purpose: Chat::CHARACTER,
      playthrough: playthrough,
      character: character,
      chat: Chat.conversation_with(character, playthrough)
    ).with_instructions(character_instructions).with_schema(Interaction::Schema)
  end

  # No instructions: everything the narrator needs is in the prompt, and the
  # character sheet already went to the pass that needed it. Repeating it here
  # invites the narrator to recite biography instead of narrating the moment.
  #
  # And no history either: this pass renders one structured answer into prose,
  # so replaying the last one would only invite it to narrate that instead.
  def narrator_agent
    @narrator_agent ||= BaseAgent.new(purpose: "interaction-narration", playthrough: playthrough)
  end

  # Stamps both passes' messages with the turn they produced. Two agents, one
  # turn: the character's own conversation runs on and the narration is thrown
  # away, but both were paid for here.
  def attribute_to!(scene)
    @character_agent&.attribute_to!(scene)
    @narrator_agent&.attribute_to!(scene)
  end

  def character_prompt(user_input)
    <<~INTERACTION_PROMPT
      What is your reaction when
      The user input is: #{user_input}
    INTERACTION_PROMPT
  end

  # Named `narrator_prompt` rather than `narrator_instructions`: the reader on
  # line 1 used to be shadowed by a two-argument method of the same name, so
  # the `@narrator_instructions` set during `ask` was unreachable and calling
  # the reader raised on arity.
  def narrator_prompt(user_input, character_response)
    fields = reaction_fields(character_response)

    <<~NARRATOR_PROMPT
      The user input is: #{user_input}
      #{character.fullname}'s internal and external thoughts and feelings are:
      pre_thought: #{fields[:pre_thought]}
      pre_feeling: #{fields[:pre_feeling]}
      action: #{fields[:action]}
      post_thought: #{fields[:post_thought]}
      post_feeling: #{fields[:post_feeling]}

      The interaction should be written in the second person, from the perspective of the user. Refer to the user as "you".
      Refer to the character by their first name or nickname.

      The response should be concise and to the point. Have #{character.fullname} (the character) act according to their personality
      and their thoughts and feelings. Do not be too verbose. Do not respond with details of the character's
      backstory. Only use the information provided in the character's backstory to understand their personality.
      Do not make up information about the character that is contradictory to their backstory.

      #{pronoun_rule}

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

  private

  # The six fields, symbol-keyed and never nil, so the prompt reads a missing
  # field as blank and `Interaction.create!` gets exactly the columns it wants.
  #
  # AND THE ONE SEAM BOTH CONSUMERS SHARE. The narrator prompt and the
  # `Interaction` row are built from this same hash, so sanitizing here is what
  # makes them agree: a field the guard rejects reaches neither, where a check
  # on the record alone would still have let the fragment shape the prose.
  # Each field is handed its own schema cap, which is what arms the truncation
  # check -- see `SanitizesGeneratedText::TruncatedTextError`.
  def reaction_fields(character_response)
    response = character_response.presence || {}

    Interaction::Schema.required_properties.to_h do |field|
      [
        field.to_sym,
        sanitize_string(response[field.to_s], max_length: Interaction::Schema.max_length_for(field))
      ]
    end
  end

  # A character's pronouns are their own, so the prompt STATES them rather than
  # handing the model a label and a rule to apply -- and it states nothing else.
  # The narrator needs the pronouns; naming a gender alongside them only gives
  # it something to make an issue of, and it is no more told that a character is
  # trans than it is told that a character is cis.
  #
  # `Character::PRONOUNS` is the table, because pronouns are a fact about the
  # person rather than about this agent, and every other prompt that needs them
  # should read the same answer. It raises on a sex it has no entry for rather
  # than falling back to they/them: a silent default is exactly how `transgender`
  # went unnoticed with no rule of its own, quietly they/them-ing people who use
  # she/her or he/him. CharacterTest pins that the table covers the whole enum.
  def pronoun_rule
    "Refer to #{character.fullname} as #{character.pronouns}. Use those pronouns and no others."
  end
end
