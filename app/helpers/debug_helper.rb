# Rendering for the debug view, and one idea: SAY WHEN SOMETHING IS ABSENT.
#
# A blank field in this view is never decoration to skip. A stub location has
# no description YET, which is different from a realized one with an empty
# description, which is different again from a value nothing in the app has
# ever written. Each of those is information, so each gets said out loud with
# its reason rather than rendered as whitespace.
module DebugHelper
  # A value, or a plain statement that there is none and why.
  def debug_value(value, absent: "not recorded")
    return tag.span("(#{absent})", class: "absent") if debug_blank?(value)

    value.to_s
  end

  # Same, for a moment on the story's clock. Always UTC and always in the
  # story's own terms -- these are story times, and formatting one in the
  # reader's zone would invite exactly the wall-clock confusion the model
  # spent a whole roadmap item getting rid of.
  def debug_time(value, absent: "never")
    return tag.span("(#{absent})", class: "absent") if value.nil?

    value.utc.strftime("%Y-%m-%d %H:%M")
  end

  def debug_minutes(minutes)
    return tag.span("(no previous turn)", class: "absent") if minutes.nil?

    minutes == minutes.to_i ? "#{minutes.to_i} min" : "#{minutes} min"
  end

  # The one-word label for a turn's branch, coloured so a log of forty turns
  # can be scanned for the two conversations in it.
  def debug_branch(branch)
    tag.span(branch.to_s, class: "branch #{branch}")
  end

  # The verdict the player recorded on a turn, coloured the same three ways the
  # play page colours the buttons -- so the log and the review table read as one
  # instrument rather than two. Nil is a turn nobody judged, which is the
  # ordinary case and not an absence worth explaining.
  def debug_verdict(verdict)
    return nil if verdict.blank?

    tag.span(verdict.to_s, class: "verdict #{verdict}")
  end

  # WHY A NON-OPENING TURN HAS NO RECEIPTS, which depends on whether a retention
  # cap is in force at all. Uncapped -- the default -- pruning is not a candidate
  # explanation, so offering it would send somebody looking for a cause that
  # cannot apply. See `Chat::KEEP_TURNS`.
  def no_receipts_reason
    return "no conversation kept — this Scene was written by something other than the loop" unless Chat.capped?

    "no conversation kept — pruned after #{Chat::KEEP_TURNS} turns " \
      "(TA_CHAT_KEEP_TURNS is set), or this Scene was written by something other than the loop"
  end

  # A block of generated prose, kept as written. `white-space: pre-wrap` in the
  # layout, because a narrator's paragraph breaks are part of what it wrote.
  def debug_prose(value, absent: "not recorded")
    return tag.span("(#{absent})", class: "absent") if debug_blank?(value)

    tag.div(value.to_s, class: "prose")
  end

  private

  def debug_blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.is_a?(String) && value.strip.empty?)
  end
end
