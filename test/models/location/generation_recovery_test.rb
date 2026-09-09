require "test_helper"

class Location::GenerationRecoveryTest < ActiveSupport::TestCase
  DETAIL = {
    "description" => "A brass token lies beside Sella at the workbench.",
    "lore" => "Sella keeps the town's oldest workshop.",
    "items" => [ { "name" => "brass token", "description" => "A small brass disc." } ],
    "people" => [ {
      "fullname" => "Sella Reed", "nickname" => "Sella", "appearance" => "A patched apron.",
      "personality" => "Patient and careful.", "backstory" => "A lifelong maker of keys.",
      "likes" => "Honest work.", "dislikes" => "Waste.", "fears" => "Fire."
    } ]
  }.freeze
  EXITS = { "exits" => [ {
    "name" => "Back Lane", "teaser" => "A narrow lane.",
    "distance" => "adjacent", "travel_method" => "walking"
  } ] }.freeze

  setup do
    @story = create(:story)
    @location = create(:location, :stub, story: @story, name: "Workshop", population: "a person or two")
  end

  test "automatic re-entry finishes paid detail without duplicating items or people" do
    failed = FakeAgent.new(DETAIL, IOError.new("provider disconnected"))
    assert_raises(IOError) { realize(failed) }
    assert_predicate @location.reload, :stub?
    assert_equal "exits_pending", @location.generation_checkpoint.fetch("phase")
    item = @location.items.templates.sole
    person = @location.characters.sole

    resumed = FakeAgent.new(EXITS)
    realize(resumed)

    assert_predicate @location.reload, :realized?
    assert_nil @location.generation_checkpoint
    assert_equal [ item.id ], @location.items.templates.pluck(:id)
    assert_equal [ person.id ], @location.characters.pluck(:id)
    assert_equal [ "Back Lane" ], @location.exits.pluck(:name)
    assert_equal [ "Location::ExitsSchema" ], resumed.schemas.map(&:name)
    BaseAgent.stub(:new, ->(*) { flunk "a completed room cannot regenerate" }) { realize(nil) }
  end

  test "failed admissions roll back together and retry restores the original described slots" do
    generator = Location::Generator.new(@location)
    registry = generator.cast_registry
    original = registry.method(:admit!)
    paid = FakeAgent.new(DETAIL)
    failure = ->(people) { original.call(people); raise IOError, "lost writer after cast admission" }

    assert_raises(IOError) do
      registry.stub(:admit!, failure) { BaseAgent.stub(:new, paid) { generator.realize! } }
    end

    assert_predicate @location.reload, :stub?
    assert_nil @location.description
    assert_empty @location.items
    assert_empty @location.characters
    slots = @location.generation_checkpoint.fetch("slots")
    resumed = Location::Generator.new(Location.find(@location.id))
    assert_equal slots.map { |slot| slot.fetch("race_id") }, resumed.cast_registry.slots.map { |slot| slot.fetch(:race).id }
    assert_equal slots.map { |slot| slot.fetch("age") }, resumed.cast_registry.slots.map { |slot| slot.fetch(:age) }
    assert_equal slots.map { |slot| slot.fetch("sex") }, resumed.cast_registry.slots.map { |slot| slot.fetch(:sex) }

    provider = FakeAgent.new(EXITS)
    BaseAgent.stub(:new, provider) { resumed.realize! }
    assert_equal 1, @location.items.templates.count
    assert_equal 1, @location.characters.count
    assert_equal slots.first.fetch("race_id"), @location.characters.sole.race_id
    assert_equal [ "Location::ExitsSchema" ], provider.schemas.map(&:name)
  end

  test "failed finalization rolls back all edges but preserves accepted exits for a model-free retry" do
    assert_raises(IOError) do
      Quest::Deadline.stub(:after_realizing!, ->(*) { raise IOError, "deadline write failed" }) do
        realize(FakeAgent.new(DETAIL, EXITS))
      end
    end

    assert_predicate @location.reload, :stub?
    assert_empty @location.exits
    assert_equal [ "Workshop" ], @story.locations.pluck(:name)
    assert_equal EXITS.fetch("exits"), @location.generation_checkpoint.fetch("exits")
    BaseAgent.stub(:new, ->(*) { flunk "both provider answers already succeeded" }) do
      Location::Generator.new(Location.find(@location.id)).realize!
    end
    assert_predicate @location.reload, :realized?
    assert_nil @location.generation_checkpoint
    assert_equal [ "Back Lane" ], @location.exits.pluck(:name)
    assert_equal 2, LocationConnection.where(location_id: @story.locations.select(:id)).count
    assert_equal 1, @location.items.templates.count
    assert_equal 1, @location.characters.count
  end

  test "a building whose finalization fails keeps the original entrance so the next entry can resume it" do
    @location.update!(width: 12, depth: 8)
    street = create(:location, story: @story, name: "Street")
    create(:location_connection, location: street, connected_location: @location)
    create(:location_connection, location: @location, connected_location: street)

    assert_raises(IOError) do
      Quest::Deadline.stub(:after_realizing!, ->(*) { raise IOError, "deadline write failed" }) do
        realize(FakeAgent.new(DETAIL))
      end
    end
    assert_predicate @location.reload, :stub?
    assert_equal "detail_pending", @location.generation_checkpoint.fetch("phase")
    assert_empty @location.child_locations
    assert_nil @location.description
    assert_equal [ @location.id ], street.exits.pluck(:id)

    BaseAgent.stub(:new, ->(*) { flunk "the accepted building detail must be reused" }) { realize(nil) }

    assert_predicate @location.reload, :realized?
    assert_nil @location.generation_checkpoint
    assert_predicate @location.child_locations, :exists?
    assert_not_includes street.exits.pluck(:id), @location.id
    assert street.exits.all? { |room| room.parent_location_id == @location.id }
  end

  test "invalid detail is not cached as an answer every retry must fail" do
    assert_raises(ActiveRecord::RecordInvalid) { realize(FakeAgent.new(DETAIL.merge("description" => ""))) }
    assert_nil @location.reload.generation_checkpoint
    assert_empty @location.items
    realize(FakeAgent.new(DETAIL, EXITS))
    assert_predicate @location.reload, :realized?
  end

  test "a prewarmed waiting generator discards its rolls in favor of the committed slots" do
    waiting = Location::Generator.new(Location.find(@location.id))
    waiting.cast_registry.slots
    producing = Location::Generator.new(@location)
    producing.cast_registry.slots.each { |slot| slot[:age] = 99 }
    assert_raises(IOError) do
      producing.registry.stub(:admit!, ->(*) { raise IOError, "interrupted before admission" }) do
        BaseAgent.stub(:new, FakeAgent.new(DETAIL)) { producing.realize! }
      end
    end
    BaseAgent.stub(:new, FakeAgent.new(EXITS)) { waiting.realize! }
    assert_equal 99, @location.characters.sole.age
  end

  test "invalid exits are not cached and the next entry asks only for exits" do
    invalid = { "exits" => [ EXITS.fetch("exits").first.merge("travel_method" => "teleporting") ] }
    assert_raises(ActiveRecord::RecordInvalid) { realize(FakeAgent.new(DETAIL, invalid)) }
    assert_not @location.reload.generation_checkpoint.key?("exits")
    resumed = FakeAgent.new(EXITS)
    realize(resumed)
    assert_equal [ "Location::ExitsSchema" ], resumed.schemas.map(&:name)
  end

  # AN UNUSABLE LABEL ON AN EDGE THIS ROOM WILL NOT WRITE. The eager check used
  # to validate every proposal, so a name #connect_exit! was always going to
  # drop failed the realization the entry had paid for -- and the pinned detail
  # checkpoint could be refused the same way on every retry.
  test "an unusable label on an already written neighbour discards only that door" do
    create(:location, story: @story, name: "Old Mill")
    answer = { "exits" => [
      EXITS.fetch("exits").first,
      { "name" => "Old Mill", "teaser" => "A shuttered mill.",
        "distance" => "adjacent", "travel_method" => "teleporting" }
    ] }

    realize(FakeAgent.new(DETAIL, answer))

    assert_predicate @location.reload, :realized?
    assert_nil @location.generation_checkpoint
    assert_equal [ "Back Lane" ], @location.exits.pluck(:name)
    assert_empty Location.find_by!(name: "Old Mill").exits
  end

  # The same rule for the room naming ITSELF under another spelling: the check
  # matched on `casecmp?` while `#connect_exit!` drops a natural-key match, so
  # "The Workshop" was validated and then never written.
  test "an unusable label on this room's own name under an article discards only that door" do
    answer = { "exits" => [
      EXITS.fetch("exits").first,
      { "name" => "The Workshop", "teaser" => "The same workbench.",
        "distance" => "adjacent", "travel_method" => "teleporting" }
    ] }

    realize(FakeAgent.new(DETAIL, answer))

    assert_predicate @location.reload, :realized?
    assert_nil @location.generation_checkpoint
    assert_equal [ "Back Lane" ], @location.exits.pluck(:name)
  end

  # AND THE FORCED PASS IS STILL VALIDATED, which is why the check asks twice
  # rather than skipping every written destination: with no ordinary exit left,
  # `into_written:` opens onto an already-written neighbour, so that edge's
  # label is the one that decides whether the answer is worth keeping.
  test "an unusable label on the only door the forced pass can open is refused" do
    create(:location, story: @story, name: "Old Mill")
    answer = { "exits" => [ { "name" => "Old Mill", "teaser" => "A shuttered mill.",
                              "distance" => "adjacent", "travel_method" => "teleporting" } ] }

    assert_raises(ActiveRecord::RecordInvalid) { realize(FakeAgent.new(DETAIL, answer)) }

    assert_predicate @location.reload, :stub?
    assert_not @location.generation_checkpoint.key?("exits")
    assert_empty @location.exits
  end

  test "the forced pass still opens onto an already written neighbour when nothing else survives" do
    mill = create(:location, story: @story, name: "Old Mill")
    answer = { "exits" => [ { "name" => "Old Mill", "teaser" => "A shuttered mill.",
                              "distance" => "adjacent", "travel_method" => "walking" } ] }

    realize(FakeAgent.new(DETAIL, answer))

    assert_predicate @location.reload, :realized?
    assert_equal [ "Old Mill" ], @location.exits.pluck(:name)
    assert_equal [ @location.name ], mill.reload.exits.pluck(:name)
  end

  # WHAT THE WRITER DROPS CANNOT STRAND THE ROOM, and these four are the cases
  # a check that read the whole answer against the graph as it arrived got
  # wrong. Every one of them is a proposal `#connect_exit!` never writes a row
  # for, so its label is never read -- and the paid detail the entry committed
  # has to open the room anyway.
  #
  # THE ORDINARY GENERATED STUB IS THE FIRST ONE: it is born with the door its
  # neighbour wrote, so the forced pass never runs for it, and a label on a
  # written room it cannot reach was refused by a fallback the writer would
  # never have taken.
  test "an unusable label on a written neighbour cannot fail a room that already has a door" do
    way_back = create(:location, story: @story, name: "Way Back")
    create(:location_connection, location: @location, connected_location: way_back)
    create(:location_connection, location: way_back, connected_location: @location)
    create(:location, story: @story, name: "Old Mill")
    answer = { "exits" => [ { "name" => "Old Mill", "teaser" => "A shuttered mill.",
                              "distance" => "adjacent", "travel_method" => "teleporting" } ] }

    realize(FakeAgent.new(DETAIL, answer))

    assert_predicate @location.reload, :realized?
    assert_nil @location.generation_checkpoint
    assert_equal [ "Way Back" ], @location.exits.pluck(:name)
    assert_empty Location.find_by!(name: "Old Mill").exits
  end

  # THE WAY BACK, NAMED AGAIN. Both directions already exist, so #connect!
  # writes nothing and the labels never reach a row -- and the door keeps the
  # values it was written with.
  test "an unusable label on the door this room already has changes nothing" do
    lane = create(:location, story: @story, name: "Back Lane")
    create(:location_connection, location: @location, connected_location: lane, distance: "adjacent")
    create(:location_connection, location: lane, connected_location: @location, distance: "adjacent")
    answer = { "exits" => [ EXITS.fetch("exits").first.merge("travel_method" => "teleporting") ] }

    realize(FakeAgent.new(DETAIL, answer))

    assert_predicate @location.reload, :realized?
    assert_equal [ "Back Lane" ], @location.exits.pluck(:name)
    assert_equal "walking",
                 LocationConnection.find_by!(location: @location, connected_location: lane).travel_method
  end

  # A SECOND SPELLING OF A DOOR THIS ANSWER JUST WROTE. The first proposal
  # supplies the pair, so the alias resolves to it and writes nothing.
  test "an unusable label on a second spelling of a door just written changes nothing" do
    answer = { "exits" => [
      EXITS.fetch("exits").first,
      { "name" => "The Back Lane", "teaser" => "The same lane.",
        "distance" => "adjacent", "travel_method" => "teleporting" }
    ] }

    realize(FakeAgent.new(DETAIL, answer))

    assert_predicate @location.reload, :realized?
    assert_equal [ "Back Lane" ], @location.exits.pluck(:name)
    assert_equal [ "Workshop", "Back Lane" ], @story.locations.order(:id).pluck(:name)
  end

  # AND A PROPOSAL PAST THE ROOM'S ALLOWANCE. The writer stops the moment the
  # cap is full, so the door it stopped before is not a door at all.
  test "an unusable label past this room's allowance is discarded with the door" do
    (Location::ExitsSchema::MAX_EXITS - 1).times do |index|
      neighbour = create(:location, story: @story, name: "Existing #{index}")
      create(:location_connection, location: @location, connected_location: neighbour)
      create(:location_connection, location: neighbour, connected_location: @location)
    end
    answer = { "exits" => [
      EXITS.fetch("exits").first,
      { "name" => "Discarded Extra", "teaser" => "A door too far.",
        "distance" => "adjacent", "travel_method" => "teleporting" }
    ] }

    realize(FakeAgent.new(DETAIL, answer))

    assert_predicate @location.reload, :realized?
    assert_includes @location.exits.pluck(:name), "Back Lane"
    assert_equal Location::ExitsSchema::MAX_EXITS, @location.exits.count
    assert_nil Location.find_by(name: "Discarded Extra")
  end

  # The same rule at the FAR end of the door: a neighbour already carrying its
  # own cap takes no more, so that proposal is never written either.
  test "an unusable label on a neighbour already at its own cap discards only that door" do
    crowded = create(:location, :stub, story: @story, name: "Crowded Door")
    Location::ExitsSchema::MAX_EXITS.times do |index|
      neighbour = create(:location, story: @story, name: "Far Existing #{index}")
      create(:location_connection, location: crowded, connected_location: neighbour)
      create(:location_connection, location: neighbour, connected_location: crowded)
    end
    answer = { "exits" => [
      EXITS.fetch("exits").first,
      { "name" => "Crowded Door", "teaser" => "A busy doorway.",
        "distance" => "adjacent", "travel_method" => "teleporting" }
    ] }

    realize(FakeAgent.new(DETAIL, answer))

    assert_predicate @location.reload, :realized?
    assert_equal [ "Back Lane" ], @location.exits.pluck(:name)
    assert_not_includes crowded.reload.exits.pluck(:name), @location.name
  end

  # AND THE OTHER HALF OF THE RULE: A LABEL THAT IS USED IS STILL REFUSED. Half
  # a pair exists, so this room's own direction is a row that has to be written
  # -- and an answer whose labels no retry could write is dropped rather than
  # replayed, while the paid detail beside it is kept.
  test "an unusable label on the missing half of a door is refused and its answer dropped" do
    lane = create(:location, story: @story, name: "Back Lane")
    create(:location_connection, location: lane, connected_location: @location, distance: "adjacent")
    answer = { "exits" => [ EXITS.fetch("exits").first.merge("travel_method" => "teleporting") ] }

    assert_raises(ActiveRecord::RecordInvalid) { realize(FakeAgent.new(DETAIL, answer)) }

    assert_predicate @location.reload, :stub?
    assert_equal "exits_pending", @location.generation_checkpoint.fetch("phase")
    assert_not @location.generation_checkpoint.key?("exits")
    assert_empty @location.exits

    resumed = FakeAgent.new(EXITS)
    realize(resumed)

    assert_equal [ "Location::ExitsSchema" ], resumed.schemas.map(&:name)
    assert_predicate @location.reload, :realized?
    assert_equal [ "Back Lane" ], @location.exits.pluck(:name)
  end

  test "the missing half of a door is written from the answer's own labels" do
    lane = create(:location, story: @story, name: "Back Lane")
    create(:location_connection, location: lane, connected_location: @location, distance: "adjacent")
    answer = { "exits" => [ EXITS.fetch("exits").first.merge("travel_method" => "climbing") ] }

    realize(FakeAgent.new(DETAIL, answer))

    assert_predicate @location.reload, :realized?
    written = LocationConnection.find_by!(location: @location, connected_location: lane)
    assert_equal "climbing", written.travel_method
    assert_equal "adjacent", written.distance
  end

  test "a successful run builds the same exits request while completion is still pending" do
    generator = Location::Generator.new(@location)
    provider = FakeAgent.new(DETAIL, EXITS)
    states = []
    provider.define_singleton_method(:ask) do |*args, **kwargs|
      states << generator.location.reload.detail_level
      super(*args, **kwargs)
    end
    BaseAgent.stub(:new, provider) { generator.realize! }

    assert_equal %w[stub stub], states
    expected = generator.exits_prompt
    # Remove the generated neighbour when rebuilding the original request.
    @location.exits.destroy_all
    @story.locations.where.not(id: @location.id).destroy_all
    assert_equal provider.prompts.last, generator.exits_prompt
    assert_not_equal expected, generator.exits_prompt
  end

  test "resumed exits continue the original persisted conversation without paying its detail again" do
    detail = DETAIL.merge("name" => "Workshop")
    first_game = create(:playthrough, story: @story)
    second_game = create(:playthrough, story: @story)
    OfflineExchange.with(detail) do
      assert_raises(RuntimeError) { Location::Generator.new(@location, playthrough: first_game).realize! }
    end
    conversation = Chat.find(@location.reload.generation_checkpoint.fetch("chat_id"))
    original_messages = conversation.exchange_messages.pluck(:id)
    assert_equal 2, original_messages.length
    assert_equal detail, conversation.messages.where(role: "assistant").sole.content_raw

    OfflineExchange.with(EXITS) do
      Location::Generator.new(Location.find(@location.id), playthrough: second_game).realize!
    end

    assert_predicate @location.reload, :realized?
    assert_equal 1, Chat.where(purpose: "location").count
    assert_equal first_game, conversation.reload.playthrough
    assert_equal original_messages, conversation.exchange_messages.limit(2).pluck(:id)
    assert_equal 4, conversation.exchange_messages.count
    assert_equal 1, conversation.messages.where(role: "assistant").filter_map { |message| message.content_raw&.fetch("description", nil) }.count
    assert_includes conversation.messages.where(role: "user").last.content, "Now list the ways out of Workshop"
  end

  test "an NPC history budget of zero cannot prune the paid location description" do
    with_paid_detail do |conversation|
      original = Chat.instance_method(:prune_history!)
      Chat.define_method(:prune_history!) { original.bind_call(self, exchanges: 0) }
      begin
        OfflineExchange.with(EXITS) { realize(nil) }
      ensure
        Chat.define_method(:prune_history!, original)
      end
      assert_equal 4, conversation.exchange_messages.count
      assert_equal DETAIL["description"], conversation.messages.where(role: "assistant").first.content_raw.fetch("description")
    end
  end

  test "deleting the originating playthrough restores paid context from the world checkpoint" do
    with_paid_detail do |conversation|
      old_chat_id = conversation.id
      original_prompt = @location.reload.generation_checkpoint.fetch("prompt")
      conversation.playthrough.destroy!
      assert_not Chat.exists?(old_chat_id)
      next_game = create(:playthrough, story: @story)

      OfflineExchange.with(EXITS) do
        Location::Generator.new(Location.find(@location.id), playthrough: next_game).realize!
      end

      replacement = next_game.chats.where(purpose: "location").sole
      assert_equal original_prompt, replacement.messages.where(role: "user").first.content
      restored = replacement.messages.where(role: "assistant").first
      assert_equal DETAIL["description"], restored.content_raw.fetch("description")
      assert_nil restored.input_tokens
      assert_nil restored.output_tokens
      assert_equal 4, replacement.exchange_messages.count
      assert_predicate @location.reload, :realized?
    end
  end

  private

  def with_paid_detail
    game = create(:playthrough, story: @story)
    OfflineExchange.with(DETAIL.merge("name" => "Workshop")) do
      assert_raises(RuntimeError) { Location::Generator.new(@location, playthrough: game).realize! }
    end
    yield Chat.find(@location.reload.generation_checkpoint.fetch("chat_id"))
  end

  def realize(provider)
    return Location::Generator.new(Location.find(@location.id)).realize! if provider.nil?

    BaseAgent.stub(:new, provider) { Location::Generator.new(Location.find(@location.id)).realize! }
  end
end
