# WHAT HAS TO BE TRUE OF THE WHOLE WORLD AFTER A WALK, whatever the walk was.
#
# These are not per-step expectations and no script asks for them: they run
# after every script, against the world it just walked, compared with the file
# it was loaded from. Four of them are the statements the engine defects of
# 2026-09-03 violated, written down as facts about the records rather than as
# facts about one turn -- because that is the shape they had. Nobody typed a
# line that said "give the closet a second door"; a room was realized and the
# closet had two doors afterwards. The fifth, `cast_unmoved`, is the same
# statement about people, added with the whereabouts record: nothing a player
# types may move anybody, and now that presence is a record there is finally
# something to assert it against.
#
#   doors_unchanged      no edge was opened or closed by walking. `Do not open a
#                        new door into a room that is already written` (53e7fbf)
#                        was exactly this: walking into The Long Hallway gave
#                        The Supply Closet a second way out, after the closet's
#                        own prose had said it had none.
#   exit_cap             no room leads more ways out than
#                        `Location::ExitsSchema::MAX_EXITS`. `Make the exit cap
#                        a cap on the room, not on one answer` (9c55969) was a
#                        room that came back with five.
#   items_accounted      every item is in one place -- held by somebody or lying
#                        somewhere, never both -- one of the world's own rows is
#                        never in neither, and the world still has the same
#                        items it started with. `take` and `drop` move a row,
#                        and a row that moved to nowhere is how an item
#                        disappears from a game. Since the captain's ruling of
#                        2026-09-04 "neither" is a place for a playthrough's own
#                        copy -- the party's hands -- so that half is asked of
#                        the world layer alone.
#   world_items_unmoved  every one of THE WORLD'S OWN rows is lying in the room
#                        the file lays it in, AND IN THE CORNER OF IT THE FILE
#                        LAYS IT IN. A typed line may carry one game's copy of
#                        the ward stamp anywhere it likes; it may not touch the
#                        row the next game copies from. This is the item half of
#                        `cast_unmoved`, and before the ruling it could not have
#                        been written at all: `take` moved the world's only row,
#                        so walking into a room and picking something up emptied
#                        it for everybody.
#                        THE CELL IS HELD ON THE SAME TERMS AS THE ROOM, which
#                        is `geometry_unmoved`'s sentence one containment level
#                        down: `items[].x` / `.y` is a value a person wrote in a
#                        file, so a walk that re-rolled a template's corner in
#                        place -- same room, same name, same layer -- would
#                        otherwise pass every instrument here, and
#                        `positions_in_bounds` would clear it for every cell of
#                        the room but one. Both ways, so a template that
#                        ACQUIRED a cell fails as loudly as one that lost it,
#                        and a file that lays nothing in a corner still passes,
#                        which is every row of all three checked-in worlds.
#                        ONE GAME'S OWN COPY IS NOT IN IT and must not be: a
#                        walk is SUPPOSED to move that cell, which is why
#                        `positions_in_bounds` is the instrument for the
#                        playthrough layer and is the one sentence here not
#                        stated against the file.
#   cast_unmoved         every character is standing exactly where the world
#                        file put them -- in which room and in which corner of
#                        it -- and anybody the file left nowhere is still
#                        nowhere. `characters.location_id` is the closed
#                        set `talk` resolves against, and NOTHING in a walk may
#                        write it: the seed file, `Character::Registry` (at
#                        realization, which this mode cannot reach) and an
#                        explicit `Character#move_to!` are the only writers, so
#                        a walk that moved somebody means a typed line has
#                        started moving people. `characters.x` / `.y` has the
#                        same writers and is held on the same terms, for
#                        `world_items_unmoved`'s reason: there is no per-game
#                        copy of a person (see `Character#position`), so a cell
#                        that moved during a walk moved for every player at
#                        once. It is stated as "unmoved"
#                        rather than as "nobody is nowhere" because nowhere is
#                        a legitimate state that two of the three checked-in
#                        worlds are in: the protagonist and any companion carry
#                        no whereabouts at all (the party is wherever the
#                        PLAYTHROUGH is), and `The Unrecorded Hour` leaves
#                        Perrin Lasco nowhere on purpose. Comparing against the
#                        file catches everything "nobody is nowhere" would --
#                        somebody who LOST their room during the walk fails it
#                        -- and does not fail on a world that means it.
#   stat_blocks_unmoved  every character's `level`, `hit_die` and three
#                        abilities are what the world file says they are, and
#                        somebody the file gives no `stats` still has none.
#                        All five columns since the captain's ruling of
#                        2026-09-04 evening -- an ability is the world's on
#                        exactly the same terms as a hit die, and `check
#                        strength` throws a die and writes nothing at all.
#                        It is `cast_unmoved` for the
#                        body instead of the whereabouts, and it is the world
#                        half of the captain's ruling of 2026-09-04: a stat
#                        block is the WORLD's, so no typed line may write one.
#                        What a walk does write is `playthrough_vitals` -- how
#                        much is left of somebody in ONE game -- and that is a
#                        different table on the other side of the layer split,
#                        so `harm 5` walks all the way through the engine
#                        without this moving. Stated as "unmoved" rather than as
#                        "everybody has one" for the same reason `cast_unmoved`
#                        is: a file that gives nobody a stat block is a
#                        legitimate world, and comparing against the file
#                        catches everything the stronger sentence would.
#                        WHAT IS NOT IN IT is `characters.hostile`, and the
#                        reason is in `hostility_unmoved` below: that is the
#                        same sentence about the same layer, and it has to cover
#                        `races.monstrous` and `locations.danger` too, neither
#                        of which is a column on a character.
#   hostility_unmoved    the WORLD's four columns about what a room is born with
#                        are what the world file says they are:
#                        `characters.hostile` for every person,
#                        `races.monstrous` for every race, and
#                        `locations.danger` and `locations.population` for every
#                        room -- the last of those since the captain's ruling of
#                        2026-09-07 gave the narrator the pick of how populated a
#                        place is (`Location::Population`), which is a fact about
#                        the world on exactly `danger`'s terms. It is
#                        `stat_blocks_unmoved`'s statement one column over --
#                        no typed line may make somebody hostile, mark a race
#                        monstrous or make a room dangerous -- and it is a
#                        SEPARATE check rather than three more keys on that one
#                        because two of the three are not columns on a character
#                        at all, and an invariant that reported a moved race
#                        under the heading "stat blocks" would send a reader to
#                        the wrong table. The writers are the seed file, the
#                        derivation at creation (`Character.hostile_by_default?`,
#                        which an offline walk cannot reach because it realizes
#                        no rooms), the roll a room is born with
#                        (`Location::Danger`) and, for the population word, the
#                        exits call of the room next door. No player is on that
#                        list and a model is on it exactly once, before the room
#                        exists. Stated as "unmoved" against the file, for
#                        `cast_unmoved`'s reason: a world with no monsters at
#                        all is the ordinary world and comparing against the
#                        file catches everything a stronger sentence would.
#   geometry_unmoved     every location's box -- `Location::Box::COLUMNS` and the
#                        `parent_location` those five numbers are read in -- is
#                        what the world file says it is, and a room the file
#                        gives no box still has none. It is
#                        `stat_blocks_unmoved`'s statement about a place instead
#                        of a body, and it is the standing constraint applied to
#                        geometry: the ENGINE owns every one of those numbers.
#                        The writers are a seed file and, from slice 2, the
#                        interior layout generator; no model and no typed line is
#                        on that list, and nothing in the play path so much as
#                        reads a coordinate today. THE PARENT IS IN IT because it
#                        is the frame -- coordinates are local to a parent and
#                        there is no global space (`Location::Box`), so a walk
#                        that re-parented a room would move it without changing a
#                        number, and an invariant over the five columns alone
#                        would not notice. Stated as "unmoved" against the file
#                        for `cast_unmoved`'s reason: a world with no interiors
#                        at all is the ordinary world -- it is what all three
#                        checked-in worlds are, by the captain's fourth ruling of
#                        2026-09-06 -- and comparing against the file catches
#                        everything a stronger sentence would.
#   positions_in_bounds  every row that says WHERE IN A ROOM it is is inside that
#                        room's box. Items in both layers and characters alike:
#                        the world's own chair, this game's copy of it, and the
#                        clerk standing beside both. It is the ONE invariant
#                        here that is not stated
#                        against the file, and it is not because it cannot be --
#                        a walk is SUPPOSED to move a position. A take clears
#                        one and a drop rolls a new one
#                        (`Playthrough::Turn#carry!` / `#put_down!`), so "unmoved"
#                        would fail on the ordinary case; what a player may
#                        never do is put a thing somewhere its room is not, and
#                        that is a statement about the rows on their own. It
#                        covers three faults in one sentence: a position outside
#                        its box, a position in a room with no box at all (there
#                        is no plane to read it in), and half a position -- and
#                        the last two are only reachable through raw SQL, since
#                        `Item` and `Character` refuse them, so what this
#                        actually watches is the drop. `Story::Doctor` reports
#                        the same three on a stored world; this asserts them
#                        after a walk.
#                        WHAT A SCRIPT OWES IT, because this one is easier to
#                        pass vacuously than the others: every invariant here is
#                        read ONCE, over the records the walk leaves behind
#                        (`EngineSweep::Walk`), and a position exists only while
#                        the thing is on a floor. So a script whose last line
#                        picks everything up leaves nothing for this to be true
#                        OF and passes whatever a drop wrote.
#                        `things-land-somewhere-in-a-room.yml` ends with a drop
#                        for exactly that reason and says so.
#                        AND THE OTHER HALF OF THAT, SAID PLAINLY: an UNPLACED
#                        row is invisible here. `Item.positioned` and
#                        `Character.positioned` take a row carrying either
#                        column, so a `#put_down!` that wrote NEITHER leaves
#                        nothing to check -- `#carry!` has already cleared the
#                        pair, so the row simply drops out of the scope. This
#                        invariant asserts that a position is in the right room,
#                        never that there is one; `Playthrough::TurnPositionTest`
#                        is what asserts a drop writes one at all.
#                        A SCRIPT ALSO OWES IT A CELL THE WRONG ROOM CANNOT
#                        HOLD. Two rooms one above the other can share a cell --
#                        `Location::Box#contains?` ignores `z` by design -- so a
#                        stale position carried from one to the other is in
#                        bounds for both and passes. `the-quay-house.yml` lays
#                        the seal ledger at an x the room above does not run to,
#                        and its header has the arithmetic.
#   room_names_unique    no two rooms of one place answer to one name, on
#                        `WorldSeed.natural_key`'s reading of "one name". The
#                        one name in the app a MODEL chooses for a row the
#                        engine then looks up by name -- `Location::RoomName`
#                        writes it at realization -- so this is the offline
#                        assertion that whatever it wrote left the building's
#                        rooms tellable apart.
#   nothing_was_written  no room changed detail level. This is the offline
#                        mode's own premise: with no model there is nothing to
#                        write a room WITH, so a stub walked into stays a stub.
#                        Since `Item::Registry` it carries a second guarantee
#                        for free -- a room furnishes itself at the moment it is
#                        realized, so a world in which nothing was written is a
#                        world in which nothing was furnished either. If this
#                        one ever fails, the sweep's assumptions have changed
#                        and the scripts need re-reading before anything else is
#                        believed.
#
# WHY THERE IS NO ITEM CAP HERE, beside `exit_cap`, though `Item::Registry` has
# two of them. `MAX_EXITS` bounds a room: nothing but the generator opens a
# door, so more than four ways out is wrong however it happened.
# `Item::Registry::MAX_PER_ROOM` and `MAX_PER_STORY` bound GENERATION -- they
# are read to decide whether to admit another candidate -- and a player may
# legitimately walk into a room carrying four things and put them all down. An
# invariant on the floor's size would flag that walk as a defect. The caps
# belong to the registry's own tests and to `rake game:doctor`, which diagnoses
# a stored world; this file only asserts what a walk did to a fresh one.
#
# WHAT THEY COST WHEN THEY HOLD, which is what they do today: nothing. A move
# offline writes no exits, so `doors_unchanged` is a statement the offline
# engine cannot currently break on its own. That is not a reason to leave it
# out. It is the assertion the defect broke, it costs four queries, and it fires
# the moment anything in a walk starts writing edges -- which is precisely the
# change that would need watching.
class EngineSweep::Invariants
  attr_reader :story, :seed

  def initialize(story, seed:)
    @story = story
    @seed = seed
  end

  def check
    [ doors_unchanged, exit_cap, items_accounted, world_items_unmoved, cast_unmoved, stat_blocks_unmoved,
      hostility_unmoved, hazards_unmoved, geometry_unmoved, positions_in_bounds, room_names_unique,
      nothing_was_written ].flatten.compact
  end

  private

  # Every pair of connected rooms, unordered and de-duplicated, so the two rows
  # a connection is stored as read as the one door they are.
  def doors_now
    LocationConnection.joins(:location)
                      .where(locations: { story_id: story.id })
                      .includes(:location, :connected_location)
                      .map { |row| [ row.location.name, row.connected_location.name ].sort }
                      .uniq.sort
  end

  def doors_in_file
    Array(seed["connections"]).map { |row| Array(row["between"]).sort }.uniq.sort
  end

  def doors_unchanged
    opened = doors_now - doors_in_file
    closed = doors_in_file - doors_now
    return nil if opened.empty? && closed.empty?

    broken("doors_unchanged",
           [ opened.any? ? "opened #{opened.map { |pair| pair.join(" <-> ") }.join("; ")}" : nil,
             closed.any? ? "closed #{closed.map { |pair| pair.join(" <-> ") }.join("; ")}" : nil ].compact.join(", "))
  end

  def exit_cap
    over = story.locations.includes(:connected_locations).select { |room| room.exits.size > Location::ExitsSchema::MAX_EXITS }
    return nil if over.empty?

    broken("exit_cap",
           over.map { |room| "#{room.name} leads #{room.exits.size} ways out, and the cap is #{Location::ExitsSchema::MAX_EXITS}" }.join("; "))
  end

  # An item is reachable through the person holding it, the room it is lying in
  # or the playthrough whose copy it is, and through nothing else -- `Item` has
  # no story of its own. Which is what makes this check work in both directions
  # at once: a row holding both of its places is found and named by `astray`,
  # and a row that ended up holding none of them AND belonging to no game is
  # found by nobody, so it shows up as gone from the world in `missing`.
  def items_now
    Item.in_story(story).to_a
  end

  # THREE STATEMENTS, ONE PER LAYER AND ONE ABOUT THE FILE.
  #
  # `astray` is both layers: an item lying in a room and in a pair of hands
  # together is takeable and already taken, whoever it belongs to.
  #
  # `homeless` is the WORLD LAYER only, and it is where the layers part. One of
  # the world's own rows in neither place is a row no closed set can ever offer;
  # a playthrough's own copy in neither place is in the party's hands, which is
  # the most ordinary state there is. See `Item#in_exactly_one_place`.
  #
  # `missing` is by NAME, and every name in the file now exists at least twice
  # over since the captain's ruling of 2026-09-04 -- once as the world's own row
  # and once per game that has walked past it -- so a name found anywhere is
  # accounted for. It is what would catch a walk that DESTROYED one of the
  # world's things, which no typed line may do.
  def items_accounted
    items = items_now
    astray = items.select { |item| Item::PLACES.count { |place| item[place].present? } > 1 }
    homeless = items.select { |item| item.template? && Item::PLACES.none? { |place| item[place].present? } }
    missing = items_in_file - items.map(&:name)

    return nil if astray.empty? && homeless.empty? && missing.empty?

    broken("items_accounted",
           [ astray.any? ? "in more than one place at once: #{astray.map(&:name).join(", ")}" : nil,
             homeless.any? ? "one of the world's own rows in no place at all: #{homeless.map(&:name).join(", ")}" : nil,
             missing.any? ? "in no place at all: #{missing.join(", ")}" : nil ].compact.join(", "))
  end

  # WHAT THE WORLD STILL HAS, whoever has been playing it. Every one of the
  # world's own rows is where the file put it and nowhere else: a typed line may
  # move one game's COPY of the ward stamp anywhere it likes, and may not touch
  # the row the next game copies from. It is the item half of `cast_unmoved`,
  # and it is the invariant the captain's ruling of 2026-09-04 turned from a
  # wish into a statement -- before it, `take` moved the world's only row and
  # this could not have been written.
  def world_items_unmoved
    moved = story.locations.flat_map { |room| Item.lying_in(room).templates.to_a }.filter_map do |item|
      wanted = items_in_file_by_name[item.name]
      next if wanted.nil?

      room, seat = wanted
      next if room == item.location&.name && seat == item.position

      "#{item.name} is #{item.whereabouts}#{" #{item.position}" if item.position} and the file says " \
        "in #{room}#{" #{seat}" if seat}"
    end
    return nil if moved.empty?

    broken("world_items_unmoved", moved.join("; "))
  end

  # `{ name => [ the room the file puts it in, the corner of it or nil ] }`, for
  # the things the file lays in rooms. Something the file gives a CHARACTER is
  # not in here: a template held by somebody has no room to be checked against,
  # and therefore no plane to read a corner in either (`Location::Spot`).
  #
  # NIL FOR A THING THE FILE PLACES BUT DOES NOT SEAT, which is every item in
  # all three checked-in worlds, and it is a real expectation rather than an
  # absence: the invariant reads it both ways, so a template that gained a cell
  # during a walk fails as loudly as one that lost the cell it was written with.
  def items_in_file_by_name
    @items_in_file_by_name ||= Array(seed["locations"]).flat_map do |room|
      Array(room["items"]).map { |item| [ item["name"], [ room["name"], Location::Spot.of(item) ] ] }
    end.to_h
  end

  def items_in_file
    (Array(seed["locations"]) + Array(seed["characters"]))
      .flat_map { |owner| Array(owner["items"]) }
      .map { |item| item["name"] }
  end

  # WHERE THE FILE PUTS EACH OF THEM, by full name: the room, and the corner of
  # it the file stands them in. A character the file does not place is in here
  # as a pair of nils, so somebody who acquired a room -- or a cell -- during
  # the walk fails just as loudly as somebody who lost one.
  def cast_in_file
    Array(seed["characters"]).to_h { |row| [ row["fullname"], [ row["location"], Location::Spot.of(row) ] ] }
  end

  def cast_unmoved
    moved = story.characters.includes(:location).order(:id).filter_map do |character|
      room, seat = cast_in_file[character.fullname]
      next if character.location&.name == room && character.position == seat

      "#{character.fullname} is #{character.whereabouts}#{" #{character.position}" if character.position} and the " \
        "file says #{room ? "in #{room}#{" #{seat}" if seat}" : "nowhere"}"
    end
    return nil if moved.empty?

    broken("cast_unmoved", moved.join("; "))
  end

  # `{ fullname => { "level" => .., "hit_die" => .., "strength" => .., ... } }`
  # out of the file, with nil for somebody it gives no `stats` -- so a character
  # who ACQUIRED a body or an ability during the walk fails just as loudly as
  # one who lost it, which is the shape `#cast_in_file` uses for the same
  # reason.
  #
  # ALL FIVE COLUMNS, which is `WorldSeed::Loader::STAT_KEYS`: the abilities are
  # the world's on exactly the same terms as the hit die, so no typed line may
  # write one of them either. What a walk DOES write is `playthrough_vitals`, on
  # the other side of the layer split, so `harm 5` walks the whole engine
  # without this moving -- and `check strength` throws a die and writes nothing
  # at all.
  def stats_in_file
    Array(seed["characters"]).to_h do |row|
      stats = row["stats"]
      [ row["fullname"], stats.is_a?(Hash) ? stats.slice(*WorldSeed::Loader::STAT_KEYS) : nil ]
    end
  end

  def stat_blocks_unmoved
    changed = story.characters.order(:id).filter_map do |character|
      wanted = stats_in_file[character.fullname]
      now = stats_on_record(character)
      next if now == wanted

      "#{character.fullname} is #{describe_stats(now)} and the file says #{describe_stats(wanted)}"
    end
    return nil if changed.empty?

    broken("stat_blocks_unmoved", changed.join("; "))
  end

  # The five columns as the file would write them, or nil for a sheet that is
  # not whole -- which is what an unseeded body reads as, and the one thing the
  # file can say nothing about.
  def stats_on_record(character)
    return nil unless character.stat_block? && character.abilities?

    WorldSeed::Loader::STAT_KEYS.to_h { |key| [ key, character.public_send(key) ] }
  end

  def describe_stats(stats)
    return "without a whole sheet" if stats.nil?

    "level #{stats["level"]}, d#{stats["hit_die"]}, " \
      "#{Character::ABILITIES.map { |ability| "#{ability} #{stats[ability.to_s]}" }.join(" ")}"
  end

  # WHO THE FILE SAYS ATTACKS THE PARTY, WHICH RACES IT CALLS MONSTERS, AND HOW
  # DANGEROUS IT SAYS EACH ROOM IS -- all three read the file's key with the
  # column's own default for an absent one, so a row that ACQUIRED hostility
  # during a walk fails exactly as loudly as one that lost it. That is
  # `#cast_in_file`'s shape and it is here for its reason.
  #
  # Three statements in one check because they are one fact: a world can contain
  # an enemy, and no typed line may change what that enemy is.
  def hostility_unmoved
    moved = [ *hostility_of_the_cast, *monstrousness_of_the_races, *danger_of_the_rooms,
              *population_of_the_rooms ]
    return nil if moved.empty?

    broken("hostility_unmoved", moved.join("; "))
  end

  def hostility_of_the_cast
    wanted = Array(seed["characters"]).to_h { |row| [ row["fullname"], row["hostile"] == true ] }

    story.characters.order(:id).filter_map do |character|
      next if character.hostile? == wanted[character.fullname]

      "#{character.fullname} is #{character.hostile? ? "hostile" : "not hostile"} and the file says "         "#{wanted[character.fullname] ? "hostile" : "not hostile"}"
    end
  end

  def monstrousness_of_the_races
    wanted = Array(seed.dig("universe", "races")).to_h { |row| [ row["name"], row["monstrous"] == true ] }

    story.universe.races.order(:name).filter_map do |race|
      next if race.monstrous? == wanted[race.name]

      "the race #{race.name.inspect} is #{race.monstrous? ? "monstrous" : "a people"} and the file says "         "#{wanted[race.name] ? "monstrous" : "a people"}"
    end
  end

  def danger_of_the_rooms
    wanted = Array(seed["locations"]).to_h { |row| [ row["name"], row["danger"].presence || Location::SAFE ] }

    story.locations.order(:id).filter_map do |room|
      next if room.danger == wanted.fetch(room.name, Location::SAFE)

      "#{room.name} is #{room.danger} and the file says #{wanted.fetch(room.name, Location::SAFE)}"
    end
  end

  # AND HOW POPULATED THE FILE SAYS EACH ROOM IS. The captain's ruling of
  # 2026-09-07 -- the narrator picks a word from a closed list, the engine rolls
  # the count inside it (`Location::Population`) -- and the word is a fact about
  # the WORLD, on exactly the terms `danger` one method up is: a seed file may
  # write it, a model may answer it while naming the way there, and NO TYPED
  # LINE MAY MOVE IT.
  #
  # THIS IS THE HALF OF THAT CHANGE A WALK CAN SEE, and the other half it cannot
  # is worth stating rather than leaving as a gap: the count is rolled when a
  # room is REALIZED, realizing a room is two model calls, and `EngineSweep`
  # replaces `BaseAgent.new` with something that raises for the length of a run
  # (`a-monster-in-a-room.yml` says the same thing about `danger`). So no script
  # in this directory can watch the engine roll a cast; what every script can
  # assert, and now does, is that a hundred typed lines leave the word alone.
  #
  # NIL IS ASSERTED AS NIL, which is the one difference from `danger`: an absent
  # key there means the column's default and here it means *nobody picked a
  # word*, so `presence` is compared against `presence` and a row that ACQUIRED a
  # word during a walk fails as loudly as one that lost it. That is the shape
  # every check in this file has and it is here for its reason.
  def population_of_the_rooms
    wanted = Array(seed["locations"]).to_h { |row| [ row["name"], row["population"].presence ] }

    story.locations.order(:id).filter_map do |room|
      next if room.population.presence == wanted.fetch(room.name, nil)

      "#{room.name} is #{room.population.inspect} and the file says " \
        "#{wanted.fetch(room.name, nil).inspect}"
    end
  end

  # NO TYPED LINE MAY CHANGE WHAT A PLACE DOES TO YOU. `hostility_unmoved`'s
  # statement for the other two columns on the world's side of the split, and
  # its own check for that check's own reason: one of the two is not on a
  # `Location` at all, and an invariant reporting a moved DOORWAY under the
  # heading "hostility" would send a reader to the wrong table.
  #
  # What a walk DOES write is `playthrough_tolls` -- how much a hazard took off
  # one body in one game -- which is on the other side of the split entirely, so
  # walking through the water all afternoon leaves this untouched.
  #
  # Read against the file both ways, like `#danger_of_the_rooms`: a room or a
  # doorway that ACQUIRED a hazard during a walk fails exactly as loudly as one
  # that lost it.
  def hazards_unmoved
    moved = [ *hazards_of_the_rooms, *hazards_of_the_doorways ]
    return nil if moved.empty?

    broken("hazards_unmoved", moved.join("; "))
  end

  def hazards_of_the_rooms
    wanted = Array(seed["locations"]).to_h { |row| [ row["name"], row["hazard"].presence ] }

    story.locations.order(:id).filter_map do |room|
      next if room.hazard == wanted.fetch(room.name, nil)

      "#{room.name} has hazard #{room.hazard.inspect} and the file says #{wanted.fetch(room.name, nil).inspect}"
    end
  end

  # KEYED ON THE DIRECTED PAIR, because that is the whole content of an edge's
  # hazard: `hazard_from` names the room you are leaving, so the file's answer
  # is about ONE of the two rows and the other one's answer is nil.
  def hazards_of_the_doorways
    wanted = Hash.new(nil)
    Array(seed["connections"]).each do |row|
      from = row["hazard_from"]
      next if from.blank? || row["hazard"].blank?

      other = Array(row["between"]).find { |name| name != from }
      wanted[[ from, other ]] = row["hazard"]
    end

    LocationConnection.joins(:location).where(locations: { story_id: story.id })
                      .includes(:location, :connected_location).order(:id).filter_map do |edge|
      pair = [ edge.location.name, edge.connected_location.name ]
      next if edge.hazard == wanted[pair]

      "the way from #{pair.first} into #{pair.last} has hazard #{edge.hazard.inspect} and the file says " \
        "#{wanted[pair].inspect}"
    end
  end

  # NO TYPED LINE MAY MOVE A WALL. The standing constraint applied to geometry,
  # and the reason it can be stated as a flat comparison against the file is
  # that a box is the WORLD's on exactly the terms a hit die and a hazard
  # already are -- see the header.
  #
  # SIX FACTS PER ROOM, not five: the parent is the frame the other five are
  # read in, so a walk that left every number alone and re-parented the room
  # would have moved it and this would say so.
  #
  # Read against the file both ways, like `#danger_of_the_rooms`: a room that
  # ACQUIRED a box during a walk fails exactly as loudly as one that lost it,
  # which is what makes this hold on the three checked-in worlds -- they declare
  # no boxes at all, so every room is expected to have none.
  def geometry_unmoved
    moved = story.locations.includes(:parent_location).order(:id).filter_map do |room|
      wanted = geometry_in_file.fetch(room.name, no_geometry)
      now = geometry_on_record(room)
      next if comparable_geometry(now) == comparable_geometry(wanted)

      "#{room.name} is #{describe_geometry(now)} and the file says #{describe_geometry(wanted)}"
    end
    return nil if moved.empty?

    broken("geometry_unmoved", moved.join("; "))
  end

  # `{ name => { the five columns, plus the parent's name } }` out of the file,
  # with nil for every key it does not write -- which is all six for every room
  # in every checked-in world.
  def geometry_in_file
    @geometry_in_file ||= Array(seed["locations"]).to_h do |row|
      [ row["name"], no_geometry.merge(Location::Box::COLUMNS.to_h { |column| [ column, row[column] ] })
                                .merge("parent" => row["parent"]) ]
    end
  end

  def geometry_on_record(room)
    Location::Box::COLUMNS.to_h { |column| [ column, room[column] ] }
                          .merge("parent" => room.parent_location&.name)
  end

  def no_geometry
    (Location::Box::COLUMNS + [ "parent" ]).index_with(nil)
  end

  # THE PARENT IS COMPARED THE WAY THE LOADER RESOLVED IT, on
  # `WorldSeed.natural_key`: `WorldSeed::Loader#load_containment!` matches a
  # `parent` key that way on purpose, so "the Rusted Anchor" and "Rusted Anchor"
  # name one place -- and an invariant comparing the two strings would call a
  # spelling the format supports a wall that moved. The names themselves are
  # left alone, so the message still reads the way the file is written.
  def comparable_geometry(geometry)
    geometry.merge("parent" => geometry["parent"].presence&.then { |name| WorldSeed.natural_key(name) })
  end

  # The three whole shapes and the broken one, said in a phrase --
  # `Location::Box.shape`'s four answers, so a broken invariant reads the same
  # way a doctor finding does.
  def describe_geometry(geometry)
    inside = geometry["parent"] ? "inside #{geometry["parent"]}" : "inside nothing"

    case Location::Box.shape(geometry)
    when :box then "#{Location::Box.of(geometry)} #{inside}"
    when :footprint then "#{geometry["width"]}x#{geometry["depth"]} paces #{inside}"
    when :partial then "part of a box (#{Location::Box::COLUMNS.select { |column| geometry[column] }.join(", ")}) #{inside}"
    else "unlaid out, #{inside}"
    end
  end

  # EVERY POSITIONED ROW IS ON THE FLOOR OF THE ROOM IT IS IN. See the header for
  # why this one is not stated against the file.
  #
  # BOTH ITEM LAYERS AND THE CAST, through the one scope each table has
  # (`Item.positioned`, `Character.positioned`), which takes a row carrying
  # EITHER column -- so half a position is caught here rather than read as
  # unplaced. `Location::Box#contains?` is false for a nil spot, which is what
  # makes that one line cover it.
  def positions_in_bounds
    astray = positioned_rows.filter_map do |record, room, label|
      box = room&.box
      next if box&.contains?(record.position)

      "#{label} is #{record.position || "part-placed"} and #{describe_floor(room)}"
    end
    return nil if astray.empty?

    broken("positions_in_bounds", astray.join("; "))
  end

  # Every row in the story that says where in a room it is, as the record, its
  # room and a phrase naming it -- `Story::Doctor#positioned_rows`' counterpart,
  # and it names the layer for that method's reason.
  def positioned_rows
    Item.in_story(story).positioned.includes(:location).order(:id)
        .map { |item| [ item, item.location, "#{item.name} (#{item.whereabouts})" ] } +
      story.characters.positioned.includes(:location).order(:id)
           .map { |person| [ person, person.location, person.fullname ] }
  end

  def describe_floor(room)
    return "is in no room, which has no plane to read a position in" if room.nil?
    return "#{room.name} has no box, so there is no plane to read that in" if room.box.nil?

    "#{room.name} is #{room.box}"
  end

  # NO TWO ROOMS OF ONE PLACE ANSWER TO ONE NAME. Not stated against the file,
  # for `#positions_in_bounds`' reason: it is a claim about the RECORDS a walk
  # left behind, and a file that shipped two rooms of one name would be a file
  # this should fail on rather than agree with.
  #
  # WHY IT IS HERE AT ALL, given that a sweep has no model and nothing offline
  # writes a name: because the thing that writes one now is
  # `Location::RoomName`, at realization, and a name it accepted is the only
  # name in the app a MODEL chose for a row the engine then looks up by name
  # (`Story::Repair`, `Story::Doctor#duplicate_locations`, half of
  # `WorldSeed::Loader`). It costs one query and one grouping when it holds,
  # which is what it does today, and it fires the moment a walk starts renaming
  # rooms -- which is exactly the change that would need watching.
  # `doors_unchanged`'s argument, applied to names.
  #
  # ROOMS OF A PLACE AND NOT EVERY CHILD ROW, because that is the contract
  # `Location::RoomName` guards from the inside: a box read in a parent's own
  # plane. Plain containment -- a district a street sits in -- is ordinary
  # places, and their names are `Story::Doctor#duplicate_locations`' to judge
  # over the whole story.
  #
  # IDENTITY IS `WorldSeed.natural_key`'s, the same spelling the doctor reports
  # a duplicate on and the same one the engine refuses on.
  def room_names_unique
    clashing = story.locations.includes(:parent_location).select(&:placed?)
                    .group_by { |room| [ room.parent_location_id, WorldSeed.natural_key(room.name) ] }
                    .values.select(&:many?)
    return nil if clashing.empty?

    broken("room_names_unique",
           clashing.map { |group|
             "#{group.first.parent_location&.name} has #{group.size} rooms called " \
               "#{group.first.name.inspect} (#{group.map { |room| "##{room.id}" }.join(", ")})"
           }.join("; "))
  end

  def nothing_was_written
    written = Array(seed["locations"]).filter_map do |row|
      room = story.locations.to_a.detect { |candidate| candidate.name == row["name"] }
      next nil if room.nil? || room.detail_level == row["detail_level"]

      "#{room.name} was #{row["detail_level"]} in the file and is #{room.detail_level} now"
    end
    return nil if written.empty?

    broken("nothing_was_written", written.join("; "))
  end

  def broken(invariant, detail)
    EngineSweep::Result::Broken.new(script: nil, invariant: invariant, detail: detail)
  end
end
