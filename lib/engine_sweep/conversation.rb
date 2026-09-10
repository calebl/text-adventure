# A fixed character decision for the offline walk. Mechanics deliberately
# skips model-written dialogue; this sweep adapter supplies the missing choice
# and invokes the real effect writer before Mechanics runs the real riposte.
# No production callback, fabricated prose or second implementation of an NPC
# action. A fixture attached to something other than a resolved talk fails.
class EngineSweep::Conversation < Playthrough::Mechanics
  def with_choice(choice)
    @npc_choice = choice
    @choice_consumed = false
    result = yield
    if choice && !@choice_consumed
      raise EngineSweep::InvalidScript, "npc_action requires a resolved conversation"
    end
    result
  ensure
    @npc_choice = nil
  end

  private

  def talk(character, understood)
    return super unless @npc_choice

    @choice_consumed = true
    choice = @npc_choice
    if choice.start_with?("give:")
      item = playthrough.items_held_by(character).find_by(name: choice.delete_prefix("give:"))
      choice = "give:#{item.id}" if item
    end
    effect = Playthrough::NpcAction.new(playthrough, character).apply!(choice)
    return change(effect.fact, understood) if effect.applied?
    return refuse(effect.fact, understood: understood) if effect.status == "rejected"

    read(note: effect.fact, understood: understood)
  end
end
