# Realizing a stub: what the player reads on arrival, plus what the place is,
# plus what is lying in it. Lengths are explicit on every field. Without them a
# strong model answered a one-word field with 2,382 characters of prose, and
# both of the prose fields are interpolated into every scene generated here.
#
# `description` DESCRIBES THE PLACE, NOT ITS NEIGHBOURS, and that clause is
# load-bearing rather than stylistic. A description is written once and never
# regenerated -- that is the whole persistence model -- so a sentence naming
# what stands across the way becomes permanently wrong the moment the world
# graph moves it. The Lunar Cartographer already has one: Room 3's description
# was generated before `WorldMechanic` existed and puts a clothier's shop
# outside the window. Asking for the place itself is what stops the next one.
#
# `items` IS HOW THINGS COME TO EXIST, and it is here rather than in a call of
# its own because a realization already makes two (see `Location::Generator`)
# and a third to ask what is on the floor would be a round trip per room to
# answer "nothing" most of the time. Riding on the description means the model
# names what it just finished describing, so the two agree by construction --
# and it is the description call rather than the exits call because the exits
# call is skipped entirely for a room already at its exit cap.
#
# It is OPTIONAL, and that is deliberate rather than lax: an empty required
# array reads as an omitted field to `BaseAgent#missing_schema_keys`, so a
# room honestly containing nothing would fail its own realization and rotate
# to another model. An absent `items` and an empty `items` both mean the same
# thing here -- nothing is lying here -- and `Item::Registry` treats them the
# same.
#
# `people` IS HOW A ROOM COMES TO HAVE SOMEBODY IN IT, and it rides on this
# call for exactly the reasons `items` does -- the room is already being
# described, so the people the model names are the people it just finished
# writing a room around, and the two agree by construction.
#
# WHAT IS NOT IN IT: race, age and sex. Those are `Character::Registry`'s
# rolls, stated in the prompt per slot before the model answers, on
# `Character::Generator`'s rule -- *asking for a value the prompt just supplied
# is a decision bought twice.* The engine decides who these people ARE; the
# model writes them.
#
# WHY IT IS SIX SHORT FIELDS AND NOT ONE LINE, which was the ask. `Character`
# validates `backstory`, `personality`, `appearance`, `likes`, `dislikes` and
# `fears` as present, because every one of them is interpolated into
# `Character#interaction_instructions` on every turn of dialogue -- so a person
# built from one line is a person nobody can hold a conversation with. They are
# capped far shorter than `Character::Schema`'s equivalents -- the table is
# `Character::Registry::PERSON_LIMITS`, read from here so the bound the model is
# given and the bound the registry checks a sheet against cannot disagree --
# which is what keeps the cost of a room with somebody in it to roughly one
# person's worth of short lines. The
# alternative -- a STUB `Character`, realized into a full sheet the first time
# somebody speaks to them, the shape `Location` already has -- is the cheaper
# call and the bigger change: it needs a `detail_level`, conditional
# validations, and a model call inside the talk branch. If the measured
# realization cost is the thing that matters, that is the follow-up.
#
# The cap is the schema's bound on ONE ANSWER. The bound on the ROOM, and on
# the world, is `Item::Registry`'s and `Character::Registry`'s, for the reason
# `Location::ExitsSchema` spells out at length: rows arrive from outside this
# call too.
#
# `name` IS HOW A ROOM OF A PLACE COMES TO BE CALLED SOMETHING, and it is the
# one field here that is asked for on SOME rooms only. `Location::Interior` lays
# a building out and numbers its rooms before anybody walks in, and a room of an
# interior gets no exits call at all (`Location::Generator#write_exits!`) -- so
# until this field there was no call in the game that could name one, and the
# player read "You are in Blackfang Warren room 3 of Blackfang Warren" for good.
#
# IT IS OPTIONAL AND THE PROMPT IS WHAT ASKS FOR IT, which is the shape that
# keeps every other room's prompt the one a baseline was measured on:
# `Location::Generator#name_instruction` is empty for anything that is not a
# room of a laid-out place STILL CALLED ONE OF ITS NUMBERS, so the sentence
# reaches exactly the rooms that need one and no baseline moves for the rest. A
# room a NEIGHBOUR named, and a room a SEED FILE named by hand, already have a
# name a player may have typed -- `Location::RoomName.for` answers nil for both,
# so this field is never asked about them and is ignored if it arrives anyway.
#
# AND THE ENGINE DECIDES WHETHER TO TAKE IT. `Location::RoomName` is the one
# author of a room's name on realization -- it refuses a blank, a comma, the
# placeholder, another of the place's placeholders, the place's own name inside
# it and any name this world has already spoken for, and the placeholder simply
# stays. The cap is read from
# there rather than written twice, for `Character::Registry::PERSON_LIMITS`'
# reason.
#
# `readable` AND `inscription` RIDE ON THE SAME ANSWER, for the same reason the
# items do. A note is born with its words or it is born without them, and the
# call that just wrote the room is the one call that can say what a note in it
# says. Asking later -- when somebody reads it -- costs a round trip and gets a
# note written by a model that has not seen the room. `Item::Inscriber` is that
# later call and it exists only for the readable thing that arrived here
# without words: a seeded one, or a row older than the columns.
#
# `inscription` is OPTIONAL and `readable` is not, which is the shape that makes
# the pair honest. Most things have nothing written on them, so `readable:
# false` is the ordinary answer and an omitted `inscription` beside it means
# exactly that. `Item::Registry` refuses an inscription on a thing marked
# unreadable rather than believing either half over the other.
# AND `people` IS THE ONE FIELD HERE WHOSE SHAPE IS NOT A CONSTANT, since the
# captain's ruling of 2026-09-07: the narrator picks how populated a place is
# from a closed list on the exits call of the room next door
# (`Location::ExitsSchema`), the engine rolls the count inside that word's band
# (`Location::Population`), and this field then requires EXACTLY that many
# people. `.for_people` is the builder and its comment is the design. It used to
# be optional and capped, with **nobody is the ordinary answer** written into its
# own description -- which is the sentence the ruling overturned, and the reason
# four of six realization answers on record named nobody in rooms that had
# offered two slots.
#
# AT NOUGHT IT IS STILL OPTIONAL, and that is load-bearing: an empty required
# array reads as an omitted field to `BaseAgent#missing_schema_keys`, so a room
# the pick called empty would fail its own realization. An absent `people` and an
# empty `people` mean the same thing there, and `Character::Registry` treats them
# the same.
#
# AND THE TWO PROSE FIELDS ARE HELD AS A BLOCK, because a BUILDING is asked for
# those two and for nothing else on this list. `Location::PlaceSchema` is that
# schema: same description, same lore, plus the picks that decide what the engine
# builds inside it -- and no `name` (a building is named by whoever named the
# exit), no `items` and no `people` (nobody ever stands in a container, so a
# thing lying in one is a thing nobody can pick up).
#
# A BLOCK AND NOT A SUPERCLASS. `RubyLLM::Schema` keeps its properties per CLASS
# -- `@properties ||= {}` on the singleton -- so `< Location::DetailSchema` would
# inherit none of them and silently send an empty schema. And a `required: false`
# object on THIS class would put five more enums into the JSON schema of every
# realization in the game in order to reach the handful that are buildings, which
# is a change to a measured artifact made as a side effect.
class Location::DetailSchema < RubyLLM::Schema
  PROSE_FIELDS = proc do
  string :description, description: "What the player sees, hears and smells standing in this place right now. Describe THIS place only -- not what neighbours it, not what is visible out of a window or across the way, because the world around it can move. Second person. One paragraph, 4 to 6 sentences.", max_length: 1200
  string :lore, description: "What this place is, who made it and what happened here. Written for the game engine rather than the player. One paragraph, 3 to 5 sentences.", max_length: 900
  end

  # AND THE WHOLE OF A ROOM'S SCHEMA IS A BLOCK TOO, one containment level out
  # from `PROSE_FIELDS` and for a second reason on top of that one: `people` is
  # the one field in this schema whose SHAPE depends on the room, so
  # `.for_people` has to be able to build a variant, and `RubyLLM::Schema` keeps
  # its properties per CLASS -- a variant cannot be a subclass, it has to be a
  # fresh class the same declarations are run against. This is those
  # declarations, and `class_exec` below is what runs them against THIS class.
  #
  # IT CALLS `PROSE_FIELDS` RATHER THAN REPEATING IT, so the two prose fields
  # have exactly one definition across all three schemas that send them -- this
  # one, its variants, and `Location::PlaceSchema`.
  #
  # THE ONE THING THE COUNT CHANGES is the `people` array, and the branch is at
  # the bottom of the block. Everything else is byte-identical between the
  # shapes on purpose -- a variant that quietly reworded a description would make
  # every realization bench figure a comparison between two prompts nobody had
  # compared.
  DECLARE = lambda do |wanted|
    class_eval(&PROSE_FIELDS)

    string :name,
           description: "What this room is called -- ONLY when the instructions above ask you to name it. Leave this out entirely otherwise. A short noun phrase a player would type to walk into it, carrying the article English wants on it: \"the counting room\". Never the name of the building it is in, never a name this story has already given to a room, a person or a thing, and never a comma.",
           required: false, max_length: Location::RoomName::LIMIT

    array :items,
          description: "Portable things lying loose in this place that a player could pick up and carry away. Empty is the right answer for most rooms.",
          required: false,
          max_items: Item::Registry::MAX_PER_ROOM do
      object do
        string :name, description: "What the thing is called, as a player would type it to pick it up. A short noun phrase, 1 to 4 words, lower case unless it is a proper name. Never the name of a person or of a place.", max_length: 60
        string :description, description: "What it is and what state it is in, consistent with the description of the room you just wrote. One or two sentences.", max_length: 400
        boolean :readable, description: "True only if this thing has WRITING on it that a player could read: a note, a letter, a label, a docket, a page, a sign, an inscription. False for everything else, which is most things."
        string :inscription, description: "The words written on it, exactly as they appear, and only when `readable` is true. Write what is actually on the thing -- what a player would read off it -- not a description of it. A few words, a line, or a few short lines; well under the limit, and finished rather than trailing off. Leave this out entirely when nothing is written on it.", required: false, max_length: Item::INSCRIPTION_LIMIT
      end
    end

    # AND THE ONE FIELD THE COUNT CHANGES. At nought it is the field it always
    # was -- optional, bounded, and asked for nobody in words; at one or more it
    # is a length the answer has to meet. `.for_people` below has the whole of
    # why.
    array :people,
          description: wanted > 1 ?
            "The #{wanted} people who are in this place right now. Write all #{wanted} the instructions describe, in the order they are given there." :
            (wanted == 1 ? "The person who is in this place right now. Write the one the instructions describe." : "People who are in this place right now."),
          required: wanted.positive?,
          min_items: (wanted if wanted.positive?),
          max_items: wanted.positive? ? wanted : Location::Population::MOST do
      object do
        string :fullname, description: "Their full name, as a player would type it to speak to them. 2 or 3 words.", max_length: Character::Registry::PERSON_LIMITS[:fullname]
        string :nickname, description: "What they are called to their face. 1 or 2 words.", max_length: Character::Registry::PERSON_LIMITS[:nickname]
        string :appearance, description: "What somebody walking in sees of them, consistent with the room you just wrote and with the race and age you were given for them. One or two sentences.", max_length: Character::Registry::PERSON_LIMITS[:appearance]
        string :personality, description: "How they behave and how they treat a stranger. One or two sentences.", max_length: Character::Registry::PERSON_LIMITS[:personality]
        string :backstory, description: "Why they are in this place and what they want. Third person, by name. Two or three sentences.", max_length: Character::Registry::PERSON_LIMITS[:backstory]
        string :likes, description: "A comma separated list of 2 or 3 things they enjoy.", max_length: Character::Registry::PERSON_LIMITS[:likes]
        string :dislikes, description: "A comma separated list of 2 or 3 things they cannot stand.", max_length: Character::Registry::PERSON_LIMITS[:dislikes]
        string :fears, description: "A comma separated list of 1 or 2 things they are afraid of.", max_length: Character::Registry::PERSON_LIMITS[:fears]
      end
    end
  end

  class_exec(0, &DECLARE)

  # THE SAME SCHEMA REQUIRING EXACTLY `wanted` PEOPLE, and this class itself for
  # a room with nobody in it.
  #
  # The captain's ruling of 2026-09-07: the narrator picks how populated a place
  # is from a closed list and the engine rolls the count inside that word's band
  # (`Location::Population`). So the count is known before this call is made, and
  # the field that used to be a ceiling the model could decline is now a length
  # it has to meet -- `min_items` and `max_items` both, and `required`, which is
  # what makes an answer with the wrong number of people a FAILED CALL that
  # rotates rather than a room quietly written empty.
  #
  # NOUGHT RETURNS THIS CLASS UNCHANGED, and that is the guard the whole design
  # rests on rather than an optimisation: an empty required array reads as an
  # OMITTED FIELD to `BaseAgent#missing_schema_keys`, so a room the pick called
  # empty would fail its own realization and rotate through every model in the
  # rotation looking for one that would invent somebody. At nought the array
  # stays optional and `Location::Generator::NOBODY_HERE` asks for nobody in
  # words.
  #
  # BUILT AT LOAD AND HELD, one class per count the table can produce, because a
  # schema class per realization would be a class per room for the life of the
  # process -- `RubyLLM::Schema` keeps its properties in class-level state, so
  # each one is retained by the constant that names it and by nothing else.
  #
  # AND EACH ONE ANSWERS TO THIS CLASS'S NAME. `RubyLLM::Chat#with_schema`
  # instantiates the class and `to_json_schema` sends `@name` to the provider,
  # which for an anonymous class would be the literal "Schema". Naming them all
  # the same thing keeps the payload identical to the one every measured
  # realization was made with, in the one field of it that is not a declaration.
  def self.for_people(wanted)
    wanted = wanted.to_i

    wanted.positive? ? EXACTLY.fetch(wanted) : self
  end

  EXACTLY = (1..Location::Population::MOST).to_h { |wanted|
    variant = Class.new(RubyLLM::Schema)
    variant.name(name)
    variant.class_exec(wanted, &DECLARE)

    [ wanted, variant ]
  }.freeze
end
