# HOW ITEMS COME TO EXIST. One class, one entry point, and every `Item` the
# app creates goes through it.
#
# Until this existed nothing in the app made an `Item` at all -- `lib/world_seed/loader.rb`
# was the only writer in the whole codebase -- so every room the world wrote
# for itself was empty and the possession mechanic the app already owns
# (`Playthrough::Turn#take_item` / `#drop_item`) could only be exercised in
# rooms a person had hand-written.
#
# ITEMS ARE BORN AS STRUCTURED RECORDS AT THE MOMENT A ROOM IS REALIZED,
# exactly the way exits are, and NOT by reading narration or by a tool the
# narrator may or may not call. That is the deliberate deviation from the
# direction plan's "populated when the narrator names something": the
# standing constraint is that the engine owns state and the narrator is
# *told* it, so a mechanic whose records depend on a model calling a tool is a
# mechanic that quietly stops working the day a model stops complying. The
# plan's real intent survives -- nothing is generated ahead of time, the
# ontology stays bounded, a stub room costs nothing until somebody walks in --
# and only the compliance dependency is dropped. `Playthrough::Moment` then
# tells the narrator what is lying here, out of these records.
#
# WHOLE, NOT STUBBED. `Location` is realized in two steps because a room's
# description is expensive and a room nobody enters should not be paid for.
# An item is a name and one line, ~15 output tokens, riding on a call that is
# already being made -- so deferring the line would save nothing now and cost
# a whole round trip later, the first time somebody examined it. Items are
# created complete. If an item ever grows a field worth a call of its own,
# that is the point to revisit it, and `Location`'s two-state shape is the
# model to copy.
#
# WHAT IT REFUSES, and every one of these is a candidate a model really can
# produce: a name the room already has, a name anything in this story already
# has, a name that is a person or a place (the closed sets `talk` and `move`
# resolve against -- an "Ashgate Market" lying on the floor makes two of the
# classifier's enums answer to one word), and anything at all once the room or
# the world is at its cap. Refusals are dropped, never raised: a room realized
# with two of the three things the model named is a good room, and a
# realization that threw away its description over an item name would not be.
class Item::Registry
  include SanitizesGeneratedText

  # HOW MANY THINGS MAY BE LYING IN ONE ROOM, in total and not per call --
  # the same distinction `Location::ExitsSchema::MAX_EXITS` documents. A
  # world file can seed a room up to and past this (`The Supply Closet` seeds
  # two), and the schema bounds one answer, so the total is enforced here,
  # against the records, on every admission.
  MAX_PER_ROOM = 3

  # HOW MANY THINGS ONE WORLD MAY HOLD AT ALL, across every room and every
  # pair of hands. The per-room cap alone bounds nothing: a world generates
  # rooms for as long as somebody keeps walking, so three per room is three
  # times however far they went. This is the ceiling on the ontology --
  # "a physics ontology" is the thing the direction plan rules out, and an
  # unbounded item table is how you get one by accident.
  #
  # 60 is four times the largest seeded world's cast-and-contents and roughly
  # twenty realized rooms' worth at the observed rate; a world that reaches it
  # has enough for anything the arc's `hold_item` trigger needs, and past it
  # a room simply generates without furniture rather than failing.
  MAX_PER_STORY = 60

  attr_reader :location, :story

  def initialize(location)
    @location = location
    @story = location.story
  end

  # Turns the bounded list a realization call answered with into `Item` rows
  # lying in this room. Returns the ones it created, which is what a test and
  # a caller that wants to log both want; the ones it refused are dropped with
  # a reason in the log.
  #
  # `candidates` is the raw `items` array off the schema'd response -- string
  # keys, unsanitized, possibly nil, possibly longer than the cap.
  def admit!(candidates)
    created = []

    Item.transaction do
      Array(candidates).each do |attributes|
        item = admit_one(attributes, created)
        created << item if item
      end
    end

    created
  end

  # HOW MANY MORE THINGS MAY BE LYING HERE, read from the records rather than
  # counted once, for the same reason `Location::Generator#room_for_exits` is:
  # rows are written as the loop goes, and a budget worked out before it would
  # not notice.
  def room_for_items
    [ MAX_PER_ROOM - Item.lying_in(location).count, 0 ].max
  end

  # Whether this world has room for another thing at all.
  def world_for_items
    [ MAX_PER_STORY - story_item_count, 0 ].max
  end

  # Every item in this story, on either side of `Item`'s one-place rule. There
  # is no `items.story_id` -- an item is owned by whoever holds it -- so this
  # is the two queries that answer for a story, and it is the same pair
  # `WorldSeed::Loader#find_item` uses.
  def story_items
    Item.where(character_id: story.characters.select(:id))
        .or(Item.where(location_id: story.locations.select(:id)))
  end

  private

  def story_item_count = story_items.count

  def admit_one(attributes, created)
    name = sanitize_string(attributes["name"].to_s)
    description = sanitize_string(attributes["description"].to_s)

    reason = refusal(name, description, created)
    return refuse(name, reason) if reason

    location.items.create!(name: name, description: description, character: nil)
  end

  # The one place that says no, and it says which no. Ordered cheapest first:
  # the shape of the answer, then the room, then the world, then the three
  # collision checks that each cost a query.
  #
  # BOTH CAPS ARE READ BACK FROM THE RECORDS on every candidate rather than
  # counted down from a budget, exactly as `Location::Generator#room_for_exits`
  # is and for the same reason: rows are written as the loop goes. Counting
  # `created` as well would charge each admission twice.
  def refusal(name, description, created)
    return "it has no name" if name.blank?
    return "it has no description" if description.blank?
    return "the room is already holding #{MAX_PER_ROOM}" if room_for_items.zero?
    return "the world is already holding #{MAX_PER_STORY}" if world_for_items.zero?
    return "this call already named it" if created.any? { |item| item.name.casecmp?(name) }
    return "the story already has one" if story_items.where("LOWER(name) = ?", name.downcase).exists?
    return "a person in this story is called that" if person_named?(name)
    return "a place in this story is called that" if place_named?(name)

    nil
  end

  def refuse(name, reason)
    Rails.logger.info do
      "[items] #{location.name.inspect} did not take #{name.presence.inspect || "an unnamed thing"}: #{reason}"
    end
    nil
  end

  # THE CLOSED SETS THIS MUST NOT COLLIDE WITH. `Playthrough::Classifier`
  # resolves a typed line against the room's cast, its exits and what is lying
  # in it, by name; an item sharing a name with one of the other two makes the
  # same word resolve two ways, and which way it goes is then an ordering
  # accident inside the classifier rather than anything the player could
  # predict. Checked against the whole story rather than the room, because the
  # player carries what they take into the room where the collision bites.
  def person_named?(name)
    story.characters.where("LOWER(fullname) = ? OR LOWER(nickname) = ?", name.downcase, name.downcase).exists?
  end

  def place_named?(name)
    story.locations.where("LOWER(name) = ?", name.downcase).exists?
  end
end
