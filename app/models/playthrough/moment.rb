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
    # HOW MUCH IS LEFT OF THE PLAYER, stated as a fact and only when the records
    # have one. It is a whole sentence for a reason `Playthrough::Vitals`'s
    # header gives: a number nobody can see is worse than no number, and this
    # line is the entire prose integration of the stat block -- the narrator is
    # TOLD what the engine decided, exactly as it is told what is lying on the
    # floor, and it is asked to decide nothing.
    #
    # SILENT FOR SOMEBODY WITH NO STAT BLOCK. `Playthrough#vitals_for` answers
    # nil for them, and saying nothing is the honest answer where "unhurt" would
    # be an assertion about a body the engine does not have.
    parts << condition.to_s if condition
    parts << (others.any? ? "Also here: #{name_list(others)}. Nobody else is present." : "Nobody else is here.")
    # HOW MUCH IS LEFT OF EVERYBODY ELSE IN THE ROOM, and whether any of them is
    # fighting the party. Until a fight could happen this was the one closed set
    # the narrator was told the names of and never the state of, which was
    # correct while nothing could hurt an NPC and is a contradiction waiting to
    # be written the moment something can.
    #
    # AT MOST THREE LINES: `Character::Registry::MAX_PER_ROOM` bounds a room's
    # cast, so this cannot grow with the world.
    #
    # `unhurt` IS LEFT UNSAID FOR AN NPC, deliberately, and it is the same rule
    # `Playthrough::Vitals` is written under: an absent row means unhurt, that
    # is the honest default for almost everybody in every world, and saying it
    # three times a turn is paying for the default in tokens. The PLAYER's line
    # above says it, because the player's body is the one the game ends on.
    parts.concat(conditions_of_others)
    # AND WHAT THE LAST EXCHANGE DID, out of `playthrough_blows` -- the numbers
    # the engine's own dice produced, stated as done.
    parts << struck_fact if struck_fact
    # AND WHAT THE PLACE ITSELF DID, out of `playthrough_tolls` -- the water on
    # the causeway, the drop through the hatch. Beside the blows and never
    # folded into them, because they are two different facts and the prose has
    # to be able to say which: somebody hit you, or the world did.
    parts << toll_fact if toll_fact
    parts << "Lying here, and takeable: #{floor_names.presence || "nothing"}."
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
  # description; the time of day; who else is standing here; what the player
  # typed on the last turn.
  #
  # EVERY LINE HERE IS A RECORD, and none of it is prose a model wrote. That is
  # a stricter rule than `#narration_context` keeps, and it has to be: the
  # narrator writes to the player, so it can be handed the last turn's prose as
  # it stands, while a character prompt is written to somebody else in the room
  # and the same sentence read there is an assertion about that character. See
  # `#last_attempt`.
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

    if (attempt = last_attempt)
      lines << attempt
    end

    if (reading = last_reading)
      lines << reading
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
      sentence = (row.inner_resolution.presence || row.action).to_s.strip
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

    @others ||= playthrough.cast_in(location) - [ protagonist ].compact
  end

  # ONE LINE PER PERSON IN THE ROOM WHOSE BODY THE RECORDS HAVE SOMETHING TO SAY
  # ABOUT, and nothing at all for the ones they do not.
  #
  #   The wharf-rat swarm is hurt (3 of 6) and is fighting you.
  #
  # Three rules, each of them the same one the rest of this class keeps. It is a
  # RECORD read out (`Playthrough#vitals_for`, the one reader, and
  # `Playthrough#foes_in`, the one reader of who is fighting), never a judgement.
  # It says a NUMBER, because "badly" is a mood and "3 of 6" is a fact -- the
  # reasoning `Playthrough::Vitals::Condition#in_words` is written under. And it
  # says nothing about somebody who is unhurt and nobody's enemy, because that
  # is the default and the default is what silence already means.
  #
  # Nobody with no stat block gets a line: `#vitals_for` answers nil for them
  # and there is no body to describe.
  def conditions_of_others
    fighting = playthrough.foes_in(location).to_set

    others.filter_map do |person|
      state = playthrough.vitals_for(person)
      next if state.nil?
      next if state.unhurt? && !fighting.include?(person)

      "#{person.fullname} is #{state.in_words}#{" and is fighting you" if fighting.include?(person)}."
    end
  end

  # WHAT THE LAST EXCHANGE DID, IN THE APP'S OWN WORDS, and it is the same shape
  # `Playthrough::Turn#taken_fact` has: the rows moved first and this is only
  # the sentence about them.
  #
  # THREE PROPERTIES, EACH DELIBERATE. It names the DAMAGE, because a number is
  # a fact where "badly" is a mood. It states ALIVE OR DEAD OUTRIGHT, because
  # the one thing the narrator must not do is kill or spare somebody the engine
  # did not. And it says the numbers are fixed -- which is not a rule the prose
  # has to obey for the mechanic to hold (the record is the record whatever the
  # paragraph does with it) but is the cheap half of *inform the prose*, exactly
  # as `Playthrough::Turn#written_words_fact` is for an inscription.
  #
  # ONLY THE ROUNDS THE PLAYER HAS NOT READ ABOUT YET: the blows of the fight
  # that is still open (`Playthrough::Blow.open`). A fight the engine has
  # already closed has a `Scene` of its own in the log, and repeating it here
  # would have the narrator write the same exchange twice.
  def struck_fact
    return @struck_fact if defined?(@struck_fact)

    blows = playthrough.blows.open.chronological.includes(:attacker, :target).to_a
    return @struck_fact = nil if blows.empty?

    @struck_fact =
      "Blows landed, recorded by the game: " +
      blows.map { |blow| one_blow(blow) }.join(" ") +
      " Those are the numbers and they do not change. Do not decide who lives, " \
      "who dies, or how much anything hurt."
  end

  # WHAT THE WORLD ITSELF TOOK, AND WHETHER THE BODY GOT CLEAR OF IT.
  #
  # `#struck_fact`'s counterpart for the other source of damage, written to the
  # same rule and for the same reason: the numbers are the engine's, they are
  # stated as done, and the paragraph is asked to decide nothing. A hazard is
  # the one thing that hurts a player with nobody in the room, so without this
  # the prose would be handed a body that had lost hit points between two turns
  # with no account of how -- which is exactly the contradiction *inform the
  # prose* exists to prevent.
  #
  # A SAVE IS A FACT TOO, and it is stated. "She got clear of it" is a sentence
  # the narrator can use and a turn where the water did nothing is a turn the
  # prose should not invent a wound for; silence about it is an invitation to
  # decide.
  #
  # ONLY THE TOLLS NO PARAGRAPH HAS CARRIED YET (`Playthrough::Toll.untold`),
  # which is `#struck_fact`'s rule stated with the right word for this table:
  # `Playthrough::Turn#play` stamps them with the Scene that told the player,
  # so one toll reaches the prose once. Bounded at two a turn by the branches
  # that write them -- a doorway and a room on an arrival, or a room on a stay.
  def toll_fact
    return @toll_fact if defined?(@toll_fact)

    tolls = playthrough.tolls.untold.chronological.includes(:character, :location, :location_connection).to_a
    return @toll_fact = nil if tolls.empty?

    @toll_fact =
      "The place itself, recorded by the game: " +
      tolls.map { |toll| one_toll(toll) }.join(" ") +
      " Those are the numbers and they do not change. Do not decide how much " \
      "anything hurt, and do not write a wound the game did not record."
  end

  # One toll, and the facts about it a paragraph must not contradict.
  def one_toll(toll)
    where = toll.where_it_was
    return "#{toll.character.fullname} got clear of #{where} and lost nothing." if toll.saved?

    "#{where} cost #{toll.character.fullname} #{toll.damage} hit point#{"s" unless toll.damage == 1} " \
      "-- #{toll.words}. #{toll.character.fullname} is " \
      "#{toll.killed? ? "dead: that was what killed them" : "alive"}."
  end

  # One blow, and the two facts about it that a paragraph must not contradict.
  def one_blow(blow)
    "#{blow.attacker.fullname} struck #{blow.target.fullname} for " \
      "#{blow.damage} hit point#{"s" unless blow.damage == 1}. " \
      "#{blow.target.fullname} is #{blow.killed? ? "dead: that was the blow that killed them" : "alive"}."
  end

  private

  def story = playthrough.story
  def location = playthrough.current_location
  def protagonist = playthrough.character

  # Through `Playthrough#condition`, which is `#vitals_for` on the protagonist
  # -- the one reader, so this prompt and the `rake game:mechanics` read-out
  # cannot come to disagree about a number.
  def condition = playthrough.condition

  # WHAT THE PLAYER JUST DID, FROM THE RECORD OF WHAT THEY TYPED rather than
  # from the prose that answered it.
  #
  # `Scene.recap_line` -- what `#narration_context` above uses, correctly -- is
  # written in registers this prompt cannot carry. A scene summary is
  # engine-facing third person ("...at the player's back", Scene::Schema); a
  # talk turn's summary is "The player spoke with <this very character>"
  # (Playthrough::Turn#talk_to); and a narrated turn has no summary at all, so
  # the fallback is the narrator's SECOND person -- addressed to the player,
  # while every other "you" in a character prompt means the character. Measured
  # on the second-person variant: the character then performs the player's
  # physical action as its own 6 times in 10 against 0 in 10 on the control
  # (Fisher exact p = 0.011).
  #
  # `scenes.typed` is a record and not prose -- the player's own words, written
  # on every branch -- and named and quoted it is already in this character's
  # register: somebody in the room, doing something. Nil only on the opening
  # arrival, which is a turn nobody took, and then the character is told
  # nothing rather than told it wrong.
  def last_attempt
    return nil if protagonist.nil?

    typed = playthrough.current_scene&.typed.to_s.strip
    return nil if typed.blank?

    %(What #{protagonist.fullname} did a moment ago: "#{typed.truncate(200)}")
  end

  # WHAT THE PLAYER WAS READING A MOMENT AGO, AND WHAT IT SAID, for somebody
  # standing next to them while they read it.
  #
  # The same shape as `#last_attempt` and for the same reason: it is a RECORD and
  # not prose. `Scene#resolved_action` says the last turn was an examine,
  # `Scene#acted_on` says of what, and `Item#inscription` holds the words the
  # engine owns -- so this is three columns read out, in the register a character
  # prompt can carry (somebody in the room, doing something), and nothing a model
  # wrote about the moment.
  #
  # WHY A CHARACTER IS TOLD AT ALL: an NPC watching the player read a docket and
  # then answering as though the page were blank is the same defect as a narrator
  # inventing what it says, one prompt over. The words are quoted here for
  # exactly the reason `Playthrough::Turn#read_fact` quotes them -- a paraphrase
  # is what drifts.
  #
  # WHAT IT DOES NOT COVER, stated rather than implied: being SHOWN something.
  # Handing a note to somebody is not an act the app owns -- there is no record
  # of it and no closed set it resolves against -- so nothing here pretends to
  # know it happened. Reading is an act the records hold, and this is that act.
  def last_reading
    scene = playthrough.current_scene
    return nil unless scene&.recorded_action == "examine"

    item = scene.acted_on_record
    return nil unless item.is_a?(Item) && item.inscribed?

    reader = protagonist ? protagonist.fullname : "The person you are speaking to"
    %(What #{reader} was reading a moment ago: the #{item.name}, which says, word for word: ) +
      %("#{item.inscription}")
  end

  def exit_names
    playthrough.exits.map(&:name).join(", ")
  end

  # WHAT THE PARTY HAS IN ITS HANDS, out of the playthrough's own record --
  # `Playthrough#carried`, the same closed set the classifier resolves a `drop`
  # against. Not the protagonist's `items`: that is one row per story and it is
  # the story's starting inventory, shared by every play of the world.
  def carried_names
    playthrough.carried.map(&:name).join(", ")
  end

  # WHAT IS ON THE FLOOR OF THIS ROOM, IN THIS GAME -- the same closed set
  # `Playthrough::Classifier` resolves a `take` against, said to the narrator
  # out of the same records and through the same one reader
  # (`Playthrough#items_lying_in`), so the prompt and the enum cannot disagree
  # about what a party can pick up. It was the one closed set the classifier computed
  # every turn and the prose was never told about (PR 98, F3), which is the
  # narrower half of an old symmetry problem: the narrator knew what the player
  # was carrying but not what they could pick up, so a `take` that resolved to
  # a real row was answered by prose with no idea the thing was there.
  #
  # Stated even when empty, for the reason the whole method list here is: "there
  # is nothing to pick up" is a fact the narrator can use, and silence about it
  # is an invitation to invent something.
  def floor_names
    return "" if location.nil?

    playthrough.items_lying_in(location).map(&:name).join(", ")
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
