# WHICH LAYER EVERY EXISTING ROW BELONGS IN, RECOVERED FROM THE TURNS THAT
# MOVED IT -- the one-time split of a database written before the world was the
# template and the playthrough owned the instances.
#
# `rake game:backfill_items` runs this. Offline, deterministic, free: no model
# call, no network. Idempotent -- a second run reports nothing to do -- so it is
# safe as one of `rake game:update`'s post-migration steps.
#
# WHAT IT IS SPLITTING. Before the captain's ruling of 2026-09-04 there was one
# layer and every game shared it. A thing lying in a room was lying there for
# everybody, so a party that picked the ward stamp up took it out of the room
# for every other play of that world: `Playthrough::Turn#carry!` moved THE row
# from `items.location_id` to `items.playthrough_id`, and the world was one row
# poorer. `rake game:doctor` could not tell such a row from the story's starting
# inventory, and neither could the exporter.
#
# THE ANSWER IS STILL ON RECORD, in the columns `Scene` has been writing since
# PR 105: `resolved_action` and `acted_on` say what each turn DID and to which
# row, `scenes.location_id` says where it did it, and a playthrough's turns are
# its `previous_scene` chain (`Playthrough#scene_chain`). So a row some chain
# records TAKING is that player's copy, and the room the earliest take happened
# in is where the world's own row belongs.
#
# FOUR OUTCOMES, TOLD APART, and the last two are the reason this is careful:
#
#   template      no chain records taking this row, so nobody ever moved it and
#                 it is where the file or `Item::Registry` put it. It stays
#                 exactly as it stands and becomes the world's own row. This is
#                 most of a database and it is reported so the figures add up.
#                 The story's own STARTING KIT is answered this way whatever the
#                 turn log says -- see `#the_story_s_own_kit?`, which is the one
#                 place the checked-in file is authority rather than
#                 corroboration, and the reason is that the log cannot answer.
#   attributed    one playthrough's chain records taking it. THE ROW BECOMES
#                 THAT PLAYTHROUGH'S OWN COPY, keeping the place it is in now --
#                 carried, or lying wherever that party put it down -- and a
#                 TEMPLATE IS PUT BACK where the earliest take on record
#                 happened, so the room is furnished again for everybody else.
#                 When two chains both took it the LATEST take wins: an item was
#                 in one place, so the last player to pick it up is the one who
#                 had it, which is the reading the engine itself had when it
#                 overwrote the column.
#   ambiguous     two chains record a take at the same story moment, or the
#                 turns that took it carry no story time at all so there is no
#                 order to choose from. NOTHING IS WRITTEN and it is reported by
#                 name: choosing would be inventing which player had it.
#   unrecoverable a row that is already one playthrough's own and nothing says
#                 what it is a copy OF -- no take on record and no template of
#                 that name in the world. It is LEFT WHERE IT IS, in that
#                 player's hands, and named: `rake game:doctor` goes on
#                 reporting it as `instance_without_a_template`, which is a
#                 report and not a defect. Taking it off somebody to tidy the
#                 records would be the only destructive thing this could do.
#
# AND THEN EVERY PLAYTHROUGH TAKES THE SNAPSHOT IT IS OWED, which is the other
# half and the one that actually restores the rooms. A game that has walked
# through four rooms gets its own copy of what is lying in each of them -- out
# of `Item::Snapshot`, the same class the live loop uses, so a backfilled game
# and a fresh one are in the same state. WHERE IT HAS BEEN is its scene chain's
# locations plus where it is standing now.
#
# WHAT THAT CHANGES FOR A DATABASE SOMEBODY IS MID-GAME IN, stated plainly: a
# room another player emptied is furnished again. Playthrough 8 walked through
# an office that playthrough 16 had already taken the stamp out of, and after
# this it has its own stamp on that floor. That is the ruling, applied
# backwards, and it is the one place this run adds something a player did not
# have before.
#
# THE WORLD FILE IS CORROBORATION, NOT AUTHORITY. It is read only to place a
# template whose take turn has no room on it, and only for the three checked-in
# worlds; a generated story has no file, and for one of those the take turn's
# own room is the whole of the evidence.
#
# IT SUPERSEDES `Item::InventoryBackfill`, which answered the narrower question
# -- whose hands is this in -- for the shared inventory PR 111 closed. That is
# one case of this one: a row held by the protagonist that a chain records
# taking is a row that chain took out of a room, so the template goes back to
# the room and the player keeps their copy. Two backfills that both decide whose
# hands a thing is in are two answers waiting to disagree.
class Item::LayerBackfill
  # ONE ROW'S ANSWER, and why it is that.
  #
  # `playthroughs` carries the parties an outcome is about, which on `ambiguous`
  # is the ones whose takes tie -- so the report can print the disagreement
  # rather than just naming it. `template` and `location` are what an
  # `attributed` row gained: the world's row that was put back, and the room it
  # was put back in.
  # `writes` IS TAKEN BEFORE ANYTHING IS APPLIED, and it has to be: `#apply!`
  # updates the row in place, so asking the row afterwards whether it needed
  # updating always answers no. It is the one question both a dry run and
  # `Update::Steps::BackfillItems` ask -- did this answer put anything in the
  # database -- so a second run over a split database reports nothing to do
  # even though every row still answers with the outcome it answered with the
  # first time.
  Answer = Data.define(:item, :outcome, :playthrough, :playthroughs, :template, :location, :writes) do
    def initialize(playthrough: nil, playthroughs: [], template: nil, location: nil, writes: false, **rest) = super

    def writes? = writes
    def template? = outcome == :template
    def attributed? = outcome == :attributed
    def ambiguous? = outcome == :ambiguous
    def unrecoverable? = outcome == :unrecoverable
  end

  # WHAT ONE PLAYTHROUGH WAS OWED: the rooms it has been in, and how many copies
  # it did not have. `copies` empty is the ordinary answer on a second run.
  Snapshot = Data.define(:playthrough, :rooms, :copies)

  Result = Data.define(:answers, :snapshots) do
    def nothing_to_do? = answers.none?(&:writes?) && snapshots.all? { |row| row.copies.empty? }
  end

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # Returns a `Result`: one `Answer` per row in item order, and one `Snapshot`
  # per playthrough in id order.
  #
  # `only:` narrows the row phase to one item and SKIPS the snapshot phase
  # entirely, which is what `Story::Repair` asks for: a run repairing one
  # finding must not quietly re-furnish a whole story's rooms, and one row's
  # answer does not depend on the others'.
  def run(dry_run: false, only: nil)
    answers = candidates(only: only).map do |item|
      answer = answer_for(item)
      apply!(answer) unless dry_run
      answer
    end

    Result.new(answers: answers, snapshots: only ? [] : snapshots(dry_run: dry_run, answers: answers))
  end

  # Every row in this world, both layers, in id order. `Item.in_story` is the
  # one place that query lives.
  def candidates(only: nil)
    scope = Item.in_story(story).order(:id)
    scope = scope.where(id: only) if only
    scope.to_a
  end

  private

  def apply!(answer)
    return unless answer.attributed?

    Item.transaction do
      template = answer.template || put_the_world_s_row_back(answer)
      # The row keeps the place it is in -- carried, or lying where that party
      # left it -- and gains the layer. `character_id` is cleared only when the
      # protagonist was holding it, because for an instance the protagonist's
      # hands ARE the party's hands and the party is a place with no holder.
      answer.item.update!(playthrough: answer.playthrough, template: template,
                          character: protagonist?(answer.item) ? nil : answer.item.character)
    end
  end

  # THE WORLD'S OWN ROW, PUT BACK. Every column but where it is and whose it is
  # (`Item::NOT_COPIED`), lying in the room the earliest take on record happened
  # in -- so what the room was furnished with is what it is furnished with
  # again. A world row of that name already lying there is used rather than
  # duplicated, which is what makes a second run write nothing.
  def put_the_world_s_row_back(answer)
    existing = Item.lying_in(answer.location).templates.by_name(answer.item.name).first
    return existing if existing

    Item.create!(answer.item.attributes.except(*Item::NOT_COPIED).merge(location: answer.location))
  end

  def protagonist?(item) = story.protagonist.present? && item.character_id == story.protagonist.id

  def answer_for(item)
    return Answer.new(item: item, outcome: :template) if the_story_s_own_kit?(item)

    takers = last_take_per_playthrough(item)

    return no_take_answer(item) if takers.empty?
    return attributed(item, takers.keys.sole) if takers.one?

    winners = takers_at_the_last_moment(takers)
    return Answer.new(item: item, outcome: :ambiguous, playthroughs: takers.keys) if winners.nil?
    return Answer.new(item: item, outcome: :ambiguous, playthroughs: winners) unless winners.one?

    attributed(item, winners.sole)
  end

  # WHAT THE FILE SAYS THE PLAYER STARTS OUT HOLDING, and for this one question
  # THE FILE IS AUTHORITY rather than corroboration -- the only place in this
  # class where it is.
  #
  # The reason is that the turn log cannot answer it. Before PR 111 the party's
  # inventory WAS `items.character_id` pointing at the protagonist, so every
  # take in a pre-PR-111 database wrote that one row: a turn recorded as taking
  # the Ward Office 12 daybook is indistinguishable from the daybook simply
  # being what the player started with, because both end with the daybook on the
  # protagonist. Reading the take as evidence takes the story's starting
  # inventory out of the world, invents a daybook lying on an office floor that
  # never had one, and leaves every future playthrough opening empty-handed.
  #
  # So a row the checked-in file names under the protagonist stays exactly where
  # it is, and the player whose log records taking it gets a copy of it through
  # the ordinary snapshot, which is what they should have had all along. A
  # generated world has no file and its protagonist is given nothing by anything
  # in the app (`rake game:new` writes no items, `Item::Registry` furnishes rooms
  # and never people), so for one of those a protagonist-held row can only have
  # got there through a take -- and there this rule correctly says nothing.
  def the_story_s_own_kit?(item)
    return false unless item.template? && protagonist?(item)

    seeded_kit.include?(item.name.to_s.downcase.strip)
  end

  def seeded_kit
    @seeded_kit ||= Array(seed_document&.dig("characters"))
                    .select { |row| row["is_protagonist"] }
                    .flat_map { |row| Array(row["items"]) }
                    .filter_map { |row| row["name"].to_s.downcase.strip.presence }
                    .to_set
  end

  # NOBODY'S CHAIN RECORDS TAKING IT. A row still in the world layer is where it
  # was put and stays there. A row already in a playthrough's layer needs a
  # template, and the only honest place to look for one is a world row of the
  # same name -- which is exactly what a copy of the story's starting inventory
  # has, and what a row nothing accounts for does not.
  def no_take_answer(item)
    return Answer.new(item: item, outcome: :template) if item.template?
    return Answer.new(item: item, outcome: :template) if item.template_id.present?

    world_row = world_row_named(item.name)
    return Answer.new(item: item, outcome: :unrecoverable) if world_row.nil?

    attributed(item, item.playthrough, template: world_row)
  end

  def attributed(item, playthrough, template: nil)
    template ||= item.template
    return Answer.new(item: item, outcome: :attributed, playthrough: playthrough, template: template,
                      writes: writes?(item, playthrough)) if template

    room = origin_room(item)
    return Answer.new(item: item, outcome: :unrecoverable) if room.nil?

    Answer.new(item: item, outcome: :attributed, playthrough: playthrough, location: room,
               writes: writes?(item, playthrough))
  end

  # WHETHER APPLYING THIS ANSWER CHANGES A ROW. A row already in the layer it
  # belongs in, already linked to what it is a copy of, is one this run would
  # write the same values back over -- which is a write nobody should be told
  # about, and the whole of what makes a second run quiet.
  def writes?(item, playthrough)
    item.playthrough_id != playthrough&.id || item.template_id.nil?
  end

  # A WORLD ROW OF THIS NAME, anywhere in the story. Names are unique in the
  # world layer -- `Item::Registry` refuses a name anything in the story already
  # has, and `WorldSeed::Loader` refuses a file with two of one name -- so this
  # is one row or none.
  def world_row_named(name)
    Item.in_story(story).templates.where("LOWER(name) = ?", name.to_s.downcase).order(:id).first
  end

  # WHERE THE WORLD'S OWN ROW BELONGS: the room the EARLIEST take of this row
  # happened in, across every chain. If two players carried it around, the first
  # one took it off the floor it had been lying on since the world was written.
  #
  # The checked-in file is the fallback and only the fallback, for a take turn
  # with no room recorded on it. Nil for a generated world whose take turn has
  # none either, and that is `unrecoverable`.
  def origin_room(item)
    takes = transitions.values.flatten.select { |scene| scene.took? && acted_on?(scene, item) }
    earliest = takes.select(&:location).min_by { |scene| [ scene.story_timestamp || Time.at(0), scene.id ] }
    return earliest.location if earliest

    seeded_room(item.name)
  end

  def seeded_room(name)
    return nil if seed_document.nil?

    row = Array(seed_document["locations"]).find do |location|
      Array(location["items"]).any? { |item| item["name"].to_s.casecmp?(name.to_s) }
    end
    return nil if row.nil?

    story.locations.find_by(name: row["name"])
  end

  # THE TURN EACH PLAYTHROUGH LAST PICKED THIS UP ON, for every chain that ever
  # did -- including the ones that went on to put it down again, which is the
  # difference from the inventory backfill this replaces. A drop is not a
  # disclaimer: the row is still the copy that player carried out of the room,
  # and it lies where they left it.
  def last_take_per_playthrough(item)
    transitions.each_with_object({}) do |(playthrough, scenes), takers|
      last = scenes.select { |scene| scene.took? && acted_on?(scene, item) }.last
      takers[playthrough] = last if last
    end
  end

  # EVERY TAKE AND DROP EACH PLAYTHROUGH MADE, in chain order, worked out ONCE
  # for the story rather than once per row.
  #
  # `Playthrough#scene_chain` walks `previous_scene` a query at a time, which is
  # the only way to read one playthrough's turns -- every playthrough of a story
  # starts on the same opening arrival, so the forward direction is not
  # single-valued. Doing that walk inside the per-item loop made a story's whole
  # turn log a query per item, and `Story::Doctor` reads this on every run.
  def transitions
    @transitions ||= story.playthroughs.order(:id).to_h do |playthrough|
      [ playthrough, playthrough.scene_chain.select { |scene| scene.took? || scene.dropped? } ]
    end
  end

  def acted_on?(scene, item) = scene.acted_on_record&.id == item.id

  # THE LATEST MOMENT ANY CHAIN PICKED IT UP, and everybody whose take is at it.
  # Nil when there is no order to choose from at all, which is a scene with no
  # `story_timestamp`: such a turn is invisible to the story's own clock
  # (`Story#clock`) and cannot be ranked against one that has it.
  #
  # STORY TIME IS THE ONLY ORDER BETWEEN TWO PLAYTHROUGHS, and it is deliberately
  # not broken by `scenes.id`. Within one chain the order is the chain, which is
  # what `last_take_per_playthrough` reads. Between two separate games the row id
  # says which player sat down at the keyboard second, which is a fact about the
  # database rather than about either fiction -- so a genuine tie is refused,
  # exactly as `Character::WhereaboutsBackfill` refuses two rooms claiming
  # somebody at one moment.
  def takers_at_the_last_moment(takers)
    return nil if takers.values.any? { |scene| scene.story_timestamp.nil? }

    latest = takers.values.map(&:story_timestamp).max

    takers.select { |_playthrough, scene| scene.story_timestamp == latest }.keys
  end

  # WHAT EVERY EXISTING PLAYTHROUGH IS OWED: its own copy of the story's kit,
  # and of what is lying in every room it has been in. `Item::Snapshot` is the
  # same class the live loop calls, so a backfilled game and one played from
  # scratch end up in the same state rather than in two states that agree today.
  def snapshots(dry_run:, answers:)
    story.playthroughs.order(:id).map do |playthrough|
      rooms = rooms_visited(playthrough)
      Snapshot.new(playthrough: playthrough, rooms: rooms,
                   copies: copies_for(playthrough, rooms, dry_run, answers))
    end
  end

  # EVERY ROOM THIS GAME HAS BEEN IN: the locations of its own turns, plus where
  # it is standing now. `Playthrough#scene_chain` is the one reader of whose
  # turns are whose; `current_location` is in the list because a game whose
  # arrival failed mid-turn is standing somewhere its chain does not name.
  def rooms_visited(playthrough)
    ([ playthrough.current_location ] + playthrough.scene_chain.map(&:location)).compact.uniq
  end

  # A DRY RUN COUNTS WITHOUT WRITING, and it has to count what the REAL run
  # would copy rather than what today's rows say. Those are two different
  # answers, because the row phase runs FIRST and changes the world the snapshot
  # phase reads, in both directions:
  #
  #   it links what it can account for   a playthrough already carrying an
  #                                      unlinked copy of the daybook is owed
  #                                      nothing. Read off today's rows it looks
  #                                      owed one, and the dry run promises a
  #                                      second daybook the real run never makes.
  #   it puts world rows back            a room that gets its ward stamp back
  #                                      owes a copy of it to every OTHER game
  #                                      that has been in that room. Read off
  #                                      today's rows there is no such template
  #                                      to owe, and the dry run misses them.
  #
  # So both corrections are made here, out of the answers the row phase produced
  # -- which the real run does not need, because by then they are rows.
  def copies_for(playthrough, rooms, dry_run, answers)
    return rooms.flat_map { |room| Item::Snapshot.new(playthrough).of_the_room!(room) } + Item::Snapshot.new(playthrough).of_the_party! unless dry_run

    held = playthrough.items.where.not(template_id: nil).pluck(:template_id).to_set
    answers.each do |answer|
      held << answer.template.id if answer.attributed? && answer.playthrough&.id == playthrough.id && answer.template
    end

    owed = rooms.flat_map { |room| Item.lying_in(room).templates.to_a } +
           (story.protagonist ? Item.for_character(story.protagonist).templates.to_a : [])

    owed.uniq.reject { |template| held.include?(template.id) } + restored_for(playthrough, rooms, answers)
  end

  # THE WORLD ROWS THE ROW PHASE IS ABOUT TO PUT BACK, for the games that will
  # be owed a copy of them. The row itself is the copy belonging to the player
  # whose take moved it, so that player is skipped; everybody else who has been
  # in that room gets one. They are reported as the row that is going back --
  # a report reads its name and nothing else, and the template it stands for
  # does not exist yet.
  def restored_for(playthrough, rooms, answers)
    answers.select { |answer| answer.attributed? && answer.location }
           .uniq { |answer| [ answer.item.name.to_s.downcase, answer.location.id ] }
           .select { |answer| rooms.include?(answer.location) && answer.playthrough&.id != playthrough.id }
           .map(&:item)
  end

  def seed_document
    return @seed_document if defined?(@seed_document)

    @seed_document = WorldSeed.checked_in_document(story.title)
  end
end
