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
  #
  # The ways out, the people here and what the player carries are FACTS IN THE
  # PROMPT now (`Playthrough::Moment`), so the rule about exits can point at
  # them instead of at "what the player has been told" -- a thing the narrator
  # had no way to know.
  #
  # AND THE RULE ABOUT A CHANGE OF POSSESSION IS DELIBERATELY NOT HERE, which is
  # a measurement and not an oversight. PR 98's review finding F1 is real -- this
  # block forbids inventing a possession and says nothing about a possession that
  # arrived THIS TURN -- and the obvious answer was a paragraph here saying so.
  # It was written, and measured on the prompt bench: it took `take_denied` from
  # 0.833 to 0.056 with the two per-turn changes below it, and it took
  # `item_not_held` from 0.054 to 0.123, REAL at p=0.0286 (take-fix-1, 2026-09-05).
  # The rise was in the shapes the rule is not about -- read turns went from 1
  # flag to 9 over four repetitions, prose that had started retrieving things
  # from other things to read them -- because a sentence about hands in the
  # SYSTEM message is on every turn in the game, and most turns move nothing.
  #
  # So the rule went where the change is: `Playthrough::Turn#taken_fact` and
  # `#dropped_fact` say it, on the turns that moved a row, and
  # `Playthrough::Moment::Handled` marks the row in the standing lists beside
  # them. Same rule, and it is read only by a turn it is true of.
  INSTRUCTIONS = <<~PROMPT.freeze
    You are the narrator of a text adventure. Write in the second person,
    present tense, addressing the player as "you". Describe what happens in
    response to what they did, in one or two short paragraphs of prose.

    Never break character, never offer the player a numbered menu, and never
    mention that you are an AI or a narrator. The ways out of here, the people
    present and what the player carries are listed in the prompt: do not add a
    way out, a person or a possession that is not on those lists. If the
    player tries something impossible, narrate the failure rather than
    refusing.
  PROMPT

  # ONE LINE ABOUT WHAT THE PLAYER IS DOING, keyed on the intent the classifier
  # resolved. Only the intents where the narrator's job changes get one:
  # `examine` is the turn where nothing is supposed to move, and it was reaching
  # the narrator indistinguishable from `other`. A resolved `move`, `talk`,
  # `take` or `drop` never reaches this class at all, and one that resolved to
  # nothing arrives with a `fact:` instead (`Playthrough::Turn#reach_fact`).
  DOING = {
    examine: "The player is looking more closely at something that is here. " \
             "Describe it. Nothing changes hands, nobody arrives and nobody leaves."
  }.freeze

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
  # `handled` IS THE ROW THAT MOVED, and it is the other half of the same
  # sentence: the fact says what the turn DID and this says which line of the
  # standing state it did it to, so `Playthrough::Moment` can mark the daybook
  # on the carried list as the one picked up this turn rather than leaving it
  # indistinguishable from a daybook the player walked in holding. Read
  # `Playthrough::Moment::Handled` for the defect that is; a caller with no row
  # to name passes nothing and the lists read exactly as they always did.
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
  def narrate(command, fact: nil, intent: nil, handled: nil, &block)
    streamed = +""
    keep = nil

    begin
      keep = agent.ask(prompt_for(command, fact, intent, handled)) do |chunk|
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
  def agent
    @agent ||= BaseAgent.new(INSTRUCTIONS, purpose: "narration", playthrough: playthrough)
  end

  def prompt_for(command, fact = nil, intent = nil, handled = nil)
    <<~PROMPT
      #{context(handled)}
      #{"\nWhat has ALREADY happened, recorded by the game: #{fact}\nNarrate it as done. Do not contradict it and do not undo it.\n" if fact.present?}
      #{"\n#{DOING[intent]}\n" if DOING.key?(intent)}
      The player types: #{command}

      Narrate what happens.
    PROMPT
  end

  # The moment, from the records: story, room, the ways out, who is here, what
  # the player carries, what just happened and what came before. One builder
  # shared with `InteractionAgent`'s narrator pass, so the two prose passes the
  # player reads interleaved cannot disagree about where they are standing.
  def context(handled = nil)
    Playthrough::Moment.new(playthrough, handled: handled).narration_context
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
