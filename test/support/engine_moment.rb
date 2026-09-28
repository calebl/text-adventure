# WHAT A PROMPT IS TOLD ABOUT THE MOMENT, AS THE ENGINE STATES IT.
#
# The moment is the Rust engine's (`moment::Moment`): the narration context a
# narrator is handed and the context a character is handed, built from the rows
# as they stand. There is no Ruby copy of it, so a test about what a prompt
# says of the room, the people in it, the fight, the tolls, the arc or what a
# character remembers asks the engine, through the same door every request
# goes through (`Playthrough::Requests`), and asserts on the words.
class EngineMoment
  # The engine's own memory tables and budgets, as the vector portion it
  # blesses carries them (`conclusions`, `conclusions_budget`,
  # `memories_budget`, `stop_words`).
  TABLES = JSON.parse(Rails.root.join("test/engine_vectors/memory.json").read).fetch("constants").freeze

  # `handled` is `{ item:, direction: }`, the item a turn moved and which way
  # (`:taken` or `:dropped`); `ending` the `Quest::Outcome` this game reached.
  def initialize(playthrough, handled: nil, ending: nil)
    @playthrough = playthrough
    @handled = handled
    @ending = ending
  end

  def narration_context(plan: true, arc: true)
    Playthrough::Requests.build(:narration_context, playthrough: @playthrough.id, plan: plan, arc: arc,
                                                    handled: handled, ending: @ending&.id)
  end

  def character_context(character, query: nil, replayed: nil)
    character_read(character, query: query, replayed: replayed).fetch("context")
  end

  def personal_facts(character) = character_read(character).fetch("personal_facts")

  # WHAT A CHARACTER REMEMBERS (the engine's `memory`): the interactions it
  # recalls for `query`, best first, as their ids; one interaction's
  # recollection; and the recollections the character context carries.
  def recall(character, query: nil, replayed: nil)
    remembered(character, query: query, replayed: replayed).fetch("recall").map { |row| row.fetch("id") }
  end

  def recollection(character, interaction)
    remembered(character, interaction: interaction.id).fetch("recollection")
  end

  def conclusions(character, query: nil, replayed: nil)
    remembered(character, query: query, replayed: replayed).fetch("conclusions")
  end

  def recollections(character, query: nil, replayed: nil)
    remembered(character, query: query, replayed: replayed).fetch("recollections")
  end

  # THE CHARACTER PASS'S PROMPT for `line`, the engine's (`dialogue`).
  def character_prompt(character, line)
    Playthrough::Requests.build(:character, playthrough: @playthrough.id, character: character.id, line: line).fetch("user")
  end

  private

  def handled
    @handled && { item: @handled.fetch(:item).id, direction: @handled.fetch(:direction).to_s }
  end

  def remembered(character, **arguments)
    Playthrough::Requests.build(:memory, playthrough: @playthrough.id, character: character.id, **arguments)
  end

  def character_read(character, query: nil, replayed: nil)
    Playthrough::Requests.build(:character_context, playthrough: @playthrough.id, character: character.id,
                                                    query: query, replayed: replayed)
  end
end
