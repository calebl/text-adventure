# WHAT SORT OF PLACE A ROOM IS, HOW MUCH SMALL STUFF LIES ABOUT IN IT, AND
# WHICH SORT EACH ROOM OF A BUILDING IS. Three closed lists and one table.
#
# THE OWNER'S DECISION OF 2026-09-27: rooms become dense with things --
# fixtures, containers whose contents are made once on the first search, and
# portable things -- and every one of them is an engine record the narrator is
# told. What a room holds will be rolled from a table keyed on what sort of
# place it is, so the sort has to be a word the engine can key on. This file is
# that word and nothing that is built on it yet.
#
# THE WORDS ARE FOR ANY SETTING, and each names one sort of place. A story may
# be a walled town, a modern city or a ship between planets, so the lists are
# not a historical fantasy's: `sleeping quarters` rather than `bedchamber`, a
# `machine room` for a mill's works and a ship's engines alike, and ships and
# stations among the buildings. A word that could be two sorts is not on
# either list -- a crossing over water is `crossing`, because a ship's bridge
# is a `control room`. They are a first cut, and the owner means to revisit
# them.
#
# THE LISTS ARE THE ENGINE'S. They are sent on calls the Rust engine makes
# every turn, so the file is its `data/location/kind.yml`, read here through
# the extension like every engine-owned file (`EngineData`).
#
# SO THE SPLIT IS `Location::Population`'s EXACTLY: THE MODEL PICKS A WORD, THE
# ENGINE DOES THE REST. The standing constraint (AGENTS.md) -- *do not ask a
# model what should happen; ask it to pick from a set the app closed, then have
# the app act.* A model never lists furniture and never writes a count; it
# picks `KINDS` and `DENSITIES` for a place it is naming as a way out, and
# `BUILDINGS` for a building it is describing.
#
# WHERE EACH PICK COMES FROM, and it is never the call that describes the room.
# What stands in a room has to be known before that room's own prompt is
# built, so the room is described with it rather than against it -- so the word
# for a place is picked by the room NEXT DOOR while it names the way there
# (`Location::ExitsSchema`), and `Location::Generator.create_stub!` writes it on
# the stub as it is created: `population`'s shape and its reason. A room of a
# building gets no exits call at all, so its word comes from the building's own
# call instead (`Location::PlaceSchema#place_kind`) and is DEALT, not picked,
# by `.deal` below, as `Location::Interior` lays the rooms out.
#
# A ROW WITH NO WORD IS THE ORDINARY CASE AND NOT AN ERROR -- the opening room,
# a seeded room whose file leaves the key out, a room of a building whose call
# picked no sort of building, and every row older than the columns. Nil means
# NOBODY PICKED, and nothing is rolled in its place: what a room with no word
# holds is the engine's quietest answer, not a guess at a word.
#
# NOTHING READS EITHER COLUMN YET, and that is the rule that a parameter ships
# inert rather than an unfinished thought: the words are on the rows first, so
# the tables that furnish a room can be built over rows that already carry
# them, and not one stored world changes how it plays on the day the columns
# arrive. `Story::Doctor` has nothing to report about them for the same reason.
module Location::Kind
  TABLES = EngineData.fetch("location/kind")

  # WHAT SORT OF PLACE A ROOM IS: the words a model picks from on the exits
  # call and a seed file may write. A word and never a list of furniture --
  # what stands in a place of each sort is the engine's to decide.
  KINDS = TABLES.fetch("kinds")

  # HOW MUCH SMALL STUFF LIES ABOUT IN IT, quietest first. A word and never a
  # count: the engine rolls how many things a word means.
  DENSITIES = TABLES.fetch("densities")

  # WHICH ROOMS A BUILDING OF EACH SORT HAS, by where they are in it: the room
  # you walk in at, the rest of the ground floor, the floors above, and the
  # floors below. Every word in it is one of `KINDS` and no band is empty,
  # which `.checked!` holds the file to as it is loaded.
  TABLE = TABLES.fetch("buildings")

  # WHAT SORT OF BUILDING A PLACE IS: the words the place call picks from. For
  # a ship or a station a storey is a deck, and the entry its airlock.
  BUILDINGS = TABLE.keys.freeze

  # THE WORD EACH ROOM OF A BUILDING IS BORN WITH, given each room's storey in
  # the order the rooms were written -- which is `Location::Interior`'s order,
  # entry room first. Nil for every room when nobody picked a sort of building,
  # or picked one this table does not have.
  #
  # DEALT, NOT ROLLED. The entry room is the building's `entry`; every other
  # room takes the next word of its band -- `ground` for storey 0, `above` for
  # higher, `below` for lower -- in turn, starting again at the top of the list
  # when it runs out. So the room you walk into an inn at is its hall, the rooms
  # upstairs are bedchambers, and a cellar is a cellar, which is what a building
  # is; and no die is thrown, so nothing here can move a draw of the layout it
  # is dealt over, and a building re-derived from its rows gets the same words.
  def self.deal(building, storeys)
    plan = TABLE[building]
    return Array.new(storeys.size) if plan.nil?

    dealt = Hash.new(0)
    storeys.each_with_index.map do |storey, index|
      next plan.fetch("entry") if index.zero?

      name = band_for(storey)
      band = plan.fetch(name)
      word = band[dealt[name] % band.size]
      dealt[name] += 1
      word
    end
  end

  def self.band_for(storey)
    if storey.positive? then "above"
    elsif storey.negative? then "below"
    else "ground"
    end
  end

  # EVERY WORD A BUILDING DEALS IS A WORD A ROOM MAY CARRY, AND EVERY BAND HAS
  # ONE, asked once, as the file is loaded -- `EngineData`'s rule that a table
  # which cannot be right fails loudly rather than writes a row `Location#kind`
  # refuses mid-layout.
  def self.checked!
    TABLE.each do |building, plan|
      bands = plan.slice("ground", "above", "below")
      empty = bands.select { |_, words| words.empty? }.keys
      raise EngineData::Error, "location/kind: #{building} has nothing to deal #{empty.join(", ")}" if empty.any?

      stray = [ plan.fetch("entry"), *bands.values.flatten ] - KINDS
      raise EngineData::Error, "location/kind: #{building} deals #{stray.inspect}, which are not kinds" if stray.any?
    end
  end

  checked!
  private_class_method :band_for, :checked!
end
