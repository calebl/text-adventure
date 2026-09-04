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
# WHO A NEW PERSON IS, THE ENGINE DECIDES. Race, age and sex are rolled here,
# one set per slot, and stated in the realization prompt BEFORE the model
# answers -- `Character::Generator`'s rule, that asking for a value the prompt
# just supplied is a decision bought twice. The model writes them; it does not
# choose what they are. `#slots` is memoized for exactly that reason: the
# prompt and the row have to agree about the person in slot 1.
#
# THREE BOUNDS, and each is read back from the records rather than counted down
# from a budget: `MAX_PER_CALL` on one answer, `MAX_PER_ROOM` on the room, and
# `MAX_PER_STORY` on the whole world. A room generates for as long as somebody
# keeps walking, so a per-room cap alone bounds nothing.
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

  # HOW MANY ONE REALIZATION MAY NAME. Two, and it is the captain's number:
  # *"the schema must allow empty and the prompt should make nobody-or-one the
  # ordinary case, not a crowd."* The schema bounds the answer
  # (`Location::DetailSchema`) and this is the same figure, kept here because
  # the prompt reads it to say how many slots it is describing.
  MAX_PER_CALL = 2

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
  # sex per slot this call may fill, rolled once and read by both the prompt
  # (`Location::Generator#people_instructions`) and the row. Memoized because
  # the two have to agree -- a prompt that described a Bell-Keeper of 44 and a
  # row that came out Shorefolk of 19 would be a person the description is
  # wrong about.
  #
  # Race comes from the universe's own generated list, exactly as
  # `Character::Generator` picks one, so a generated person always belongs to
  # one of the world's peoples.
  def slots
    @slots ||= Array.new(MAX_PER_CALL) do
      { race: story.universe.races.sample, age: rand(18..80), sex: Character.sexes.values.sample }
    end
  end

  # How many this call may actually name: the smaller of what one answer may
  # hold, what is left of the room and what is left of the world.
  def allowance
    [ MAX_PER_CALL, room_for_people, world_for_people ].min
  end

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

  def admit_one(candidate, slot)
    character = resolve(candidate)
    return create_one(candidate, slot) if character.nil?

    reason = refusal(character)
    return refuse(character.fullname, reason) if reason

    character.update!(location: location)
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

    details = slots.fetch(slot % MAX_PER_CALL)
    story.characters.create!(
      fullname: fullname,
      nickname: field(attributes, :nickname).presence,
      location: location,
      race: details[:race],
      age: details[:age],
      sex: details[:sex],
      **SHEET.to_h { |name| [ name, field(attributes, name) ] }
    )
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
