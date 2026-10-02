# Narrates arriving somewhere and keeps the moment as a Scene.
#
# NOT the narrator (`Playthrough::Turn#narrate`), and the difference is the
# point. The narrator answers what the player TYPED: it streams unschema'd prose
# because a player is watching it land a token at a time, and that is the one
# documented exception to the structured-output rule. This narrates walking INTO
# a place, which is not a turn -- it is the record of a moment in the world,
# written the way every other record here is written:
#
#   * schema'd, one call, two fields. The description is what the player reads;
#     the summary is what the rest of the game remembers (see Scene::Schema).
#     Streaming would buy back one field and cost the other, and it would make
#     this class a copy of the narrator with a different prompt.
#   * it does not stream, and on the path that calls it that costs almost
#     nothing: arriving somewhere new means realizing the location first, which
#     is two unstreamed calls and ~670 output tokens. Streaming the ~120 tokens
#     that follow them is not what the player is waiting on.
#
# Arrival reads differently the second time. THIS GAME's own scene chain is the
# whole mechanism (`Location#last_visit_in`): a location this party has never
# stood in gets narrated as discovery, and one it has gets narrated as coming
# back, with how long they were gone stated in the prompt. Walking into a
# room you left an hour ago should not read like finding it.
#
# NOT `Location#last_protagonist_visit`, which is the WORLD's stamp and is
# written by every playthrough of the story. Reading it here told a player on
# their first arrival that they were last here 28 minutes ago, because another
# game had been; it is `Story::Map`'s frontier, where world-wide is right.
class Scene::Generator
  include SanitizesGeneratedText
  include ActionView::Helpers::DateHelper

  attr_reader :location, :previous_scene, :origin, :story, :completed_scene

  # `previous_scene` is the player's preceding moment -- the linked-list
  # link, not the last scene in this location. It is optional because the
  # story's opening arrival has nothing before it.
  #
  # `opening` marks the one arrival that belongs to the world: see .opening.
  #
  # `playthrough` supplies this game's origin and destination state as well
  # as filing the conversation: living cast, bodies, inventory, wounds and the
  # crossing. Older games can have a fight-closing scene in the room they
  # escaped, so previous_scene is a history link and cannot override the
  # party's actual whereabouts. World-building has no game and uses the link.
  #
  # `reactions` are the ids of the volition rows the people in the room wrote
  # as the party came in (the engine's reactions step): what they said or did
  # is told in the prompt's "As You Come In" block. The Rust engine writes
  # them on every move; nothing in this loop does, so only a caller that
  # stages them -- the arrival bench -- names any.
  def initialize(location, previous_scene: nil, opening: false, playthrough: nil, reactions: [])
    @location = location
    @previous_scene = previous_scene
    @origin = playthrough ? playthrough.current_location : previous_scene&.location
    @opening = opening
    @playthrough = playthrough
    @reactions = reactions
    @story = location.story
  end

  # The story's opening arrival, narrated once at WORLD-BUILDING time.
  #
  # Every other room the player walks into is narrated the moment they walk in.
  # The opening room is the one they never walk into -- they are simply standing
  # in it -- so until this existed the first thing a new player read was the
  # room's own description standing in for an arrival nobody wrote.
  #
  # Generating it here rather than at playthrough-start is the point of the
  # whole exercise. `rake game:new` pays for it once (~1,302 in / ~200 out, the
  # same as any arrival), WorldSeed::Exporter writes it into the seed file where
  # it can be hand-authored -- it is the most important prose in the game -- and
  # WorldSeed::Loader loads it with the world. A player starting a story pays no
  # model call at all and reads real narrated prose immediately.
  #
  # It is marked `is_opening`, which is what makes it world rather than
  # progress: it is exported, it is shared by every playthrough of the story,
  # and it deliberately does NOT stamp `last_protagonist_visit` (see Scene).
  def self.opening(story)
    location = story.opening_location
    raise ArgumentError, "#{story.title.inspect} has no location to open in" if location.nil?

    new(location, opening: true).generate!
  end

  # Raises rather than returning a half-made scene: a generator that swallows a
  # failure turns a bad API key into "the AI wrote garbage" downstream. A stub
  # raises for the same reason -- it has no description and no lore, so there is
  # nothing to arrive in. Realize it first (`Location::Generator#realize!`,
  # which no-ops on an already realized location).
  def generate!
    return Playthrough::Command::Journal.read("arrival") if Playthrough::Command::Journal.saved?("arrival")

    raise ArgumentError, "cannot narrate arriving in #{location.name.inspect}: it is still a stub" unless location.realized?

    # Read off the chain BEFORE this arrival joins it, or every arrival would
    # look like a return that happened zero minutes ago.
    returning = returning?
    at = story_timestamp
    elapsed = location.time_since_last_visit(chain_head, at)
    cast = characters_present

    answer = agent.with_schema(Scene::Schema).ask(
      arrival_prompt(returning, elapsed, cast), verify: method(:finished!)
    ).content

    scene = Playthrough::Command::Journal.commit("arrival") do
      row = persist_arrival!(answer, cast: cast, at: at, engine_fact: arrival_engine_fact)
      row.narrated_toll_ids = arrival_context.toll_ids if arrival_context
      row.narrated_volition_ids = []
      row
    end

    # The turn the exchange above belongs to only exists now, so the messages
    # are stamped with it here rather than by the caller. See BaseAgent#attribute_to!.
    attribute_to(scene)
    scene
  end

  # The journey already happened when its prose fails. This is the engine's
  # account of the destination and crossing, with no further provider call.
  # If saving succeeded and only attribution failed, reuse that scene so a
  # caller's recovery cannot append the arrival twice.
  def fallback!(error: nil)
    return completed_scene if completed_scene
    raise ArgumentError, "an arrival fallback needs a playthrough" unless @playthrough
    raise ArgumentError, "cannot arrive in a stub" unless location.realized?

    context = arrival_context
    description = ([ "You arrive at #{location.name}." ] + context.facts).join(" ")
    Playthrough::Command::Journal.commit("arrival") do
      scene = persist_arrival!(
        { "description" => description, "summary" => description },
        cast: context.living, at: story_timestamp, engine_fallback: true,
        engine_fact: arrival_engine_fact
      )
      scene.narrated_toll_ids = context.toll_ids
      scene.narrated_volition_ids = []
      scene.rendering_error = error
      scene.safety_notice = true if error.is_a?(BaseAgent::CrisisResponseError)
      scene
    end
  end

  # Whether THIS GAME's party has stood here before, off its chain up to the
  # moment before this arrival. The opening arrival has no chain, so it is a
  # first.
  def returning?
    !location.last_visit_in(chain_head).nil?
  end

  # The newest moment of this game before the arrival: the scene it came from,
  # or the game's current one when a caller gave no link.
  def chain_head
    return nil if opening?

    previous_scene || @playthrough&.current_scene
  end

  # WHEN IN THE STORY THIS ARRIVAL HAPPENS, and the one place the game turns a
  # journey into elapsed story time.
  #
  # The opening arrival IS the moment the story starts, and `start_time` is
  # already the world's fixed in-story clock -- so it is read from the world
  # rather than from the wall clock, and the seed file does not have to carry a
  # timestamp that would only ever restate it.
  #
  # Every other arrival is the previous scene plus how long the walk took, which
  # `LocationConnection` already answers from its fixed tables. So the story's
  # clock advances by the world's own distances, and `#time_since_last_visit`
  # -- the value that becomes "you were last here about an hour ago" in the
  # prompt -- is measured in the fiction rather than against whenever the player
  # happened to have a browser open. That is the wall-clock defect, and it is
  # fixed in this one place: `Time.current` is gone from the whole arrival path,
  # so a visit holds a story moment rather than an instant on the machine's
  # clock.
  def story_timestamp
    return story.start_time if opening?
    return story.clock if previous_scene.nil?

    previous_scene.story_timestamp + journey_minutes.minutes
  end

  # How long the walk in took. Nil `previous_scene` never reaches here, and a
  # move with no edge should not either -- `Playthrough::Classifier` resolves a
  # destination out of the room's real exits -- so the fallback is for a caller
  # that placed the player somewhere by hand. It borrows the shortest distance
  # there is rather than zero, because two scenes at the same story instant
  # would make "how long since you were here" answer nothing at all.
  def journey_minutes
    edge = LocationConnection.find_by(location: origin, connected_location: location)
    return LocationConnection::DISTANCES.fetch("adjacent") if edge.nil?

    LocationConnection.travel_minutes(edge.distance, edge.travel_method) ||
      LocationConnection::DISTANCES.fetch("adjacent")
  end

  def opening?
    @opening
  end

  # Who the game knows is standing here, decided from records rather than asked
  # for. Three sources, and each is something the app can actually answer:
  #
  #   the protagonist  -- they are the one arriving
  #   companions       -- they travel with the protagonist, so they are wherever
  #                       the protagonist is
  #   the room's cast  -- `Character.present_in(location)`: the people the
  #                       records place here. One column, read back.
  #
  # THE THIRD SOURCE USED TO BE `holdovers` -- whoever was in the last scene
  # played in this location -- and that is the whole of what changed. Nothing
  # recorded where anybody stood, so the cast was reconstructed on every
  # arrival out of the last scene that happened to have written one, and a
  # place nobody had visited was empty however central the person standing in
  # it was. Arriving at The Tide Post recorded the protagonist alone, on all
  # three runs checked, in a world whose premise is Neb Halloran chained to
  # that post. The record answers that outright, and the cast this returns is
  # now written INTO the Scene from the records rather than being the only
  # place the records ever existed. See `Character`'s header.
  #
  # THE PARTY IS STILL DERIVED and always will be: the protagonist and their
  # companions are wherever the PLAYTHROUGH is, and two players walking the
  # same world stand in different rooms at once, so a story-level column on
  # `characters` cannot hold that. This method is the one place the party and
  # the world's own people are added together.
  def characters_present
    return arrival_context.living if arrival_context

    ([ story.protagonist ] + companions + Character.present_in(location).to_a).compact.uniq
  end

  # The same answer without building an arrival. `Playthrough::Classifier` needs
  # to know who the player can speak to, and that has to be the same list the
  # arrival narration introduced them to -- a classifier that worked it out
  # separately would sooner or later refuse to talk to someone the game had
  # just put in the room.
  def self.characters_present(location)
    new(location).characters_present
  end

  def agent
    @agent ||= BaseAgent.new(purpose: "arrival", playthrough: @playthrough).with_instructions(system_prompt)
  end

  def system_prompt = EngineData.fetch("scene/generator").fetch("system_prompt")

  def arrival_prompt(returning, elapsed, cast)
    prompt = <<~PROMPT
      ## Universe Details
      #{story.universe.prompt_details(:scene)}
      ## Story Details
      title: #{story.title}
      genre: #{story.genre}
      summary: #{story.summary}

      ## The Place
      name: #{location.name}
      description: #{location.description}
      lore: #{location.lore}
      ways out: #{exit_names}

      ## Who Is Here
      #{cast_list(cast)}

      ## Just Before This
      #{lead_in}

      ## Instructions
      #{arrival_instructions(returning, elapsed)}
      - Address the player as "you", in the present tense
      - One paragraph. Do not re-describe the place item by item -- the
        description above is already what is here, and your job is the moment
        of coming into it
      - Anyone listed above is here; write them as already present, not as
        arriving. Do not add a person who is not on that list
      - Do not name a way out that is not on the list above
      - Respect the stated length of each field
    PROMPT
    return prompt unless arrival_context

    prompt += <<~PROMPT

      ## Current State On Arrival
      The place description is the world's original account. These current records
      take precedence over its claims about people, items and wounds. Narrate the
      recorded crossing result as part of this arrival.
      #{arrival_context.facts.join("\n")}
    PROMPT
    return prompt if reacted.empty?

    prompt + <<~PROMPT

      ## As You Come In
      These people reacted to your arrival, recorded by the game. Narrate each as part of this arrival, in the order given. Anyone below who walked out is seen leaving as you come in; add nobody else. Nothing anyone says changes what is recorded above.
      #{reacted.join("\n")}
    PROMPT
  end

  # WHAT THE PEOPLE HERE DID AS THE PARTY CAME IN, in id order: the fact of
  # each reaction that went through. Silence writes no row, and a reaction that
  # stayed put or could not be taken tells nothing.
  def reacted
    return [] if @reactions.empty? || @playthrough.nil?

    @playthrough.volitions.where(id: @reactions, status: "applied").order(:id).pluck(:fact)
  end

  private

  # The story has a complete arrival by this point. Filing its model messages
  # is diagnostic bookkeeping; a failure there must not stop the move or make
  # a caller append a second arrival as recovery.
  def attribute_to(scene)
    agent.attribute_to!(scene)
  rescue StandardError => error
    Rails.logger.warn("Arrival attribution failed: #{error.class}")
  end

  # THROUGH `BaseAgent#ask`'s `verify:` SEAM, so an answer the provider cut
  # off at a cap is a failed call that rotates, and an arrival no model
  # finished falls to `#fallback!` -- rather than half a sentence being kept
  # as the moment and shown to the player.
  def finished!(content)
    Scene::Schema::MAX_LENGTHS.each do |field, cap|
      sanitize_string(content[field.to_s], max_length: cap)
    end
  end

  def arrival_context
    @arrival_context ||= Scene::ArrivalContext.new(@playthrough, location: location, at: story_timestamp) if @playthrough
  end

  # The exact destination receipt handed to the arrival writer. A Location's
  # durable description and the playthrough's live state can diverge later, so
  # prose verification must not try to reconstruct this snapshot after the
  # player has moved another item or person.
  def arrival_engine_fact
    arrival_context&.facts&.join("\n")
  end

  def persist_arrival!(answer, cast:, at:, engine_fallback: false, engine_fact: nil)
    @completed_scene = Scene.create!(
      story: story,
      location: location,
      previous_scene: previous_scene,
      characters: cast,
      description: sanitize_string(answer["description"]),
      summary: sanitize_string(answer["summary"]),
      engine_fact: engine_fact,
      is_opening: opening?,
      story_timestamp: at,
      **(engine_fallback ? { engine_fallback: true } : {})
    )
  end

  # The two shapes this generator exists to tell apart.
  #
  # The discovery line says "what catches them on the way in" and not "what
  # catches them FIRST": the model took the word as the opener, and "The first
  # thing that strikes you" began most first visits. Dropping it moved the
  # arrival bench's `first_thing_opener` reading from 22 to 14 of 36, a real
  # difference with every other reading noise (`db/eval/arrival-first-visit-2026-09-28`
  # against `arrival-branches`). The opener still occurs; it is no longer invited.
  def arrival_instructions(returning, elapsed)
    texts = EngineData.fetch("scene/generator")
    return texts.fetch("arrival_first") unless returning

    format(texts.fetch("arrival_returning"), elapsed: distance_of_time_in_words(elapsed))
  end

  # Name, nickname and race -- the same ~15-token line `Character::Generator`
  # uses for its cast list. The narration needs to know who to mention, not who
  # they are; a character's full sheet belongs to a conversation with them.
  #
  # The protagonist is on the list -- they are the one arriving -- and is
  # MARKED as the player, because the instruction below says to write everyone
  # listed as already present. Unmarked, that reads as an instruction to write
  # the player into the room as a bystander they then meet.
  def cast_list(cast)
    lines = cast.map do |character|
      line = "#{character.fullname} (#{character.nickname}), #{character.race&.name}"
      character == story.protagonist ? "#{line} -- the player, the one arriving" : line
    end

    lines.join("\n").presence || (@playthrough ? "Nobody is alive here." : "Nobody but the player.")
  end

  def exit_names
    location.exits.pluck(:name).join(", ").presence || "None written yet."
  end

  # The link backwards, told as one line. The previous scene's summary is
  # preferred over its description for exactly the reason the summary is
  # written: it is the same moment in a fraction of the tokens.
  def lead_in
    return "Nothing. This is where the story opens." if previous_scene.nil?

    from = origin
    coming_from = from && from != location ? "The player has come from #{from.name}. " : ""

    "#{coming_from}#{previous_scene.summary.presence || previous_scene.description}"
  end

  def companions
    story.characters.where(is_companion: true).to_a
  end
end
