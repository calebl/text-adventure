# Narrates one turn: takes what the player typed, streams the prose back, and
# keeps the finished text as a Scene.
#
# DELIBERATELY UNSCHEMA'D. `AGENTS.md` requires structured output on every LLM
# call, and this is the one documented exception. Structured output and token
# streaming are mutually exclusive here: with a schema attached the model emits
# JSON, so the player watches `{\n  "description": "The doorway...` arrive a
# character at a time. Narration is the only thing a player reads live, so it
# streams and stays plain; everything that populates a record stays schema'd.
# Do not "fix" this by adding a schema.
class Scene::Narrator
  # Kept short on purpose. `Character#interaction_instructions` inlines the
  # whole universe (~3,200 tokens) and every one of those tokens is
  # time-to-first-token, which the player experiences as dead air.
  INSTRUCTIONS = <<~PROMPT.freeze
    You are the narrator of a text adventure. Write in the second person,
    present tense, addressing the player as "you". Describe what happens in
    response to what they did, in one or two short paragraphs of prose.

    Never break character, never offer the player a numbered menu, and never
    mention that you are an AI or a narrator. Do not invent an exit to
    somewhere the player has not been told about. If the player tries
    something impossible, narrate the failure rather than refusing.
  PROMPT

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # Streams the narration for `command`, yielding each chunk of text as it
  # arrives, and returns the persisted Scene.
  #
  # The persist happens in an `ensure` so a browser that closes mid-stream --
  # `ActionController::Live` raises ClientDisconnected and kills the generation
  # -- still keeps whatever was written. Otherwise the player reloads to find
  # their turn gone and has to retype it.
  def narrate(command, &block)
    text = +""

    begin
      agent.ask(prompt_for(command)) do |chunk|
        part = chunk.content.to_s
        next if part.empty?

        text << part
        block&.call(part)
      end
    ensure
      @scene = persist(text)
    end

    @scene
  end

  private

  attr_reader :playthrough

  def agent
    BaseAgent.new(INSTRUCTIONS)
  end

  def prompt_for(command)
    <<~PROMPT
      #{context}

      The player types: #{command}

      Narrate what happens.
    PROMPT
  end

  def context
    story = playthrough.story
    parts = [ "Story: #{story.title} (#{story.genre})", "Premise: #{story.summary}" ]

    if (location = playthrough.current_location)
      parts << "The player is in #{location.name}: #{location.description}"
    end

    if (character = playthrough.character)
      parts << "The player is #{character.fullname}."
    end

    if (previous = playthrough.current_scene)
      parts << "What just happened: #{previous.description}"
    end

    parts.join("\n\n")
  end

  # Blank narration is not worth a record -- that is a failed turn, and saving
  # it would fail the Scene description validation anyway.
  def persist(text)
    return if text.blank?

    scene = Scene.create!(
      story: playthrough.story,
      location: playthrough.current_location,
      previous_scene: playthrough.current_scene,
      description: text,
      story_timestamp: Time.current
    )
    playthrough.update!(current_scene: scene)
    scene
  end
end
