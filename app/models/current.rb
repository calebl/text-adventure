# WHO A MODEL CALL IS SPENT ON, for the length of one turn.
#
# `Playthrough::Session#play` sets it around the loop, so every call the turn
# makes -- the narrator, an NPC, a room realized on the way in, a System One
# read -- is filed under the player whose turn it is, however far from the
# playthrough the code that makes the call sits. `BaseAgent` stamps it on the
# chat it opens; `SystemOneAgent` stamps it on its receipt. Both read it and
# neither sets it. Outside a turn it is empty, and a call made then belongs to
# nobody's allowance (world building, the benches).
class Current < ActiveSupport::CurrentAttributes
  attribute :player, :playthrough
end
