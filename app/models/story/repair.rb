# Fixes what can be fixed about a story, and says plainly what cannot.
#
# THE WHOLE OF THIS CLASS IS ONE RULE: never invent data to make a validation
# pass. A generated world is expensive and it is the captain's; a repair that
# quietly wrote a plausible description or picked a plausible race would leave a
# story that passes every check and contradicts itself, which is worse than the
# broken one it replaced. So a repair only ever does one of two things:
#
#   SAFE      writes a value that is already on record somewhere else. The
#             reverse of a connection whose values are direction-neutral by
#             design; an opening arrival's timestamp, which IS the story's
#             start_time; a playthrough's location, which its own current scene
#             names. No model, no key, no judgement.
#
#             ONE REPAIR STRETCHES THAT SENTENCE AND IT IS STATED HERE RATHER
#             THAN DISCOVERED: `character_without_a_stat_block` rolls a hit die,
#             and nothing on record implies one. It is safe because the ENGINE
#             is that number's sole author by the captain's ruling of
#             2026-09-04 -- *"A model cannot set an NPC's numbers, the engine
#             rolls them"* -- so writing one is not inventing world data to make
#             a validation pass; it is the only thing that was ever going to
#             decide it, doing so. The roll is deterministic
#             (`Character::StatBlock`), so a rehearsal and the repair agree and
#             a re-run a year later re-derives the same body. See
#             `Story::Doctor#stat_blocks`. `character_without_abilities` and
#             `ability_out_of_range` are the same stretch one column-set over,
#             and `Story::Doctor#abilities` carries the same note.
#
#             A FOLD IS A SAFE REPAIR TOO, and it is the only kind that removes
#             a row. Re-seeding a played world used to leave two rows where the
#             file declares one thing -- two supply closets, two daybooks, a
#             lane opening twice onto the fixed city -- and the file is what
#             proves they are one. So the fold moves everything off the row a
#             re-seed created (what is lying in it, anybody standing in it, its
#             doorways) onto the row with the history and removes what is left.
#             NOTHING PLAY CREATED IS DESTROYED: `Story::Doctor` raises these
#             `safe` only where exactly one of the rows carries anybody's
#             history and nothing refers to the rest, and every handler
#             re-checks that before it touches a row. See
#             `#repair_duplicate_locations`.
#
#   GENERATE  asks a model to write something the world genuinely does not
#             contain yet -- a room, its exits, the opening arrival. That is a
#             legitimate repair and it is how the world was built in the first
#             place, but it costs a call and an API key, so it is opt-in and
#             the count of calls is stated before any of them is made.
#
# Everything else is reported by `Story::Doctor` with remedy `:manual` and left
# alone. `rake game:doctor` says which stories those are; the honest answer for
# most of them is `rake game:delete`.
class Story::Repair
  # One thing this did or refused to do. `status` is :repaired, :skipped or
  # :failed -- a repair that raises is caught and reported rather than taking
  # the rest of the run down with it, because the run is over several findings
  # and the ones after a failure are still worth attempting.
  Result = Data.define(:code, :status, :message) do
    def repaired? = status == :repaired
  end

  # Which findings this knows how to act on, and what each one costs in model
  # calls. A finding code that is not in here is reported and never touched --
  # adding a repair means adding an entry AND a handler, so the two cannot drift.
  HANDLERS = {
    missing_start_time: { calls: 0, handler: :repair_missing_start_time },
    opening_scene_without_timestamp: { calls: 0, handler: :repair_opening_scene_timestamp },
    one_way_connection: { calls: 0, handler: :repair_one_way_connection },
    connection_directions_disagree: { calls: 0, handler: :repair_disagreeing_connection },
    playthrough_without_location: { calls: 0, handler: :repair_playthrough_location },
    character_moved_from_the_seed: { calls: 0, handler: :repair_seeded_whereabouts },
    character_absent_in_the_seed: { calls: 0, handler: :repair_seeded_absence },
    character_absent_but_somewhere: { calls: 0, handler: :repair_deliberate_absence },
    protagonist_holds_a_taken_item: { calls: 0, handler: :repair_shared_inventory },
    playthrough_missing_a_copy: { calls: 0, handler: :repair_missing_copies },
    copy_lags_its_template: { calls: 0, handler: :repair_lagging_copies },
    character_without_a_stat_block: { calls: 0, handler: :repair_missing_stat_block },
    character_without_abilities: { calls: 0, handler: :repair_missing_abilities },
    ability_out_of_range: { calls: 0, handler: :repair_ability_out_of_range },
    hp_above_maximum: { calls: 0, handler: :repair_hp_above_maximum },
    vitals_for_an_unmet_character: { calls: 0, handler: :repair_unmet_vitals },
    protagonist_without_vitals: { calls: 0, handler: :repair_missing_vitals },
    duplicate_locations: { calls: 0, handler: :repair_duplicate_locations },
    duplicate_items: { calls: 0, handler: :repair_duplicate_items },
    mobile_doorway_re_asserted: { calls: 0, handler: :repair_re_asserted_doorway },
    no_realized_location: { calls: 2, handler: :repair_no_realized_location },
    opening_location_is_a_stub: { calls: 2, handler: :repair_opening_location_stub },
    opening_has_no_exits: { calls: 1, handler: :repair_missing_exits },
    location_has_no_exits: { calls: 1, handler: :repair_missing_exits },
    no_opening_scene: { calls: 1, handler: :repair_no_opening_scene }
  }.freeze

  attr_reader :story, :generate

  # `generate: false` is the default on purpose: the cheap half runs without a
  # key, and nothing spends the captain's tokens unless he asked for it.
  def initialize(story, generate: false)
    @story = story
    @generate = generate
  end

  def doctor
    @doctor ||= Story::Doctor.new(story)
  end

  # The findings this run would act on, in the order it would act on them.
  def plan
    doctor.findings.select { |finding| actionable?(finding) }
  end

  # Findings that carry a model-call repair this run is NOT going to make,
  # because `generate` is off. `rake game:repair` prints these as the offer.
  def deferred
    return [] if generate

    doctor.findings.select { |finding| finding.remedy == :generate && HANDLERS.key?(finding.code) }
  end

  # Findings nothing can honestly do anything about.
  def manual
    doctor.findings.reject { |finding| HANDLERS.key?(finding.code) && finding.repairable?(generate: true) }
  end

  # How many model calls `#apply!` will make. Printed before any of them is.
  def model_calls
    plan.sum { |finding| HANDLERS.fetch(finding.code).fetch(:calls) }
  end

  # Runs the plan and returns a Result per finding.
  #
  # Deliberately NOT one transaction. A generated repair is several model calls
  # and the world's own writers persist as they go -- `Location::Generator`
  # saves the description before it asks for the exits precisely so a failure
  # keeps the expensive half. Wrapping the run would throw that away on the last
  # failure, which is the opposite of what this is for.
  def apply!
    plan.map do |finding|
      begin
        message = send(HANDLERS.fetch(finding.code).fetch(:handler), finding)
        Result.new(code: finding.code, status: :repaired, message: message)
      rescue => e
        Result.new(code: finding.code, status: :failed, message: "#{e.class}: #{e.message}")
      end
    end
  ensure
    @doctor = nil
  end

  private

  def actionable?(finding)
    HANDLERS.key?(finding.code) && finding.repairable?(generate: generate)
  end

  # A story started no later than its earliest scene. Derived, not chosen.
  def repair_missing_start_time(_finding)
    at = story.scenes.minimum(:story_timestamp)
    story.update!(start_time: at)
    "set start_time to #{at.utc.iso8601}, the story's earliest scene"
  end

  # An opening arrival happens at the story's start_time by definition -- that
  # is why the seed format does not carry a timestamp for it at all.
  def repair_opening_scene_timestamp(finding)
    finding.subject.update!(story_timestamp: story.start_time)
    "stamped opening scene ##{finding.subject.id} with the story's start_time"
  end

  # Both rows of an edge carry the same values, which is only correct because
  # everything on them is direction-neutral. `time_to_travel` is derived by
  # LocationConnection rather than copied.
  def repair_one_way_connection(finding)
    row = finding.subject
    LocationConnection.create!(
      location: row.connected_location,
      connected_location: row.location,
      distance: row.distance,
      travel_method: row.travel_method
    )
    "wrote the way back from #{row.connected_location.name} to #{row.location.name}"
  end

  # The exporter resolves a disagreement the same way: keep the row on the
  # location nearer the opening, because that is the direction the world was
  # written outward from.
  def repair_disagreeing_connection(finding)
    row = finding.subject
    reverse = LocationConnection.find_by(location: row.connected_location, connected_location: row.location)
    reverse.update!(distance: row.distance, travel_method: row.travel_method)
    "made #{reverse.location.name} -> #{reverse.connected_location.name} agree with the way out (#{row.distance}, #{row.travel_method})"
  end

  # Where that player is standing is on record: it is where their last scene
  # happened.
  def repair_playthrough_location(finding)
    playthrough = finding.subject
    location = playthrough.current_scene.location
    playthrough.update!(current_location: location)
    "put playthrough ##{playthrough.id} back in #{location.name}, where its current scene happens"
  end

  # Where the world file says that person stands. On record and checked in --
  # `characters[].location` in `db/seeds/worlds/*.yml` -- so this is the same
  # kind of repair the connection reversal is: a value that already exists
  # somewhere else, written back. It is the same thing re-seeding does, minus
  # re-asserting the rest of the file over a world somebody has played.
  #
  # `Character#move_to!` and not the registry, because this IS the explicit
  # decision: the file says so.
  def repair_seeded_whereabouts(finding)
    character = finding.subject
    room = doctor.seeded_whereabouts[character.fullname]
    # THE SAME FINDING WITH THE OTHER ANSWER: a file that marks somebody
    # `absent: true` places them nowhere, and putting them back is
    # `Character#absent!` rather than a room. Both halves of
    # `character_moved_from_the_seed` are the file's own statement written back,
    # which is what makes either of them safe.
    return repair_seeded_absence(finding) if room.nil? && doctor.seeded_absences.include?(character.fullname)

    location = story.locations.find_by(name: room)
    raise ArgumentError, "the world file places #{character.fullname} in #{room.inspect}, which this story has no location called" if location.nil?

    character.move_to!(location)
    "put #{character.fullname} back in #{location.name}, where the world file places them"
  end

  # NOWHERE ON PURPOSE, WRITTEN ONTO A ROW THAT PREDATES THE MARKER. The same
  # kind of repair as the one above, from the same source: `characters[].absent`
  # in a checked-in `db/seeds/worlds/*.yml`. This is the one-time path for a
  # database seeded before `characters.deliberately_absent` existed -- the
  # captain's own, where Perrin Lasco is nowhere and correct and the doctor
  # reported him on every run.
  #
  # It also serves `character_absent_but_somewhere` for a seeded world, which
  # is the contradiction read from the file's side: the file says absent, so
  # absent is what gets written.
  def repair_seeded_absence(finding)
    character = finding.subject
    raise ArgumentError, "#{seed_file} does not mark #{character.fullname} `absent: true`" unless doctor.seeded_absences.include?(character.fullname)

    character.absent!
    "marked #{character.fullname} absent on purpose, as #{seed_file} says they are"
  end

  # The checked-in file for this story, named the way `Story::Doctor` names it
  # in its own messages -- `WorldSeed.checked_in_document` is what actually
  # reads it, and this is only how a repair says which file it read.
  def seed_file
    "db/seeds/worlds/#{WorldSeed.slug(story.title)}.yml"
  end

  # THE MARKER WINS. `deliberately_absent` with a whereabouts is a row saying
  # two things at once, and the marker is the half that is a statement about the
  # world rather than a position: it says nobody may be offered this person to
  # speak to. Safe because no value is invented -- the row already carries the
  # answer, and putting them back to nowhere is what `Character#absent!` is.
  #
  # `Character#move_to!` is what UNDOES this deliberately: it clears the marker
  # when it places somebody, so an engine mechanic that brings them back leaves
  # a row this never sees.
  def repair_deliberate_absence(finding)
    character = finding.subject
    room = character.location&.name

    character.absent!
    "took #{character.fullname} out of #{room.inspect} and back to nowhere, which the record says is deliberate"
  end

  # PUTS ONE ROW IN THE LAYER IT BELONGS IN, out of `Item::LayerBackfill` -- the
  # same reading the finding was raised from, run for real this time. The row
  # becomes the copy of the player whose chain took it, and one of the world's
  # own rows is put back in the room the take happened in, so the world is not a
  # thing poorer for somebody having picked it up.
  #
  # Safe because the answer is on record: `scenes.resolved_action`,
  # `scenes.acted_on` and `scenes.location_id` say which turn took this row and
  # where. The backfill is asked for THIS row's answer and nothing else is
  # written, so a run that repairs one finding does not quietly re-furnish a
  # story's rooms; and if the answer has stopped being attributable since the
  # doctor read it, this says so rather than guessing.
  def repair_shared_inventory(finding)
    item = finding.subject
    answer = Item::LayerBackfill.new(story).run(only: item.id).answers.first
    raise ArgumentError, "no turn records taking #{item.name.inspect} any more, so there is nobody to attribute it to" unless answer&.attributed?

    "gave #{item.name} to playthrough ##{answer.playthrough.id}, whose turn log records taking it" \
      "#{", and put the world's own row back in #{answer.location.name}" if answer.location}"
  end

  # TAKES THE SNAPSHOT A GAME WAS OWED, out of `Item::Snapshot` -- the same
  # class the live loop calls on arrival and at the top of every turn.
  #
  # Safe because every row it writes is a copy of a row that already exists:
  # this is the world it has already walked through, written down for that game.
  # Nothing is invented and nothing anybody is holding is touched.
  def repair_missing_copies(finding)
    playthrough = finding.subject
    result = Item::LayerBackfill.new(story).run
    made = result.snapshots.find { |snapshot| snapshot.playthrough.id == playthrough.id }&.copies || []

    "gave playthrough ##{playthrough.id} its own copy of #{made.size} thing(s) it had walked past"
  end

  # A COPY BROUGHT FORWARD TO WHAT THE WORLD NOW SAYS. `safe` because every
  # value it writes is already on the template, one row over in the same table,
  # and `Item::TemplateRefresh::TEXT` is the whole of what moves -- where the
  # thing is and whose hands it is in are the player's and are never touched.
  # Only copies NO turn has acted on; the rest are reported
  # (`touched_copy_lags_its_template`) and left alone.
  def repair_lagging_copies(finding)
    playthrough = finding.subject
    refreshed = Item::TemplateRefresh.new(story).refresh!(only: playthrough)

    "brought #{refreshed.size} of playthrough ##{playthrough.id}'s cop(ies) forward to what the world now " \
      "says: #{refreshed.map(&:to_s).join("; ")}"
  end

  # A BODY FOR SOMEBODY WHO HAD NONE, rolled rather than recovered -- the one
  # `safe` repair in this class that writes a number nothing else on record
  # implies. The header says why that is still safe; `Character::StatBackfill`
  # is the same act for a whole story at once, and `bin/update` runs it first.
  def repair_missing_stat_block(finding)
    character = finding.subject
    rolled = Character::StatBlock.for_existing(character)
    character.update!(**rolled)

    "rolled #{character.fullname} a body: level #{rolled[:level]}, d#{rolled[:hit_die]} (#{character.max_hp} hp)"
  end

  # THE THREE ABILITIES FOR SOMEBODY WHO HAD NONE, rolled rather than recovered
  # -- the mirror of `#repair_missing_stat_block` above and safe on exactly the
  # same argument, which the header states. It writes ONLY the ability columns:
  # a hand-authored hit die is a record and the records win over a derivation,
  # so re-deriving the whole sheet here would quietly rewrite one.
  # `Character::StatBackfill` is the same act for a whole story at once, and
  # `bin/update` runs it first.
  def repair_missing_abilities(finding)
    character = finding.subject
    rolled = roll_abilities!(character)

    "rolled #{character.fullname} three abilities: #{rolled.map { |ability, score| "#{ability} #{score}" }.join(", ")}"
  end

  # A NUMBER 3d6 COULD NEVER HAVE COME UP, replaced by three the engine did roll.
  # `Character` refuses one outside `Character::ABILITY_RANGE`, so the row
  # arrived through raw SQL -- and there is no record of what the intended
  # number was, which makes re-rolling the set the only honest answer and the
  # engine's own authorship the thing that makes it safe.
  def repair_ability_out_of_range(finding)
    character = finding.subject
    before = Character::ABILITIES.to_h { |ability| [ ability, character[ability] ] }
    rolled = roll_abilities!(character, all: true)

    "re-rolled #{character.fullname}'s abilities from #{before.values.join("/")} to #{rolled.values.join("/")}"
  end

  # THE ABILITY HALF OF THE SHEET AND NOTHING ELSE. `all: false` fills the empty
  # columns, which is what a missing set needs; `all: true` overwrites the three,
  # which is what a number the engine could not have rolled needs.
  def roll_abilities!(character, all: false)
    rolled = Character::StatBlock.for_existing(character).slice(*Character::ABILITIES)
    rolled = rolled.select { |ability, _| character[ability].nil? } unless all
    character.update!(**rolled)

    rolled
  end

  # A CONDITION CLAMPED BACK TO WHAT THE TEMPLATE ALLOWS. On record, on the
  # character: `Character#max_hp` is derived from the stat block, so this writes
  # a value the world already holds. It happens when a re-seed lowers a hit die
  # under a game in progress, which is a legitimate file edit.
  def repair_hp_above_maximum(finding)
    row = finding.subject
    was = row.hp_current
    row.update!(hp_current: row.character.max_hp)

    "brought #{row.character.fullname} in playthrough ##{row.playthrough_id} from #{was} down to " \
      "#{row.hp_current}, the most that body can hold"
  end

  # A CONDITION FOR SOMEBODY THAT GAME NEVER MET, removed. Safe because an
  # absent row MEANS unhurt (`Playthrough::Vitals`), which is exactly what an
  # unmet person is -- so deleting it loses no fact, and the row said something
  # about an encounter that never happened.
  def repair_unmet_vitals(finding)
    row = finding.subject
    who = row.character.fullname
    game = row.playthrough_id
    row.destroy!

    "dropped playthrough ##{game}'s condition for #{who}, who that game has never stood in a room with"
  end

  # THE PLAYER'S OWN CONDITION, WRITTEN FROM THE TEMPLATE. Derived and not
  # chosen: `Playthrough::Vitals.instantiate!` starts a body at
  # `Character#max_hp`, which is the same statement the snapshot makes when a
  # playthrough is created. `playthrough_missing_a_copy`'s argument, one table
  # over.
  def repair_missing_vitals(finding)
    playthrough = finding.subject
    row = Playthrough::Vitals.instantiate!(playthrough, playthrough.character)

    "gave playthrough ##{playthrough.id} a condition for #{playthrough.character.fullname}, " \
      "at the #{row.hp_current} their stat block starts them on"
  end

  # TWO ROWS THAT ARE ONE ROOM, FOLDED ONTO THE ONE WITH THE HISTORY -- and the
  # only repair in this class that removes a row, so the rule it is under is
  # worth stating twice: NOTHING PLAY CREATED IS DESTROYED. `Story::Doctor`
  # raises this `safe` only where a checked-in file declares one room under the
  # pair's natural key and only one of the rows has anybody's history in it, so
  # the row that goes is the one a re-seed created; and what is on it -- what is
  # lying in it, anybody standing in it, its doorways, any child location -- is
  # MOVED to the survivor first rather than dropped with it.
  #
  # Safe by the same argument the seeded whereabouts are: the answer is on
  # record in a checked-in file. The file says there is one such room, so the
  # two rows are one room, and the survivor takes the file's spelling -- which
  # is exactly what re-seeding does now that `WorldSeed::Loader` recognizes a
  # rename.
  def repair_duplicate_locations(finding)
    key = WorldSeed.natural_key(finding.subject.name)
    group = doctor.duplicate_location_rows(key)
    name = doctor.seeded_location_names[key]

    raise ArgumentError, "#{seed_file} declares no room matching #{finding.subject.name.inspect} any more" if name.blank?
    raise ArgumentError, "there is only one #{name.inspect} now, so there is nothing to fold" unless group.size > 1

    stood_in = group.select { |room| doctor.stood_in?(room) }
    raise ArgumentError, "somebody has stood in #{stood_in.size} of these rooms, and two histories cannot be folded into one" if stood_in.size > 1

    survivor = stood_in.first || group.min_by(&:id)
    ghosts = group - [ survivor ]
    moved = ghosts.sum { |ghost| fold_location_into(ghost, survivor) }
    survivor.update!(name: name)

    "folded #{ghosts.map { |ghost| "##{ghost.id} #{ghost.name.inspect}" }.join(", ")} into ##{survivor.id}, now " \
      "#{name.inspect} as #{seed_file} spells it (#{moved} row(s) moved over)"
  end

  # Everything hanging off the row that is going, then the row. `Location` has
  # `dependent: :destroy` on its items and scenes, which is why they are moved
  # rather than left to it: the caller has already refused a ghost with any
  # scene, and moving the items is the difference between folding two rooms and
  # losing what was in one of them.
  def fold_location_into(ghost, survivor)
    moved = Item.where(location: ghost).update_all(location_id: survivor.id)
    moved += Character.where(location: ghost).update_all(location_id: survivor.id)
    moved += Location.where(parent_location: ghost).update_all(parent_location_id: survivor.id)
    moved += fold_doorways(ghost, survivor)
    ghost.destroy!
    moved
  end

  # The ghost's doorways, re-pointed at the survivor. A row that would become a
  # loop (the two rooms lead to each other) or a doorway the survivor already
  # has is dropped instead: both rows describe the same edge, and
  # `location_connections` has a unique index on the pair.
  def fold_doorways(ghost, survivor)
    rows = LocationConnection.where(location: ghost).or(LocationConnection.where(connected_location: ghost)).to_a

    rows.count do |row|
      from = row.location_id == ghost.id ? survivor.id : row.location_id
      to = row.connected_location_id == ghost.id ? survivor.id : row.connected_location_id

      if from == to || LocationConnection.where(location_id: from, connected_location_id: to).where.not(id: row.id).exists?
        row.destroy!
        false
      else
        row.update!(location_id: from, connected_location_id: to)
        true
      end
    end
  end

  # THE LEFTOVER OF A RENAMED ITEM. `Story::Doctor` raises this `safe` only
  # where a checked-in file declares one item under the pair's natural key, the
  # row it names exists, and nothing refers to the others -- no party carrying
  # one, no turn log recording a take of one. The loader has already written
  # the file's description, place and inscription onto the row the file names,
  # so what is left is a row nothing in the world points at.
  def repair_duplicate_items(finding)
    survivor = finding.subject
    key = WorldSeed.natural_key(survivor.name)
    name = doctor.seeded_item_names[key]

    raise ArgumentError, "#{seed_file} declares no item matching #{survivor.name.inspect}" if name.blank?
    raise ArgumentError, "#{survivor.name.inspect} is not the name #{seed_file} gives it (#{name.inspect})" unless survivor.name == name

    leftovers = doctor.duplicate_item_rows(key) - [ survivor ]
    raise ArgumentError, "there is only one #{name.inspect} now, so there is nothing to fold" if leftovers.empty?

    handled = leftovers.reject { |item| doctor.untouched?(item) }
    raise ArgumentError, "#{handled.map(&:name).join(", ")} #{handled.one? ? "has" : "have"} been handled by a player, so #{handled.one? ? "it is" : "they are"} theirs" if handled.any?

    removed = leftovers.map { |item| "##{item.id} #{item.name.inspect} (#{item.whereabouts})" }
    leftovers.each(&:destroy!)

    "removed #{removed.join(", ")}, which #{seed_file} calls #{name.inspect} and ##{survivor.id} already is"
  end

  # THE DOORWAY A RE-SEED WROTE BACK OVER THE ARRANGEMENT THE WORLD HAD MOVED
  # TO. Closed both ways, because a connection is two rows and one of them
  # alone is `one_way_connection`.
  #
  # Safe because the file says which doorway it declares and
  # `WorldMechanic::ShuffleConnections` says it moves the far end of exactly
  # that kind of edge -- so the pair being on record after a night has run is a
  # re-seed's doing. IT REFUSES TO STRAND ANYTHING: the world has to still be
  # whole afterwards, checked the same way the mechanic checks its own
  # arrangements, because a repair that split a world in two would be worse
  # than the extra doorway.
  def repair_re_asserted_doorway(finding)
    row = finding.subject
    from = row.location
    to = row.connected_location
    raise ArgumentError, "the world would fall into two halves without #{from.name} <-> #{to.name}" unless doctor.whole_without?(row)

    LocationConnection.where(location: from, connected_location: to)
                      .or(LocationConnection.where(location: to, connected_location: from))
                      .destroy_all

    "closed #{from.name} <-> #{to.name}, the doorway #{seed_file} declares and a re-seed wrote back over the " \
      "arrangement #{from.name} had moved to"
  end

  # Two model calls: the room's description and lore, then its exits.
  def repair_no_realized_location(_finding)
    location = Location::Generator.opening(story)
    "realized #{location.name.inspect} as the opening location"
  end
  alias_method :repair_opening_location_stub, :repair_no_realized_location

  # One model call. `write_exits!` is public for exactly this recovery: a room
  # realized when the exits call failed is realized forever, and `realize!`
  # returns it untouched.
  def repair_missing_exits(finding)
    location = finding.subject
    Location::Generator.new(location).write_exits!
    "wrote #{location.exits.reload.count} way(s) out of #{location.name}"
  end

  # One model call, and the same one `rake game:new` makes.
  def repair_no_opening_scene(_finding)
    scene = Scene::Generator.opening(story)
    "narrated the opening arrival in #{scene.location.name} (scene ##{scene.id})"
  end
end
