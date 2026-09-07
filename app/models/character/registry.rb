# WHERE A PERSON ENDS UP, and the one thing in the app that decides it without
# being told to. The people half of the noun registry: `Item::Registry` says
# how a thing comes to be lying in a room, this says how a person comes to be
# standing in one.
#
# THE ONE RULE IT EXISTS FOR: A CHARACTER WHO ALREADY HAS A WHEREABOUTS IS NOT
# MOVED. That is the Tide Post defect written down. `Scene::Generator` used to
# work out the room's cast from scratch on every arrival -- the protagonist,
# anyone `is_companion`, and whoever was in the last scene here that recorded
# anybody -- so a place nobody had visited was empty, and arriving at The Tide
# Post recorded the protagonist alone on all three runs checked, in a world
# whose whole premise is Neb Halloran chained to that post. A cast that is
# regenerated is a cast that forgets. So a proposed cast is a PROPOSAL: this
# reconciles it against the records, the records win wherever they have an
# answer, and the arrival Scene's cast is then written FROM the records.
#
# WHAT IT REFUSES, and each is a real candidate:
#
#   somebody already somewhere else  left exactly where they are. The proposal
#                                    is evidence about a room, never authority
#                                    over a person.
#   somebody absent on purpose       left nowhere. `characters.deliberately_absent`
#                                    is a world's own statement that this person
#                                    has been removed from it -- The Unrecorded
#                                    Hour's whole premise about Perrin Lasco --
#                                    so placement would undo the premise as a
#                                    side effect of describing a room.
#   a room already at its cap        `MAX_PER_ROOM`, read back from the records
#                                    on every admission the way both of
#                                    `Item::Registry`'s caps are.
#   a name already taken            by a character, an item or a place. The
#                                    classifier resolves a typed line against
#                                    all three closed sets by name, so one word
#                                    answering to two of them makes which one
#                                    the player gets an ordering accident.
#   a world already at its cap      `MAX_PER_STORY`, across every room.
#
# AND IT CREATES, on the captain's ruling *"rooms should be born with people in
# them sometimes."* Built the way `Item::Registry` builds a room's furniture and
# not the way the direction plan first imagined it: **as structured records at
# the moment a room is realized, out of the same call that describes it**, never
# by a narrator tool call and never by reading prose for a name. That is the
# standing constraint (AGENTS.md) -- the engine owns state and the narrator is
# TOLD -- and it is why this supersedes `ta-narrator-memory`'s
# characters-by-tool-call for CREATION; that item keeps only the memory and
# cast-list half.
#
# HOW MANY OF THEM THERE ARE IS NOT THIS FILE'S, AND THAT IS THE ONE THING
# WORTH KNOWING BEFORE READING IT. `Location::Population` owns the words a room
# may be described by, the band of counts behind each word and the rolls; this
# reads a number off it (`#drawn`) and clamps it against the records. The
# captain's ruling of 2026-09-07 is quoted in full there and so is what it
# overturned -- including the sentence that used to stand in this header, that
# nobody is the ordinary answer. It is not any more: the ordinary answer is
# whatever word the model picked for this place.
#
# WHO A NEW PERSON IS, THE ENGINE DECIDES. Race, age and sex are rolled here,
# one set per slot, and stated in the realization prompt BEFORE the model
# answers -- `Character::Generator`'s rule, that asking for a value the prompt
# just supplied is a decision bought twice. The model writes them; it does not
# choose what they are. `#slots` is memoized for exactly that reason: the
# prompt and the row have to agree about the person in slot 1.
#
# AND WHETHER THEY ARE A MONSTER, which is the room's own doing. The captain's
# seventh ruling of 2026-09-04 evening: *a dangerous room draws its inhabitants
# from the universe's monstrous races instead of its peoples*, and *a generated
# character whose race is monstrous is hostile by default*. So `#slots` throws
# one `Location::Danger` die per slot against `locations.danger`, picks the race
# out of `Race.monstrous` or `Race.peoples` accordingly, and `#create_one`
# derives `characters.hostile` from the race in one line. There is no field for
# hostility on `Location::DetailSchema` and nothing in the realization prompt
# mentions one -- the same standing rule the stat block below is under.
#
# AND SO IS THEIR BODY, and that one is not even stated. `characters.level` and
# `characters.hit_die` are rolled by `Character::StatBlock` -- the captain's
# ruling of 2026-09-04, *"A model cannot set an NPC's numbers, the engine rolls
# them"* -- and the realization prompt says nothing about them, because a hit
# die is of no use to a paragraph. There is therefore no field on
# `Location::DetailSchema`'s `people` for a model to have answered with one.
#
# TWO BOUNDS, and each is read back from the records rather than counted down
# from a budget: `MAX_PER_ROOM` on the room and `MAX_PER_STORY` on the whole
# world. A room generates for as long as somebody keeps walking, so a per-room
# cap alone bounds nothing.
#
# THEY ARE THE HARD LIMIT AND A POPULATION BAND IS ONLY A DISTRIBUTION, and the
# two are different kinds of number on purpose. The band is what the room is
# LIKE; the caps are what the game can hold -- a seed file may hand-author a
# crowd, `#move_to!` may walk somebody into a full room, and a room is realized
# once while people arrive for as long as the game runs. So the rolled count is
# CLAMPED by both (`#drawn`) and neither cap moved for the 2026-09-07 ruling,
# and `Story::Doctor`'s two cap findings go on reporting a room or a world past
# them exactly as they did.
#
# Refusals are DROPPED, never raised, on `Item::Registry`'s rule: a room
# realized with two of the three people the proposal named is a good room, and
# a realization that threw away its description over a cast is not.
#
# WHAT CALLS IT: `Location::Generator#write_detail!`, with the `people` array
# off the realization answer. The seed file does NOT -- it writes its own
# placements straight, because a hand-authored world IS the decision and
# re-seeding has to be able to put a played world's cast back
# (`WorldSeed::Loader#load_characters!`) -- and `Character#move_to!` is the
# explicit call for a mechanic that means to move somebody.
#
# `Story::Doctor` reports a room past `MAX_PER_ROOM` and a world past
# `MAX_PER_STORY`, exactly as it does for `Item::Registry`'s two.
class Character::Registry
  include SanitizesGeneratedText

  # THE FIELDS A NEW PERSON'S SHEET HAS TO CARRY, and the whole of what the
  # model supplies about who they are. Every one of them is `presence: true` on
  # `Character` because every one is interpolated into
  # `Character#interaction_instructions` -- so a person missing any of them is a
  # person nobody can hold a conversation with, and the honest thing is to
  # refuse them rather than write a row that cannot be talked to.
  SHEET = %i[appearance personality backstory likes dislikes fears].freeze

  # HOW LONG EACH OF THEM MAY BE, and this is the schema's caps rather than a
  # copy of them: `Location::DetailSchema` reads this table, so the bound the
  # model is given and the bound this class checks a sheet against cannot
  # disagree.
  #
  # SIZED TO A FINISHED ANSWER, which is the whole of how `SanitizesGeneratedText`
  # tells truncation from a near miss: a field arriving AT its cap was cut off
  # by the provider rather than ended by the model, and that is only a signal
  # if a finished sentence lands nowhere near it. The first live realization
  # under this schema came back with `appearance` and `personality` cut
  # mid-word at 200 and `backstory` at 300 -- "She is small and" -- so the caps
  # are ~150 characters a sentence, the ratio `Character::Schema` already uses
  # (400 for two or three sentences, 1,200 for four to six). They stay well
  # under that schema's, because this one rides on a call the room is already
  # paying for.
  PERSON_LIMITS = {
    fullname: 60, nickname: 30,
    appearance: 300, personality: 300, backstory: 450,
    likes: 160, dislikes: 160, fears: 160
  }.freeze

  # HOW MANY PEOPLE THE ENGINE WILL PLACE IN ONE ROOM, in total and not per
  # call -- the same distinction `Item::Registry::MAX_PER_ROOM` documents. It
  # bounds PLACEMENT and nothing else: a seed file may hand-author a crowd (it
  # is world data, written by a person, and `WorldSeed::Loader` places exactly
  # what the file says), and `#move_to!` is an explicit decision. What this
  # stops is a room quietly accumulating a cast nobody chose.
  #
  # Three, and it is the same number for the same reason `Item::Registry` picks
  # three: `Playthrough::Classifier` offers the room's cast as a closed enum on
  # every single turn, and the fullname AND nickname of everybody present go
  # into it. Three people is six names, which is a list a player can hold in
  # their head and a model can copy from exactly.
  MAX_PER_ROOM = 3

  # THERE IS NO `MAX_PER_CALL` HERE ANY MORE, and its absence is the shape of
  # the captain's ruling of 2026-09-07 rather than a tidy-up. It was two -- *"the
  # schema must allow empty and the prompt should make nobody-or-one the
  # ordinary case, not a crowd"* -- and it was a CEILING the prompt offered with
  # "AT MOST" for the model to fill as sparsely as it liked. There is no ceiling
  # now: `#slots` is exactly as long as the count the engine rolled, and the most
  # any one call can ask for is the top of `Location::Population`'s widest band,
  # which that file publishes as `MOST` and `Location::DetailSchema` reads.
  # Naming the same number twice is how the schema's bound and the table's
  # widest band come to disagree.

  # HOW MANY PEOPLE ONE WORLD MAY HOLD AT ALL, seeded and generated together.
  # The per-room cap bounds nothing on its own: a world generates rooms for as
  # long as somebody keeps walking, so three per room is three times however far
  # they went, and the ontology this is meant to bound would not be.
  #
  # Twelve, and the reasoning is `Item::Registry::MAX_PER_STORY`'s with the
  # numbers a cast has rather than an inventory's. The largest seeded world has
  # three characters; twelve is four times that, and roughly twenty realized
  # rooms' worth at the rate the prompt asks for (nobody, ordinarily). It is far
  # smaller than the item ceiling on purpose -- a person is not furniture. Every
  # character standing in a room goes into `Playthrough::IntentSchema`'s closed
  # enum by fullname AND nickname on every single turn, and a world past this
  # generates rooms with nobody in them rather than failing.
  MAX_PER_STORY = 12

  attr_reader :location, :story

  def initialize(location)
    @location = location
    @story = location.story
  end

  # Turns a proposed cast into rows standing in this room, and returns WHO IS
  # ACTUALLY HERE afterwards, read back out of the records.
  #
  # `candidates` may hold the schema'd hashes a realization answered with, a
  # `Character` record, or a bare name -- because the things that propose a cast
  # do it differently, and every one of them is a proposal either way.
  #
  # A candidate that RESOLVES to somebody this story already has is placed if
  # they are nowhere and left exactly where they are if they are not; a
  # candidate with a sheet on it that resolves to nobody is CREATED. Anything
  # refused is dropped with a reason in the log, never raised: a room realized
  # with one of the two people the model named is a good room, and a
  # realization that threw away its description over a name would not be.
  def admit!(candidates)
    Character.transaction do
      Array(candidates).each_with_index { |candidate, slot| admit_one(candidate, slot) }
    end

    present
  end

  # WHO THE ENGINE HAS ALREADY DECIDED THE NEXT PEOPLE ARE: one race, age and
  # sex per slot this call WILL fill, rolled once and read by both the prompt
  # (`Location::Generator#people_instructions`) and the row. Memoized because
  # the two have to agree -- a prompt that described a Bell-Keeper of 44 and a
  # row that came out Shorefolk of 19 would be a person the description is
  # wrong about.
  #
  # WHICH POOL A RACE COMES OUT OF IS THE ROOM'S OWN `danger`, and that is the
  # captain's seventh ruling of 2026-09-04 evening: *a dangerous room draws its
  # inhabitants from the universe's monstrous races instead of its peoples*. One
  # `Location::Danger` roll per slot, out of ONE generator for the whole call --
  # `Roll`'s standing rule, so the people this realization writes are decided
  # together and re-derivably. A safe room throws no die at all and draws from
  # the peoples every time, which is what every room already written is.
  #
  # AND THE POOL DECIDES HOSTILITY, one line below in `#create_one`. Nothing
  # here asks a model anything: the race is the engine's own choice and the flag
  # is read off it.
  #
  # AND HOW MANY SLOTS THERE ARE IS `Location::Population`'s, which is the whole
  # of what the captain's ruling of 2026-09-07 changed here. This used to build
  # `MAX_PER_CALL` slots as a CEILING and let the model name as few of them as
  # it liked; it now builds EXACTLY the number the engine rolled inside the band
  # the model picked, so the length of this array is the length of the answer the
  # prompt asks for and the length of the array the schema requires. An empty
  # array is a room the pick said has nobody in it, and it is a complete answer
  # rather than a failure.
  #
  # TWO GENERATORS, AND WHICH ONE IS WHICH IS THE DESIGN RATHER THAN AN
  # ACCIDENT. HOW MANY people a room has is drawn by `Location::Population` off
  # the ROOM'S NAME, because a population is a fact about a place and a place
  # survives being exported and re-seeded with every id re-issued. WHO each of
  # them is is drawn here off `Location::Danger.generator_for`, which keys on the
  # room's id -- unchanged by the 2026-09-07 ruling, so a seeded world's cast
  # comes out exactly as it did before wherever the count matches.
  #
  # ONE `monstrous?` THROW PER SLOT, IN ORDER, out of one generator --
  # `Roll`'s standing rule, and the order is fixed here rather than incidental:
  # inserting a roll ahead of another one moves every answer after it.
  def slots
    @slots ||= begin
      rng = Location::Danger.generator_for(location)

      Array.new(drawn) do
        { race: race_from(Location::Danger.monstrous?(location, rng: rng)),
          age: rand(18..80), sex: Character.sexes.values.sample }
      end
    end
  end

  # HOW MANY THIS CALL ASKS FOR, and it is the length of `#slots` rather than a
  # second calculation of the same number -- the two used to be able to
  # disagree, and the prompt states one person per slot, so they cannot be
  # allowed to.
  def allowance = slots.size

  # WHO THE RECORDS PLACE HERE. The closed set, read through the one scope, so
  # a caller of this class never has to know how presence is stored.
  def present
    Character.present_in(location).to_a
  end

  # HOW MANY MORE PEOPLE MAY BE PLACED HERE, read from the records on every
  # check rather than counted once -- rows are written as the loop goes, and a
  # budget worked out before it would not notice. `Item::Registry#room_for_items`
  # has the same shape and the same reason.
  def room_for_people
    [ MAX_PER_ROOM - Character.present_in(location).count, 0 ].max
  end

  # Whether this world has room for another person at all.
  def world_for_people
    [ MAX_PER_STORY - story.characters.count, 0 ].max
  end

  private

  # HOW MANY PEOPLE THIS ROOM GETS: the word somebody picked for it, the count
  # the engine rolls inside that word's band, and then the two caps read back
  # from the records. `Location::Population` owns the first two and its header
  # is the design.
  #
  # THE CAPS ARE STILL THE HARD LIMIT AND THEY DID NOT MOVE. A band is a
  # distribution, `MAX_PER_ROOM` and `MAX_PER_STORY` are invariants, and the
  # clamp is what keeps the second true of the first: a room a seed file already
  # put three people in has no slots left however busy the pick called it, and a
  # world at `MAX_PER_STORY` gets rooms with nobody in them rather than failing.
  # That is also the whole of *a seeded room's own cast wins* -- nothing here
  # removes anybody, it only stops asking for more.
  def drawn
    [ Location::Population.count_for(location), room_for_people, world_for_people ].min
  end

  # ONE OF THE TWO POOLS, and a pool that is empty falls back to the whole race
  # list rather than to nobody. Writing NOBODY would mean a room quietly losing
  # the person its description was about, which is the failure every refusal in
  # this class is written to avoid.
  #
  # THE TWO FALLBACKS ARE NOT SYMMETRICAL, and the asymmetry is worth stating
  # because one of them is louder than it looks:
  #
  #   no monstrous races  a dangerous room gets an ordinary person, and the
  #                       room's danger simply does not bite. This is the world
  #                       every GENERATED universe is in today --
  #                       `Universe::Generator` marks no race `monstrous` (see
  #                       `Location::Danger`'s header) -- so it is the ordinary
  #                       case rather than the corner.
  #   no peoples          a SAFE room gets somebody of a monstrous race, and the
  #                       line below then derives them hostile. Said plainly: in
  #                       a universe whose every race is a monster there is
  #                       nobody else to be, so every room is dangerous whatever
  #                       its `danger` says. That is a true statement about such
  #                       a world rather than a hole in the parameter -- the
  #                       alternative is a room described around a person it does
  #                       not have. No checked-in world is in this state and
  #                       nothing in the app can put one there;
  #                       `Character::GeneratorTest` pins the same fallback for a
  #                       protagonist.
  def race_from(monstrous)
    pool = monstrous ? story.universe.monstrous_races : story.universe.peoples

    (pool.presence || story.universe.races).sample
  end

  def admit_one(candidate, slot)
    character = resolve(candidate)
    return create_one(candidate, slot) if character.nil?

    reason = refusal(character)
    return refuse(character.fullname, reason) if reason

    # SOMEBODY WHO WAS NOWHERE, PLACED -- and placed IN the room as well as into
    # it, through `Character#move_to!` so that the whereabouts and the position
    # are written by the one statement that owns both. It used to write
    # `location:` straight; the two have to move together (see that method), and
    # `#move_to!` is the one statement in the app that writes them together --
    # so every path that moves somebody INTO a room goes through it: this line,
    # `Story::Repair` putting a seeded whereabouts back, and
    # `Character::WhereaboutsBackfill` recovering one from the old arrival
    # casts. `#place!` below is not one of them and does not need to be: it
    # writes the position alone, for a row this class created standing in the
    # room already. A seed file is the only other author, and it writes both
    # columns too (`WorldSeed::Loader`).
    #
    # AND SOMEBODY ALREADY STANDING HERE, WHICH ALSO REACHES THIS LINE. It is
    # not only the nowhere case: `#refusal` returns nil for a person this very
    # room already holds, because a realization that names somebody it already
    # has is agreeing with the record rather than asking for anything. That
    # makes the call below a move whose destination is the room the row already
    # names, and `#move_to!` rolls nothing for one -- so a corner a seed file
    # laid somebody in survives being described again. Said here as well as
    # there because this is the caller that reaches the case.
    #
    # `#move_to!` ALSO CLEARS `deliberately_absent`, which is not a change in
    # behaviour but is worth saying: `#refusal` has already declined anybody the
    # file marks absent on purpose, so nobody reaching this line carries the
    # marker.
    character.move_to!(location)
  end

  # A PERSON WHO DID NOT EXIST A MOMENT AGO, out of the sheet the realization
  # answered with and the details this class had already decided. Returns nil
  # on anything it will not take, which is the same contract every other
  # refusal here has.
  #
  # A bare name with no sheet behind it is not a person: `#admit!` also takes
  # names, and a name alone is somebody the caller believed already existed.
  # Inventing one from a string would put a character in the world with no
  # appearance, nothing to say and nobody who wrote them.
  def create_one(candidate, slot)
    return refuse(label(candidate), "this story has nobody of that name and there is no sheet to write one from") unless candidate.is_a?(Hash)

    attributes = candidate.transform_keys(&:to_s)
    fullname = field(attributes, :fullname)

    reason = creation_refusal(fullname, attributes)
    return refuse(fullname, reason) if reason

    # ONE PERSON PER SLOT, AND A CANDIDATE PAST THE LAST SLOT IS REFUSED. It
    # used to wrap -- `slots.fetch(slot % MAX_PER_CALL)` -- back when `#slots`
    # was a fixed-length ceiling and an extra entry could only be a model
    # ignoring `max_items`. Now the array is exactly as long as the count the
    # engine rolled (`#drawn`), so a wrap would write a second person off the
    # first person's race and age: two rows the prompt described once. The
    # honest answer is the one this class gives everything it will not take.
    details = slots[slot]
    return refuse(fullname, "the engine rolled #{slots.size} #{"person".pluralize(slots.size)} for this room and this is number #{slot + 1}") if details.nil?
    story.characters.create!(
      fullname: fullname,
      nickname: field(attributes, :nickname).presence,
      location: location,
      race: details[:race],
      age: details[:age],
      sex: details[:sex],
      # AND WHETHER THEY ATTACK YOU IS DERIVED FROM THE RACE, in one line. The
      # captain's seventh ruling of 2026-09-04 evening: a generated character
      # whose race is monstrous is hostile by default. The race came out of the
      # pool this room's `danger` chose (`#slots`), so nothing a model answered
      # reaches this -- `Location::DetailSchema` has no field for hostility and
      # the realization prompt does not mention it, exactly as it does not
      # mention a hit die.
      hostile: Character.hostile_by_default?(details[:race]),
      # AND THE ENGINE ROLLS THEIR BODY. The captain's ruling of 2026-09-04 --
      # *"A model cannot set an NPC's numbers, the engine rolls them"* -- and it
      # is the same rule the race, age and sex above are already under, one
      # column further: `Location::DetailSchema` has no field for a stat and
      # nothing in the realization prompt mentions one, so there is nothing here
      # for a model to have answered. See `Character::StatBlock`.
      **Character::StatBlock.for_new(story, sequence: slot),
      **SHEET.to_h { |name| [ name, field(attributes, name) ] }
    ).then { |person| place!(person) }
  rescue SanitizesGeneratedText::TruncatedTextError => e
    # A HALF-WRITTEN PERSON IS WORSE THAN NO PERSON, and refusing one is what
    # this class does with everything it will not take. Elsewhere in the app a
    # truncated field is a FAILED CALL that reaches the rotation
    # (`BaseAgent#ask`'s `verify:` seam) -- here it must not be, because the
    # call it would fail is the room's own description, which is already saved
    # and cost the expensive half of the realization. So the room keeps its
    # description and loses a person, exactly as it does for a refused name.
    refuse(attributes["fullname"], "the sheet was cut off: #{e.message}")
  end

  # AND WHERE IN THE ROOM THEY ARE STANDING, which the ENGINE decides and no
  # model is asked -- the same sentence the race, the hostility and the stat
  # block above are under, one pair of columns further: `Location::DetailSchema`
  # has no field for a coordinate and the realization prompt does not mention
  # one. `Location::Placement` is the one writer and its header has the design.
  #
  # A SECOND WRITE, AND IT HAS TO BE, for `Item::Registry#place!`'s reason: the
  # seed is the row's own id, so the row has to exist before it can be placed.
  # It is not `#move_to!` -- the row was created standing in the room already,
  # and this only decides where in it.
  #
  # A ROOM WITH NO BOX PLACES NOBODY, which is every room in a generated world
  # today; the update is skipped rather than written as a pair of nils.
  def place!(person)
    placement = Location::Placement.in_the_world(location, person)
    person.update!(**placement) if placement.values.any?
    person
  end

  # One field of a proposed sheet, sanitized under the cap the model was given.
  # Passing the cap is what turns the truncation check on -- see
  # `SanitizesGeneratedText`.
  def field(attributes, name)
    sanitize_string(attributes[name.to_s].to_s, max_length: PERSON_LIMITS.fetch(name))
  end

  # The one place that says no to a NEW person, and it says which no. Ordered
  # cheapest first, the way `Item::Registry#refusal` is: the shape of the
  # answer, then the room, then the world, then the three collision checks that
  # each cost a query.
  def creation_refusal(fullname, attributes)
    return "it has no name" if fullname.blank?

    missing = SHEET.select { |field| attributes[field.to_s].to_s.strip.empty? }
    return "the sheet is missing #{missing.join(", ")}" if missing.any?
    return "there is nobody left to write: this universe has no races" if story.universe.races.none?
    return "the room already holds #{MAX_PER_ROOM}" if room_for_people.zero?
    return "the world already holds #{MAX_PER_STORY} people" if world_for_people.zero?
    return "a person in this story is already called that" if person_named?(fullname)
    return "a place in this story is called that" if place_named?(fullname)
    return "something in this story is called that" if thing_named?(fullname)

    nil
  end

  # THE CLOSED SETS A NEW NAME MUST NOT COLLIDE WITH, and they are the same
  # three `Item::Registry` guards, read from the other side.
  # `Playthrough::Classifier` resolves a typed line against the room's cast, its
  # exits and what is lying in it, by name; a person sharing a name with one of
  # the other two makes the same word resolve two ways, and which way it goes is
  # an ordering accident inside the classifier rather than anything the player
  # could predict.
  #
  # A person is checked by FULLNAME only, and against fullnames and nicknames
  # both: `Character` already refuses a duplicate fullname outright, and this is
  # the same rule said before the row is built so the refusal reads as a refusal
  # rather than as a validation error.
  def person_named?(name)
    story.characters.where("LOWER(fullname) = ? OR LOWER(nickname) = ?", name.downcase, name.downcase).exists?
  end

  def place_named?(name)
    story.locations.where("LOWER(name) = ?", name.downcase).exists?
  end

  def thing_named?(name)
    Item.in_story(story).where("LOWER(name) = ?", name.downcase).exists?
  end

  # The one place that says no, and it says which no. The whereabouts check is
  # first because it is the rule this class exists for: a room at its cap that
  # names somebody already standing somewhere else should read as "he is at the
  # post", not as "the room is full".
  def refusal(character)
    # NOWHERE ON PURPOSE IS NOT AN EMPTY SLOT. The second half of the rule this
    # class exists for: it places somebody who is nowhere, it never moves
    # somebody who is not, AND it never places somebody whose absence is the
    # world's premise. `The Unrecorded Hour` is about Perrin Lasco having been
    # removed from it, so a realization that named him would put him back into
    # the game as a side effect of describing a room. `Character#move_to!` is
    # the explicit call for a mechanic that MEANS to bring him back, and it
    # clears the marker when it does.
    return "#{character.pronoun_forms.subject} is absent from this world on purpose, and a proposal does not undo that" if character.deliberately_absent?

    if character.somewhere?
      return nil if character.location_id == location.id

      return "#{character.pronoun_forms.subject} is already in #{character.location.name}, and a proposal does not move anybody"
    end

    return "the room already holds #{MAX_PER_ROOM}" if room_for_people.zero?

    nil
  end

  # A `Character` of this story, however it was named. Matched on fullname or
  # nickname, case-insensitively, which is the pair `Playthrough::Classifier`
  # already offers a player -- a proposal should be able to say "Neb" for the
  # same reason a player can.
  def resolve(candidate)
    return candidate if candidate.is_a?(Character) && candidate.story_id == story.id

    name = candidate.is_a?(Character) ? candidate.fullname : candidate.to_s
    return nil if name.blank?

    story.characters.where("LOWER(fullname) = ? OR LOWER(nickname) = ?", name.downcase, name.downcase).first
  end

  def label(candidate)
    candidate.is_a?(Character) ? candidate.fullname : candidate.to_s
  end

  def refuse(name, reason)
    Rails.logger.info do
      "[cast] #{location.name.inspect} did not take #{name.presence.inspect || "an unnamed person"}: #{reason}"
    end
    nil
  end
end
