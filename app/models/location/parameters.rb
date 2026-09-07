# WHAT A MODEL MAY DECIDE ABOUT A BUILDING, AS A CLOSED LIST PER QUESTION AND A
# TABLE OF NUMBERS BEHIND EACH ONE.
#
# THE CAPTAIN'S CALL 7, 2026-09-06: *"the location generator should decide if the
# location has multiple rooms / areas inside it. And we should provide some
# direction on how to make that decision."* And the same evening, which is the
# whole of this file: *"model is prompted with the setting and story to determine
# the parameters for the location (how many rooms, how many floors, how many
# basements, is it dangerous, is it more dangerous as you go higher or lower,
# etc). I think the engine will need to provide a list of options it can choose
# from."* And then, flatly: **"The model never writes a free number, only picks
# from the list."**
#
# SO EVERY ENTRY BELOW IS A LABEL A MODEL PICKS AND A NUMBER THE ENGINE READS.
# `Location::DANGERS`' shape and its reason: the label is what a person writing
# a world reads, the number is what the engine rolls, and a free number is a
# field something outside the engine could fill in wrongly. Nothing in any schema
# asks for a number, and nothing here is a rule engine -- these are parameters,
# and the behaviour that consumes them is `Location::Interior`'s and
# `Location::Danger`'s.
#
# WHICH SIX, AND WHY NOT MORE. The captain's Call 1 of 2026-09-07 -- **CHOSE: b,
# your five plus a hazard pick from Location::HAZARDS** -- so: whether it has an
# inside, how far up, how far down, how dangerous, which way the danger runs, and
# what the place DOES to somebody standing in it. Two things he was offered and
# are deliberately NOT here:
#
#   `locations.mobile` IS NOT OFFERED. A mobile place is a WORLD MECHANIC's
#   parameter, read by `WorldMechanic`'s operations and by nothing else. A model
#   picking it would be a model deciding which shuffle lanes a world has, and
#   `WorldMechanic::ShuffleConnections` refuses a file with fewer than two mobile
#   locations. It stays seeded.
#
#   `location_connections.distance` IS NOT OFFERED EITHER, and it is already in
#   the right house on both sides of the wall: inside a building the distance is
#   arithmetic off the two boxes (`Location::Interior#distance_for`), and outside
#   one the exits call already picks it from a closed enum of its own.
#
# NOTHING HERE GETS A COLUMN, and that is the design rather than a saving. The
# footprint is the one pick with somewhere to live -- `locations.width` and
# `locations.depth`, which is what `Location#place?` reads -- and every other
# pick is CONSUMED AT LAYOUT, in the same transaction it was picked in, and read
# back off the rows afterwards:
#
#   how many storeys  the min and max `z` of the children
#   the gradient      each room's own `danger`, which is what the gradient WAS
#   how warren-like   the count of `LocationConnection` rows per room
#   the hazard        `locations.hazard` per room, rolled at a share
#
# A stored parameter beside those rows would be a second record that could
# disagree with them, which is `Location::Interior`'s own doctrine: *a parameter
# with no world to supply it is a column the doctor would have to report on.*
#
# AND A DEFAULT IS ALWAYS THE QUIETEST OPTION. Every field is optional -- an
# absent pick is a legal answer and the commonest one -- so the defaults decide
# what a world looks like when nothing says otherwise, and the answer is: flat
# ground, no cellar, nothing dangerous and nothing that hurts you.
# `Eval::Realization::Scorer`'s `inside_declined` and `parameters_declined` are
# what measure how often that happens, because a prompt that quietly stopped
# building anything would otherwise clear every rate in the bench.
class Location::Parameters
  # --- whether it has an inside, and how big -----------------------------------

  # THE QUIETEST OPTION AND THE DEFAULT: this exit leads to a stretch of road, a
  # clearing, a bridge -- somewhere with no rooms in it. It is FIRST on the list
  # every named exit gets, which is the captain's Call 3 of 2026-09-07 (*the
  # model's own first pick, with 'no inside' on the list every stub gets*): there
  # is no separate question of which stubs are asked, because a road answers this
  # and costs nothing further.
  NO_INSIDE = "no inside".freeze

  # THE BAND A LABEL NAMES, IN PACES A SIDE. `Location::Interior::FOOTPRINT_SIDES`'
  # shape, and the engine rolls each side independently inside the band.
  #
  # A FOOTPRINT AND NOT A ROOM COUNT, which is the one place this vocabulary
  # departs from the captain's own wording and it is `Location::Interior`'s rule
  # that decides it: THE FOOTPRINT IS THE WORLD'S PARAMETER AND THE DIVISION IS
  # BEHAVIOUR. Ask for both and the two answers can disagree -- a model that says
  # "twelve rooms" and "cramped" has described nothing the engine can build. So
  # the label is phrased in ROOMS, because rooms are what he named and what a
  # model reasons about better than paces, and the number behind it is the
  # footprint.
  INSIDE = {
    NO_INSIDE => nil,
    "one room" => (3..5),
    "a few rooms" => (6..9),
    "a warren of rooms" => (12..18)
  }.freeze

  # THE FEWEST ROOMS A BAND PROMISES, and the ONLY consumer is the bench --
  # `Eval::Realization::Scorer#judge_parameters_the_engine_narrowed`, which is
  # how "the engine could not honour that pick" becomes a measured rate instead
  # of an argument. Deliberately below what each band usually produces: the
  # division is rolled, so a band that came out at its own floor was not
  # narrowed, it was rolled small.
  ROOMS_A_BAND_PROMISES = { "one room" => 1, "a few rooms" => 2, "a warren of rooms" => 4 }.freeze

  # --- how far up and how far down ---------------------------------------------
  #
  # TWO PICKS AND NOT ONE, which is a decision rather than an oversight. They are
  # the two ends of one storey range and the engine builds one range from them,
  # but a tower and a crypt are different fictions and a model has to be able to
  # choose one without the other. Folded into a single "how tall, how deep" pick,
  # `deep` and `two storeys up` would be mutually exclusive for no reason.
  #
  # THE VALUE IS A COUNT OF STOREYS, at and above the ground floor for the first
  # and below it for the second -- `Location::Interior::STOREYS` and `BASEMENTS`'
  # own units, so a pick is handed over in the numbers that file already speaks.
  STOREYS_ABOVE = { "ground floor only" => 1, "one storey up" => 2, "two storeys up" => 3 }.freeze
  STOREYS_BELOW = { "none" => 0, "a cellar" => 1, "two levels down" => 2, "deep" => 3 }.freeze

  # --- how dangerous, and which way it runs ------------------------------------

  # WHAT A ROOM OF THIS BUILDING MAY BE BORN AS, and THE LIST IS THE WEIGHTING --
  # `Location::Danger::ROLLED`'s shape and its reason: `Roll.one_of` draws one
  # entry, so a key written twice is twice as likely, and a second table of
  # probabilities would be a second thing to keep in step with the first.
  #
  # THE PICK MOVES THE ODDS AND THE DIE STILL DECIDES EACH ROOM. That is the
  # standing constraint applied to a building: a model saying "dangerous" must
  # not be able to make every room dangerous, because then one word from a model
  # decides what a player meets in nine rooms. What it does is shift the
  # distribution, and `Location::Danger` throws for each room as it is born.
  #
  # `deadly` IS NOT ON THE LIST AND NEVER WILL BE. It stays a seed file's word --
  # `Location::DANGERS`' own rule: a room where every inhabitant is a monster is a
  # decision somebody made about a world, not an accident of a die, and certainly
  # not a label a model picked in passing.
  DANGER = {
    Location::SAFE => [ Location::SAFE ] * 7 + [ "uneasy" ],
    "uneasy" => [ Location::SAFE ] * 4 + [ "uneasy" ] * 3 + [ "dangerous" ],
    "dangerous" => [ Location::SAFE ] * 2 + [ "uneasy" ] * 3 + [ "dangerous" ] * 3
  }.freeze

  # THE LADDER THE GRADIENT WALKS, quietest first. It is `DANGER`'s own keys in
  # order, named so `#danger_for` can step along it rather than each caller
  # knowing which way is worse.
  LADDER = DANGER.keys.freeze

  # WHICH WAY THE DANGER RUNS, as the sign of the storey it gets worse in. Zero
  # is a gradient of nothing, which is why there is no separate "flat or not" to
  # ask: a base level and a direction are one parameter with two fields, and a
  # gradient with no base level is a slope from nothing.
  FLAT = "the same throughout".freeze
  GRADIENT = { FLAT => 0, "worse the deeper you go" => -1, "worse the higher you climb" => 1 }.freeze

  # --- what the place does to somebody standing in it --------------------------

  NO_HAZARD = "none".freeze

  # THE KEYS `Location::HAZARDS` ALREADY HAS, and not one more. The table is
  # closed, the die list is closed, and an entry with a new `when:` would need a
  # branch written for it in `Playthrough::Hazards` -- so a model picks from what
  # the engine can already do to somebody, and never describes a new hazard.
  HAZARDS = [ NO_HAZARD, *Location::HAZARDS.keys ].freeze

  # HOW OFTEN A ROOM OF A HAZARDOUS BUILDING ACTUALLY CARRIES THE HAZARD: this
  # many faces of `HAZARD_DIE`, thrown per room as it is born.
  #
  # THE PICK IS A RATE AND NOT AN ASSIGNMENT, AND THAT IS LOAD-BEARING RATHER
  # THAN TIDY. `Location::HAZARDS` carries a `when:` per entry, and TWO OF THE
  # FOUR ARE CHARGED EVERY TURN -- `silent` and `airless`. `Playthrough::Hazards`
  # routes both through `Character#harm!`, so a building every room of which was
  # `airless` would take hit points off the party every turn they stood inside it
  # and could end a playthrough by arithmetic, with no fight, no monster and
  # nothing the player could have done differently. A rolled per-room share is
  # what keeps a deep airless warren survivable: some rooms are bad and the way
  # through them is not.
  #
  # AND THE DIE IS THE ENGINE'S, ALWAYS. A model picks the KEY and never
  # `locations.hazard_die`; the engine draws that from `Location::HAZARD_DICE`.
  # This is not a preference -- `Location#a_hazard_is_whole` refuses a row
  # carrying a key without a die, so a pick that did not roll one would be an
  # invalid record.
  HAZARD_DIE = 6
  HAZARD_SHARE = 2

  # THE PICKS AS A VALUE, off whatever came back -- an absent block, an absent
  # field, or a label outside the list all fall to the quietest option. The
  # schema makes an out-of-list value impossible to parse, so the fallback is for
  # the two cases a schema cannot rule out: nothing at all, and a set of picks
  # read back out of a stored file.
  def self.from(picks)
    picks = picks.to_h { |key, value| [ key.to_s, value ] } if picks.respond_to?(:to_h)

    new(picks.is_a?(Hash) ? picks : {})
  end

  # EVERY DEFAULT, which is what a place laid out by anything other than a model
  # pick gets: `Location::Interior.lay_out!` with no parameters at all, and the
  # engine's own fallback for a caller with no model available.
  def self.none = new({})

  attr_reader :picks

  def initialize(picks)
    @picks = picks
  end

  def inside = pick(INSIDE, "inside", NO_INSIDE)

  def inside? = inside != NO_INSIDE

  # THE FOOTPRINT THIS BAND ASKS FOR, as two sides rolled independently inside
  # it, or NIL for `no inside`. The roll is the caller's -- it hands the
  # generator, because a footprint written at stub time has to be re-derivable
  # from the story and the room count like every other draw in the app (`Roll`).
  def footprint(rng)
    band = INSIDE.fetch(inside, nil)
    return nil if band.nil?

    [ Roll.one_of(band.to_a, rng: rng), Roll.one_of(band.to_a, rng: rng) ]
  end

  def storeys_above = pick(STOREYS_ABOVE, "storeys_above", STOREYS_ABOVE.keys.first)

  def storeys_below = pick(STOREYS_BELOW, "storeys_below", STOREYS_BELOW.keys.first)

  def above = STOREYS_ABOVE.fetch(storeys_above)

  def below = STOREYS_BELOW.fetch(storeys_below)

  def danger = pick(DANGER, "danger", Location::SAFE)

  def gradient = pick(GRADIENT, "gradient", FLAT)

  def hazard = HAZARDS.include?(picks["hazard"]) ? picks["hazard"] : NO_HAZARD

  def hazard? = hazard != NO_HAZARD

  # WHAT A ROOM ON THIS STOREY MAY BE BORN AS: the building's own list, shifted
  # one rung along `LADDER` in the direction the gradient runs. One rung and not
  # one per floor, because the ladder has three rungs and a five-storey building
  # would otherwise spend the whole of it on the second floor -- what the
  # gradient says is *worse down there*, not *unsurvivable at the bottom*.
  def danger_for(storey) = DANGER.fetch(LADDER[rung_for(storey)])

  # HOW MANY FACES OF `HAZARD_DIE` GIVE A ROOM ON THIS STOREY THE PLACE'S HAZARD.
  # Zero for a building that picked none -- and at a share of zero NO DIE IS
  # THROWN AT ALL, which is `Location::Danger.monstrous?`'s rule and the caller's
  # to keep. The gradient moves it by the same one step the danger moves by.
  def hazard_share_for(storey)
    return 0 unless hazard?

    (HAZARD_SHARE + step_for(storey)).clamp(0, HAZARD_DIE)
  end

  private

  # WHICH WAY THIS STOREY LEANS: one step worse in the gradient's direction, one
  # step quieter against it, and nothing on a flat building or on the ground
  # floor. One step and not one per floor, because the ladder has three rungs and
  # a five-storey building would otherwise spend the whole of it on the second
  # floor -- what the gradient says is *worse down there*, not *unsurvivable at
  # the bottom*.
  #
  # READ BY BOTH HALVES, and it has to be: the danger and the hazard are the same
  # slope said about two different columns, and a second derivation would let one
  # of them lean the other way.
  def step_for(storey) = (GRADIENT.fetch(gradient) * storey.to_i).clamp(-1, 1)

  # WHERE ON THE LADDER A ROOM OF THIS STOREY SITS, and never off either end.
  def rung_for(storey) = (LADDER.index(danger) + step_for(storey)).clamp(0, LADDER.size - 1)

  def pick(table, key, fallback) = table.key?(picks[key]) ? picks[key] : fallback
end
