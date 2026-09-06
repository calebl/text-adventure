# THE MACHINERY BEHIND ONE TURN, beside the prose that turn produced.
#
# The captain's words, 2026-09-05: *"while in the regular game mode, I want to
# be able to select any given turn and see the current game state as well as the
# exact prompt that was given to the narrator. Having to switch over to debug
# mode is too slow and I can't compare the two side by side."* So this is
# `Playthrough::Debug` narrowed to ONE turn and rendered on the play page, not a
# second window into the machine: the prompt half is
# `Playthrough::Debug::Turn#conversations` verbatim, through the same
# `debug/_conversation` partial the debug page renders, so the two cannot come
# to disagree about what was sent.
#
# READ ONLY, and it inherits that rule rather than restating it. Everything here
# is a read of records that already exist -- no model call, no write, no
# `Story#catch_up_world!`, nothing that advances a playthrough. `Playthrough::Debug`
# is pinned to that by a table-wide before/after snapshot
# (`test/models/playthrough/debug_test.rb`) and `Playthrough::MachineryTest`
# makes the same assertion about this.
#
# THE STATE HALF IS FIVE THINGS AND NOT SIX. The captain's scope, given after
# the task was written: the story time, who was in the room, what was lying in
# it, what the player was carrying, and what each person present was carrying.
# No branch, no evidence, no closed sets, no exits, no vitals, no cost figures
# -- those are the debug page's, and a panel that sits beside the prose has to
# be readable in one glance.
#
# TWO OF THE FIVE ARE HISTORICAL AND THREE ARE NOT, and that is said out loud in
# the panel rather than implied away:
#
#   * `scenes.story_timestamp` and the turn's recorded cast (`characters_scenes`,
#     snapshotted onto every turn by `Playthrough::Turn#play`) are AS OF THAT
#     TURN. They are columns written when the turn was played.
#   * what is lying in a room, what the party carries and what somebody is
#     holding are `Item` rows, and an item row has no history: it says where the
#     thing is NOW. Nothing in the app records what was on a floor at a past
#     story moment, so a panel claiming to is inventing one.
#
# Each row carries its own mark in the panel -- "as of this turn" or "now" --
# so a reader never has to know which of the five is which.
class Playthrough::Machinery
  # The one purpose told apart from the rest, because it is read second rather
  # than first. See `#prose_conversations`.
  CLASSIFIER = "classifier".freeze

  # One person in the room and what they are holding, in this game. `items` is
  # NOW -- see the note above -- and the protagonist is deliberately not one of
  # these: the party's own hands are a row of their own (`#carried`), and
  # `Item` puts a party's copies in neither a room nor anybody's hands.
  Holding = Data.define(:character, :items)

  attr_reader :playthrough, :scene

  def initialize(playthrough, scene)
    @playthrough = playthrough
    @scene = scene
  end

  # THE TURN, as `Playthrough::Debug` tells it -- asked of that class rather
  # than rebuilt here, so the prompt half of this panel and the debug page's are
  # the same records read by the same code.
  def turn = @turn ||= debug.turn_for(scene)

  def debug = @debug ||= Playthrough::Debug.new(playthrough)

  # ------------------------------------------------------------------------
  # THE PROMPT HALF: what the models were given and what came back.
  # ------------------------------------------------------------------------

  # Every conversation this turn paid for, in the order the loop made the calls.
  def conversations = turn.conversations

  # THE PROSE CALL FIRST AND THE CLASSIFIER SECOND, which is the opposite of the
  # order they happened in and the right order to READ them in: the captain is
  # comparing a passage against the prompt that produced it, and the classifier
  # exchange is context for how the line was read rather than the thing being
  # compared. It is included because it is part of "what the model was given".
  def prose_conversations = conversations.reject { |exchange| exchange.purpose == CLASSIFIER }
  def classifier_conversations = conversations.select { |exchange| exchange.purpose == CLASSIFIER }

  # Whether there is anything to show at all. A turn whose receipts were pruned
  # (`TA_CHAT_KEEP_TURNS`), and an opening arrival, which was generated when the
  # world was built rather than on a turn anybody played.
  def receipts? = turn.recorded?
  def opening? = turn.opening?

  # ------------------------------------------------------------------------
  # THE STATE HALF: five rows, and each one says whether it is historical.
  # ------------------------------------------------------------------------

  # (1) WHAT TIME IT WAS IN THE FICTION when this turn landed. A column on the
  # turn, so this is as of the turn.
  def story_time = scene.story_timestamp

  # (2) WHO WAS IN THE ROOM, out of the cast snapshotted onto the turn rather
  # than out of `Character.present_in` -- the snapshot is what the turn recorded
  # and the scope is what is true now, and the difference between them is the
  # whole reason `characters_scenes` is still written. As of the turn.
  def cast = @cast ||= scene.characters.to_a

  # (3) WHAT IS LYING IN THE ROOM, in this game. NOW: an `Item` row says where
  # a thing is, not where it was.
  def lying_here = @lying_here ||= playthrough.items_lying_in(scene.location).to_a

  # (4) WHAT THE PARTY IS CARRYING, in this game. NOW, for the same reason.
  def carried = @carried ||= playthrough.carried.to_a

  # (5) WHAT EACH PERSON IN THE ROOM IS CARRYING, in this game. NOW, and the
  # people are the turn's own recorded cast, so the row is honest about the
  # join: these are the people who were here, holding what they hold now.
  def held
    @held ||= cast.reject { |who| who == playthrough.character }
                  .map { |who| Holding.new(character: who, items: playthrough.items_held_by(who).to_a) }
  end

  # WHERE THE TURN WAS PLAYED. Not one of the five, but the room's name is what
  # rows 3 and 5 are about and a panel that named neither would be unreadable.
  def location = scene.location
end
