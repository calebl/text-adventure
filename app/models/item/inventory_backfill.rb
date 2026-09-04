# WHOSE HANDS A THING IS IN, RECOVERED FROM THE TURN THAT PICKED IT UP.
#
# `items.playthrough_id` is written from now on -- by
# `Playthrough::Turn#carry!`, and by `Playthrough#take_up_the_starting_inventory`
# when a game begins. Every database older than the column has the party's
# inventory on `items.character_id`, pointing at `story.protagonist`: one
# `Character` row per story, so one inventory shared by every play of a world.
# The captain's playthrough 17 opened holding what 16 had picked up.
#
# The answer is still on record, in the columns `Scene` has been writing since
# PR 105: `resolved_action` and `acted_on` say what each turn DID and to which
# row, and a playthrough's turns are its `previous_scene` chain
# (`Playthrough#scene_chain`). So a take is attributable to the player who made
# it. `rake game:backfill_inventory` runs this.
#
# FOUR OUTCOMES, TOLD APART, and the last two are the reason this is careful:
#
#   attributed    one playthrough's chain records a `take` of this exact row
#                 and no later `drop` of it. The row moves into that party's
#                 hands. When two chains both do, the LATEST take wins -- an
#                 item is in one place, so the last player to pick it up is the
#                 one holding it, which is the same reading the engine itself
#                 had when it overwrote `character_id`.
#   starting      no chain records a take of it at all, so nobody ever picked it
#                 up and the seed file put it there. It STAYS held by the
#                 protagonist, as the story's starting inventory, and every
#                 existing playthrough is given its own copy -- because before
#                 the column every playthrough was reading this very row, and a
#                 backfill that left them empty-handed would take the daybook
#                 out of a game in progress.
#   ambiguous     two chains record a take at the same story moment, or the
#                 turns that took it carry no story time at all so there is no
#                 order to choose from. NOTHING IS WRITTEN and it is reported by
#                 name: an item is in one place, so choosing would be inventing
#                 which player has it.
#   unrecoverable no take is on record AND the story's checked-in world file
#                 does not name it under the protagonist -- so it is not the
#                 starting inventory and the turn that took it was never
#                 labelled (`rake game:backfill_transitions` refuses to guess
#                 those). It is PUT DOWN in the room the most recent playthrough
#                 that could have held it is standing in, on
#                 `Playthrough::Turn#drop_item`'s own rule: a player who walks
#                 away leaves it where they left it. Stated in the output, every
#                 time, because it is the one outcome that moves a thing to a
#                 place no record named.
#
# THE WORLD FILE IS CORROBORATION, NOT AUTHORITY. It is read only to tell
# `starting` from `unrecoverable`, and only for the three checked-in worlds; a
# generated story has no file, and a generated protagonist is given no items by
# anything in the app (`rake game:new` writes none and `Item::Registry`
# furnishes rooms, never people), so for one of those "no take on record" is
# already the whole of the evidence.
#
# NPCs AND COMPANIONS ARE LEFT ALONE. `Item.for_character` was never the party's
# inventory for anybody but the protagonist -- nothing has ever read a
# companion's items as the player's -- so the world's own people keep their
# possessions on `items.character_id`, which is where they belong.
#
# Offline, deterministic, free: no model call, no network.
class Item::InventoryBackfill
  # ONE ITEM'S ANSWER, and why it is that.
  #
  # `playthroughs` carries the parties an outcome is about, which is a different
  # set for each: on `ambiguous` it is the ones whose takes tie, so the report
  # can print the disagreement rather than just naming it, and on `starting` it
  # is the ones owed a copy of the story's kit.
  Answer = Data.define(:item, :outcome, :playthrough, :playthroughs, :location) do
    def initialize(playthrough: nil, playthroughs: [], location: nil, **rest) = super

    def attributed? = outcome == :attributed
    def starting? = outcome == :starting
    def ambiguous? = outcome == :ambiguous
    def unrecoverable? = outcome == :unrecoverable
  end

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # Returns the `Answer`s, in item order, for everything the protagonist was
  # holding when it started. An item already on a playthrough is not touched at
  # all: this is a backfill, not a re-derivation, and the records win over the
  # history everywhere else in this app.
  # `only:` narrows it to one item, which is what `Story::Repair` asks for: a
  # run repairing one finding must not quietly reshuffle a story's whole
  # inventory, and one item's answer does not depend on the others'.
  def run(dry_run: false, only: nil)
    candidates(only: only).map do |item|
      answer = answer_for(item)
      apply!(answer) unless dry_run
      answer
    end
  end

  # Everything this could speak for: held by the protagonist, which is the one
  # pair of hands the old shared inventory ever wrote.
  def candidates(only: nil)
    return [] if story.protagonist.nil?

    scope = Item.for_character(story.protagonist).order(:id)
    scope = scope.where(id: only) if only
    scope.to_a
  end

  private

  def apply!(answer)
    case answer.outcome
    when :attributed
      answer.item.update!(playthrough: answer.playthrough, character: nil, location: nil)
    when :starting
      answer.playthroughs.each { |playthrough| copy_to(answer.item, playthrough) }
    when :unrecoverable
      answer.item.update!(playthrough: nil, character: nil, location: answer.location) if answer.location
    end
  end

  # The same copy `Playthrough#take_up_the_starting_inventory` makes, and it
  # skips a party that already carries the name: re-running this must not hand
  # the kit out twice.
  def copy_to(item, playthrough)
    return if playthrough.carried.by_name(item.name).exists?

    playthrough.items.create!(name: item.name, description: item.description, properties: item.properties)
  end

  def answer_for(item)
    holders = last_take_per_playthrough(item)

    if holders.empty?
      return Answer.new(item: item, outcome: :starting, playthroughs: playthroughs_without(item)) if starting_inventory?(item)

      # `walked_away_in` is nil only for a story with no room to put anything
      # down in, and then nothing is written: an item nowhere is a state no
      # closed set can offer, so leaving it in the protagonist's hands is the
      # lesser wrong and `rake game:doctor` goes on reporting it.
      return Answer.new(item: item, outcome: :unrecoverable, location: walked_away_in)
    end

    return Answer.new(item: item, outcome: :attributed, playthrough: holders.keys.sole) if holders.one?

    winners = holders_at_the_last_moment(holders)
    return Answer.new(item: item, outcome: :ambiguous, playthroughs: holders.keys) if winners.nil?
    return Answer.new(item: item, outcome: :ambiguous, playthroughs: winners) unless winners.one?

    Answer.new(item: item, outcome: :attributed, playthrough: winners.sole)
  end

  # THE TURN EACH PLAYTHROUGH LAST PICKED THIS UP ON, for the playthroughs whose
  # chain does not go on to put it down again. A chain is read in order, so the
  # last take-or-drop of this row is what that player did with it; only a chain
  # ending on a take can be holding it.
  def last_take_per_playthrough(item)
    transitions.each_with_object({}) do |(playthrough, scenes), holders|
      last = scenes.select { |scene| acted_on?(scene, item) }.last
      holders[playthrough] = last if last&.took?
    end
  end

  # EVERY TAKE AND DROP EACH PLAYTHROUGH MADE, in chain order, worked out ONCE
  # for the story rather than once per item.
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

  def acted_on?(scene, item)
    scene.acted_on_record&.id == item.id
  end

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
  def holders_at_the_last_moment(holders)
    return nil if holders.values.any? { |scene| scene.story_timestamp.nil? }

    latest = holders.values.map(&:story_timestamp).max

    holders.select { |_playthrough, scene| scene.story_timestamp == latest }.keys
  end

  # WHETHER THE WORLD ITSELF PUT THIS IN THE PROTAGONIST'S HANDS. True for a
  # generated story, which has no file to check and whose protagonist nothing in
  # the app gives items to; for a checked-in world, true only when the file
  # names it.
  def starting_inventory?(item)
    return true if seed_document.nil?

    seeded_names.include?(item.name.to_s.downcase.strip)
  end

  def seeded_names
    @seeded_names ||= Array(seed_document["characters"])
                      .select { |row| row["is_protagonist"] }
                      .flat_map { |row| Array(row["items"]) }
                      .filter_map { |row| row["name"].to_s.downcase.strip.presence }
                      .to_set
  end

  def seed_document
    return @seed_document if defined?(@seed_document)

    @seed_document = WorldSeed.checked_in_document(story.title)
  end

  # Playthroughs of this story that are not already carrying this name -- the
  # ones a starting-inventory copy is owed to.
  #
  # A NAME PROMISED EARLIER IN THIS RUN COUNTS AS CARRIED, which is what makes
  # the dry run's figures the figures the real run will produce. A world can
  # hold two rows of one name -- `rake game:doctor` reports it as
  # `duplicate_items` -- and without this the second of them would be reported
  # as owing every playthrough a copy that `copy_to` then declines to make.
  def playthroughs_without(item)
    name = item.name.to_s.downcase.strip

    story.playthroughs.order(:id).reject do |playthrough|
      next true unless promised.add?([ playthrough.id, name ])

      playthrough.carried.by_name(item.name).exists?
    end
  end

  def promised = @promised ||= Set.new

  # WHERE A PLAYER WHO WALKED AWAY LEFT IT: the room the most recently created
  # playthrough of this story is standing in, since that is the last party that
  # could have been holding the row. The story's opening room is the fallback
  # for a story with no playthroughs at all, or one standing nowhere -- a room
  # that exists and that every game has been through, rather than a guess.
  def walked_away_in
    return @walked_away_in if defined?(@walked_away_in)

    last = story.playthroughs.order(:id).last
    @walked_away_in = last&.current_location || story.locations.realized.order(:id).first
  end
end
