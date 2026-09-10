# THE LAST PARAGRAPH OF A GAME, WRITTEN BY THE NARRATOR AND OWNED BY THE
# ENGINE.
#
# THE CAPTAIN'S CALL 5, 2026-09-06, and it is his one departure from the
# direction report's recommendation: *the narrator writes a real ending, told
# the conclusion.* His Q4 on the same board asked for an engine-authored one.
# Those are one paragraph asked about on two boards, and the project's own rule
# splits them without overruling either:
#
#   THE ENGINE OWNS THE FACT -- `Playthrough::Arc#conclude!` decides which
#   `Quest::Outcome` this game reached, writes `playthrough_endings`,
#   `playthroughs.ended_at` and the closing `Scene`, and stops the game. None of
#   that is here and none of it may move here. THE GAME BEING OVER IS NEVER A
#   MODEL'S DECISION.
#
#   THE NARRATOR RENDERS IT -- this class, told the reached outcome's own
#   sentence as a fact the engine is holding (`Playthrough::Moment`, in the same
#   place and the same shape as the next-open-step line), and asked for the
#   prose.
#
#   THE STORED SENTENCE IS THE FALLBACK, the way `Playthrough::Refusal#text` is
#   one: it is ALREADY on the row before this class is called, so every way this
#   call can fail leaves the player an ending. A model that declines on the
#   final turn of a forty-turn game must not cost somebody the end of their
#   story.
#
# --- ONE SCENE, RENDERED IN PLACE, AND WHY IT IS NOT A SECOND ONE ----------
#
# THE DECISION, because the alternative was real and was rejected: the narrated
# ending REPLACES the description of the closing `Scene` the arc already wrote.
# It is not a scene that follows it.
#
# A FOLLOWING SCENE WOULD PUT TWO LAST PARAGRAPHS IN THE LOG -- the engine's
# sentence and then the prose about it -- on the one turn where the game has
# exactly one thing left to say. And it would make the fallback visible as a
# defect: a player whose model answered would read the sentence twice over, once
# plainly and once well.
#
# SO THE ROW IS WRITTEN FIRST AND RENDERED SECOND, which is also what makes the
# fallback free of any branch: there is no path on which the closing Scene has
# no words, because the words are on it before this class exists.
#
# WHOSE WORDS THEY ARE IS RECORDED ON THE ROW, and that is what keeps
# `Scene::ENGINE_AUTHORED` honest rather than approximately right. `conclude` is
# the engine's own last paragraph and stays in that list for ever; `ending` --
# `Scene::NARRATED_ENDING` -- is this class's, and is ordinary narration to
# `Story::Audit`, `Eval::Richness` and `Story::Scoreboard`, exactly as a
# `throw`'s prose is. One row, two labels, and the label is written by whoever
# wrote the words. See `Scene::ACTIONS`.
#
# AND THE ENGINE'S SENTENCE SURVIVES THE PARAGRAPH THAT REPLACED IT: it stays
# in `summary`, which is where `Scene.recap_line` reads a turn's one line of
# memory from anyway. Nothing has to go looking for what the engine said.
#
# --- WHAT THE PROSE MAY NOT DO, AND WHO STOPS IT ---------------------------
#
# NOTHING MOVES ON THIS TURN. The arc wrote an outcome, an `ended_at` and this
# Scene; it moved nobody, gave nothing away and opened no door. So the
# instructions say so -- inform the prose -- and the records are what they were
# either way -- gate the state. `Story::Audit` reads the paragraph against them
# afterwards, which is the third part of the same rule, and it can only do that
# because the row is labelled as narration rather than skipped as engine copy.
#
# --- WHERE IT RUNS, AND THE ONE PLACE IT MUST NOT --------------------------
#
# `Playthrough::Turn#play`, after `Playthrough::Arc#run!` has answered and
# OUTSIDE the transaction that wrote the ending: SQLite gives one writer, and a
# provider round trip inside that transaction would hold the lock for the length
# of a paragraph.
#
# AND NOT IN `Playthrough::Mechanics#answered_by_the_world`, which is the same
# step of the same turn for the offline sweep. That mode makes no model call at
# all, so what a sweep walks to is the FALLBACK -- the stored sentence, on the
# row, asserted by `lib/engine_sweep/scripts/an-ending-with-words.yml`. The one
# guarantee this whole design rests on is the one an offline walk can prove.
class Scene::Ending
  # `Chat::PURPOSES`' own word for this pass, which is also the word a bench
  # would group a case by and the one `BaseAgent` writes on the conversation.
  PURPOSE = "ending".freeze

  # KEPT SHORT, for `Scene::Narrator::INSTRUCTIONS`' reason: every token here is
  # time-to-first-token, and this is the one paragraph in the game the player is
  # waiting on with nothing left to type.
  #
  # IT IS TOLD THE ENDING AND ASKED TO WRITE IT, which is the whole of what
  # makes this a different call from a narrated turn. `Playthrough::Moment`
  # deliberately withholds the conclusion from every other prose pass -- telling
  # a model how the story ends invites it to write toward an ending the engine
  # has not recorded -- and that objection is spent here: the engine HAS
  # recorded it, and the sentence in the prompt is the record.
  #
  # A NEW PROMPT, SO IT IS A NEW VERSION. It sends its own system message and
  # `Playthrough::PromptVersion.for_chat` digests it like any other; the
  # narrator's own instructions are untouched by this file, which is what keeps
  # the checked-in prompt-bench baseline a baseline. See EVALUATION.md.
  INSTRUCTIONS = <<~PROMPT.freeze
    You are the narrator of a text adventure, and this is the last thing the
    player will ever read of this story. The game is over.

    The prompt states the ending the game reached. It is a fact, already
    recorded: write THAT ending and no other. Do not end the story a different
    way, do not leave it open, and do not say what happens next.

    Write it in the second person, present tense, addressing the player as
    "you", in one short paragraph of prose -- two at the most.

    Nothing moves as it is written: the player stays where they are, nothing
    changes hands, nobody arrives and nobody leaves. The ways out of here, the
    people present and what the player carries are listed in the prompt; do not
    add a way out, a person or a possession that is not on those lists. Never
    break character, never offer the player a menu, and never mention that you
    are an AI or a narrator.
  PROMPT

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # Renders `conclusion` -- `Playthrough::Arc::Concluded`, the outcome this game
  # reached and the Scene its sentence is already on -- and returns that Scene.
  # Chunks of prose are yielded as they arrive, exactly as `Scene::Narrator`
  # yields them, so the browser streams the ending the way it streams a turn.
  #
  # IT RETURNS THE SCENE ON EVERY PATH, and that is the API rather than an
  # accident: the caller has an ending to show whatever this call did.
  def narrate!(conclusion, &block)
    return Playthrough::Command::Journal.read("ending_scene") if Playthrough::Command::Journal.saved?("ending_scene")

    scene = conclusion.scene
    prose = ask(conclusion, &block)
    return scene if prose.blank?

    Playthrough::Command::Journal.commit("ending_scene") do
      scene.update!(description: prose, resolved_action: Scene::NARRATED_ENDING)
      scene
    end
    agent.attribute_to!(scene)
    scene
  end

  private

  attr_reader :playthrough

  # THE CALL, AND EVERY WAY IT CAN FAIL ANSWERS THE SAME THING: nil, which is
  # the stored sentence standing. `BaseAgent` has already rotated whatever it
  # rotates for by the time anything reaches here, so this is the end of the
  # line and not a place to retry from.
  #
  # A CRISIS RESPONSE IS CAUGHT HERE RATHER THAN LEFT TO THE JOB, unlike a
  # narrated turn's: `NarrationJob` answers `BaseAgent::CrisisResponseError` by
  # showing the safety notice INSTEAD of the turn, and doing that on this turn
  # would take the ending off the page along with the suppressed text. The
  # notice is for prose the app will not show; the ending is a record the app
  # owes the player, and the two must not be traded for one another.
  #
  # AND A PARAGRAPH THAT STOPS MID-SENTENCE IS NOT KEPT, which is the one
  # judgement in this file. `Scene::Narrator` keeps a truncated turn -- half a
  # paragraph about a door is better than no answer, and the player can type
  # again. Nobody types again after this one. `Story::Audit::Prose.truncated?`
  # is the project's one reader of that question and it is read, not
  # reimplemented.
  #
  # WHAT IT COSTS THE MEASUREMENT, stated because it is a real cost: a fallback
  # leaves no narration on the row, so the ending pass's own failure rate cannot
  # be read back out of `scenes`. It is in the log, and in the bench when there
  # is one.
  # THE BLOCK IS HANDED TEXT AND NOT A CHUNK, which is `Scene::Narrator#narrate`'s
  # own contract and not a detail: `NarrationJob` appends what it is yielded
  # straight into a buffer it broadcasts, so a consumer handed a provider's chunk
  # object would broadcast the object's inspection. The two prose passes a player
  # reads on this turn stream through one block and must yield one thing.
  def ask(conclusion, &block)
    text = agent.ask(prompt_for(conclusion)) { |chunk|
      part = chunk.content.to_s
      block&.call(part) unless part.empty?
    }.content.to_s.strip
    return nil if text.blank?
    return nil if Story::Audit::Prose.truncated?(text)

    text
  rescue StandardError => e
    Rails.logger.warn { "The ending fell back to the stored sentence: #{e.class}: #{e.message}" }
    nil
  end

  def agent
    @agent ||= BaseAgent.new(INSTRUCTIONS, purpose: PURPOSE, playthrough: playthrough)
  end

  # THE MOMENT, AND THEN THE ASK. One `Playthrough::Moment` and not a second
  # builder, for the reason that class exists: the two prose passes a player
  # reads one after the other on this turn must not disagree about where they
  # are standing.
  def prompt_for(conclusion)
    <<~PROMPT
      #{Playthrough::Moment.new(playthrough, ending: conclusion.outcome).narration_context}

      Write the ending.
    PROMPT
  end
end
