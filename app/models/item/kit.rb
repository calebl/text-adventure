# WHAT STANDS IN A ROOM AND WHAT LIES ABOUT IN IT, rolled from a table keyed
# on what sort of place it is. The owner's dense-rooms decision of 2026-09-27:
# *D2 source: kit tables only* -- no model names a desk, lists a drawer or
# writes a count. A model picked the room's two words (`Location::Kind`) on the
# call next door; this rolls the rest and writes it down, before the room's own
# writer is asked to describe it, and `Location::Generator#already_here` states
# what was written.
#
# THE TABLES ARE THE ENGINE'S, `data/item/kits.yml`, read here through the
# extension like every engine-owned file (`EngineData`), because the Rust engine
# furnishes every room a turn realizes and both have to roll the same room the
# same way. The file's header says what each key means; this says why the roll
# has the shape it has.
#
# SEEDED ON THE ROOM'S NAME, `Location::Population.generator_for`'s seed with a
# kind of its own (`Roll::KIT`): a room's furniture is a fact about somewhere, a
# re-seeded world is the same somewhere, and the realization bench re-loads a
# world per repetition -- a kit keyed on the row would state a different room
# in the prompt on every run. ONE GENERATOR, THROWN IN ONE ORDER: a die per
# piece the kind lists, in the file's order; then, for each piece that came up,
# the count of what lies on or in it and a draw per thing; then the count of
# small stuff at the room's density and a draw per thing. No name is drawn
# twice in one room, and the list is cut at `VISIBLE` -- pieces first, so a cut
# only ever drops small stuff.
#
# A ROOM WITH NO WORD GETS NOTHING, which is the rule that a parameter ships
# inert: a kind the table does not have, or none at all, rolls no die and
# writes no row, so no stored world changes how it plays. No density word means
# no small stuff; the pieces are the kind's.
#
# ONCE PER ROOM, AND THE ROWS ARE THE TRUTH AFTERWARDS. `#furnish!` writes
# templates -- the world layer, copied into each game by `Item::Snapshot` --
# only into a room that is not a place and holds no kit row yet, so a
# realization picked up again after a failed call furnishes nothing twice, and
# a room renamed by its writer keeps the furniture its placeholder name rolled.
#
# WHAT IS WRITTEN. A fixed piece is a `Item::FIXTURE`, `immovable`, holding what
# the table says; a piece that can be carried off is a portable thing of the
# table's bulk; a thing on or in a piece is a portable thing lying `within` it,
# with no position of its own; small stuff is a portable thing on the floor.
# Every row carries its `kit_key` -- `kind/piece`, `kind/piece/thing` or
# `kind/loose/thing` -- which is what keeps a kit row out of the room writer's
# caps (`Item.bespoke`) and tells the doctor who wrote it. A description is one
# engine line and no prose: nothing sends an item's description to a model, and
# the narrator is what makes a desk read like a desk.
class Item::Kit
  TABLES = EngineData.fetch("item/kits")

  # THE DIE A PIECE'S SHARE IS READ AGAINST, and the most one kit puts in a room.
  DIE = TABLES.fetch("kit_die")
  VISIBLE = TABLES.fetch("visible")

  # THE MOST ONE ROOM SHOWS: its fixtures and everything lying in it, the
  # owner's decision D6 of 2026-09-27. What a kit puts there and what the
  # room's writer may add, together -- so the table's `visible` is this less the
  # writer's own allowance, and `Story::Doctor` reports a room past it.
  MAX_VISIBLE_PER_ROOM = 24

  # WHAT EACH PIECE IS: one of `Item::HOLDS` for a piece fixed in place, or a
  # bulk for a piece that stands here and can be carried off.
  PIECES = TABLES.fetch("pieces")

  # One thing a kit writes. `within` is the index, in the same list, of the
  # piece it lies on or in.
  Thing = Data.define(:name, :tier, :holds, :bulk, :within, :how, :kit_key)

  # THE ROOM'S KIT, as values and in the order it is written. Pure: it reads the
  # tables and throws the dice, and touches no record.
  def self.roll(name:, kind:, density:)
    kit = TABLES.fetch("kinds")[kind]
    return [] if kit.nil?

    rng = Roll.generator(story: 0, sequence: Zlib.crc32(WorldSeed.natural_key(name.to_s)), kind: Roll::KIT)
    pieces = kit.fetch("pieces").select { |_piece, share| Roll.die(DIE, rng: rng) <= share }.keys
    things = pieces.map { |piece| piece_thing(kind, piece) }
    used = pieces.dup

    pieces.each_with_index do |piece, index|
      pool = TABLES.fetch("pools")[TABLES.fetch("holding")[piece]]
      next if pool.nil?

      how = PIECES.fetch(piece) == "hollow" ? "in" : "on"
      draw(pool.fetch("from"), Roll.one_of(pool.fetch("count"), rng: rng), used, rng).each do |name|
        things << Thing.new(name: name, tier: Item::PORTABLE, holds: nil, bulk: Item::HANDY, within: index,
                            how: how, kit_key: "#{kind}/#{piece}/#{name}")
      end
    end

    band = TABLES.fetch("density")[density]
    if band
      draw(kit.fetch("loose"), Roll.one_of(band, rng: rng), used, rng).each do |name|
        things << Thing.new(name: name, tier: Item::PORTABLE, holds: nil, bulk: Item::HANDY, within: nil,
                            how: nil, kit_key: "#{kind}/loose/#{name}")
      end
    end

    things.first(VISIBLE)
  end

  def self.piece_thing(kind, piece)
    word = PIECES.fetch(piece)
    fixed = Item::HOLDS.include?(word)
    Thing.new(name: piece, tier: fixed ? Item::FIXTURE : Item::PORTABLE, holds: (word if fixed),
              bulk: fixed ? Item::IMMOVABLE : word, within: nil, how: nil, kit_key: "#{kind}/#{piece}")
  end

  # THE ONE ENGINE LINE A KIT'S ROW IS DESCRIBED BY, given the piece it lies on
  # or in (anything with a `name`), or nil.
  def self.description_of(thing, within)
    return "The #{thing.name}, #{thing.how} the #{within.name}." if within
    return "The #{thing.name}, fixed in place." if thing.tier == Item::FIXTURE

    "The #{thing.name}."
  end

  # `count` names out of `from`, never one already `used` in the room, drawn one
  # at a time from what is left; fewer when the pool runs dry.
  def self.draw(from, count, used, rng)
    count.times.filter_map do
      left = from - used
      next if left.empty?

      name = Roll.one_of(left, rng: rng)
      used << name
      name
    end
  end

  attr_reader :location

  def initialize(location)
    @location = location
  end

  # THE ROOM'S KIT, written as the world's own rows, once. Returns the rows it
  # wrote: none for a place, a room already furnished, or a room with no word.
  def furnish!
    return [] if location.place? || furnished?

    things = self.class.roll(name: location.name, kind: location.kind, density: location.density)
    Item.transaction do
      things.each_with_object([]) { |thing, rows| rows << write!(thing, rows) }
    end
  end

  def furnished? = location.items.templates.where.not(kit_key: nil).exists?

  private

  def write!(thing, written)
    within = thing.within && written.fetch(thing.within)
    item = location.items.create!(
      name: thing.name, description: self.class.description_of(thing, within), tier: thing.tier, holds: thing.holds,
      bulk: thing.bulk, within: within, how: thing.how, kit_key: thing.kit_key,
      use_kind: TABLES.fetch("use_kinds").fetch(thing.name, "ordinary"),
      combustible: TABLES.fetch("combustible").include?(thing.name),
      readable: TABLES.fetch("readable").include?(thing.name)
    )
    return item if within

    placement = Location::Placement.in_the_world(location, item)
    item.update!(**placement) if placement.values.any?
    item
  end


  # A TABLE THAT CANNOT BE RIGHT FAILS AS IT IS LOADED, `Location::Kind`'s rule:
  # every kind is one `Location::Kind` has, every piece a kind lists says what
  # it is, every `holding` names a pool and a fixed piece that holds things, and
  # no thing a pool or a kind's small stuff can draw shares a piece's name.
  def self.checked!
    problems = []
    problems << "kinds #{(TABLES.fetch("kinds").keys - Location::Kind::KINDS).inspect} are not Location::Kind's" if (TABLES.fetch("kinds").keys - Location::Kind::KINDS).any?
    words = Item::HOLDS + (Item::BULK.keys - [ Item::IMMOVABLE ])
    PIECES.each { |piece, word| problems << "#{piece} is #{word.inspect}" unless words.include?(word) }
    TABLES.fetch("kinds").each do |kind, kit|
      kit.fetch("pieces").each_key { |piece| problems << "#{kind} lists #{piece}, which is no piece" unless PIECES.key?(piece) }
    end
    TABLES.fetch("holding").each do |piece, pool|
      problems << "#{piece} holds from #{pool}, which is no pool" unless TABLES.fetch("pools").key?(pool)
      problems << "#{piece} holds things and is #{PIECES[piece].inspect}" unless %w[top hollow closed].include?(PIECES[piece])
    end
    PIECES.each { |piece, word| problems << "#{piece} is #{word} and holds nothing" if %w[top hollow].include?(word) && !TABLES.fetch("holding").key?(piece) }
    drawn = TABLES.fetch("pools").values.flat_map { |pool| pool.fetch("from") } + TABLES.fetch("kinds").values.flat_map { |kit| kit.fetch("loose") }
    problems << "#{(drawn & PIECES.keys).inspect} are both a piece and a thing" if (drawn & PIECES.keys).any?
    TABLES.fetch("density").each_key { |word| problems << "density #{word} is not Location::Kind's" unless Location::Kind::DENSITIES.include?(word) }
    TABLES.fetch("use_kinds").each_value { |use| problems << "#{use} is no use kind" unless Item::USE_KINDS.include?(use) }
    unless VISIBLE + Item::Registry::MAX_PER_ROOM == MAX_VISIBLE_PER_ROOM
      problems << "visible #{VISIBLE} and the writer's #{Item::Registry::MAX_PER_ROOM} are not #{MAX_VISIBLE_PER_ROOM}"
    end
    raise EngineData::Error, "item/kits: #{problems.join("; ")}" if problems.any?
  end

  checked!
  private_class_method :piece_thing, :draw, :checked!
end
