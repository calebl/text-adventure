# WHAT THE PROMPTS ARE TOLD ABOUT THE MOMENT THE PLAYER IS STANDING IN, built
# once per turn out of the records and nothing else.
#
# Three prompts write about the same moment -- `Scene::Narrator` answering the
# typed command, `InteractionAgent`'s narrator pass turning a character's
# reaction into prose, and the character pass itself -- and until this existed
# each assembled its own idea of it. The narrator knew the room and the last
# turn; the interaction narrator knew neither; the character knew the universe
# and its own sheet and not which room it was standing in. Meanwhile
# `Playthrough::Classifier` computed the room's exits, its cast, what is lying
# here and what the player carries, every turn, and threw them away once the
# intent was resolved.
#
# THOSE ARE CLOSED SETS THE APP ALREADY HOLDS, and handing them to the prose is
# the cheap half of the standing constraint -- *inform the prose* -- done with
# facts rather than rules. The narrator's instructions have always said not to
# invent an exit the player has not been told about; this is what finally tells
# it which exits those are. It does not make the narrator obey. It makes the
# case where it disobeys a contradiction of a stated fact rather than a guess
# about an unstated one, and `Playthrough::Drift` measures whether it helped.
#
# One builder for all three so they cannot disagree about where the player is,
# and so the register the player reads stays one register across the turn
# types they read interleaved. Nothing here asks a model anything.
class Playthrough::Moment
  # HOW MUCH OF WHAT A CHARACTER HAS ALREADY CONCLUDED a character prompt may
  # carry, in characters. Same shape as `Playthrough::RECAP_BUDGET`, and for the
  # same reason: a fixed budget rather than a fixed count keeps a long
  # conversation's cost flat.
  CONCLUSIONS_BUDGET = 400

  # How many exchanges back it will even look, on top of the ones the durable
  # chat already replays verbatim. The budget is the real limit.
  CONCLUSIONS = 6

  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # THE MOMENT FOR A NARRATOR: everything a prose pass answering the player
  # needs, in the order it needs it. The story and the room first, then the
  # closed sets, then what just happened and what came before it.
  #
  # The closed sets are stated even when empty. "The player is carrying
  # nothing" is a fact the narrator can use; silence about it is an invitation
  # to decide.
  def narration_context
    parts = [ "Story: #{story.title} (#{story.genre})", "Premise: #{story.summary}" ]

    if location
      parts << "The player is in #{location.name}: #{location.description}"
      parts << "Ways out of here: #{exit_names.presence || "none"}. There are no others."
    end

    parts << "The player is #{protagonist.fullname}." if protagonist
    parts << (others.any? ? "Also here: #{name_list(others)}. Nobody else is present." : "Nobody else is here.")
    parts << "The player is carrying: #{carried_names.presence || "nothing"}."

    if (previous = playthrough.current_scene)
      parts << "What just happened: #{previous.description}"
    end

    if (recap = playthrough.recap)
      parts << "Earlier, in order:\n#{recap}"
    end

    parts.join("\n\n")
  end

  # THE MOMENT FROM A CHARACTER'S SIDE, for the character pass's per-turn
  # message. Short on purpose: the durable conversation replays the last
  # `Chat::HISTORY_EXCHANGES` of these verbatim, so every line here is paid
  # for again on the next turn and the one after. The room's name and not its
  # description; the time of day; who else is standing here; the one line the
  # game remembers the last turn by.
  #
  # And it is in the per-turn message rather than in the system instructions
  # deliberately: a moment belongs to the turn it happened in, and a replayed
  # exchange should carry the room it happened in rather than the one the
  # player has since walked to.
  def character_context(character, replayed: Chat::HISTORY_EXCHANGES)
    lines = []
    lines << "Where you are: #{location.name}." if location
    lines << "The time is about #{time_of_day}."

    company = others.reject { |other| other == character }
    lines << "Also here, besides the two of you: #{name_list(company)}." if company.any?

    if (line = Scene.recap_line(playthrough.current_scene))
      lines << "What just happened: #{line}"
    end

    if (concluded = conclusions(character, replayed: replayed)).any? && protagonist
      lines << "What you have already concluded about #{protagonist.fullname}, earlier in this conversation:\n" +
               concluded.map { |sentence| "- #{sentence}" }.join("\n")
    end

    lines.join("\n")
  end

  # WHAT THIS CHARACTER DECIDED, on the exchanges the durable chat no longer
  # replays. `Interaction` keeps every exchange in full and `Chat#prune_history!`
  # keeps the last two verbatim; this is what finally reads the rest back. The
  # design always said "the interactions hold the memory" -- nothing had ever
  # opened it.
  #
  # Only this playthrough's exchanges: interactions hang off scenes, and the
  # scene chain is what makes a scene this playthrough's rather than another
  # player's walk through the same world. Newest first under the budget, then
  # back into order, the way `Playthrough#recap` does it.
  #
  # `replayed` is how many of the most recent exchanges the chat is already
  # sending verbatim, so they are skipped here rather than paid for twice.
  def conclusions(character, replayed: Chat::HISTORY_EXCHANGES)
    rows = Interaction.where(character: character, scene_id: playthrough.scene_chain.map(&:id)).chronological.to_a
    replayed = [ replayed.to_i, 0 ].max
    rows = rows[0...-replayed] || [] if replayed.positive?

    room = CONCLUSIONS_BUDGET
    kept = []
    rows.last(CONCLUSIONS).reverse_each do |row|
      sentence = (row.inner_resolution.presence || row.summary).to_s.strip
      next if sentence.blank? || sentence.length > room

      room -= sentence.length
      kept.unshift(sentence)
    end

    kept
  end

  # The people the records put in this room besides the player -- the same
  # answer the classifier accepts a `talk` against, so the narrator cannot be
  # told about someone the player then cannot speak to.
  def others
    return [] if location.nil?

    @others ||= Scene::Generator.characters_present(location) - [ protagonist ].compact
  end

  private

  def story = playthrough.story
  def location = playthrough.current_location
  def protagonist = playthrough.character

  def exit_names
    playthrough.exits.map(&:name).join(", ")
  end

  def carried_names
    return "" if protagonist.nil?

    Item.for_character(protagonist).order(:id).map(&:name).join(", ")
  end

  def name_list(people)
    people.map { |person| person.nickname.present? ? "#{person.fullname} (#{person.nickname})" : person.fullname }.join(", ")
  end

  # Story time, not the wall clock (AGENTS.md, *Story time*). The hour is what a
  # person in the room knows; the date is not something they would say.
  def time_of_day
    playthrough.story_now.strftime("%-l %P")
  end
end
