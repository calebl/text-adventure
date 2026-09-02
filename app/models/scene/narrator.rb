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
  # The persist happens in an `ensure` so a turn that is cut off keeps whatever
  # was written, rather than leaving the player to reload and retype. That used
  # to be the browser's doing -- `ActionController::Live` raised
  # ClientDisconnected and killed the generation. `NarrationJob` holds no
  # connection, so a closed tab no longer reaches this at all; what is left for
  # the `ensure` is a model that stops mid-sentence, which is why it stays.
  # `fact` is SOMETHING THE APP HAS ALREADY DONE, in its own words -- the row is
  # written and this is only the sentence about it (`Playthrough::Turn#take_item`).
  # It goes in as a statement rather than a request, because the narrator has no
  # say in whether it is true. If the prose contradicts it the record still
  # stands, which is the point; `Story::Audit` is what notices.
  #
  # A RESPONSE THE GAME WILL NOT KEEP IS NOT PERSISTED, which is the other half
  # of `BaseAgent`'s refusal check. The `ensure` below saves whatever arrived,
  # and that is right for a call that died mid-sentence and wrong for a model
  # that declined: saving a refusal would put "I'm not going to narrate that"
  # in the turn log as the scene, and a world that keeps what it generates
  # would keep it. `BaseAgent::UnusableResponseError` is the one exception to
  # the `ensure`, and it covers both a refusal that exhausted the rotation and a
  # crisis response, which must not be kept for a different reason.
  #
  # `keep` IS THE LAST ATTEMPT'S CONTENT, NOT THE STREAM. The block is handed
  # the chunks of every attempt -- `BaseAgent#ask` restarts the stream when it
  # rotates -- so the accumulated buffer holds a refusal AND its replacement
  # end to end, and saving that would file both as one scene. `response.content`
  # is what the model that actually answered wrote. (The player may still have
  # watched the first attempt arrive; the end-of-turn `#turn_log` replace is
  # what takes it off the page, since the log renders the persisted scene.)
  def narrate(command, fact: nil, &block)
    streamed = +""
    keep = nil

    begin
      keep = agent.ask(prompt_for(command, fact)) do |chunk|
        part = chunk.content.to_s
        next if part.empty?

        streamed << part
        block&.call(part)
      end.content.to_s
    rescue BaseAgent::UnusableResponseError
      raise
    rescue
      # Died mid-stream. Keep whatever prose arrived -- this is what the
      # `ensure` has always been for.
      keep = streamed
      raise
    ensure
      @scene = persist(keep)
    end

    @scene
  end

  private

  attr_reader :playthrough

  # Memoized, unlike before: the conversation it writes has to still be reachable
  # after `#narrate` returns, so #persist can stamp its messages with the Scene.
  #
  # PROSE, so it asks for the prose model order rather than the app-wide
  # default: this is the text a player reads, and minimax writes about 1.7x as
  # much of it. Named at the call site on purpose -- there is no policy layer
  # deciding this, so `grep prose_model_options` finds every caller.
  # See BaseAgent::PROSE_MODEL_IDS.
  def agent
    @agent ||= BaseAgent.new(INSTRUCTIONS,
                             model_options: BaseAgent.prose_model_options,
                             purpose: "narration", playthrough: playthrough)
  end

  def prompt_for(command, fact = nil)
    <<~PROMPT
      #{context}
      #{"\nWhat has ALREADY happened, recorded by the game: #{fact}\nNarrate it as done. Do not contradict it and do not undo it.\n" if fact.present?}
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

    # EVERYTHING BEFORE THAT, in one line per turn. The narrator used to see
    # exactly one scene, so a playthrough had a memory one turn deep and the
    # only way to make it deeper was to paste in more full descriptions -- which
    # is what puts a long game outside the context window. `Playthrough#recap`
    # spends the summaries `Scene::Generator` has been writing on every arrival
    # instead, under a fixed character budget: several turns of memory for about
    # what one more description would have cost. See Playthrough::RECAP_BUDGET.
    if (recap = playthrough.recap)
      parts << "Earlier, in order:\n#{recap}"
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
      story_timestamp: playthrough.story_time_after("action")
    )
    agent.attribute_to!(scene)
    playthrough.update!(current_scene: scene)
    scene
  end
end
