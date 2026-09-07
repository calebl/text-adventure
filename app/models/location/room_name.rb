# WHAT A ROOM OF A PLACE IS CALLED ONCE SOMEBODY HAS WRITTEN IT, and the one
# place in the app that decides whether a proposed name is one the room may
# have.
#
# WHY IT EXISTS. `Location::Interior` lays a building out before anybody walks
# in and numbers its rooms -- `The Custom House room 3` -- which is deliberately
# provisional (see `.placeholder_name`). Until this file nothing ever replaced
# it: `Location::DetailSchema` had no `name` field and a room of an interior
# gets no exits call at all (`Location::Generator#write_exits!`), so the one
# call that could have named a room never asked, and the player read *"You are
# in The Blackfang Warren room 3 of Blackfang Warren"* for the rest of the game.
# `Location::Plan`'s header carried the deferral; this is the item it named.
#
# THE MODEL PROPOSES AND THIS DECIDES, which is `Item::Registry`'s and
# `Character::Registry`'s shape rather than a new one, and it is the standing
# constraint applied to a name: the prompt states the rules because that raises
# the odds, and NOTHING depends on them being followed. A name that breaks one
# of them is refused here and the placeholder stays -- a provisional name is a
# worse room, a wrong name is a broken one.
#
# NOTHING RAISES, EVER, and that is a rule about WHERE this runs rather than a
# preference. `Location::Generator#write_detail!` calls this between the answer
# arriving and the room being saved, with the description and the lore already
# in hand and the cast and the floor still to be admitted. A raise on a name
# would cost the room its whole realization -- the prose that was paid for, the
# people, the things -- so every refusal below returns and logs. It is
# `Item::Registry#written_words`' reasoning about the same seam.
#
# WHAT IT REFUSES, AND WHY EACH ONE:
#
#   BLANK, or a field the provider cut off at the cap
#   (`SanitizesGeneratedText::TruncatedTextError`). Half a name is not a shorter
#   name.
#
#   A COMMA. `Playthrough::Grammar::JOINING_WORDS` reads one as *and*, so a line
#   naming a room with a comma in it is refused as two acts in a line -- a room
#   the player can see and cannot walk into. `.placeholder_name` carries the
#   same rule and states the general form of it: a name the engine writes has to
#   be a name the grammar can be handed back.
#
#   THE NAME THE ROOM ALREADY HAS. A model handed the placeholder in the prompt
#   sometimes hands it straight back, and accepting it would spend a field to
#   change nothing.
#
#   ANOTHER OF THIS PLACE'S PLACEHOLDERS, in the SHAPE
#   `Location::Interior.placeholder_name?` knows -- including a number no room
#   of this building has. `The Custom House room 12` in an eight-room building
#   is not caught by the collision check below (no row answers to it) and is the
#   worst of these to accept: a room permanently called a placeholder that was
#   never provisional.
#
#   THE PLACE'S OWN NAME ANYWHERE INSIDE IT (`#repeats_place?`). The play page
#   prints the room and the place together, so *"the Rusted Anchor taproom"*
#   reads as *"the Rusted Anchor taproom of The Rusted Anchor"* -- the doubling
#   this class exists to remove, one notch quieter. The prompt says to keep the
#   place's name out; this is what makes that a guarantee rather than a request.
#
#   A NAME THIS WORLD HAS ALREADY GIVEN TO SOMEWHERE, SOMEBODY OR SOMETHING.
#   The rule `Character::Registry#creation_refusal` applies to a person named
#   after a place, asked the other way round. IT IS THE WHOLE STORY AND NOT ONLY
#   THIS PLACE'S ROOMS, which is wider than it needs to be for one reason:
#   `Story::Doctor#duplicate_locations` reports two locations of one story
#   answering to one name as a defect a person has to resolve by hand, and
#   `Story::Repair` and half the app look a room up by name
#   (`story.locations.find_by(name:)`). Accepting a name that made one would be
#   the engine writing the very row the doctor is there to find.
#
# IDENTITY IS `WorldSeed.natural_key`'s, not the written string's -- case, runs
# of whitespace and a leading article are not part of it. That is the repo's one
# spelling of "the same name written differently" and it is the spelling
# `Story::Doctor` reports a duplicate on, so a name this accepts cannot be a
# name the doctor then calls a collision.
#
# A LEADING ARTICLE IS PART OF THE NAME AND IS ASKED FOR. The captain's ruling
# of 2026-09-06 has the play page read *"the <room> of <place>"*, and the line
# that renders it (`app/views/playthroughs/_turn_log.html.erb`) prints the
# STORED name as it stands -- which is what lets one line read correctly for a
# room called `The Custom House room 1` and for a room called `the counting
# room` alike. The article costs nothing: `WorldSeed.natural_key` drops it from
# the identity and `Playthrough::Grammar::LEADING_WORDS` drops it from what the
# player types.
#
# A SEED FILE'S ROOM NAME NEVER REACHES THIS, and `.for` is what makes that
# true rather than nearly true. `WorldSeed::Loader` writes the name the file
# gives and makes no model call, so this is only ever asked about a name that
# came back from one -- but the ROOM it is asked about could still be one a file
# had named by hand, because a file may draw a whole building as stub rooms. So
# `.for` answers nil for a room whose name is not one of the place's
# placeholders, and a hand-authored name is never proposed against.
#
# AND A NAME WRITTEN HERE IS STILL THE FILE'S TO RE-ASSERT. Renaming a stub the
# file declares means the file's name and the row's have parted, which
# `WorldSeed.find_location` recognizes on the place and the box -- so a re-seed
# renames that row back rather than writing a second room at the same
# coordinates. That reader is the other half of this one, and neither is safe
# without it.
#
# AND A NAME IS WRITTEN ONCE, AT REALIZATION, like every other detail field. A
# room already realized keeps whatever it is called: nothing here renames a row
# in a database somebody has played.
class Location::RoomName
  include SanitizesGeneratedText

  # The cap the prompt asks the model to stay under AND the cap this refuses a
  # name over -- one number, so the bound the model is given and the bound the
  # engine checks cannot disagree. `Character::Registry::PERSON_LIMITS`'s rule.
  # The figure is `Location::ExitsSchema`'s own name field's, because it is the
  # same thing: a place's name as a player would type it.
  LIMIT = 60

  # A ROOM OF A LAID-OUT PLACE THAT IS STILL CALLED A NUMBER, OR NIL for
  # everything else -- so a caller asks one question and has no gate of its own.
  # TWO THINGS ARE ASKED HERE and they are two different questions:
  #
  #   WHERE THE ROOM IS. `Location#containing_place` is the gate and not a
  #   second reading of it: a box read in a parent's own plane, which is what
  #   tells an interior room from plain containment (a district a street sits
  #   in) and from a room inside nothing at all.
  #
  #   AND WHETHER IT IS STILL CALLED WHAT `Location::Interior` CALLED IT
  #   (`.placeholder_name?`). A room whose name is a real one is not asked to
  #   propose another, and that is what makes the header's claim about a seed
  #   file true rather than nearly true: `Location::Generator#lay_out_interior!`
  #   documents that a file may draw a whole building by hand, and such a file
  #   may ship `The Cellar Stair` as a STUB room of the place. Every room this
  #   engine laid out, and every stub room of every checked-in world, carries a
  #   placeholder and passes; a hand-authored name is left alone -- which
  #   matters most where it is easiest to miss, because a stub room's name is
  #   listed as an exit and may already have been typed by the player.
  #
  # IT IS THE GATE AND NOT A REFUSAL, deliberately. Nil here means the prompt
  # never ASKS such a room to name itself -- `Location::Generator#name_instruction`
  # is empty and `Eval::Realization::Stage::Standing#name_asked?` records false,
  # so the row leaves both name checks' denominators. Refusing after asking
  # would instead report a `room_name_refused` defect against a room that was
  # never a candidate, and a rate a check did not earn is worse than no rate.
  # `#refusal_for`'s "it is the name this room already has" is the other half
  # and stays: that one is about the PROPOSAL, this one is about the room.
  def self.for(room)
    place = room&.containing_place
    return nil unless place && Location::Interior.placeholder_name?(place, room.name)

    new(room, place)
  end

  attr_reader :room, :place

  def initialize(room, place)
    @room = room
    @place = place
  end

  # THE NAMES THIS PLACE HAS ALREADY GIVEN OUT, for the prompt to state -- and
  # the placeholders are left off it. Naming what nothing has named yet is the
  # noise `#accept` refuses anyway, and this rides on a prompt sent once per
  # room: a fourteen-room building would spend fourteen lines saying "not the
  # numbers", which is `Location::Generator#known_names_note`'s reason for
  # truncating and the same trade.
  #
  # SAYING IT UP FRONT IS WHAT STOPS A REFUSAL BEING SPENT, which is
  # `#items_instructions`' rule: a name refused after the call is a room that
  # kept its placeholder for a collision it was never shown.
  def named_siblings
    place.child_locations.where.not(id: room.id).order(:id).pluck(:name)
         .compact_blank.reject { |name| Location::Interior.placeholder_name?(place, name) }
  end

  # THE NAME TO WRITE, OR NIL TO KEEP THE ONE THE ROOM HAS. Nil is a complete
  # answer and the caller writes nothing -- see the header for why nothing
  # raises.
  def accept(proposed)
    name = clean(proposed)
    return refuse(proposed, "it arrived blank") if name.blank?

    reason = refusal_for(name)
    return refuse(name, reason) if reason

    name
  end

  private

  # The cap is checked on the RAW text, which is what `SanitizesGeneratedText`
  # does and why: the provider counted those characters, so that is the length
  # that says whether it cut the answer off.
  def clean(proposed)
    sanitize_string(proposed.to_s, max_length: LIMIT).presence
  rescue SanitizesGeneratedText::TruncatedTextError
    nil
  end

  # THE ONE PLACE THAT SAYS NO, AND IT SAYS WHICH NO. Ordered cheapest first:
  # the shape of the string, then the two names this object already holds, then
  # the one check that costs queries.
  def refusal_for(name)
    return "it carries a comma, which Playthrough::Grammar reads as two acts in one line" if name.include?(",")
    return "it is the name this room already has" if same?(name, room.name)
    return "it is one of #{place.name}'s own placeholders" if Location::Interior.placeholder_name?(place, name)
    return "it has #{place.name} in it, which the line that reads it prints anyway" if repeats_place?(name)

    kind = taken[WorldSeed.natural_key(name)]
    kind && "#{kind} in this story is already called that"
  end

  # THE PLACE'S OWN NAME, INSIDE THE ROOM'S. It is the VERIFY half of a rule the
  # prompt was only informing: `Location::Generator#name_instruction` tells the
  # model to name the ROOM only and never to put the place's name into it,
  # because the play page prints the two together -- *"the counting room of The
  # Custom House"* (the captain's ruling of 2026-09-06) -- and a model that
  # ignored it gave *"the Rusted Anchor taproom of The Rusted Anchor"*. Which is
  # a milder spelling of the very doubling this class exists to take out of the
  # game, and it slipped past `Location::Interior.placeholder_name?` because
  # that answers a SHAPE (`<place> room <n>`) rather than the question of
  # whether the place is named at all.
  #
  # CONTAINMENT AND NOT EQUALITY, on `WorldSeed.natural_key`'s reading of a
  # name: the whole failure is a room name with the place's inside it, so an
  # exact match would catch the one case nobody proposes.
  #
  # A PLACE WITH NO NAME REFUSES NOTHING, because every string contains the
  # empty one. Unreachable through the app -- `Location` validates a name -- and
  # written down because the alternative is a fixture that quietly refuses every
  # name a test proposes.
  def repeats_place?(name)
    key = WorldSeed.natural_key(place.name)

    key.present? && WorldSeed.natural_key(name).include?(key)
  end

  # EVERY NAME THIS STORY HAS SPOKEN FOR, by natural key, with what kind of
  # thing holds it -- so a refusal names the collision rather than merely
  # reporting one. Places first, because a place is the collision that matters
  # and the label should say so when a row is both.
  def taken
    @taken ||= begin
      found = {}
      story.locations.where.not(id: room.id).pluck(:name).each { |name| found[WorldSeed.natural_key(name)] ||= "somewhere" }
      story.characters.pluck(:fullname, :nickname).flatten.each { |name| found[WorldSeed.natural_key(name)] ||= "somebody" }
      Item.in_story(story).pluck(:name).each { |name| found[WorldSeed.natural_key(name)] ||= "something" }
      found.except("")
    end
  end

  def story = room.story

  def same?(one, other) = WorldSeed.natural_key(one) == WorldSeed.natural_key(other)

  def refuse(proposed, reason)
    Rails.logger.info do
      "[rooms] #{room.name.inspect} kept its name and refused " \
        "#{proposed.presence&.inspect || "an unnamed room"}: #{reason}"
    end
    nil
  end
end
