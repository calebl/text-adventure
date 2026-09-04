# WHAT A READABLE THING SAYS, WRITTEN DOWN ONCE.
#
# The second and last writer of `Item#inscription`. `Item::Registry` is the
# first and the ordinary one: a thing realized with a room is born with its
# words out of the same call that described the room. This exists for the
# readable thing that has none -- a seeded note whose file did not spell one
# out, or a row written before the columns existed -- and it fills that gap
# exactly once, on the first read, as a RECORD and before any narration.
#
# WHY THE RECORD AND NOT THE PROSE. The narrator can write what a note says. It
# did, in the captain's own game: the player picked up "the folded note" and the
# paragraph said "Midnight. The Bell. They know about the maps." -- and nothing
# kept it, so the next reading was free to say something else. That is the
# standing constraint's own example (AGENTS.md): the engine owns the state and
# the prose is told. A note whose text lives only in a paragraph is a note whose
# text drifts.
#
# THE GATE IS `readable`, AND IT IS THE WHOLE GATE. Nothing here decides whether
# a thing has writing on it -- `Item::Registry` decides that at realization and
# a seed file decides it by hand. Ask this for a ward stamp and it returns nil
# without a call: an item nobody marked readable never gets text generated for
# it, which is what stops "everything in the world quietly grows a paragraph".
#
# ONCE. `#inscribe!` returns the stored words when there are stored words, so a
# second reading of the same note is a database read and no model call at all.
# That is the same "generate once per place" guarantee `Location::Generator`
# makes, on a smaller record.
class Item::Inscriber
  include SanitizesGeneratedText

  attr_reader :item, :playthrough

  # `playthrough` is only what the conversation gets filed under (see Chat), so
  # the turn that paid for this call is the turn it shows up under on the debug
  # page. World-building callers with no playthrough leave it out.
  def initialize(item, playthrough: nil)
    @item = item
    @playthrough = playthrough
  end

  # The words on this thing, or nil if it has none to have. Generates exactly
  # once and never again; raises what `BaseAgent` raises, because a failed call
  # is a failed turn and a swallowed one would leave the player reading a note
  # the records still do not hold.
  def inscribe!
    return nil unless item.readable?
    return item.inscription if item.inscription.present?

    item.update!(inscription: written_words)
    item.inscription
  end

  # The conversation, so a caller can file it under the scene the turn produced
  # (`BaseAgent#attribute_to!`) the way `Playthrough::Turn#move_to` files a
  # realization. Nil when nothing was asked.
  def agent
    @agent ||= BaseAgent.new(purpose: "inscription", playthrough: playthrough)
                        .with_instructions(INSTRUCTIONS)
  end

  def asked? = !@agent.nil?

  INSTRUCTIONS = <<~PROMPT.freeze
    You write the words that are actually written on objects in a text
    adventure: what is on a note, a letter, a docket, a label, a sign, a page.

    You are not narrating and you are not describing the object. You write only
    the text a person would read off it, in the hand and the register of the
    world it belongs to.

    DO NOT INCLUDE EMOJIS IN YOUR RESPONSE.
  PROMPT

  private

  # THROUGH `BaseAgent#ask`'s `verify:` SEAM, so a provider that cut the answer
  # off is a failed call that ROTATES rather than a raise outside the loop. It
  # is the same argument `InteractionAgent#ask` makes and it matters more here:
  # this field is written once and then quoted to the player verbatim on every
  # later reading, so half a sentence would be half a sentence forever.
  def written_words
    words = nil

    agent.with_schema(Item::InscriptionSchema).ask(
      prompt,
      verify: ->(content) { words = sanitize_string(content["inscription"], max_length: Item::INSCRIPTION_LIMIT) }
    )

    raise BaseAgent::SchemaIgnoredError, "the inscription for #{item.name.inspect} came back empty" if words.blank?

    words
  end

  # EVERYTHING THE WORDS HAVE TO BE CONSISTENT WITH, and no more than that. The
  # world, the thing itself, and where it is -- which is what somebody writing
  # the note would have known. Deliberately NOT the playthrough's recap or the
  # last turn's prose: an inscription is a fact about the OBJECT, written
  # whenever it was written, and a note that answers the turn the player is
  # having is a note the world did not have in it a moment earlier.
  def prompt
    <<~PROMPT
      #{story_context}

      ## The Thing
      name: #{item.name}
      what it is: #{item.description}
      #{whereabouts_line}

      ## Instructions
      Write what is written on the #{item.name}.
      - The text itself, as it appears on the object. Not a description of it
      - Consistent with the world above and with what the thing is
      - Whoever wrote it wrote it before now, for their own reasons, and not for
        the person reading it
      - It may be a few words, a line, or a short paragraph. Short is usual
      - Respect the stated length
    PROMPT
  end

  # WHERE THE THING IS, in the words `Item#whereabouts` already answers in --
  # the same sentence `rake game:doctor` prints -- plus the room's own
  # description when it is lying in a written room, because a docket nailed to a
  # wall says something about that wall.
  #
  # A thing somebody is HOLDING gets the sentence and no room. Nothing records
  # where a character stands (ROADMAP, *nothing records where a character
  # stands*), so whose hands it is in is honestly the whole of what the records
  # can say -- and a room guessed at here would be a guess written into a field
  # that is never regenerated.
  def whereabouts_line
    place = item.location
    return "where it is: #{item.whereabouts}" if place.nil?

    "where it is: #{item.whereabouts}\n#{place.name}: #{place.description.presence || place.teaser}"
  end

  def story
    @story ||= item.location&.story || item.character&.story
  end

  def story_context
    return "" if story.nil?

    <<~CONTEXT
      ## Universe Details
      #{story.universe&.prompt_details(:place)}

      ## Story Details
      title: #{story.title}
      genre: #{story.genre}
      preface: #{story.preface}
      summary: #{story.summary}
    CONTEXT
  end
end
