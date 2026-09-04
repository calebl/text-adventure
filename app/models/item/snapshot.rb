# THE INITIAL SNAPSHOT ANY PLAYTHROUGH USES, and the only thing in the app that
# creates an `Item` in the playthrough layer.
#
# The captain's ruling of 2026-09-04, verbatim: *"each play through should have
# its own copy of items. If a location is generated with items in it, that
# should become the initial snapshot that any playthrough uses but what happens
# to the items after that should be managed by the playthrough."* This is the
# "initial snapshot" half. `Item::Registry` is still the only writer of the
# world layer; this copies what it wrote, once, per game.
#
# LAZY, AT FIRST CONTACT, AND NEVER AHEAD OF IT. A world generates itself for as
# long as somebody keeps walking, so instantiating a whole story at the moment a
# game begins would copy rooms nobody will ever open and would go stale the
# first time one of them was realized. So the copy happens when the party is
# actually in front of the thing: the room they are standing in at the top of
# every turn (`Playthrough::Turn#play`), the room they have just walked into
# after it is realized (`#move_to`), and the protagonist's own kit when the
# playthrough is created. The `rake game:mechanics` mode calls the same two.
#
# THE GUARD IS PER TEMPLATE, NOT PER ROOM, and that is what makes it correct
# rather than merely idempotent. "This room is done" would be wrong in three
# ordinary ways: a party that takes the ward stamp and walks back in would find
# it re-copied onto the floor; somebody who walks into the room later has
# templates the first visit never saw; and a person who walks in carrying
# something has items the room never had. Asking instead "does this playthrough
# already hold a copy of THIS template" answers all three with one query, and it
# is the question `items(playthrough_id, template_id)` is indexed for.
#
# WHERE A COPY LANDS is where the template is, with ONE stated exception. A
# template lying in a room copies to an instance lying in that room; a template
# in an NPC's hands copies to an instance in that NPC's hands, in this game. A
# template held by the PROTAGONIST copies into THE PARTY'S OWN HANDS -- because
# the protagonist is the player, `Story#starting_inventory` is the world's word
# for what the player starts out holding, and the party is wherever the
# playthrough is rather than wherever a character row says. Companions are NOT
# the exception: `Item.for_character` was never the party's inventory for
# anybody but the protagonist, so a companion's lantern stays in the companion's
# hands exactly like any other person's.
#
# NO MODEL, NO NETWORK, NO GENERATION. Every row it writes is a copy of a row
# that already exists.
class Item::Snapshot
  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # A ROOM AND THE PEOPLE STANDING IN IT, which is what "first contact" means
  # for everything a turn can reach: what is lying here is the closed set `take`
  # resolves against, and who is here is the closed set `talk` does, so the
  # things in their hands are one door away either way.
  #
  # Nil is a no-op: a playthrough standing nowhere has no room to snapshot, and
  # nothing in the app produces one -- `current_location` is optional and a
  # hand-made playthrough can.
  def of_the_room!(location)
    return [] if location.nil?

    templates = Item.lying_in(location).templates.order(:id).to_a
    people = Character.present_in(location).to_a

    copy_all!(templates.map { |template| [ template, { location: location } ] } +
              people.flat_map { |person| held_by(person) })
  end

  # ONE PERSON'S POSSESSIONS, for a caller that has met somebody without
  # standing in a room with them. Nothing calls it today -- `#of_the_room!`
  # reaches everybody a turn can reach -- and it exists because the rule is
  # about meeting a person and not about the room they happen to be in, so a
  # branch that ever meets one somewhere else has the statement to call.
  def of_the_person!(character)
    return [] if character.nil?

    copy_all!(held_by(character))
  end

  # WHAT THE STORY STARTS THE PLAYER HOLDING, in this party's own hands.
  # `Story#starting_inventory` is the world's answer and this is the copy of it,
  # made once when a playthrough is created. It used to be
  # `Playthrough#take_up_the_starting_inventory`, a rule of its own; it is an
  # ordinary case of the rule above now, and the only thing left that is special
  # about it is WHERE the copy lands (see the header).
  def of_the_party!
    protagonist = playthrough.story&.protagonist
    return [] if protagonist.nil?

    copy_all!(Item.for_character(protagonist).templates.order(:id).map { |template| [ template, {} ] })
  end

  private

  # A person's templates and where their copies go: into that person's hands,
  # in this game -- unless the person is the protagonist, whose things are the
  # party's and belong in the party's own hands.
  def held_by(character)
    into = character.is_protagonist? ? {} : { character: character }

    Item.for_character(character).templates.order(:id).map { |template| [ template, into ] }
  end

  # THE ONES THIS PLAYTHROUGH HAS NO COPY OF YET, copied. One query for the
  # whole set rather than one per candidate, because this runs at the top of
  # every turn and almost every turn has nothing to do.
  #
  # In a transaction so a snapshot is all of a room or none of it: a turn that
  # failed halfway through copying would leave the party looking at half a room
  # and would never try again, since the guard would see the half it made.
  def copy_all!(candidates)
    return [] if candidates.empty?

    wanted = candidates.reject { |template, _into| already_copied.include?(template.id) }
    return [] if wanted.empty?

    Item.transaction do
      wanted.map do |template, into|
        already_copied << template.id
        copy!(template, into)
      end
    end
  end

  # EVERY COLUMN BUT WHERE IT IS AND WHOSE IT IS -- `Item::NOT_COPIED`, which is
  # the exception list rather than a list of fields, so the next column added to
  # `items` comes along without anybody remembering it. See that constant.
  def copy!(template, into)
    playthrough.items.create!(
      template.attributes.except(*Item::NOT_COPIED).merge(template: template, **into)
    )
  end

  # THE TEMPLATE IDS THIS PLAYTHROUGH ALREADY HOLDS A COPY OF. Read once per
  # instance of this class and added to as it copies, so a single call that
  # snapshots a room and the three people in it asks the database once.
  #
  # An instance with no `template_id` counts for nothing here, deliberately: it
  # is a row `rake game:doctor` reports (`instance_without_a_template`) and
  # `rake game:backfill_items` links, and guessing at the link by name would be
  # the one thing every backfill in this app refuses to do.
  def already_copied
    @already_copied ||= playthrough.items.where.not(template_id: nil).pluck(:template_id).to_set
  end
end
