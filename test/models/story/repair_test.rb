require "test_helper"

# The safe half of these runs against records only -- no agent is stubbed at all,
# because a repair that reached for a model here would blow up rather than
# quietly cost the captain a call. The generated half uses FakeAgent, the same
# seam every generator test uses.
class Story::RepairTest < ActiveSupport::TestCase
  def story_with_one_way_edge
    story = create(:story)
    opening = create(:location, story: story, name: "Your Office")
    street = create(:location, :stub, story: story, name: "The Street")
    create(:location_connection, location: opening, connected_location: street,
                                 distance: "a short walk", travel_method: "walking")
    create(:character, :protagonist, story: story)
    create(:scene, :opening, story: story, location: opening, story_timestamp: story.start_time)
    story
  end

  test "writes the missing direction of a one-way connection" do
    story = story_with_one_way_edge
    opening = story.locations.find_by(name: "Your Office")
    street = story.locations.find_by(name: "The Street")

    results = Story::Repair.new(story).apply!

    assert_equal [ :one_way_connection ], results.map(&:code)
    assert results.all?(&:repaired?)

    back = LocationConnection.find_by(location: street, connected_location: opening)

    assert back, "the player has to be able to walk back the way they came"
    assert_equal "a short walk", back.distance
    assert_equal "walking", back.travel_method
    # Derived by LocationConnection rather than copied, which is the point of
    # deriving it there.
    assert_equal LocationConnection.find_by(location: opening, connected_location: street).time_to_travel,
                 back.time_to_travel
  end

  test "makes two disagreeing directions agree with the way out" do
    story = story_with_one_way_edge
    opening = story.locations.find_by(name: "Your Office")
    street = story.locations.find_by(name: "The Street")
    create(:location_connection, location: street, connected_location: opening,
                                 distance: "days away", travel_method: "riding")

    results = Story::Repair.new(story).apply!

    assert_equal [ :connection_directions_disagree ], results.map(&:code)
    back = LocationConnection.find_by(location: street, connected_location: opening)

    assert_equal "a short walk", back.distance
    assert_equal "walking", back.travel_method
  end

  test "derives a missing start_time from the story's earliest scene" do
    story = story_with_one_way_edge
    at = story.start_time
    story.update_columns(start_time: nil)

    Story::Repair.new(story.reload).apply!

    assert_in_delta at.to_i, story.reload.start_time.to_i, 1
  end

  test "puts a playthrough with no location back where its scene happens" do
    story = story_with_one_way_edge
    opening = story.locations.find_by(name: "Your Office")
    playthrough = create(:playthrough, story: story, current_location: opening, current_scene: story.opening_scene)
    playthrough.update_columns(current_location_id: nil)

    Story::Repair.new(story.reload).apply!

    assert_equal opening, playthrough.reload.current_location
  end

  # THE LINE THIS WHOLE CLASS TURNS ON. A missing opening arrival can only be
  # written by a model, so an ordinary repair leaves it alone and says so.
  test "does not make a model call unless generation was asked for" do
    story = story_with_one_way_edge
    story.opening_scene.destroy!
    repair = Story::Repair.new(story.reload)

    assert_equal 0, repair.model_calls
    assert_equal [ :no_opening_scene ], repair.deferred.map(&:code)
    # No agent is stubbed: if this reached for one it would raise here.
    results = repair.apply!

    assert_equal [ :one_way_connection ], results.map(&:code)
    assert_nil story.reload.opening_scene
  end

  test "narrates the missing opening arrival when generation is allowed" do
    story = story_with_one_way_edge
    story.opening_scene.destroy!
    repair = Story::Repair.new(story.reload, generate: true)

    assert_equal 1, repair.model_calls

    agent = FakeAgent.new({ "description" => "The door sticks, then gives.", "summary" => "The story opens." })
    results = BaseAgent.stub(:new, agent) { repair.apply! }

    assert_includes results.map(&:code), :no_opening_scene
    assert results.all?(&:repaired?), results.map(&:message).join("\n")

    scene = story.reload.opening_scene

    assert scene
    assert_equal "The door sticks, then gives.", scene.description
    assert_equal story.start_time.to_i, scene.story_timestamp.to_i
  end

  test "writes the exits of a realized room that has none" do
    story = create(:story)
    opening = create(:location, story: story, name: "The Cell")
    create(:character, :protagonist, story: story)
    create(:scene, :opening, story: story, location: opening, story_timestamp: story.start_time)
    repair = Story::Repair.new(story, generate: true)

    assert_equal 1, repair.model_calls

    agent = FakeAgent.new({ "exits" => [ { "name" => "The Corridor", "teaser" => "Cold light under the door.",
                                           "distance" => "adjacent", "travel_method" => "walking" } ] })
    results = BaseAgent.stub(:new, agent) { repair.apply! }

    assert_equal [ :opening_has_no_exits ], results.map(&:code)
    assert results.all?(&:repaired?), results.map(&:message).join("\n")
    assert_equal [ "The Corridor" ], opening.reload.exits.map(&:name)
    # Both directions, the way Location::Generator writes them.
    assert LocationConnection.find_by(location: opening.exits.first, connected_location: opening)
  end

  test "realizes an opening location that is still a stub" do
    story = create(:story)
    create(:location, :stub, story: story, name: "The Drowned Ledger", teaser: "The tide is coming in.")
    repair = Story::Repair.new(story, generate: true)

    assert_equal 2, repair.model_calls, "a room is its detail and then its exits"

    agent = FakeAgent.new(
      { "description" => "Water over the floorboards.", "lore" => "It was a counting house once." },
      { "exits" => [ { "name" => "The Stair", "teaser" => "Up, and dry.", "distance" => "adjacent", "travel_method" => "taking stairs" } ] }
    )
    BaseAgent.stub(:new, agent) { repair.apply! }

    opening = story.reload.opening_location

    assert opening.realized?
    assert_equal "Water over the floorboards.", opening.description
    assert_equal [ "The Stair" ], opening.exits.map(&:name)
  end

  # NEVER INVENT DATA TO MAKE A VALIDATION PASS. A story with nothing to derive
  # from is reported and left exactly as it was.
  test "refuses to repair what would have to be invented" do
    story = create(:story)
    story.update_columns(start_time: nil, summary: nil)
    repair = Story::Repair.new(story, generate: true)

    assert_empty repair.plan
    assert_empty repair.apply!
    assert_includes repair.manual.map(&:code), :no_locations
    assert_includes repair.manual.map(&:code), :missing_start_time
    assert_nil story.reload.start_time
    assert_nil story.summary
  end

  test "a failing repair is reported and does not stop the ones after it" do
    story = story_with_one_way_edge
    story.opening_scene.destroy!
    repair = Story::Repair.new(story.reload, generate: true)

    # An agent with nothing queued raises on the first ask, which is what a
    # missing API key looks like from in here.
    results = BaseAgent.stub(:new, FakeAgent.new) { repair.apply! }

    assert_equal 2, results.size
    assert_equal [ :repaired ], results.select { |r| r.code == :one_way_connection }.map(&:status)
    assert_equal [ :failed ], results.select { |r| r.code == :no_opening_scene }.map(&:status)
  end

  test "a healthy story has nothing to plan, defer or report" do
    story = story_with_one_way_edge
    opening = story.locations.find_by(name: "Your Office")
    street = story.locations.find_by(name: "The Street")
    create(:location_connection, location: street, connected_location: opening,
                                 distance: "a short walk", travel_method: "walking")
    repair = Story::Repair.new(story.reload, generate: true)

    assert_empty repair.plan
    assert_empty repair.deferred
    assert_empty repair.manual
  end
  # THE ANSWER IS ON RECORD IN A CHECKED-IN FILE, which is what makes putting a
  # displaced character back a `safe` repair rather than an invention -- the
  # same argument the connection reversal makes.
  test "puts a seeded character back where the world file places them" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-salt-assizes.yml"))
    neb = story.characters.find_by(fullname: "Neb Halloran")
    neb.move_to!(story.locations.find_by(name: "The Vestry Hulk"))
    repair = Story::Repair.new(story)

    assert_equal [ :character_moved_from_the_seed ], repair.plan.map(&:code)
    assert_equal 0, repair.model_calls

    result = BaseAgent.stub(:new, -> { flunk "a safe repair asked a model something" }) { repair.apply!.sole }

    assert_predicate result, :repaired?
    assert_equal "The Tide Post", neb.reload.location.name
  end

  # THE ONE-TIME PATH for a database seeded before `characters.deliberately_absent`
  # existed: the file says `absent: true`, so nowhere on purpose is on record in
  # the repository and writing the marker costs nothing.
  test "marks a seeded character the world file says is absent on purpose" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    perrin = story.characters.find_by(fullname: "Perrin Lasco")
    perrin.update_column(:deliberately_absent, false)
    repair = Story::Repair.new(story)

    assert_equal [ :character_absent_in_the_seed ], repair.plan.map(&:code)
    assert_equal 0, repair.model_calls

    result = BaseAgent.stub(:new, -> { flunk "a safe repair asked a model something" }) { repair.apply!.sole }

    assert_predicate result, :repaired?
    assert_predicate perrin.reload, :absent?
    assert_predicate Story::Doctor.new(story), :healthy?
  end

  # THE MARKER WINS over a whereabouts, the same way the file wins over a moved
  # character: it is the world's own statement that nobody may be offered this
  # person to speak to.
  test "puts a character marked absent on purpose back to nowhere" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    perrin = story.characters.find_by(fullname: "Perrin Lasco")
    perrin.update_column(:location_id, story.locations.first.id)
    repair = Story::Repair.new(story)

    assert_equal [ :character_absent_but_somewhere ], repair.plan.map(&:code)

    result = repair.apply!.sole

    assert_predicate result, :repaired?
    assert_predicate perrin.reload, :absent?
  end

  # The same finding with the other answer: `character_moved_from_the_seed` can
  # arrive about a character the file marks absent rather than places, and both
  # halves are the file's own statement written back.
  test "puts a character the file marks absent back to nowhere from a room" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    perrin = story.characters.find_by(fullname: "Perrin Lasco")
    perrin.update_columns(deliberately_absent: false, location_id: story.locations.first.id)
    repair = Story::Repair.new(story)

    assert_equal [ :character_moved_from_the_seed ], repair.plan.map(&:code)

    assert_predicate repair.apply!.sole, :repaired?
    assert_predicate perrin.reload, :absent?
  end

  # THE ANSWER IS ON RECORD IN THE TURN LOG: `scenes.resolved_action` and
  # `scenes.acted_on` say which turn took the row, and a turn belongs to one
  # playthrough. So attributing a shared inventory costs no model call.
  test "gives an item the protagonist holds to the playthrough whose turn log took it" do
    story = story_with_one_way_edge
    street = story.locations.find_by(name: "The Street")
    create(:location_connection, location: street, connected_location: story.locations.find_by(name: "Your Office"),
                                 distance: "a short walk", travel_method: "walking")
    played = create(:playthrough, story: story.reload, character: story.protagonist,
                                  current_location: story.locations.find_by(name: "Your Office"))
    stamp = create(:item, character: story.protagonist, name: "ward stamp")
    played.update!(current_scene: create(:scene, story: story, location: played.current_location,
                                                 story_timestamp: story.start_time + 1.hour,
                                                 typed: "take the ward stamp",
                                                 resolved_action: "take", acted_on: stamp))
    repair = Story::Repair.new(story)

    # The same game is also owed its copy of what it has walked past, which is
    # a second safe repair and a different one: this test is about the first.
    assert_includes repair.plan.map(&:code), :protagonist_holds_a_taken_item
    assert_equal 0, repair.model_calls

    results = BaseAgent.stub(:new, -> { flunk "a safe repair asked a model something" }) { repair.apply! }
    result = results.find { |row| row.code == :protagonist_holds_a_taken_item }

    assert_predicate result, :repaired?
    assert_match(/gave ward stamp to playthrough ##{played.id}/, result.message)
    assert_equal played, stamp.reload.playthrough
    assert_nil stamp.character_id
    assert_predicate stamp, :carried?

    # AND THE WORLD IS NOT A THING POORER FOR HER HAVING PICKED IT UP: one of
    # the world's own rows is put back in the room the take happened in.
    assert_match(/put the world's own row back in Your Office/, result.message)
    assert_equal "Your Office", stamp.template.location.name
    assert_predicate stamp.template, :template?
  end

  # ONE FINDING IS ONE ITEM. A repair run that reshuffled a story's whole
  # inventory would be doing something the captain did not ask for, so the
  # backfill is asked for this row's answer and nothing else.
  test "repairing one item leaves the story's starting inventory alone" do
    story = story_with_one_way_edge
    street = story.locations.find_by(name: "The Street")
    create(:location_connection, location: street, connected_location: story.locations.find_by(name: "Your Office"),
                                 distance: "a short walk", travel_method: "walking")
    played = create(:playthrough, story: story.reload, character: story.protagonist,
                                  current_location: story.locations.find_by(name: "Your Office"))
    stamp = create(:item, character: story.protagonist, name: "ward stamp")
    daybook = create(:item, character: story.protagonist, name: "a daybook nobody took")
    played.update!(current_scene: create(:scene, story: story, location: played.current_location,
                                                 story_timestamp: story.start_time + 1.hour,
                                                 typed: "take the ward stamp",
                                                 resolved_action: "take", acted_on: stamp))

    repair = Story::Repair.new(story)
    finding = repair.plan.find { |row| row.code == :protagonist_holds_a_taken_item }
    repair.send(:repair_shared_inventory, finding)

    assert_equal played, stamp.reload.playthrough
    assert_equal story.protagonist, daybook.reload.character
    assert_predicate daybook, :template?
    assert_empty played.carried.by_name(daybook.name), "no copy was handed out by a one-item repair"
  end

  # --- folding what re-seeding a played world left behind --------------------
  #
  # THE ONLY REPAIRS IN THIS CLASS THAT REMOVE A ROW, and the rule they are
  # under is that nothing play created is destroyed: what is on the row a
  # re-seed made is moved onto the row with the history first, and a row
  # anybody has touched is refused.

  test "folds two rooms that are one room onto the one with the history" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    closet = story.locations.find_by(name: "The Supply Closet")
    closet.update!(last_protagonist_visit: story.start_time)
    ghost = create(:location, story: story, name: "Supply Closet", detail_level: "stub", teaser: "The second one.")
    join(story.opening_location, ghost)
    apron = Item.in_story(story).find_by(name: "copy-room apron")
    apron.update!(location: ghost)
    repair = Story::Repair.new(story)

    assert_equal [ :duplicate_locations ], repair.plan.map(&:code)
    assert_equal 0, repair.model_calls

    result = BaseAgent.stub(:new, -> { flunk "a safe repair asked a model something" }) { repair.apply!.sole }

    assert_predicate result, :repaired?
    assert_nil Location.find_by(id: ghost.id)
    assert_equal "The Supply Closet", closet.reload.name
    assert_equal closet, apron.reload.location, "what was on the row a re-seed made moved rather than went with it"
    assert_equal [ "The Supply Closet", "The Long Hallway" ], story.opening_location.exits.reload.pluck(:name)
    assert_predicate Story::Doctor.new(story.reload), :healthy?
  end

  test "refuses to fold two rooms both of which have been stood in" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    story.locations.find_by(name: "The Supply Closet").update!(last_protagonist_visit: story.start_time)
    create(:location, story: story, name: "Supply Closet", detail_level: "stub",
                      teaser: "The second one.", last_protagonist_visit: story.start_time)
    repair = Story::Repair.new(story)

    assert_empty repair.plan
    assert_equal [ :duplicate_locations ], repair.manual.map(&:code)
  end

  test "removes the leftover of a renamed item" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    stamp = Item.in_story(story).find_by(name: "ward stamp")
    leftover = create(:item, name: "Ward Stamp", description: "The second one.", character: nil, location: stamp.location)
    repair = Story::Repair.new(story)

    assert_equal [ :duplicate_items ], repair.plan.map(&:code)

    assert_predicate repair.apply!.sole, :repaired?
    assert_nil Item.find_by(id: leftover.id)
    assert_equal "ward stamp", stamp.reload.name
    assert_predicate Story::Doctor.new(story), :healthy?
  end

  test "closes the doorway a re-seed wrote back over the arrangement the world had moved to" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-lunar-cartographer.yml"))
    story.world_mechanics.sole.update!(last_run_at: story.start_time + 1.day)
    lane = story.locations.find_by(name: "Mournwell Lane")
    circle = story.locations.find_by(name: "Sovereign's Circle")
    join(lane, create(:location, story: story, name: "The Long Quay", detail_level: "stub", teaser: "Barges."))
    join(story.locations.find_by(name: "Larkspur Quarter rooftops"), circle)
    repair = Story::Repair.new(story)

    assert_equal [ :mobile_doorway_re_asserted ], repair.plan.map(&:code)

    assert_predicate repair.apply!.sole, :repaired?
    assert_not_includes lane.exits.reload.pluck(:name), "Sovereign's Circle"
    assert_includes circle.exits.reload.pluck(:name), "Larkspur Quarter rooftops", "the world is still whole"
  end

  # --- the bodies, and the conditions --------------------------------------

  # THE ONE `safe` REPAIR THAT WRITES A NUMBER NOTHING ELSE ON RECORD IMPLIES,
  # and it is safe because the engine is that number's sole author -- the
  # captain's ruling of 2026-09-04. The roll is deterministic, which is what
  # these two assert together: the same body comes back a second time.
  test "rolls a body for somebody who has none" do
    story = create(:story)
    nobody = create(:character, :without_a_stat_block, story: story)
    repair = Story::Repair.new(story)

    assert_includes repair.plan.map(&:code), :character_without_a_stat_block
    assert repair.apply!.all?(&:repaired?)
    assert_predicate nobody.reload, :stat_block?
    assert_includes Character::HIT_DICE, nobody.hit_die
  end

  test "the body it rolls is the one Character::StatBlock would roll again" do
    story = create(:story)
    nobody = create(:character, :without_a_stat_block, story: story)
    wanted = Character::StatBlock.for_existing(nobody)

    Story::Repair.new(story).apply!

    assert_equal [ wanted[:level], wanted[:hit_die] ], [ nobody.reload.level, nobody.hit_die ]
  end

  # A FOE WITH NO BODY, and the same roll behind a louder finding. `Story::Doctor`
  # reports it under its own code because "a monster nothing can fight" is worth
  # saying; what is missing is still a stat block, so the two codes share one
  # handler rather than keeping two copies of one repair.
  test "rolls a body for a foe who has none" do
    story = create(:story)
    monster = create(:character, :monster_without_a_stat_block, story: story)
    repair = Story::Repair.new(story)

    assert_includes repair.plan.map(&:code), :hostile_without_a_stat_block
    assert repair.apply!.all?(&:repaired?)
    assert_predicate monster.reload, :stat_block?
    assert_predicate monster, :hostile?, "repairing a body does not disarm the monster"
    assert_equal Character::StatBlock.for_existing(monster)[:hit_die], monster.hit_die
  end

  # THE ABILITY HALF, and the mirror of the two above. `:safe` on exactly the same
  # argument: nothing on record implies a strength, and the ENGINE is that
  # number's sole author by the captain's ruling of 2026-09-04.
  test "rolls three abilities for somebody who had none" do
    story = create(:story)
    nobody = create(:character, :without_abilities, story: story, level: 2, hit_die: 10)
    repair = Story::Repair.new(story)

    assert_includes repair.plan.map(&:code), :character_without_abilities
    assert repair.apply!.all?(&:repaired?)
    assert_predicate nobody.reload, :abilities?
    assert_equal Character::StatBlock.for_existing(nobody).slice(*Character::ABILITIES),
                 Character::ABILITIES.index_with { |ability| nobody[ability] }
  end

  # THE RECORDS WIN OVER A DERIVATION: repairing the abilities must not rewrite a
  # hand-authored hit die, which is what a seeded world's file says.
  test "rolling the abilities leaves the stat block exactly where it was" do
    story = create(:story)
    nobody = create(:character, :without_abilities, story: story, level: 2, hit_die: 10)

    Story::Repair.new(story).apply!

    assert_equal [ 2, 10 ], [ nobody.reload.level, nobody.hit_die ]
  end

  # A NUMBER 3d6 COULD NEVER HAVE COME UP, re-rolled -- and the whole set, because
  # there is no record of what the intended number was and a set with one engine
  # number in it beside two nobody can account for is not an answer.
  test "re-rolls an ability the engine could never have rolled" do
    story = create(:story)
    somebody = create(:character, story: story)
    Character.where(id: somebody.id).update_all(strength: 25)
    repair = Story::Repair.new(story)

    assert_includes repair.plan.map(&:code), :ability_out_of_range
    assert repair.apply!.all?(&:repaired?)
    assert_includes Character::ABILITY_RANGE, somebody.reload.strength
    assert_equal Character::StatBlock.for_existing(somebody).slice(*Character::ABILITIES),
                 Character::ABILITIES.index_with { |ability| somebody[ability] }
  end

  # A BULK THE ENGINE HAS NO TABLE FOR, CLAMPED TO THE COLUMN'S OWN DEFAULT.
  # `Item::HANDY` is what the schema would have written and what every row
  # already written is, so this puts a value back rather than inventing one.
  test "puts an unknown bulk back to the column's default" do
    story = create(:story)
    room = create(:location, story: story)
    item = create(:item, :lying, location: room, name: "the ward stamp")
    item.update_column(:bulk, "featherweight")
    repair = Story::Repair.new(story)

    assert_includes repair.plan.map(&:code), :item_with_an_unknown_bulk
    assert repair.apply!.all?(&:repaired?)
    assert_equal Item::HANDY, item.reload.bulk
    assert_predicate item, :throwable?
  end

  test "brings a condition back down to what its stat block allows" do
    story = create(:story)
    room = create(:location, story: story)
    rowe = create(:character, story: story, location: room, level: 1, hit_die: 10)
    game = create(:playthrough, story: story, character: create(:character, :protagonist, story: story),
                                current_location: room)
    row = Playthrough::Vitals.instantiate!(game, rowe)
    rowe.update!(hit_die: 6)

    Story::Repair.new(story).apply!

    assert_equal 6, row.reload.hp_current
  end

  test "drops a condition for somebody that game never met" do
    story = create(:story)
    room = create(:location, story: story)
    stranger = create(:character, story: story, location: create(:location, story: story),
                                  level: 1, hit_die: 8)
    game = create(:playthrough, story: story, character: create(:character, :protagonist, story: story),
                                current_location: room)
    row = Playthrough::Vitals.create!(playthrough: game, character: stranger, hp_current: 8)

    Story::Repair.new(story).apply!

    assert_not Playthrough::Vitals.exists?(row.id)
  end

  test "gives a game its own protagonist's condition back" do
    story = create(:story)
    room = create(:location, story: story)
    vance = create(:character, :protagonist, story: story, level: 1, hit_die: 6)
    game = create(:playthrough, story: story, character: vance, current_location: room)
    game.vitals.destroy_all

    Story::Repair.new(story).apply!

    assert_equal 6, game.reload.vitals_for(vance).hp
  end

  private

  # Both directions of one doorway, the way every writer in the app makes one.
  def join(from, to)
    [ [ from, to ], [ to, from ] ].each do |origin, destination|
      create(:location_connection, location: origin, connected_location: destination,
                                   distance: "adjacent", travel_method: "walking")
    end
  end

  # --- a copy that lags the world's own row ---------------------------------

  # THE SLATE. A seed file gave the tide-slate its words the morning after the
  # world was seeded; a re-seed writes them onto the world's own row and stops
  # there, because re-asserting a file must never reach into a game in progress.
  # This is what carries them into the copies nobody has handled.
  def story_with_a_lagging_copy
    story = create(:story)
    room = create(:location, story: story, name: "Your Office")
    street = create(:location, :stub, story: story, name: "The Street")
    [ [ room, street ], [ street, room ] ].each do |from, to|
      create(:location_connection, location: from, connected_location: to,
                                   distance: "a short walk", travel_method: "walking")
    end
    create(:character, :protagonist, story: story)
    create(:scene, :opening, story: story, location: room, story_timestamp: story.start_time)
    played = create(:playthrough, story: story, character: story.protagonist, current_location: room)
    template = create(:item, :lying, location: room, name: "assize tide-slate")
    copy = create(:item, :lying, location: room, playthrough: played, template: template,
                                 name: template.name, description: template.description)
    template.update!(readable: true, inscription: "Three hours forty after noon.")

    [ story, played, copy.reload ]
  end

  test "brings an untouched copy forward to what the world now says" do
    story, _played, copy = story_with_a_lagging_copy

    results = Story::Repair.new(story).apply!

    assert_includes results.map(&:code), :copy_lags_its_template
    assert results.select { |result| result.code == :copy_lags_its_template }.all?(&:repaired?)

    copy.reload
    assert_predicate copy, :readable?
    assert_equal "Three hours forty after noon.", copy.inscription
    assert_equal "Your Office", copy.location.name, "a repair moved a thing in somebody's game"
  end

  test "a copy a turn has acted on is left exactly as it stands" do
    story, _played, copy = story_with_a_lagging_copy
    create(:scene, story: story, location: copy.location, resolved_action: "take", acted_on: copy)

    results = Story::Repair.new(story).apply!

    assert_not_includes results.map(&:code), :copy_lags_its_template
    assert_not_predicate copy.reload, :readable?
    assert_nil copy.inscription
    assert_includes Story::Repair.new(story).manual.map(&:code), :touched_copy_lags_its_template
  end

  test "a second run has nothing left to bring forward" do
    story, = story_with_a_lagging_copy
    Story::Repair.new(story).apply!

    assert_not_includes Story::Repair.new(story).plan.map(&:code), :copy_lags_its_template
  end

  # --- what a fight can leave behind -----------------------------------------

  # THE REPAIR IS `Playthrough::Turn#spill!` ITSELF -- the same statement
  # `#harm!` makes in the transaction that takes the last hit point -- so it
  # writes nothing the engine would not have written, and every value it uses is
  # already on record.
  test "a dead body holding things is emptied onto the floor of the room it is in" do
    story = create(:story)
    room = create(:location, story: story)
    rowe = create(:character, story: story, location: room, level: 1, hit_die: 8)
    game = create(:playthrough, story: story, character: create(:character, :protagonist, story: story),
                                current_location: room)
    Playthrough::Vitals.instantiate!(game, rowe).update!(hp_current: 0)
    template = create(:item, character: rowe, name: "bell-rope tally")
    copy = create(:item, playthrough: game, character: rowe, name: "bell-rope tally", template: template)

    results = Story::Repair.new(story).apply!

    assert_includes results.map(&:code), :dead_body_holding_things
    assert_equal room, copy.reload.location
    assert_nil copy.character
    assert_equal rowe, template.reload.character, "the world's own row never moved"
    assert_empty Story::Doctor.new(story).findings.select { |f| f.code == :dead_body_holding_things }
  end

  # THE ANSWER IS ON RECORD: zero hit points ends a playthrough (the captain's
  # ruling of 2026-09-04), and `Playthrough#end!` dates it at that game's own
  # story clock.
  test "a player at zero in a game that is not over ends the game" do
    story = create(:story)
    room = create(:location, story: story)
    vance = create(:character, :protagonist, story: story, level: 1, hit_die: 8)
    game = create(:playthrough, story: story, character: vance, current_location: room)
    Playthrough::Vitals.instantiate!(game, vance).update!(hp_current: 0)

    results = Story::Repair.new(story).apply!

    assert_includes results.map(&:code), :playthrough_dead_but_not_ended
    assert_predicate game.reload, :over?
    assert_equal game.story_now, game.ended_at
  end

  # NO REPAIR, AND IT IS STATED: deleting the row would erase a fight the
  # records say happened, and clearing the mark alone would tell a live foe to
  # stop fighting.
  test "a fight with somebody never met is left for a person to look at" do
    story = create(:story)
    room = create(:location, story: story)
    elsewhere = create(:location, story: story)
    stranger = create(:character, story: story, location: elsewhere, level: 1, hit_die: 8)
    game = create(:playthrough, story: story, character: create(:character, :protagonist, story: story),
                                current_location: room)
    Playthrough::Vitals.create!(playthrough: game, character: stranger, hp_current: 8,
                               provoked_at: game.story_now)

    repair = Story::Repair.new(story)

    assert_includes repair.manual.map(&:code), :provoked_without_a_meeting
    assert_not_includes repair.plan.map(&:code), :provoked_without_a_meeting
  end
end
