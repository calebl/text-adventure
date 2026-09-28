# WHAT THE PLAY BOX CAN COMPLETE, FOR THIS TURN, AS FACTS THE SERVER ALREADY HAS.
#
# THE CAPTAIN'S RULING OF 2026-09-04, EVENING: *"support a slash prefix
# autocomplete in the text box, and resolve those and verb-prefixed lines offline
# then fallback to the model."* This is the first half of it -- the verbs a
# `/` offers, and after a verb the closed set that verb resolves against -- and
# since his ruling of 2026-09-05, *"I think we should only auto accept the slash
# commands"*, it is the whole surface of the offline path: what the box completes
# to is exactly what the grammar reads.
#
# IT INVENTS NOTHING, AND THE ENGINE BUILDS IT. The Rust engine reads every
# typed line, so it is the one that says what the box completes to: its
# resolving words, each physical attempt's own word, and after each the names
# the same closed sets hold that the classifier is offered and the grammar
# resolves (`Playthrough::RustEngine.glance`'s `slash_menu`). The menu cannot
# invent an item, tool, recipient or doorway that either reader would be unable
# to bind, and this holds the engine's answer without a word of its own.
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
  attr_reader :playthrough

  def initialize(playthrough, document = Playthrough::RustEngine.glance(playthrough))
    @playthrough = playthrough
    @menu = document.fetch("slash_menu")
  end

  # The whole menu, ready to be a data attribute. Keyed by the WORD the player
  # types rather than by the action it resolves to, because the word is what the
  # box completes and what the grammar reads back.
  def to_h
    { verbs: @menu["verbs"].map { |verb| { word: verb["word"], hint: verb["hint"] } },
      targets: @menu["targets"] }
  end

  def to_json(*args) = to_h.to_json(*args)
end
