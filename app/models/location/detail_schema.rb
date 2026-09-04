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
# writing a room around, and the two agree by construction. Optional and
# bounded for the same reasons too: **nobody is the ordinary answer**, and an
# absent `people` and an empty `people` mean the same thing.
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
class Location::DetailSchema < RubyLLM::Schema
  string :description, description: "What the player sees, hears and smells standing in this place right now. Describe THIS place only -- not what neighbours it, not what is visible out of a window or across the way, because the world around it can move. Second person. One paragraph, 4 to 6 sentences.", max_length: 1200
  string :lore, description: "What this place is, who made it and what happened here. Written for the game engine rather than the player. One paragraph, 3 to 5 sentences.", max_length: 900

  array :items,
        description: "Portable things lying loose in this place that a player could pick up and carry away. Empty is the right answer for most rooms.",
        required: false,
        max_items: Item::Registry::MAX_PER_ROOM do
    object do
      string :name, description: "What the thing is called, as a player would type it to pick it up. A short noun phrase, 1 to 4 words, lower case unless it is a proper name. Never the name of a person or of a place.", max_length: 60
      string :description, description: "What it is and what state it is in, consistent with the description of the room you just wrote. One or two sentences.", max_length: 400
    end
  end

  array :people,
        description: "People who are in this place right now. Nobody is the right answer for most rooms.",
        required: false,
        max_items: Character::Registry::MAX_PER_CALL do
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
