# HOW POPULATED A PLACE IS, and the whole of how that gets decided.
#
# THE CAPTAIN'S RULING, 2026-09-07, and it REVISES an earlier one of his own:
# *"revisit my ruling about nobody being in a room as the ordinary case. Where
# does that come from? I don't think I agree with it anymore. The narrarator
# should get to decide how populated a room should be."* Offered a closed-list
# pick with the engine rolling the exact count inside the band, or the model
# naming as many people as it liked up to the cap, he chose: *"go with the
# closed-list pick."*
#
# SO THE SPLIT IS: THE MODEL PICKS A WORD, THE ENGINE PICKS THE NUMBER. That is
# the standing constraint (AGENTS.md) with the decision handed back to prose as
# far as it can honestly go and no further -- *do not ask a model what should
# happen; ask it to pick from a set the app closed, then have the app act.* The
# set is `LABELS`, the acting is `.count_for`, and the model never writes a
# number: it cannot answer four in a room the classifier can only offer three
# names out of, and it cannot answer nothing in a room it just described as a
# market.
#
# WHAT THIS REPLACES, said plainly because it was in the app for three days and
# is the reason the item existed. `Character::Registry#slots` used to roll a
# CEILING and the realization prompt offered it with "AT MOST", alongside the
# sentence *"NOBODY is the right answer for most rooms."* So the engine decided
# WHO and the MODEL decided HOW MANY, and it decided zero: story 7, The Iron
# Gate Descends, reached a player with one character in it, and that character
# was the player. Both halves of that are gone -- the ceiling and the sentence.
#
# AND THE REJECTED ALTERNATIVE IS THE OTHER DIRECTION: an engine-authored
# weighted table with nobody as the mode, which is what the neohack scout
# proposed and what the ruling above overturned before it was built. A table
# whose mode is nobody is the ceiling's defect moved indoors -- it produces the
# same empty world, only now the engine is the one deciding it, and the prose
# that knows a market is busy has no way to say so.
#
# THE TABLE IS LABEL -> BAND, AND THE LIST IS THE BAND'S WEIGHTING --
# `Location::Danger::ROLLED`'s shape and `Character::HIT_DICE`'s, chosen for
# that shape's reason: `Roll.one_of` draws one entry, so a count written twice
# in a band is twice as likely, and there is no second table of probabilities to
# keep in step with the first. `Location::DANGERS`' doctrine one file over
# applies whole: the labels are what a person writing a world reads, the numbers
# are what the engine rolls, and a free number is a field something outside the
# engine could fill in wrongly.
#
# WHY THE TOP OF THE WIDEST BAND IS THE ROOM CAP AND NOT MORE. A crowd is
# written in PROSE -- the description says market, and it should -- while the
# people the engine writes rows for are the people the player can walk up to and
# TALK to. Every one of those goes into `Playthrough::IntentSchema`'s closed
# enum by fullname AND nickname on every single turn, which is what
# `Character::Registry::MAX_PER_ROOM` is three for. So `a crowd` means "as many
# as this game can let you address", not "as many as are in the room", and the
# gap between the word and the row count is the honest one rather than a
# shortfall.
#
# WHERE THE PICK COMES FROM, and it is not the call that describes the room.
# `Character::Registry#slots` states WHO each person is in the detail prompt
# before the model answers, so how many slots there are has to be known BEFORE
# that prompt is built -- and the detail call is the first call a room gets. So
# the pick rides on the EXITS call of the room NEXT DOOR, per named exit, and is
# stored on the stub row as it is created (`Location::Generator.create_stub!`).
# It is `location_connections.distance`'s shape exactly: a fact about a place
# the model answers for while it is naming the way there.
#
# A ROW WITH NO LABEL IS THE ORDINARY CASE AND NOT AN ERROR, and there are four
# ways to be one:
#
#   the opening room     built unsaved with the story (`Story::Generator`), so
#                        nothing ever named it as an exit. It rolls its label
#                        from `ROLLED` like any other unnamed room, which keeps
#                        the captain's ruling of 2026-09-05 -- *"the opening
#                        room should not guarantee at least one person. The
#                        protagonist can start by themselves."* -- true by the
#                        same table that makes it true of everywhere else.
#   a room of an interior `Location::Interior` lays out a building before
#                        anybody walks in and no model names its rooms; a room
#                        of one gets no exits call at all
#                        (`Location::Generator#write_exits!`).
#   a seeded room        a world file MAY write the key and an absent one is not
#                        filled in, on `WorldSeed::Loader`'s rule for every
#                        seeded parameter.
#   a row older than the column  every stub in every database that existed
#                        before this migration.
#
# All four take the same path: `.label_for` rolls one out of `ROLLED`, seeded on
# the room's NAME, so the answer is the same in any process for ever, the same
# after a world is exported and re-seeded, and no room is left without one. That
# method's comment and `Roll::POPULATION`'s have why it is the name and not the
# row.
#
# A SEEDED ROOM'S OWN CAST WINS, and that falls out rather than being enforced
# here: the count is clamped by `Character::Registry#room_for_people`, which is
# read back from the records, so a room a world file put three people in has no
# slots left whatever its label says. Nothing in this file or that one removes
# anybody.
#
# `Story::Doctor` DOES NOT CHECK THE LABEL AGAINST THE COUNT, and that is a
# decision rather than an omission: the roll is not a promise, the rows are the
# truth, and people arrive and leave for as long as the game runs. A room
# labelled `a crowd` whose two people walked off is a room two people walked out
# of. What the doctor still reports is a room or a world past the caps, exactly
# as it did.
module Location::Population
  # WHAT A PLACE MAY BE, AND HOW MANY PEOPLE EACH WORD MEANS. The keys are what
  # a model picks from and a seed file may write; the values are what the engine
  # rolls inside.
  #
  # THREE WORDS AND NOT FOUR, because a fourth would have to overlap: the room
  # cap is three people, so the whole of what a band can say is nobody, somebody,
  # or as many as the game can address. Two labels that drew the same numbers
  # would be a choice the model could get wrong with no difference to show for
  # it.
  #
  # `a person or two` LEANS TO ONE, which is the one place a weighting is used
  # rather than a range: two people in a room is two conversations and two sets
  # of six short fields on the same call, so the middle word means one person
  # more often than it means two. That is a statement about cost and about how a
  # room reads, not about how populated a world should be -- the shape of the
  # world is the model's pick, and this only spreads the word it picked.
  BANDS = {
    "nobody" => [ 0 ],
    "a person or two" => [ 1, 1, 2 ],
    "a crowd" => [ 2, 3, 3 ]
  }.freeze

  LABELS = BANDS.keys.freeze

  # WHAT A ROOM NOBODY PICKED FOR COMES OUT AS, and the list is the weighting.
  # Half of them are peopled and half are not -- so a world explored through its
  # interiors, and a player's very first room, meet somebody about as often as
  # one explored through its doors, and neither is guaranteed anybody. See the
  # header for the four ways to have no label.
  ROLLED = [ "nobody", "nobody", "a person or two", "a crowd" ].freeze

  # THE MOST PEOPLE ONE REALIZATION MAY BE ASKED FOR, read off the table rather
  # than written beside it: the schema's `max_items` and this file's widest band
  # cannot disagree if there is only one of them. It is
  # `Character::Registry::MAX_PER_ROOM` today, and that is not a coincidence to
  # be tidied away -- see the header on why a crowd stops at the room cap.
  MOST = BANDS.values.flatten.max

  # THE WORD FOR THIS ROOM, whether somebody chose it or not. A row that carries
  # a label is answered with it; a row that does not rolls one.
  #
  # AND THE ROLL IS SEEDED ON THE ROOM'S NAME, which is the one roll in the app
  # that is not seeded on a row -- `Roll::POPULATION`'s comment has the whole of
  # why and this is the half that belongs here. A word is a fact about a PLACE,
  # and a place's durable identity is its natural key rather than its id
  # (`WorldSeed.natural_key`, and `WorldSeed::Loader`'s whole matching doctrine):
  # a world exported and re-seeded is the same world, and every row in it has a
  # new id. Seeding on the id would give the same room a different word on every
  # load -- which is also what made the realization bench's staged worlds
  # unstable, since `Eval::Realization::Stage` re-loads a world per repetition.
  #
  # SO IT TAKES NO GENERATOR, and that is the visible difference from
  # `.count_for` below. The word is the ROOM's, decided once and the same for
  # ever; the count is THIS REALIZATION's, drawn from the generator the room's
  # cast is drawn from. `Location::Danger` already makes the same split between
  # what a room IS (`.for_a_new_room`, its own seed) and what one realization
  # does with it (`.generator_for`).
  def self.label_for(location)
    stored = location.population.presence
    return stored if BANDS.key?(stored)

    Roll.one_of(ROLLED, rng: Roll.generator(story: 0, sequence: key_for(location), kind: Roll::POPULATION))
  end

  # THE ROOM'S NAME AS AN INTEGER, through the same natural key the loader
  # matches a re-seeded room on -- so a room the file renamed only in its
  # article, or in its spacing, keeps the word it had.
  #
  # TWO WORLDS WITH A ROOM OF ONE NAME DRAW THE SAME WORD, and that is deliberate
  # rather than overlooked: `story: 0` is this file saying the roll does not
  # belong to a world, the way a stat block's `playthrough: 0` says it does not
  # belong to a game. Putting the story id in would undo the whole property above,
  # because a re-seeded world is a new story row.
  def self.key_for(location) = Zlib.crc32(WorldSeed.natural_key(location.name.to_s))

  # HOW MANY PEOPLE THE ENGINE WILL ASK FOR, thrown inside the band the label
  # names.
  #
  # IT TAKES THE LABEL RATHER THAN THE ROOM, so that a caller which needs both
  # throws each die once: `.label_for` may itself roll, and a method that called
  # it again would advance the same generator twice for one question and give
  # the second reader a different word from the first.
  #
  # AND IT COMES OUT OF THE GENERATOR IT IS HANDED, on `Roll`'s standing rule --
  # a caller throwing several dice for one decision throws them from one seed in
  # one order. `Character::Registry#slots` is that caller and the generator is
  # `Location::Danger.generator_for`'s, the one this room's cast is already
  # drawn from: the label, the count and then who each person is, in that order,
  # so the whole of a room's cast is re-derivable from the room's own id.
  #
  # UNCLAMPED -- `Character::Registry` clamps it against the room and the world,
  # because those are read back from the records and this knows nothing about
  # either.
  def self.count_for(label, rng:)
    Roll.one_of(BANDS.fetch(label), rng: rng)
  end
end
