# WHERE THE ARC IS READ, ONE TURN AT A TIME -- and it is the app reading its own
# records, never a model being asked what happened.
#
# THE STANDING CONSTRAINT, applied to plot. The direction report weighed three
# ways of deciding a beat had been reached and only one survives: asking the
# narrator by tool call is a call a model may silently not make; a second model
# pass costs 2.4-7.3 s to answer *"no beat reached"* on almost every turn; and
# the app reading four record predicates costs about four milliseconds and no
# tokens at all. So a beat is reached because the records say so.
#
# --- the four predicates, and why each is asked of a PLAYTHROUGH ------------
#
#   reach_location  the party is standing in the room. Read off
#                   `playthrough.current_location_id`, which is an attribute
#                   already in hand -- no query at all.
#   speak_to        this turn's `Scene` carries an `Interaction` with them.
#                   `Playthrough::Turn#talk_to` writes both in one statement, so
#                   the scene the turn just produced is the honest per-game
#                   record of who was spoken to.
#   hold_item       this game's own copy of the thing is in the party's hands.
#                   `Playthrough#carried` is the ONE reader of that closed set
#                   and this comes through it, so the arc and the classifier
#                   cannot come to disagree about what the player is holding.
#   time_passed     this game's clock has passed the story's start by the step's
#                   own minutes. `Playthrough#story_now` and not `Story#clock`:
#                   the story's clock is the high-water mark across every
#                   playthrough, and a beat is one player's.
#
# EVERY ONE OF THEM IS A QUESTION ABOUT ONE GAME, which is why they live here
# and not on `Quest::Step`. What the world says a step IS belongs to the world;
# whether somebody has reached it belongs to the game.
#
# --- where it runs, and the three rules it inherits by running there --------
#
# `Playthrough::Turn#play` after the tolls are claimed and the world has
# answered, beside `Playthrough::Riposte` and `Playthrough::Hazards`; and
# `Playthrough::Mechanics#answered_by_the_world`, in the same place, so the
# browser and the offline sweep cannot come to disagree about whether an arc
# moved. All three of that step's rules are right for this:
#
#   A REFUSED LINE EVALUATES NOTHING -- a refused line writes nothing, so it
#   cannot reach a beat. The captain's ruling of 2026-09-04.
#   AN ENGINE-VIEW INSTRUMENT EVALUATES NOTHING -- `stats`, `check`, a read-out
#   is not a turn.
#   IT RUNS ON EVERY LINE THE ENGINE PLAYED -- a look, a read, a move. A player
#   who walks into the right room and then stands there typing `look` has still
#   reached the beat, because standing there is what the step asked for.
#
# AFTER THE HAZARDS AND NOT BEFORE THEM, which is the one ordering decision here
# and it is load-bearing: a room whose hazard takes the last hit point ends the
# game on this turn, and an arc that concluded before the world had finished
# acting would hand a dead player an ending.
#
# --- what it may write, and what it must never -----------------------------
#
# IT WRITES `playthrough_beats`, `playthrough_endings`, `playthroughs.ended_at`,
# ONE `Scene`, and ONE `WorldEvent`. It writes nothing in `quests`,
# `quest_steps` or `quest_outcomes` -- the arc is the world's, exactly as a stat
# block is, and `EngineSweep::Invariants#quest_unmoved` asserts that over every
# walk.
#
# AND IT NEVER CREATES A `Location`. Growing the world toward an unbound target
# is `Quest::Deadline`'s, which runs at realization -- the moment the world
# grows -- and not on a turn.
#
# --- the ending, and why the engine writes this one paragraph ---------------
#
# THE GAME BEING OVER IS NEVER A MODEL'S DECISION. Reaching the last step of the
# main arc writes the reached outcome, `playthroughs.ended_at` and an
# engine-authored closing `Scene` -- `Scene::ENGINE_AUTHORED` gains `"conclude"`
# so `Story::Audit` and `Eval::Richness` skip it and `Story::Scoreboard` counts
# it excluded, because a smaller denominator must never read as a better rate.
#
# THE STORED SENTENCE IS NOT THE FINAL ANSWER AND IS NOT MEANT TO BE. The
# captain's Call 5 of 2026-09-06 chose *the narrator writes a real ending, told
# the conclusion*, and his Q4 on the same board chose an engine-authored one.
# Those are one paragraph asked about on two boards, and the project's own rule
# splits them without overruling either: **the engine owns the fact, the
# narrator writes the prose, the stored sentence is the fallback** the way
# `Refusal#text` is one. The prose half is `ta-quest-ending` -- a NEW narration
# prompt, so it needs cases on `rake eval:prompt` before it ships, and a model
# that refuses on the final turn of a forty-turn game must not cost the player
# their ending. What lands here is the record and the fallback; the paragraph
# replaces the sentence later and nothing else moves.
#
# --- and failure, which is not the opposite of completable ------------------
#
# A playthrough that ENDS with its arc unfinished writes a `WorldEvent` --
# *"a failed quest gets stored as an event that can have future ramifications"*,
# 2026-09-06. The event names the playthrough it happened in, because a failure
# is one game's and the stream is the story's; see `WorldEvent`. `Quest#status`
# is untouched: the world still permitted the ending, this player did not reach
# it, and `Story::Doctor`'s `quest_target_unreachable` stays fatal about the
# first while saying nothing about the second.
class Playthrough::Arc
  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # Reads every open arc against this game and writes what has become true.
  # Returns the beats it wrote, which is nothing on almost every turn.
  #
  # A STORY WITH NO ARC PAYS ONE `exists?`, which is every world in the
  # repository but one and every world generated before this shipped.
  def run!
    return [] if quests.empty?

    # THE GAME BEING OVER COMES FIRST, and it is first for the reason it is
    # first in `Playthrough::Turn#play`: nothing below can be true of a game
    # that has stopped. The world may have taken the last hit point a few lines
    # above this, on the very turn the last beat would have landed -- and a dead
    # player has not finished the arc, they have failed it.
    return record_failure! if playthrough.over?

    reached = quests.flat_map { |quest| reach_due_beats!(quest) }
    conclude!
    reached
  end

  # THE ONE LINE THE NARRATOR IS EVER TOLD ABOUT THE ARC, and the whole of what
  # `Playthrough::Moment` asks for: the next open step's own summary. The
  # captain's Call 4 of 2026-09-06.
  #
  # NEVER THE CONCLUSION AND NEVER THE WHOLE ARC. Telling a model the ending
  # invites it to write toward an ending the engine has not recorded, which is
  # the railroad by the back door and a contradiction `Story::Audit` could not
  # see. Telling it the next beat is the same shape as telling it what is lying
  # on the floor: a fact the engine owns, rendered.
  #
  # THE MAIN ARC ONLY. A side quest is discovered rather than planned, and three
  # of them in the prompt would be an outline.
  def next_step
    arc = main_arc
    return nil if arc.nil? || arc.doomed?

    arc.next_step_for(playthrough)
  end

  # WHICH ENDING THIS GAME REACHED, or nil for one still being played. The one
  # reader of that question, so the closing scene, the read-out and the sweep
  # cannot come to three different answers.
  def ending
    return nil if main_arc.nil?

    Playthrough::Ending.find_by(playthrough: playthrough,
                                quest_outcome: Quest::Outcome.where(quest_id: main_arc.id))
  end

  # WHETHER THIS TRIGGER IS TRUE RIGHT NOW, off the records. Public because
  # `rake game:mechanics` and the sweep both want to state a step's state
  # without writing one, and because a predicate nothing can ask is a predicate
  # nothing can check.
  #
  # AN UNBOUND STEP IS NEVER REACHED, whatever the world happens to contain: the
  # arc waits for a ROW, and a name that matches nothing is a step whose target
  # has not been grown yet. `time_passed` is the exception and the only one --
  # it wants no row, so it is bound by construction.
  def reached?(step)
    return false if step.nil?
    return elapsed?(step) if step.time_passed?
    return false if step.unbound?

    case step.trigger_kind
    # THE ROOM AND NOT THE BUILDING -- `Quest::Step#target_room` is the one
    # reader of which room a step means, and a step that named a place with an
    # inside means its entry room, because nobody ever stands in a container.
    when "reach_location" then standing_in?(step.target_room&.id)
    when "speak_to" then spoke_to?(step.target_id)
    when "hold_item" then holding?(step.target_id)
    else false
    end
  end

  private

  # The story's arcs that are still open, main and side, in a stable order.
  # A `doomed` arc -- a seed file's authored tragedy -- is deliberately not one:
  # its beats are not reachable by design, and evaluating them every turn would
  # be paying for an answer the world already gave.
  def quests
    @quests ||= playthrough.story.quests.open_arcs.includes(:steps, :outcomes).order(:id).to_a
  end

  def main_arc = @main_arc ||= quests.detect(&:main?)

  def reach_due_beats!(quest)
    quest.steps.filter_map do |step|
      next if reached_ids.include?(step.id)
      next unless reached?(step)

      beat = Playthrough::Beat.reach!(playthrough, step, at: playthrough.story_now)
      reached_ids << step.id
      beat
    end
  end

  # WHICH BEATS THIS GAME ALREADY HAS, read ONCE per turn. Held rather than
  # asked per step because a turn asks about every step of every open arc, and
  # a query per step would make the arc's cost grow with the arc.
  def reached_ids
    @reached_ids ||= Playthrough::Beat.where(playthrough: playthrough).pluck(:quest_step_id)
  end

  # THE END, WRITTEN ONCE, IN ONE TRANSACTION -- the outcome, the closing scene
  # and `playthroughs.ended_at` together. Half an ending is a game that is over
  # with nothing to read, or a paragraph in a game that carries on.
  def conclude!
    arc = main_arc
    return nil if arc.nil? || playthrough.over? || !arc.finished_by?(playthrough)

    outcome = arc.default_outcome
    # AN ARC WITH NO ENDING TO REACH ends nothing, and says so rather than
    # inventing a sentence. `Story::Doctor`'s `quest_without_an_outcome` is
    # what reports the world; this is what stops the app closing a game with
    # nothing to show for it.
    return nil if outcome.nil?

    at = playthrough.story_now

    Playthrough.transaction do
      Playthrough::Ending.create!(playthrough: playthrough, quest_outcome: outcome, reached_at: at)
      scene = write_conclusion!(outcome, at: at)
      playthrough.update!(current_scene: scene)
      playthrough.end!(at: at)
    end
  end

  # THE CLOSING SCENE, AND THE ENGINE WROTE THE WORDS. `resolved_action` is
  # `"conclude"` -- in `Scene::ACTIONS` because the engine may record it, and in
  # `Scene::ENGINE_AUTHORED` because the engine wrote it, which are two
  # different questions that list answers separately on purpose.
  def write_conclusion!(outcome, at:)
    Scene.create!(
      story: playthrough.story,
      location: playthrough.current_location,
      previous_scene: playthrough.current_scene,
      description: outcome.summary,
      summary: outcome.summary,
      story_timestamp: at,
      resolved_action: "conclude"
    )
  end

  # A GAME THAT STOPPED SHORT OF ITS OWN ENDING, written to the one event
  # stream. Idempotent on the (story, playthrough, source) triple, so a line
  # typed into a finished game -- which `Playthrough::Turn#play` refuses before
  # it reaches here anyway -- could not write a second one.
  #
  # NOTHING FOR A GAME THAT FINISHED, and nothing for a world whose arc has no
  # steps at all: an arc nobody could start is not an arc somebody failed.
  def record_failure!
    arc = main_arc
    return [] if arc.nil? || arc.steps.empty? || ending.present?
    return [] if failure_recorded?

    WorldEvent.create!(
      story: playthrough.story,
      playthrough: playthrough,
      source: WorldEvent::QUEST,
      occurred_at: playthrough.ended_at || playthrough.story_now,
      summary: "#{arc.title} was left unfinished: #{describe_progress(arc)}."
    )

    []
  end

  def failure_recorded?
    WorldEvent.exists?(story: playthrough.story, playthrough: playthrough, source: WorldEvent::QUEST)
  end

  # HOW FAR THIS GAME GOT, in the app's own words and out of the records. Named
  # rather than counted, because a step's `summary` is the sentence a person
  # wrote about it and a number is not a ramification anything could read.
  def describe_progress(arc)
    step = arc.next_step_for(playthrough)
    return "every beat was reached and the ending was never written" if step.nil?

    "it stopped at #{step.summary}"
  end

  def standing_in?(location_id) = location_id.present? && playthrough.current_location_id == location_id

  # THE TURN'S OWN SCENE, which after a talk is the scene `#talk_to` just wrote
  # and set `current_scene` to. A turn that spoke to nobody carries no
  # interaction, so this is one indexed read that answers false on every other
  # kind of turn.
  def spoke_to?(character_id)
    scene = playthrough.current_scene
    return false if scene.nil?

    Interaction.exists?(scene_id: scene.id, character_id: character_id)
  end

  # THIS GAME'S OWN COPY OF THE THING, IN THE PARTY'S HANDS. Through
  # `Playthrough#carried`, which is the one reader of that closed set, and
  # keyed on `template_id` -- the arc is bound to the WORLD's row (see
  # `Quest::Binder`) and what a player picks up is their copy of it.
  def holding?(template_id) = playthrough.carried.exists?(template_id: template_id)

  # THIS GAME'S CLOCK, AGAINST THE STORY'S OWN BEGINNING. Not `Story#clock`,
  # which is the high-water mark across every playthrough -- a second player
  # would otherwise start a world already past its own deadlines.
  def elapsed?(step)
    start = playthrough.story.start_time
    return false if start.nil? || step.minutes.nil?

    playthrough.story_now >= start + step.minutes.minutes
  end
end
