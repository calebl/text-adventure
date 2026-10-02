# WHY THIS PLAYTHROUGH ENDED, AND THEREFORE WHAT THE PLAYER IS TOLD. One
# question, asked in one place, answered off the records.
#
# --- the bug this file is the answer to ------------------------------------
#
# `playthroughs.ended_at` says a game is over. It does not say WHY, and until
# this class existed nothing asked: the play page and `Playthrough::Refusal`
# both read `Playthrough#over?` and both reached straight for
# `Playthrough::DeathNotice`, because when that column landed death was the only
# thing that set it. `Playthrough::Arc#conclude!` is the second thing that sets
# it -- so a player who finished their story read their brand-new narrated
# ending and then, directly under it, "You are dead."
#
# The captain's ruling of 2026-09-05 on the fight UI is the rule that governs
# it: **presentation must say what actually happened.**
#
# --- THE RULE, and it is derived and never narrated ------------------------
#
# In this order, off rows and nothing else:
#
#   1. A `Playthrough::Ending` row -- the reached `Quest::Outcome`, written by
#      `Playthrough::Arc#conclude!` in the same transaction as `ended_at` --
#      means THE STORY CONCLUDED. `Playthrough::StoryOverNotice` has the words.
#   2. Otherwise, the protagonist's `Playthrough::Vitals` at zero means DEATH.
#      `Playthrough::DeathNotice` has the words, unchanged.
#
# THE ENDING WINS WHEN BOTH ARE ON RECORD, and the app cannot currently write
# that pair: `#conclude!` returns nil for a game already over and `#harm!` ends
# a game the moment it takes the last hit point, so whichever landed first
# closed the game and the other never ran. If a repaired database ever carries
# both, the arc reached its end and the body reaching zero afterwards is not
# what stopped the game.
#
# NOTHING HERE READS PROSE. Not the closing paragraph, not a scene's label as a
# substitute for the row -- *gate the state, inform the prose*: the records
# decide, and the words follow them.
#
# --- and a game that is over with NEITHER record ---------------------------
#
#   3. Otherwise the game STOPPED, and `Playthrough::StoppedNotice` has the
#      words: it says the game stopped before the story reached an ending, and
#      nothing else, because nothing else is on record.
#
# No path in the app writes that row on its own -- `Playthrough::Turn#harm!`
# and `Playthrough::Arc#conclude!` are the only writers of `ended_at` and each
# writes its own reason in the same transaction -- so what leaves one is a
# game ended by hand, a repair run against a schema older than
# `playthrough_endings`, a game with no protagonist marked ended, or a dead
# protagonist whose `Playthrough::Vitals` row is gone. `Story::Doctor`'s
# `playthrough_ended_for_no_recorded_reason` reports every one.
#
# THE OWNER'S RULING REPLACED AN EARLIER ONE. This case used to show the death
# copy, on the argument that death was the one set of words that still read
# true with nothing behind it. It does not: "you are dead" over a protagonist
# the records have alive is presentation saying what did not happen. So there
# are three sets of words, and each claims only what its records hold.
#
# --- and WHICH ENDING, and what earned it ----------------------------------
#
# *"that ending did not make any sense. I don't even understand how I
# triggered it."* The owner, 2026-09-28, after a game of The Lunar
# Cartographer closed on a paragraph about a man who was already dead. The
# notice said the story was over and nothing about why this ending, so the
# player had the prose and nothing to check it against.
#
# `#finished` is that check, and it is read off the same rows the engine
# decided on: the arc's goals in its own order, the one that was met last, and
# the reason this ending was the one reached -- the reached outcome's rule
# (`Quest::Outcome::CONDITIONS`) stated as what this game actually did. It is
# the app's words, never a model's, and it says what the records say even
# where an ending's own sentence claims more than its rule can know.
class Playthrough::EndNotice
  # THE ARC THIS GAME FINISHED, AS THE PLAYER IS TOLD IT. `goals` are the
  # step summaries in the arc's order, so goal N is the arc's step N;
  # `last_goal` is the number of the one this game met last, which is the one
  # that ended it; `reason` is one sentence of why this ending.
  Finished = Data.define(:quest, :goals, :last_goal, :reason)

  def self.for(playthrough) = new(playthrough)

  def initialize(playthrough)
    @playthrough = playthrough
  end

  attr_reader :playthrough

  # THE ONE PREDICATE, and the rule above is the whole of it. `#exists?` rather
  # than the loaded association: the play page asks this once per render and a
  # game has at most one ending.
  def concluded? = playthrough.endings.exists?

  # Whether the records say the protagonist died -- not merely "not concluded".
  def died? = reason == :died

  # WHICH RECORD ACTUALLY ANSWERED, and so which of the three sets of words the
  # player reads. `:unrecorded` is the third case the header names -- it renders
  # as `Playthrough::StoppedNotice` and `Story::Doctor` reports it as a finding.
  def reason
    return :concluded if concluded?
    return :died if protagonist_dead?

    :unrecorded
  end

  # THE AUTHOR OF THE WORDS, one per reason.
  NOTICES = {
    concluded: Playthrough::StoryOverNotice,
    died: Playthrough::DeathNotice,
    unrecorded: Playthrough::StoppedNotice
  }.freeze

  # `Playthrough::Refusal`'s word for each reason.
  REFUSAL_KINDS = { concluded: :concluded, died: :dead, unrecorded: :stopped }.freeze

  def heading = notice::HEADING

  def paragraphs = notice::PARAGRAPHS

  # THE ONE-LINE VERSION, for a line typed into a finished game. Same author
  # either way as the standing notice above, so the refusal and the statement
  # where the input used to be cannot come to disagree about why the game is
  # over -- which is the guarantee `DeathNotice`'s header claims for its own two
  # shapes, kept across all three notices.
  def sentence = notice.sentence(playthrough.character)

  # AND `Playthrough::Refusal`'s word for it, so that class does not have to ask
  # this one two questions to build one refusal.
  def refusal_kind = REFUSAL_KINDS.fetch(reason)

  # THE ENDING'S OWN LAST WORDS, OR NIL WHEN THE LOG ALREADY CARRIES THEM.
  #
  # `Playthrough::Arc#conclude!` writes the closing `Scene` with the reached
  # outcome's sentence on it and `Scene::Ending` replaces that sentence with the
  # narrator's paragraph IN PLACE -- so on every ordinary finished game the last
  # entry of the turn log IS the ending, and printing it again in the notice
  # directly beneath would put the same paragraph on the screen twice. That is
  # the objection `Scene::Ending`'s header raises against writing a second
  # scene, and the play page already answers it once in the same shape: a
  # refusal that is `#game_over?` prints only the echo, because "two of it on
  # one screen reads as a bug".
  #
  # SO THIS IS THE OTHER HALF OF THAT RULE. When there is no closing `Scene` on
  # the chain -- a repaired database, or an ending row a future writer lands
  # without one -- the stored outcome sentence is what a finished game has left
  # to say, and it is said here rather than nowhere.
  def closing_words
    return nil unless concluded?
    return nil if closing_scene

    ending&.to_s.presence
  end

  # THE CLOSING SCENE, WHICH IS THE HEAD OF THE CHAIN OR IT IS NOWHERE. The arc
  # points `playthroughs.current_scene` at it in the same transaction and stops
  # the game, so nothing can ever follow it; walking the chain for it would be a
  # query per turn of the whole playthrough to answer what one row already says.
  def closing_scene
    scene = playthrough.current_scene
    scene if scene&.ending?
  end

  # WHICH ENDING THIS GAME REACHED. At most one -- `Playthrough::Ending`'s
  # `#one_ending_per_quest` is what makes that true -- and the oldest wins if a
  # world ever grows a second arc to finish, because the first one to close is
  # the one that stopped the game.
  def ending = playthrough.endings.order(:reached_at, :id).first

  # WHICH GOAL WAS MET AND WHY THIS ENDING, or nil for a game that did not
  # conclude -- and for one whose beats are not on record, which only a
  # repaired database holds, because a reason nobody can read is not given.
  def finished
    outcome = (ending&.quest_outcome if concluded?)
    return nil if outcome.nil?

    quest = outcome.quest
    steps = quest.steps.to_a
    met = playthrough.beats.where(quest_step: steps).in_story_order.includes(:quest_step).map { |beat| beat.quest_step.position }
    return nil if met.empty?

    Finished.new(quest: quest.title, goals: steps.map(&:summary), last_goal: met.last,
                 reason: "Goal #{met.last} was the last you met, and it finished the story. #{why(outcome, met)}")
  end

  private

  def notice = NOTICES.fetch(reason)

  # THE REACHED OUTCOME'S RULE, SAID AS WHAT THIS GAME DID. One sentence per
  # row of `Quest::Outcome::CONDITIONS`, and a rule this does not know says
  # nothing rather than guessing.
  def why(outcome, met)
    case outcome.condition
    when nil
      if outcome.quest.outcomes.any?(&:conditional?)
        "None of the story's other endings applied, so this is the one it was built toward."
      else
        "This is the ending the story was built toward."
      end
    when "out_of_order"
      later, earlier = first_out_of_order(met)
      "You met goal #{later} before goal #{earlier}, which is what this ending is for."
    when "slower_than"
      "You met it more than #{story_duration(outcome.minutes)} after the story began, which is what this ending is for."
    when "while_alive"
      "You met goal #{outcome.step_position} while #{outcome.character&.fullname} was still alive, " \
        "which is what this ending is for."
    end
  end

  # The first goal met ahead of one the arc lists before it, and that one:
  # `Playthrough::Arc#out_of_order?`'s answer, named.
  def first_out_of_order(met)
    met.each_with_index do |later, index|
      earlier = met.drop(index + 1).find { |position| position < later }
      return [ later, earlier ] if earlier
    end
    met.last(2)
  end

  def story_duration(minutes)
    hours, rest = minutes.to_i.divmod(60)
    parts = []
    parts << "#{hours} hour#{"s" unless hours == 1}" if hours.positive?
    parts << "#{rest} minute#{"s" unless rest == 1}" if rest.positive? || hours.zero?
    parts.join(" and ")
  end

  def protagonist_dead?
    who = playthrough.character
    return false if who.nil?

    playthrough.vitals_for(who)&.dead? || false
  end
end
