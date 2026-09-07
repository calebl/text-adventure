# REALIZING A BUILDING: everything a room is asked for, plus the six things only
# a building can be asked.
#
# WHY IT IS A SECOND CLASS AND NOT A FIELD ON `Location::DetailSchema`. The
# `parameters` block is offered to a stub carrying a footprint and no rooms, and
# to nothing else -- so it must not reach the detail call of an ordinary room,
# and a schema is fixed per class. A `required: false` object on the one schema
# would put five enums into the JSON schema of EVERY realization in the game,
# which is a change to every call in the world made in order to reach the
# handful that are buildings. `Location::Generator#geometry_facts`' rule, applied
# to the schema instead of to the prose: *empty means the prompt is the one a
# baseline was measured on, character for character* -- and the schema is part of
# what was measured even though `Eval::Realization::Version` cannot digest it.
#
# AND IT IS THE SAME PROSE FIELDS AND NOT A SECOND COPY OF THEM.
# `RubyLLM::Schema` keeps its properties PER CLASS -- `@properties ||= {}` on the
# singleton -- so a subclass inherits none of them and `< Location::DetailSchema`
# would silently produce an empty schema. The two prose fields are therefore held
# as a block on that class and evaluated into this one, which is the one
# arrangement where an edit to what a description IS reaches both.
#
# WHAT A BUILDING IS NOT ASKED, and each is a rule rather than an omission:
#
#   NO `name`. A building was named by whoever named the exit that reached it,
#   and `Location::RoomName` is for a ROOM of one still called a number.
#
#   NO `items` AND NO `people`. Nobody ever stands in a container -- the
#   captain's ruling of 2026-09-06 and `Location::Interior.way_in` -- so a thing
#   lying in one is a thing no player can pick up and a person in one is a person
#   nobody can talk to. The rooms are where both belong, and each room is asked
#   as it is reached.
#
# WHAT THE PICKS ARE AND WHY EACH IS A CLOSED LIST is `Location::Parameters`, in
# full: the captain's Call 7 of 2026-09-06 and his Call 1 of 2026-09-07, the
# table of numbers behind every label, and the reason the hazard is a rate rather
# than an assignment. Nothing here is a number, and every field is optional with
# the quietest option first -- an absent pick is a legal answer and the
# commonest one, which is what `Eval::Realization::Scorer#judge_parameters_declined`
# measures.
class Location::PlaceSchema < RubyLLM::Schema
  class_eval(&Location::DetailSchema::PROSE_FIELDS)

  object :parameters,
         description: "What kind of building this is. Every field is optional; leave one out and the " \
                      "game takes the quietest option. Answer for the place you have just described.",
         required: false do
    string :storeys_above,
           description: "How far up it goes, counting the ground floor. Most buildings are one floor.",
           enum: Location::Parameters::STOREYS_ABOVE.keys, required: false
    string :storeys_below,
           description: "How far down it goes below the ground floor. Most buildings have nothing under them.",
           enum: Location::Parameters::STOREYS_BELOW.keys, required: false
    string :danger,
           description: "How likely a room of it is to hold something that means the player harm. " \
                        "Most buildings are safe.",
           enum: Location::Parameters::DANGER.keys, required: false
    string :gradient,
           description: "Whether that gets worse in one direction. Only say so when the place itself " \
                        "makes it true -- a cellar that gets worse the further down you go, a tower " \
                        "that gets worse the higher you climb.",
           enum: Location::Parameters::GRADIENT.keys, required: false
    string :hazard,
           description: "What standing in its rooms does to a person, if anything. NONE is the right " \
                        "answer for almost every building: this is not atmosphere, it is a place that " \
                        "takes hit points off whoever walks through it.",
           enum: Location::Parameters::HAZARDS, required: false
  end
end
