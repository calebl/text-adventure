# WHAT THE PLAY BOX CAN COMPLETE, FOR THIS TURN, AS FACTS THE SERVER ALREADY HAS.
#
# THE CAPTAIN'S RULING OF 2026-09-04, EVENING: *"support a slash prefix
# autocomplete in the text box, and resolve those and verb-prefixed lines offline
# then fallback to the model."* This is the first half of it -- the five verbs a
# `/` offers, and after a verb the closed set that verb resolves against -- and
# since his ruling of 2026-09-05, *"I think we should only auto accept the slash
# commands"*, it is the whole surface of the offline path: what the box completes
# to is exactly what the grammar reads.
#
# IT INVENTS NOTHING AND QUERIES NOTHING NEW. The verbs are
# `Playthrough::Grammar::RESOLVING`, so the box cannot offer a word the grammar
# does not read; the names are `Playthrough::Classifier#offered_for`, which is
# the same closed set the model is offered and the same one a typed name is
# matched against. Three ways of saying a thing and one list behind all of them.
#
# AND SINCE THE CAPTAIN'S RULING OF 2026-09-05 -- *"I think we should only auto
# accept the slash commands"* -- THIS MENU IS THE WHOLE OF THE OFFLINE PATH'S
# SURFACE. A line is read by the grammar only behind a `/`, so what the box
# completes to is exactly what goes offline: the shortcut is opt-in and visible,
# and a player who never types `/` never leaves the path they are on today.
#
# IT IS RENDERED INTO THE FORM AND NEVER FETCHED. `_turn_log` carries it as a
# data attribute on every render, and `#turn_log` is replaced at the end of every
# turn -- so the sets rebuild themselves with the turn and the browser makes no
# request, holds no cache and asks no model. A page with no JavaScript is a plain
# text box and loses nothing but the menu.
#
# WHAT IS DELIBERATELY NOT OFFERED. `other` -- it carries no record, so there is
# nothing to complete and plain text is how a player says anything else. A
# nickname beside a fullname -- the grammar matches either, and offering one
# person twice reads as two people. And every engine-view verb (`stats`, `harm`,
# `check`): those are `rake game:mechanics`'s instruments and the browser has no
# engine view.
class Playthrough::SlashMenu
  # ONE LINE ABOUT EACH VERB, for the menu row. Short enough to sit beside the
  # word; the closed set underneath it is the real explanation.
  HINTS = {
    "go" => "a way out of here",
    "talk" => "somebody standing here",
    "take" => "something lying here",
    "drop" => "something you are carrying",
    "read" => "something here or in your hands"
  }.freeze

  attr_reader :playthrough

  def initialize(playthrough, classifier: nil)
    @playthrough = playthrough
    @classifier = classifier
  end

  def classifier = @classifier ||= Playthrough::Classifier.new(playthrough)

  # The whole menu, ready to be a data attribute. Keyed by the WORD the player
  # types rather than by the action it resolves to, because the word is what the
  # box completes and what the grammar reads back.
  def to_h
    {
      verbs: Playthrough::Grammar::RESOLVING.keys.map { |word| { word: word, hint: HINTS[word] } },
      targets: Playthrough::Grammar::RESOLVING.to_h { |word, action| [ word, names_for(action) ] }
    }
  end

  def to_json(*args) = to_h.to_json(*args)

  private

  # As the player would type them, out of the one place that names a record --
  # `fullname` for a person, `name` for a place or a thing. Duplicates are
  # dropped: two things of one name in one room are one thing to somebody typing
  # the name, which is exactly what both resolvers already do with them.
  def names_for(action)
    classifier.offered_for(action).map { |record| Playthrough::Classifier.label_for(record) }.compact_blank.uniq
  end
end
