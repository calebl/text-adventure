# WHAT THE ENGINE SAYS WHEN IT WILL NOT PLAY A LINE, and the one author of it.
#
# THE CAPTAIN'S RULING, 2026-09-04, in his words:
#
#   *"If someone tries to do two things or more at a time, we should refuse and
#   prompt the player to pick only 1 thing. Or if we can't determine what they
#   are trying to do, then we should refuse and ask for clarification. This can
#   all be in the mechanics and doesn't need to go through narration."*
#
# So a refused line is a turn that DID NOTHING: no row moves, no `Scene` is
# written, the story's clock does not advance, the playthrough does not move,
# and no narrator is asked for a sentence about it. What the player gets instead
# is this -- the app's own words, built out of records it is already holding,
# for no model call beyond the classifier that had already run.
#
# FIVE SHAPES, TOLD APART BECAUSE THEY ARE DIFFERENT FACTS -- three about the
# LINE, one about a THING the line named, and one about the game it was typed
# into:
#
#   :named_more_than_one  it named two things the records really have, and a
#                         turn is one act. Nothing named is missing; the limit
#                         is the loop's. Counted by `Playthrough::Overreach`.
#   :unresolved           it reached for a way out, a person or a thing the
#                         closed sets do not have. Counted by
#                         `Playthrough::Drift`. An `examine` is never this: a
#                         look is not reaching for a record it could have
#                         missed, which is why `Playthrough::Drift::ACTIONS`
#                         does not carry it and `Playthrough::Overreach::ACTIONS`
#                         does.
#   :immovable            IT NAMED A THING THAT DOES NOT MOVE. The one refusal
#                         shape that is a fact about a record rather than about
#                         the reading: a `throw` of something whose
#                         `Item::BULK` carries no penalty. No die is thrown,
#                         nothing happens and no story time is spent, which is
#                         what makes it a refusal instead of the FUMBLE a failed
#                         lift is -- a fumble is a turn the engine PLAYED and
#                         this is a turn it would not. Counted by nothing: it is
#                         neither drift (the reach resolved, twice) nor
#                         overreach (one act was asked for). See
#                         `data/ta-combat-scout` §13.3.
#   :unreadable           the classifier's own answer was unusable -- an intent
#                         outside `Playthrough::IntentSchema::INTENTS` that
#                         still named a record. Nothing counts it, because it is
#                         a defect on our side rather than a reach on the
#                         player's; it goes to the log.
#   :dead                 THE PLAYER IS DEAD AND THE GAME IS OVER -- the
#                         captain's ruling of 2026-09-04. It is not a reading of
#                         a line at all: it is refused BEFORE the classifier
#                         runs, so it costs no model call and no line is ever
#                         read again in this playthrough. It is the one shape
#                         here that is a fact about the GAME rather than about
#                         the line, which is why it is built from
#                         `Playthrough::DeathNotice` and not from an `Intent`,
#                         and why `.for` never returns one. Counted by nothing:
#                         a dead player reaching for nothing is not drift.
#
# THE COUNTERS ARE UNTOUCHED BY THE RULING, and that is deliberate: it changes
# what a turn DOES, not what is measured. `Playthrough::Classifier#classify`
# writes the `Playthrough::Overreach` or `Playthrough::Drift` row before the
# loop ever asks whether the line is refused, from exactly the place it always
# did, and both are free.
#
# WHAT IS *NOT* REFUSED, because the line matters as much as the rule. A
# coherent non-mechanic line -- `other`, or an `examine` that landed on nothing
# -- is not undeterminable. "look at the sky", "wait", a remark to nobody: the
# classifier placed them, they reach for no record they could have missed, and
# they stay narrated. Refusing them would refuse everything that is not one of
# the acts that move a row, which is a different game. An `examine` that named
# TWO things IS refused, like any other line asking twice: a readable thing
# named alongside another thing is one line asking for two acts.
#
# WHY A REFUSAL IS NOT A `Scene`. It is the app talking rather than the world,
# which is the same argument `Playthrough::SafetyNotice` and
# `Playthrough::TurnFailureNotice` are made of, and it is also what the
# instruments require: `Scene#description` is read as NARRATION by
# `Story::Audit`, `Eval::Richness` and both frozen corpora, and a row of engine
# copy in that column would be audited as prose the narrator wrote. A refusal
# also has no moment in it -- `Scene`'s `after_create` stamps
# `Location#last_protagonist_visit` and `Story#clock` is
# `MAX(scenes.story_timestamp)` -- so writing one would move story time on a
# turn whose whole point is that nothing happened. The durable record of a
# refused line is the counter row, which is the table built to hold exactly it.
#
# `#reason` AND `#text` ARE THE SAME COPY IN TWO ORDERS, because the two
# consumers differ in one respect and only one. `Playthrough::Mechanics` prints
# the whole engine read-out under every refusal, so it reads `#reason` and the
# lists are printed once. The browser has no read-out, so it reads `#text` --
# the same fact with what IS here folded into the middle of it, which is the
# answer a player standing in the wrong room needs. The pieces are held apart
# (`fact`, `offer`, `UNCHANGED`) so that both orders read as English rather than
# as one string with another bolted onto the end.
class Playthrough::Refusal
  KINDS = %i[named_more_than_one unresolved immovable unreadable dead].freeze

  # ONE ACT, PHRASED AS THE PLAYER WOULD HAVE TYPED IT, so a refusal that says
  # "pick one" is naming two things somebody can actually pick between.
  #
  # Bare names, no article: it is the house style for everything the engine says
  # about a record (`Playthrough::Mechanics` names what would have worked the
  # same way), and "take the Perrin's private index" reads as a mistake.
  # `examine` is here because a look resolves a record too since
  # `ta-item-inscriptions` -- against both item sets at once -- so "read the note
  # and the index" is one line asking for two acts like any other, and the pair
  # has to be sayable. `read` rather than `examine`, because that is the word a
  # player types.
  ASKED = {
    move: "go to %s",
    talk: "talk to %s",
    take: "take %s",
    drop: "drop %s",
    examine: "read %s",
    # WHAT A THROW ASKS FOR, in the word a player types. Unreachable TODAY and
    # here anyway: only `:named_more_than_one` reads this table, and a throw's
    # `also_named` is always nil because the fixed grammar produces none. It is
    # the entry the seventh classifier intent will need (slice 8), and a table
    # missing a row for an action `Scene::ACTIONS` already has would fall back to
    # a bare `%s`.
    throw: "throw %s"
  }.freeze

  # WHY THE REACH RESOLVED TO NOTHING, and it is two different facts told apart:
  # the set was empty, or the set had things in it and the command did not land
  # on one of them. It used to be one sentence for both, so "pickup everything"
  # in a room with three things on the floor was refused with "Nothing of that
  # name is lying here" -- printed directly above a read-out listing all three.
  # The command had named no name at all.
  #
  # NEITHER SAYS WHAT THE PLAYER TYPED. The classifier answered `nothing`; it
  # never said which words in the line it could not place, and a refusal that
  # guesses at that is how a wrong guess gets stated as a fact.
  MISSED = {
    move: "That did not resolve to one of the ways out of here.",
    talk: "That did not resolve to anybody who is here.",
    take: "That did not resolve to anything lying here.",
    drop: "That did not resolve to anything you are carrying."
  }.freeze

  EMPTY = {
    move: "There is no way out of here at all.",
    talk: "There is nobody here to talk to.",
    take: "There is nothing lying here to pick up.",
    drop: "You are carrying nothing, so there is nothing to put down."
  }.freeze

  NOTHING_MATCHED = "That resolved to nothing.".freeze

  # WHAT IS ACTUALLY HERE, for the consumer that has no read-out under it. Only
  # ever printed when the set has something in it: `EMPTY` has already said the
  # set is empty, and "Lying here: nothing" says it twice and worse.
  OFFERS = {
    move: "The ways out are: %s.",
    talk: "Here with you: %s.",
    take: "Lying here: %s.",
    drop: "You are carrying: %s."
  }.freeze

  # Said on every shape, because on every shape it is the thing the player most
  # needs to know: the line they typed did not half-happen.
  UNCHANGED = "Nothing has changed.".freeze

  attr_reader :kind, :typed, :fact, :offer

  # THE REFUSAL A CLASSIFIED LINE EARNS, or nil when the loop can play it.
  #
  # One entry point on purpose: `Playthrough::Classifier::Intent#refused?` is
  # the predicate and this is the sentence, so `Playthrough::Turn` and
  # `Playthrough::Mechanics` cannot come to disagree about which lines are
  # refused or about what a refusal says. The order matches `#refused?`.
  #
  # `offered` is the closed set the action reads against
  # (`Playthrough::Classifier#offered_for`) and is only read by the
  # `:unresolved` shape -- the other two name records they already hold.
  def self.for(intent, typed:, offered: [])
    return named_more_than_one(intent, typed: typed) if intent.named_more_than_one?
    return unresolved(intent, typed: typed, offered: offered) if intent.reached_for_nothing?
    return unreadable(typed: typed) if intent.unreadable?
    return immovable(intent, typed: typed) if intent.throws_the_immovable?

    nil
  end

  # THE LINE NOBODY WILL EVER PLAY AGAIN, and the second public entry point.
  #
  # It is separate from `.for` because it is not a reading of the line: there is
  # no `Intent` and there never will be one, since a dead playthrough is refused
  # in front of the classifier so that a turn after death costs nothing at all.
  # Both modes call it from the same place -- the first statement of
  # `Playthrough::Turn#play` and of `Playthrough::Mechanics#run` -- so the
  # browser and `rake game:mechanics` cannot come to disagree about whether a
  # game is over.
  #
  # The words are `Playthrough::DeathNotice`'s, which is the one author of what
  # a dead player is told; read its header before changing any of them.
  def self.dead(typed:, character: nil)
    new(kind: :dead, typed: typed, fact: Playthrough::DeathNotice.sentence(character))
  end

  # TWO ACTS ON ONE LINE. Both halves are named, in the same verb, because they
  # came out of the same closed set through the same matcher -- see
  # `Playthrough::Classifier#also_record`.
  def self.named_more_than_one(intent, typed:)
    new(kind: :named_more_than_one, typed: typed,
        fact: "You asked for two things at once: #{asked(intent.action, intent.subject)}, " \
              "and #{asked(intent.action, intent.also_named)}. One line is one act -- " \
              "pick one and type it on its own.")
  end

  # A THING THAT DOES NOT MOVE FOR ANYBODY. The item is named and so is what
  # made it unliftable, because the answer a player needs is which of the things
  # in their hands they CAN throw -- and `Item::BULK`'s labels are the whole of
  # that vocabulary.
  #
  # No `offer`: what else is being carried is not the answer, and the closed set
  # for a throw is two sets rather than one. The engine says why this thing
  # stayed put and stops.
  def self.immovable(intent, typed:)
    item = intent.item

    new(kind: :immovable, typed: typed,
        fact: "The #{item.name} is #{item.bulk} and does not move for anybody: it cannot be picked up " \
              "and thrown at all, so no die was thrown for it.")
  end

  def self.unresolved(intent, typed:, offered: [])
    records = Array(offered)

    new(kind: :unresolved, typed: typed,
        fact: missed(intent.action, records),
        offer: offer(intent.action, records))
  end

  # THE CLASSIFIER ANSWERED SOMETHING THIS APP DOES NOT HAVE, while still
  # naming a record. It should not be reachable -- `intent` is a closed enum --
  # which is exactly why it is worth a branch rather than a coercion: the
  # coercion read it as `other`, dropped the record on the floor and narrated
  # the raw line, so a provider ignoring the table looked like a player musing
  # about the weather.
  def self.unreadable(typed:)
    new(kind: :unreadable, typed: typed,
        fact: "That did not come back as anything the game knows how to do. " \
              "Say it again as one plain action -- go somewhere, talk to somebody, " \
              "take something, or put something down.")
  end

  def self.asked(action, record)
    format(ASKED.fetch(action.to_sym, "%s"), Playthrough::Classifier.label_for(record))
  end

  def self.missed(action, records)
    table = records.empty? ? EMPTY : MISSED

    table.fetch(action.to_sym, NOTHING_MATCHED)
  end

  def self.offer(action, records)
    return nil if records.empty?

    template = OFFERS[action.to_sym]
    return nil if template.nil?

    format(template, records.map { |record| Playthrough::Classifier.label_for(record) }.join(", "))
  end

  private_class_method :named_more_than_one, :unresolved, :immovable, :unreadable, :asked, :missed, :offer

  def initialize(kind:, typed:, fact:, offer: nil)
    raise ArgumentError, "#{kind.inspect} is not one of #{KINDS.inspect}" unless KINDS.include?(kind)

    @kind = kind
    @typed = typed.to_s
    @fact = fact
    @offer = offer
  end

  # WHETHER THIS IS A LINE THE ENGINE WOULD NOT PLAY, or a GAME that is over.
  # The three reading shapes leave the player standing where they were with
  # another line to type; `:dead` does not, so neither answer ends with
  # `UNCHANGED` -- "nothing has changed" is an invitation to try again, and
  # there is nothing to try.
  def game_over? = kind == :dead

  # FOR THE CONSUMER THAT PRINTS THE RECORDS UNDERNEATH: the fact and nothing
  # else, so the lists are said once.
  def reason = game_over? ? fact : "#{fact} #{UNCHANGED}"

  # AND FOR THE ONE THAT DOES NOT: what would have worked, in the middle, where
  # it reads as part of the answer rather than as an appendix to it.
  def text = [ fact, offer, (UNCHANGED unless game_over?) ].compact_blank.join(" ")

  def to_s = text
end
