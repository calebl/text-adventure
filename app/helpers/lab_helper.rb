# Rendering for the realization lab, and one idea: SAY WHO DECIDED EACH STEP.
#
# The captain, 2026-09-07: *"It's still hard for me to hold in my head the full
# sequence of everything that happens each turn or as you move into a new
# room/location."* So the sample page is one column in sequence and every step
# in it carries a mark saying whether a MODEL answered it or the ENGINE decided
# it from records it already held. That is the README's turn-diagram convention
# -- purple for a model call, teal for the app deciding -- applied to a page, and
# it is the whole reason the page is a column and not a grid.
#
# `DebugHelper` is loaded too (helpers are all-in by default), so `debug_value`,
# `debug_verdict` and `debug_prose` are used here rather than respelled.
module LabHelper
  # WHO ANSWERED THIS STEP. `:model` or `:engine`, and nothing else -- a third
  # word would be a step this page cannot honestly place on either side of the
  # line the whole instrument is about.
  def lab_who(who)
    tag.span(who == :model ? "the model" : "the engine", class: "who #{who}")
  end

  # ONE PICK AGAINST THE EXPECTATION FOR IT. Teal for a hit, the warn colour for
  # a miss, grey for a pick the kind said nothing about -- and grey is the
  # ordinary case, because *don't care* is the default.
  #
  # `allowed` is nil for *don't care* and a list otherwise; a pick that was never
  # made at all reads as a miss when there is an expectation to miss, which is
  # `Lab::Realization::HitRate#hit?`'s rule and the population word's whole
  # story.
  def lab_pick(value, allowed)
    shown = value.presence || "(nothing at all)"
    return tag.span(shown, class: "pick unscored") if allowed.blank?

    tag.span(shown, class: "pick #{allowed.include?(value) ? "hit" : "miss"}")
  end
end
