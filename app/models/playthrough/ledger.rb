# WHAT ONE PERSON SAW HAPPEN, IN ONE GAME, BOUNDED.
#
# `Playthrough::Memory` is the other half of this and stays exactly as it is:
# it is bounded lexical recall over CONVERSATIONS, and it can only ever recall
# an exchange this character had with the player. A character who watched the
# player take the daybook off the table has no memory of it there, because
# nothing in that table is about anything but talking.
#
# THIS IS THE REST OF WHAT THEY EXPERIENCED, and it needs no new table: every
# event it reports is already a row the engine wrote for its own reasons.
# The ledger only files them against a WITNESS.
#
#   their own acts    `playthrough_volitions` -- what they decided to do and
#                     what came of it (`Playthrough::Volition`).
#   blows             `playthrough_blows`, thrown by them or landed on them.
#   what the place    `playthrough_tolls`, in the room they were standing in.
#   took
#
# A READER AND NEVER A WRITER, and that is the whole reason it is a class
# rather than a fourth table. A copy of these events filed a second time would
# be a second writer of facts the engine already owns, and the two copies could
# disagree -- which is the defect `Playthrough::Moment#personal_facts` was
# quietly one step away from, assembling its own three-row blow ledger inline
# on every prompt.
#
# BOUNDED TWICE, so a long playthrough's prompt cost stays flat: `ROWS` caps
# how many events are considered at all, and `BUDGET` caps the characters they
# are allowed to spend -- the same pair `Playthrough::Moment::MEMORIES_BUDGET`
# and `Playthrough::Memory` already use, and the same reason. A game forty
# turns in must cost the same per turn as a game four turns in.
#
# NEWEST LAST, OLDEST DROPPED. The rows are read newest-first so that what is
# dropped when the budget runs out is the oldest thing, and handed back in
# chronological order so that a prompt reads them the way they happened.
#
# EVERY LINE IS A RECORD, which is the rule the prompt this feeds is under
# (`Playthrough::Moment#character_context`): the sentences are the engine's own
# `fact` columns, and none of it is prose a model wrote.
class Playthrough::Ledger
  # HOW MANY EVENTS ARE EVEN LOOKED AT. `Playthrough::Moment::PERSONAL_BLOWS`
  # was three, of one kind; this is the same order of magnitude over three
  # kinds, which is what keeps the block a few lines rather than a history.
  ROWS = 8

  # AND HOW MANY CHARACTERS THEY MAY SPEND. Sized against
  # `MEMORIES_BUDGET`'s 1,200: this block sits beside that one in the same
  # prompt, and it is the shorter of the two because an engine fact is one
  # sentence where a recollection is an exchange.
  BUDGET = 800

  Event = Data.define(:at, :id, :sentence)

  attr_reader :playthrough, :character

  def initialize(playthrough, character)
    @playthrough = playthrough
    @character = character
  end

  # THE SENTENCES, OLDEST FIRST, INSIDE BOTH BOUNDS.
  #
  # `location:` NARROWS THE TOLLS AND NOTHING ELSE, because a toll is a fact
  # about a ROOM and the only tolls this person witnessed are the ones taken
  # where they were standing. A blow and their own act already name them, so
  # they need no room to be theirs.
  def recall(location: nil)
    rows = (own_acts + blows + tolls_in(location)).sort_by { |event| [ event.at.to_i, event.id ] }
    within_budget(rows.last(ROWS)).map(&:sentence)
  end

  private

  # WHAT THEY DID, out of the receipts `Playthrough::Volition` wrote. `wait`
  # rows are in it: a character who has stood in the same room for six turns
  # knowing it is worth a sentence, and it is the one source here that says
  # anything about what they have been CHOOSING.
  def own_acts
    playthrough.volitions.where(character: character).order(id: :desc).limit(ROWS)
               .map { |row| Event.new(at: row.created_at, id: row.id, sentence: "You: #{row.fact}") }
  end

  def blows
    playthrough.blows.where(attacker: character).or(playthrough.blows.where(target: character))
               .includes(:attacker, :target, :location).order(id: :desc).limit(ROWS)
               .map do |blow|
      Event.new(at: blow.created_at, id: blow.id,
                sentence: "You experienced this recorded blow: #{blow.attacker.fullname} struck " \
                          "#{blow.target.fullname} for #{blow.damage} hit points in #{blow.location.name}. " \
                          "This is a past event; your condition above is current.")
    end
  end

  # WHAT THE PLACE TOOK IN FRONT OF THEM. Nothing at all where the caller names
  # no room, because a toll with nobody who saw it is a fact about the world
  # rather than about this person.
  def tolls_in(location)
    return [] if location.nil?

    playthrough.tolls.where(location: location).includes(:character, :location)
               .order(id: :desc).limit(ROWS)
               .map do |toll|
      Event.new(at: toll.created_at, id: toll.id, sentence: "You saw this happen here: #{toll}")
    end
  end

  # OLDEST DROPPED WHEN THE BUDGET RUNS OUT, and the drop is silent here rather
  # than stated -- unlike `Playthrough#recap`, which says so, because that one
  # is the player's own history and this is somebody's recollection. A person
  # who has forgotten the earliest thing does not announce it.
  def within_budget(rows)
    spent = 0
    kept = []
    rows.reverse_each do |event|
      break if spent + event.sentence.length > BUDGET

      spent += event.sentence.length
      kept.unshift(event)
    end
    kept
  end
end
