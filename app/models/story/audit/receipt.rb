# WHAT A SCENE'S ENGINE RECEIPT SAYS, read back out of the exact words the
# engine wrote into `Scene#engine_fact`.
#
# THE RECEIPT IS THE RECORD AND THIS ONLY READS IT. `Scene#engine_fact` holds
# the sentences the app supplied to a scene's prose writer, frozen at the moment
# it wrote them -- `Scene::ArrivalContext#facts` on a playthrough arrival,
# `Playthrough::NpcAction#apply!` on a conversation. Both are fixed templates,
# so a line either has one of the shapes below or it says nothing this class
# can read. Nothing here reconstructs a receipt from rows that may have moved
# since, which is the whole reason the column exists.
#
# WHAT IT READS, and only lines a check here needs:
#
#   Dead here: A, B. They cannot speak or act.     -> #dead
#   Also here: A, B. Nobody else is alive here.    -> #living
#   Lying here: a, b.                              -> #lying
#   You are carrying: a, b.                        -> #carried
#   <name> changes no possessions, travel ...      -> #possessions_unchanged?
#   The proposed action was rejected: ... changed. -> #possessions_unchanged?
#
# AND IT HOLDS THE COMPARISON, so there is one reading of a receipt against a
# passage: `Story::Audit#check_receipt` turns `#contradictions` into flags, and
# `Story::Audit::ReceiptTest` measures the same method over stored evaluation
# sets that have no database behind them. A measurement that re-implemented the
# comparison would be measuring a second reading that could drift from this one.
#
# A NAME IS SPLIT ON ", " because that is how the writers join a list. A name
# that itself holds ", " is read as two, and the halves are then scanned for as
# names of their own; no name in a checked-in world holds one. The readers
# are pinned to the writers in `Story::Audit::ReceiptTest`, which builds each
# receipt through the real writer rather than copying its words.
class Story::Audit::Receipt
  Prose = Story::Audit::Prose

  DEAD = /\ADead here: (?<names>.+)\. They cannot speak or act\.\z/
  ALSO_HERE = /\AAlso here: (?<names>.+)\. Nobody else is alive here\.\z/
  LYING = /\ALying here: (?<names>.+)\.\z/
  CARRIED = /\AYou are carrying: (?<names>.+)\.\z/

  # The two receipts that say, in words, that no possession moved: a character
  # who chose no effect, and a proposed effect the engine refused.
  UNCHANGED = [
    / changes no possessions, travel agreement or ceasefire\.\z/,
    /\AThe proposed action was rejected: .+ No possessions, travel agreement or ceasefire changed\.\z/
  ].freeze

  # THE CHECKS THIS READS, and the turn a receipt for each is written on. A
  # scene of that shape with no receipt is counted unjudged by `Story::Audit`.
  SHAPES = { dead_shown_alive: :arrival, carried_shown_lying: :arrival, handover_invented: :talk }.freeze

  # One sentence of prose that says otherwise. `subject` is the person or the
  # thing the receipt names, nil for a handover (the receipt names neither).
  Contradiction = Data.define(:code, :subject, :claim)

  attr_reader :text

  # Nil for a scene with no receipt, and for a scene out of a database whose
  # `scenes` table predates the column (`Scene#recorded_engine_fact`).
  def self.for(scene)
    text = scene.recorded_engine_fact
    new(text) if text.present?
  end

  def initialize(text)
    @text = text.to_s
  end

  def dead = names_on(DEAD)

  def living = names_on(ALSO_HERE)

  def lying = names_on(LYING)

  def carried = names_on(CARRIED)

  def possessions_unchanged? = lines.any? { |line| UNCHANGED.any? { |shape| line.match?(shape) } }

  # Whether this receipt states the fact `code` reads: the check's denominator.
  def states?(code)
    case code
    when :dead_shown_alive then dead.any?
    when :carried_shown_lying then (carried - lying).any?
    when :handover_invented then possessions_unchanged?
    else false
    end
  end

  # EVERY SENTENCE OF `prose` THAT SAYS WHAT THIS RECEIPT SAYS IS NOT SO, at
  # most one per person or thing. `protagonist` is the player's names, which a
  # dead person's name must not share (the receipt never names the player).
  def contradictions(prose, protagonist: [])
    return [] if prose.blank?

    dead_shown_alive(prose, protagonist) + carried_shown_lying(prose) + handover_invented(prose)
  end

  private

  # A NAME THE DEAD SHARE WITH THE LIVING IS DROPPED, not guessed at: with a
  # dead Maren Vosk and a living Maren Holt in one room, "Maren stands" is
  # about whichever of them the prose means.
  def dead_shown_alive(prose, protagonist)
    alive = (living.flat_map { |name| Prose.character_names(name) } + protagonist).map(&:downcase)

    dead.filter_map do |person|
      names = Prose.character_names(person).reject { |name| alive.include?(name.downcase) }
      claim = Prose.living_claims(prose, names).first
      Contradiction.new(code: :dead_shown_alive, subject: person, claim: claim) if claim
    end
  end

  # An alias a carried thing shares with something lying here is dropped for
  # the same reason: "the daybook on the desk" may be the other daybook.
  def carried_shown_lying(prose)
    here = lying.flat_map { |name| Prose.item_names(name) }.map(&:downcase)

    (carried - lying).filter_map do |item|
      names = Prose.item_names(item).reject { |name| here.include?(name.downcase) }
      claim = Prose.lying_claims(prose, names).first
      Contradiction.new(code: :carried_shown_lying, subject: item, claim: claim) if claim
    end
  end

  def handover_invented(prose)
    return [] unless possessions_unchanged?

    claim = Prose.handover_claims(prose).first
    claim ? [ Contradiction.new(code: :handover_invented, subject: nil, claim: claim) ] : []
  end

  def lines = @lines ||= text.split("\n").map(&:strip)

  def names_on(shape)
    lines.filter_map { |line| line.match(shape)&.[](:names) }
         .flat_map { |names| names.split(", ") }
         .map(&:strip)
         .reject { |name| name.blank? || name == "nothing" }
         .uniq
  end
end
