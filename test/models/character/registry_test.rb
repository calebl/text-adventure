require "test_helper"

# The people half of the noun registry. One rule matters more than the rest and
# it is the Tide Post defect written down: a proposal never moves somebody who
# is already somewhere.
class Character::RegistryTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @here = create(:location, story: @story, name: "The Causeway Court")
    @there = create(:location, story: @story, name: "The Tide Post")
  end

  def registry(location = @here) = Character::Registry.new(location)

  # --- placing --------------------------------------------------------------

  test "somebody nowhere is placed, and the room's cast is what comes back" do
    brace = create(:character, story: @story, fullname: "Ammon Brace")

    present = registry.admit!([ brace ])

    assert_equal @here, brace.reload.location
    assert_equal [ brace ], present
  end

  test "a proposal may name somebody by fullname or by nickname" do
    neb = create(:character, story: @story, fullname: "Neb Halloran", nickname: "Neb")

    registry.admit!([ "neb" ])

    assert_equal @here, neb.reload.location
  end

  test "the cast that comes back is read out of the records, not out of the proposal" do
    standing = create(:character, story: @story, fullname: "Ammon Brace", location: @here)

    present = registry.admit!([])

    assert_equal [ standing ], present
  end

  # --- refusing -------------------------------------------------------------

  # THE DEFECT THIS CLASS EXISTS FOR. Arriving at The Tide Post recorded the
  # protagonist alone on all three runs checked, in a world whose premise is
  # that Neb Halloran is chained to that post -- because the cast was
  # regenerated from scratch every time. A proposal is evidence about a room and
  # never authority over a person.
  test "a character who is already somewhere is not moved" do
    neb = create(:character, story: @story, fullname: "Neb Halloran", location: @there)

    present = registry.admit!([ neb ])

    assert_equal @there, neb.reload.location, "the proposal moved somebody it should only have proposed"
    assert_equal [], present
  end

  # THE SECOND HALF OF THAT RULE: nowhere on purpose is not an empty slot.
  # `The Unrecorded Hour` is about Perrin Lasco having been removed from the
  # world, so a realization that named him would put him back into the game as a
  # side effect of describing a room.
  test "a character who is absent on purpose is not placed" do
    perrin = create(:character, story: @story, fullname: "Perrin Lasco")
    perrin.absent!

    present = registry.admit!([ perrin ])

    assert_predicate perrin.reload, :absent?, "the registry undid a world's own premise"
    assert_equal [], present
  end

  # `Character#move_to!` is the explicit call for a mechanic that MEANS to bring
  # somebody back, and it clears the marker -- so once they are in a room the
  # registry treats them like anybody else who is already somewhere.
  test "a character brought back explicitly is no longer refused as absent" do
    perrin = create(:character, story: @story, fullname: "Perrin Lasco")
    perrin.absent!
    perrin.move_to!(@there)

    registry.admit!([ perrin ])

    assert_equal @there, perrin.reload.location, "the proposal moved somebody it should only have proposed"
    assert_not_predicate perrin, :deliberately_absent?
  end

  # A NAME ALONE IS NOT A PERSON. `#admit!` also takes names, and a name with no
  # sheet behind it is somebody the caller believed already existed -- inventing
  # one from a string would put a character in the world with no appearance,
  # nothing to say and nobody who wrote them.
  test "a bare name nobody answers to is refused rather than invented" do
    assert_no_difference -> { Character.count } do
      assert_equal [], registry.admit!([ "Somebody Who Does Not Exist" ])
    end
  end

  test "a character of another story is not placed here" do
    stranger = create(:character, story: create(:story), fullname: "Neb Halloran")

    registry.admit!([ stranger ])

    assert_predicate stranger.reload, :nowhere?
  end

  test "a room already at its cap takes nobody else" do
    Character::Registry::MAX_PER_ROOM.times { create(:character, story: @story, location: @here) }
    late = create(:character, story: @story, fullname: "One Too Many")

    assert_equal 0, registry.room_for_people
    registry.admit!([ late ])

    assert_predicate late.reload, :nowhere?
  end

  # The cap is read back from the records on every candidate rather than counted
  # down from a budget, exactly as `Item::Registry`'s two are -- rows are
  # written as the loop goes.
  test "the cap counts the people written by this very call" do
    over = (Character::Registry::MAX_PER_ROOM + 2).times.map { create(:character, story: @story) }

    present = registry.admit!(over)

    assert_equal Character::Registry::MAX_PER_ROOM, present.size
    assert_equal Character::Registry::MAX_PER_ROOM, Character.present_in(@here).count
  end

  # Placing somebody who is already standing here is a no-op rather than a
  # refusal, so re-proposing a room's own cast does not spend its allowance.
  test "somebody already in this room is not counted against the cap again" do
    standing = create(:character, story: @story, location: @here)

    registry.admit!([ standing, standing ])

    assert_equal Character::Registry::MAX_PER_ROOM - 1, registry.room_for_people
  end

  test "a refusal never raises and never loses the rest of the proposal" do
    neb = create(:character, story: @story, fullname: "Neb Halloran", location: @there)
    brace = create(:character, story: @story, fullname: "Ammon Brace")

    present = registry.admit!([ neb, "nobody of that name", brace ])

    assert_equal [ brace ], present
    assert_equal @there, neb.reload.location
  end

  # --- creating -------------------------------------------------------------
  #
  # The captain's ruling: *"rooms should be born with people in them
  # sometimes."* Built the way `Item::Registry` builds a room's furniture --
  # structured records out of the call that describes the room.

  test "a sheet nobody in this story answers to becomes a person standing here" do
    created = nil

    assert_difference -> { Character.count }, 1 do
      created = registry.admit!([ sheet(fullname: "Neb Halloran", nickname: "Neb") ]).sole
    end

    assert_equal "Neb Halloran", created.fullname
    assert_equal "Neb", created.nickname
    assert_equal @here, created.location
    assert_equal @story, created.story
    assert_equal [ created ], Character.present_in(@here).to_a
  end

  # Every field a `Character` is validated on has to arrive, or the row cannot
  # be talked to -- `Character#interaction_instructions` interpolates all six.
  test "a created person carries the whole sheet the conversation prompt reads" do
    created = registry.admit!([ sheet(fullname: "Neb Halloran") ]).sole

    Character::Registry::SHEET.each do |field|
      assert_equal "a #{field} line", created.public_send(field), field
    end
    assert_predicate created, :valid?
  end

  # --- where monsters come from ---------------------------------------------
  #
  # THE CAPTAIN'S SEVENTH RULING, 2026-09-04 evening: a dangerous room draws its
  # inhabitants from the universe's monstrous races instead of its peoples, and
  # a generated character whose race is monstrous is hostile by default. Nothing
  # a model answers reaches either half -- `Location::DetailSchema` has no field
  # for a race or for hostility, and the realization prompt states the race this
  # class has already rolled.

  test "a safe room draws every slot from the world's peoples" do
    create(:race, :monstrous, universe: @story.universe)

    registry.slots.each { |slot| assert_not_predicate slot[:race], :monstrous? }
  end

  test "a deadly room draws every slot from the world's monsters" do
    create(:race, :monstrous, universe: @story.universe)
    lair = create(:location, :deadly, story: @story, name: "The Sump")

    registry(lair).slots.each { |slot| assert_predicate slot[:race], :monstrous? }
  end

  test "a dangerous room draws from both pools" do
    create(:race, :monstrous, universe: @story.universe)
    rooms = 12.times.map { |n| create(:location, :dangerous, story: @story, name: "Chamber #{n}") }
    drawn = rooms.flat_map { |room| Character::Registry.new(room).slots.map { |slot| slot[:race].monstrous? } }

    assert_includes drawn, true
    assert_includes drawn, false
  end

  # THE MIRROR CASE, and it is the louder of the two fallbacks: in a universe
  # whose every race is a monster there is nobody else to be, so a safe room's
  # inhabitant comes out of the bestiary and the derivation then makes them
  # hostile. That is a true statement about such a world rather than a hole in
  # `danger` -- the alternative is a room described around a person it does not
  # have. No checked-in world is in this state and nothing in the app can put
  # one there; this pins the behaviour so the header's claim is measured.
  test "a safe room in a world with nothing but monsters writes one, and it is hostile" do
    @story.universe.races.each { |race| race.update!(monstrous: true) }

    created = registry.admit!([ sheet(fullname: "Marek Sollen") ]).sole

    assert_equal [], @story.universe.peoples.to_a
    assert_equal Location::SAFE, @here.danger
    assert_predicate created.race, :monstrous?
    assert_predicate created, :hostile?
  end

  test "a dangerous room in a world with no monsters writes ordinary people" do
    lair = create(:location, :deadly, story: @story, name: "The Sump")

    assert_equal [], @story.universe.monstrous_races.to_a
    registry(lair).slots.each { |slot| assert_not_nil slot[:race] }
  end

  test "somebody born in a dangerous room of a monstrous race is hostile" do
    create(:race, :monstrous, universe: @story.universe)
    lair = create(:location, :deadly, story: @story, name: "The Sump")

    created = Character::Registry.new(lair).admit!([ sheet(fullname: "Marek Sollen") ]).sole

    assert_predicate created.race, :monstrous?
    assert_predicate created, :hostile?
  end

  test "somebody born in a safe room is not hostile" do
    create(:race, :monstrous, universe: @story.universe)
    created = registry.admit!([ sheet(fullname: "Grenn Ollivar") ]).sole

    assert_not_predicate created.race, :monstrous?
    assert_not_predicate created, :hostile?
  end

  # A MONSTER IS AN ORDINARY PERSON IN EVERY RESPECT BUT ONE, and the nine
  # fields say so: the registry refuses a half-written monster exactly as it
  # refuses a half-written landlord.
  test "a monster is written with the whole sheet a conversation reads" do
    create(:race, :monstrous, universe: @story.universe)
    lair = create(:location, :deadly, story: @story, name: "The Sump")

    created = Character::Registry.new(lair).admit!([ sheet(fullname: "Marek Sollen") ]).sole

    Character::Registry::SHEET.each { |field| assert_predicate created.public_send(field), :present? }
    assert_predicate created, :stat_block?
    assert_predicate created, :abilities?
  end

  # The same room asked twice picks the same people, which is what makes a room
  # re-derivable and `DRY_RUN=1` worth anything one layer up.
  test "one room's slots are the same slots in any process" do
    create(:race, :monstrous, universe: @story.universe)
    lair = create(:location, :dangerous, story: @story, name: "The Sump")

    first = Character::Registry.new(lair).slots.map { |slot| slot[:race].monstrous? }
    second = Character::Registry.new(lair).slots.map { |slot| slot[:race].monstrous? }

    assert_equal first, second
  end

  # WHO THEY ARE IS THE ENGINE'S, on `Character::Generator`'s rule. The rolls
  # are made before the prompt is built and the row has to match what the prompt
  # said, or the room was described around one person and written around
  # another.
  test "race, age and sex come from the slot the prompt was told about" do
    # ONE instance, because the rolls are its own: the prompt and the row have
    # to come out of the same registry or the room is described around one
    # person and written around another.
    registry = registry(@here)
    slot = registry.slots.first

    created = registry.admit!([ sheet(fullname: "Neb Halloran") ]).sole

    assert_equal slot[:race], created.race
    assert_equal slot[:age], created.age
    assert_includes @story.universe.races, created.race

    # `sex_label` and not `sex`: a slot holds the STORED value -- "non-binary",
    # "trans woman" -- because that is what the prompt says out loud, and
    # `Character#sex` reads back the enum KEY. Only `male` and `female` are
    # spelt the same either way, so asserting on `sex` passes two rolls in five
    # and fails the other three, which is how this reached CI green locally.
    assert_equal slot[:sex], created.sex_label
    assert_equal slot[:sex], Character.sexes.fetch(created.sex)
  end

  # EVERY ROLL, not the one this run happened to make. `#slots` samples a sex,
  # and only two of the five are spelt the same as their enum key -- so a test
  # that asserts on one random roll is green two runs in three and red in CI on
  # the third. This walks all five.
  test "every sex the slot can roll writes a row the prompt's own line describes" do
    Character.sexes.each do |key, stored|
      # A fresh room per sex: MAX_PER_ROOM is 3 and there are five of them.
      room = create(:location, story: @story)
      registry = Character::Registry.new(room)
      registry.define_singleton_method(:slots) { [ { race: story.universe.races.first, age: 40, sex: stored } ] }

      person = registry.admit!([ sheet(fullname: "Person #{key}") ]).sole

      assert_equal key, person.sex, "the row does not hold the enum key for #{key}"
      assert_equal stored, person.sex_label, "the row does not read back what the prompt said for #{key}"
    end
  end

  test "the second person in one answer gets the second slot" do
    registry = registry(@here)
    first, second = registry.slots

    people = registry.admit!([ sheet(fullname: "Neb Halloran"), sheet(fullname: "Ammon Brace") ])

    assert_equal [ first[:race], second[:race] ], people.map(&:race)
    assert_equal [ first[:age], second[:age] ], people.map(&:age)
  end

  # --- what creation refuses -------------------------------------------------

  test "a sheet with no name is refused" do
    assert_no_difference -> { Character.count } do
      registry.admit!([ sheet(fullname: "  ") ])
    end
  end

  test "a sheet missing a field the conversation prompt reads is refused" do
    assert_no_difference -> { Character.count } do
      registry.admit!([ sheet(fullname: "Neb Halloran").except("fears") ])
    end
  end

  # THE THREE CLOSED SETS A NAME MUST NOT COLLIDE WITH, and they are
  # `Item::Registry`'s three read from the other side: the classifier resolves a
  # typed line against the cast, the exits and what is lying here BY NAME, so
  # one word answering to two of them is an ordering accident.
  test "a name a person in this story already answers to is refused" do
    create(:character, story: @story, fullname: "Neb Halloran", nickname: "Neb")

    assert_no_difference -> { Character.count } do
      registry.admit!([ sheet(fullname: "neb") ])
      registry.admit!([ sheet(fullname: "NEB HALLORAN") ])
    end
  end

  test "a name a place in this story has is refused" do
    assert_no_difference -> { Character.count } do
      registry.admit!([ sheet(fullname: "The Tide Post") ])
    end
  end

  test "a name something in this story has is refused" do
    create(:item, :lying, location: @there, name: "Assize tide-slate")

    assert_no_difference -> { Character.count } do
      registry.admit!([ sheet(fullname: "Assize tide-slate") ])
    end
  end

  # A HALF-WRITTEN PERSON IS WORSE THAN NO PERSON. Elsewhere a truncated field
  # is a failed call that reaches the model rotation; here it must not be,
  # because the call it would fail is the room's own description -- already
  # saved, and the expensive half of the realization. The first live
  # realization under this schema came back with `appearance` cut mid-word.
  test "a sheet the provider cut off is refused rather than written" do
    cut = sheet(fullname: "Neb Halloran").merge(
      "appearance" => "x" * Character::Registry::PERSON_LIMITS[:appearance]
    )

    assert_no_difference -> { Character.count } do
      registry.admit!([ cut ])
    end
  end

  test "a truncated sheet does not raise, and does not lose the room's other person" do
    cut = sheet(fullname: "Neb Halloran").merge(
      "backstory" => "x" * Character::Registry::PERSON_LIMITS[:backstory]
    )

    people = registry.admit!([ cut, sheet(fullname: "Ammon Brace") ])

    assert_equal [ "Ammon Brace" ], people.map(&:fullname)
  end

  # The caps are sized to a FINISHED answer, which is the whole of how
  # truncation is told from a near miss -- see `SanitizesGeneratedText`.
  test "the schema hands the model the same caps this class checks against" do
    fields = Location::DetailSchema.new.to_json_schema.dig(:schema, :properties, :people, :items, :properties)

    Character::Registry::PERSON_LIMITS.each do |field, cap|
      assert_equal cap, fields.dig(field, :maxLength), field
    end
  end

  test "this very answer naming one person twice creates one of them" do
    assert_difference -> { Character.count }, 1 do
      registry.admit!([ sheet(fullname: "Neb Halloran"), sheet(fullname: "Neb Halloran") ])
    end
  end

  # --- the caps --------------------------------------------------------------
  #
  # All three are read back from the records on every candidate rather than
  # counted down from a budget, exactly as `Item::Registry`'s two are: rows are
  # written as the loop goes.

  test "a room at its cap takes nobody new either" do
    Character::Registry::MAX_PER_ROOM.times { create(:character, story: @story, location: @here) }

    assert_no_difference -> { Character.count } do
      registry.admit!([ sheet(fullname: "Neb Halloran") ])
    end
  end

  # A per-room cap bounds nothing on its own: a world generates rooms for as
  # long as somebody keeps walking.
  test "a world at its cap generates rooms with nobody in them" do
    (Character::Registry::MAX_PER_STORY - @story.characters.count).times { create(:character, story: @story) }

    assert_equal 0, registry.world_for_people
    assert_no_difference -> { Character.count } do
      registry.admit!([ sheet(fullname: "Neb Halloran") ])
    end
  end

  test "the allowance is the smallest of the three bounds" do
    assert_equal Character::Registry::MAX_PER_CALL, registry.allowance

    create(:character, story: @story, location: @here)
    create(:character, story: @story, location: @here)

    assert_equal 1, registry.allowance
  end

  # A refusal costs the room a person and never its description: a room realized
  # with one of the two the model named is a good room.
  test "one refused sheet does not lose the other" do
    create(:character, story: @story, fullname: "Neb Halloran")

    people = registry.admit!([ sheet(fullname: "Neb Halloran"), sheet(fullname: "Ammon Brace") ])

    assert_equal [ "Ammon Brace" ], people.map(&:fullname)
  end

  private

  # One entry of `Location::DetailSchema`'s `people` array, as a realization
  # answers with it: string keys, every field of the sheet, and nothing the
  # engine decides.
  def sheet(fullname:, nickname: "Nick")
    { "fullname" => fullname, "nickname" => nickname }.merge(
      Character::Registry::SHEET.to_h { |field| [ field.to_s, "a #{field} line" ] }
    )
  end
end
