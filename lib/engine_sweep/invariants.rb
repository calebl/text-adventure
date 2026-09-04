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
#   items_accounted      every item is in exactly one place -- held by somebody
#                        or lying somewhere, never both and never neither -- and
#                        the world still has the same items it started with.
#                        `take` and `drop` move a row, and a row that moved to
#                        nowhere is how an item disappears from a game. "The
#                        same items" is exact rather than a floor because
#                        `Item::Registry` writes only at realization, which this
#                        mode cannot reach: a walk that gained an item would
#                        mean something else had started making them.
#   cast_unmoved         every character is standing exactly where the world
#                        file put them, and anybody the file left nowhere is
#                        still nowhere. `characters.location_id` is the closed
#                        set `talk` resolves against, and NOTHING in a walk may
#                        write it: the seed file, `Character::Registry` (at
#                        realization, which this mode cannot reach) and an
#                        explicit `Character#move_to!` are the only writers, so
#                        a walk that moved somebody means a typed line has
#                        started moving people. It is stated as "unmoved"
#                        rather than as "nobody is nowhere" because nowhere is
#                        a legitimate state that two of the three checked-in
#                        worlds are in: the protagonist and any companion carry
#                        no whereabouts at all (the party is wherever the
#                        PLAYTHROUGH is), and `The Unrecorded Hour` leaves
#                        Perrin Lasco nowhere on purpose. Comparing against the
#                        file catches everything "nobody is nowhere" would --
#                        somebody who LOST their room during the walk fails it
#                        -- and does not fail on a world that means it.
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
    [ doors_unchanged, exit_cap, items_accounted, cast_unmoved, nothing_was_written ].flatten.compact
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

  # An item is reachable through the person holding it or the room it is lying
  # in, and through nothing else -- `Item` has no story of its own. Which is
  # what makes this check work in both directions at once: an item holding both
  # owners is found twice and named by `astray`, and an item that ended up
  # holding NEITHER is found by nobody and shows up as gone from the world.
  def items_now
    Item.where(character_id: story.characters.select(:id))
        .or(Item.where(location_id: story.locations.select(:id)))
        .to_a
  end

  def items_accounted
    items = items_now
    astray = items.reject { |item| item.character_id.present? ^ item.location_id.present? }
    missing = items_in_file - items.map(&:name)

    return nil if astray.empty? && missing.empty?

    broken("items_accounted",
           [ astray.any? ? "in two places at once: #{astray.map(&:name).join(", ")}" : nil,
             missing.any? ? "in no place at all: #{missing.join(", ")}" : nil ].compact.join(", "))
  end

  def items_in_file
    (Array(seed["locations"]) + Array(seed["characters"]))
      .flat_map { |owner| Array(owner["items"]) }
      .map { |item| item["name"] }
  end

  # WHERE THE FILE PUTS EACH OF THEM, by full name. A character the file does
  # not place is in here as nil, so somebody who acquired a room during the
  # walk fails just as loudly as somebody who lost one.
  def cast_in_file
    Array(seed["characters"]).to_h { |row| [ row["fullname"], row["location"] ] }
  end

  def cast_unmoved
    moved = story.characters.includes(:location).order(:id).filter_map do |character|
      wanted = cast_in_file[character.fullname]
      next if character.location&.name == wanted

      "#{character.fullname} is #{character.whereabouts} and the file says " \
        "#{wanted ? "in #{wanted}" : "nowhere"}"
    end
    return nil if moved.empty?

    broken("cast_unmoved", moved.join("; "))
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
