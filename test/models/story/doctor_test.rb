require "test_helper"

# Every check in Story::Doctor mirrors a precondition the play path really has,
# so each test here breaks a story the way the database can really break it and
# asserts the sentence a person would get back.
class Story::DoctorTest < ActiveSupport::TestCase
  # A story shaped like `rake game:new` leaves one: a realized opening room with
  # a way out, an opening arrival, and somebody to be.
  def healthy_story
    story = create(:story)
    opening = create(:location, story: story, name: "Your Office")
    elsewhere = create(:location, :stub, story: story, name: "The Street")
    connect(opening, elsewhere)
    create(:character, :protagonist, story: story)
    create(:scene, :opening, story: story, location: opening, story_timestamp: story.start_time)
    story
  end

  def connect(from, to, distance: "adjacent", travel_method: "walking")
    [ [ from, to ], [ to, from ] ].map do |location, connected|
      create(:location_connection, location: location, connected_location: connected,
                                   distance: distance, travel_method: travel_method)
    end
  end

  def codes(story)
    Story::Doctor.new(story).findings.map(&:code)
  end

  # THE SHAPE OF AN OLD DATABASE: an item on the story's one protagonist row
  # that one playthrough's turn log records taking. Returns the pair.
  def a_shared_inventory(story)
    played = create(:playthrough, story: story, character: story.protagonist,
                                  current_location: story.locations.first)
    item = create(:item, character: story.protagonist, name: "ward stamp")
    played.update!(current_scene: create(:scene, story: story, location: story.locations.first,
                                                 story_timestamp: story.start_time + 1.hour,
                                                 typed: "take the ward stamp",
                                                 resolved_action: "take", acted_on: item))
    [ played, item ]
  end

  def finding(story, code)
    Story::Doctor.new(story).findings.find { |f| f.code == code }
  end

  test "a story generated the way the game generates them is healthy" do
    doctor = Story::Doctor.new(healthy_story)

    assert_empty doctor.findings, doctor.findings.map(&:message).join("\n")
    assert doctor.playable?
    assert doctor.healthy?
    assert_equal "healthy", doctor.headline
  end

  # THE CHECK THE APP ALREADY MAKES. PlaythroughsController#opening_location
  # takes the first REALIZED location and refuses the story when there is none.
  test "a story whose every location is still a stub is unplayable" do
    story = create(:story)
    create(:location, :stub, story: story)

    doctor = Story::Doctor.new(story)

    assert_not doctor.playable?
    assert_includes doctor.findings.map(&:code), :no_realized_location
    assert_equal :generate, finding(story, :no_realized_location).remedy
    assert_match(/still a stub/, doctor.headline)
  end

  test "a story with no locations at all cannot be repaired" do
    story = create(:story)

    found = finding(story, :no_locations)

    assert found
    assert found.fatal?
    assert_equal :manual, found.remedy
    assert_match(/nothing on record to derive one from/, found.message)
  end

  # Story#opening_location is the lowest-id location and is what
  # Scene::Generator.opening and the exporter mean; the controller starts play
  # in the first REALIZED one. When they disagree the story plays from
  # somewhere the rest of the code does not think it opens in.
  test "reports an opening location that is a stub while play starts elsewhere" do
    story = create(:story)
    declared = create(:location, :stub, story: story, name: "The Rope Bridge")
    played = create(:location, story: story, name: "The Counting House")
    connect(declared, played)

    found = finding(story, :opening_location_is_a_stub)

    assert found
    assert_not found.fatal?, "the story still opens, in the realized room"
    assert_equal declared, found.subject
    assert_match(/The Counting House/, found.message)
    assert_match(/The Rope Bridge/, found.message)
  end

  # The documented cost of saving a room's description before asking for its
  # exits: realize! returns an already-realized room untouched, so one whose
  # exits call failed stays exitless forever.
  test "an opening room with no exits is fatal and a dead end elsewhere is a warning" do
    story = create(:story)
    opening = create(:location, story: story, name: "The Cell")
    stranded = create(:location, story: story, name: "The Sump")
    story.reload

    doctor = Story::Doctor.new(story)
    opening_finding = doctor.findings.find { |f| f.code == :opening_has_no_exits }
    stranded_finding = doctor.findings.find { |f| f.code == :location_has_no_exits }

    assert opening_finding
    assert opening_finding.fatal?
    assert_equal opening, opening_finding.subject
    assert stranded_finding
    assert_not stranded_finding.fatal?
    assert_equal stranded, stranded_finding.subject
    assert_equal :generate, stranded_finding.remedy
  end

  test "a story with no opening arrival is playable but warned about" do
    story = healthy_story
    story.opening_scene.destroy!

    doctor = Story::Doctor.new(story.reload)

    assert doctor.playable?
    assert_includes doctor.findings.map(&:code), :no_opening_scene
    assert_equal :generate, finding(story, :no_opening_scene).remedy
    assert_match(/game:export/, finding(story, :no_opening_scene).message)
  end

  # A connection is two rows written from one answer. A missing reverse means
  # the player walks somewhere and cannot walk back.
  test "reports a connection that exists in only one direction" do
    story = healthy_story
    LocationConnection.where(location: story.locations.find_by(name: "The Street")).delete_all

    found = finding(story.reload, :one_way_connection)

    assert found
    assert_equal :safe, found.remedy
    assert_match(/cannot walk there and not back|walk there and not back/, found.message)
  end

  test "reports two directions of one edge that disagree" do
    story = healthy_story
    street = story.locations.find_by(name: "The Street")
    LocationConnection.find_by(location: street).update_columns(distance: "days away", travel_method: "riding")

    found = finding(story.reload, :connection_directions_disagree)

    assert found
    assert_equal :safe, found.remedy
    assert_match(/disagree/, found.message)
  end

  test "reports a distance that is not one of the fixed values" do
    story = healthy_story
    LocationConnection.where(location: story.locations).update_all(distance: "a bit of a walk")

    found = finding(story.reload, :unknown_distance)

    assert found
    assert_equal :manual, found.remedy
  end

  # Nothing crashes without a protagonist -- the cast list compacts -- but the
  # player is nobody, so it is reported rather than repaired: which character
  # ought to be the player is not derivable from anything.
  test "reports a story with no protagonist and never offers to pick one" do
    story = healthy_story
    story.protagonist.update!(is_protagonist: false)

    found = finding(story.reload, :no_protagonist)

    assert found
    assert_not found.fatal?
    assert_equal :manual, found.remedy
    assert_match(/is_protagonist/, found.message)
  end

  test "reports a character whose race belongs to another universe" do
    story = healthy_story
    stranger = create(:race, universe: create(:universe))
    character = story.characters.first
    character.update_columns(race_id: stranger.id)

    found = finding(story.reload, :character_race_from_another_universe)

    assert found
    assert_equal :manual, found.remedy
    assert_equal character, found.subject
    assert_match(/inventing who they are/, found.message)
  end

  # Story#clock falls back to start_time, and every turn stamps its scene from
  # it -- without one the first turn raises on `nil + minutes`.
  test "a story with no start_time is unplayable, and derivable when it has scenes" do
    story = healthy_story
    at = story.start_time
    story.update_columns(start_time: nil)

    found = finding(story.reload, :missing_start_time)

    assert found
    assert found.fatal?
    assert_equal :safe, found.remedy, "the story's earliest scene is at #{at}"
  end

  test "a story with no start_time and no scenes cannot be repaired" do
    story = create(:story)
    create(:location, story: story)
    story.update_columns(start_time: nil)

    assert_equal :manual, finding(story.reload, :missing_start_time).remedy
  end

  # Location has_many :playthroughs, dependent: :nullify -- so a destroyed room
  # leaves its players standing nowhere, and a player standing nowhere has no
  # exits to be offered and can never move again.
  test "reports a playthrough left standing nowhere and can place it from its scene" do
    story = healthy_story
    opening = story.locations.find_by(name: "Your Office")
    scene = story.opening_scene
    playthrough = create(:playthrough, story: story, current_location: opening, current_scene: scene)
    playthrough.update_columns(current_location_id: nil)

    found = finding(story.reload, :playthrough_without_location)

    assert found
    assert_equal :safe, found.remedy
    assert_equal playthrough, found.subject
    assert_match(/Your Office/, found.message)
  end

  test "reports a universe with no races" do
    story = healthy_story
    story.characters.destroy_all
    Race.where(universe: story.universe).destroy_all

    assert_includes codes(story.reload), :universe_without_races
  end

  test "Doctor.all covers every story oldest first" do
    first = create(:story, created_at: 2.days.ago)
    second = create(:story, created_at: 1.day.ago)

    assert_equal [ first.id, second.id ], Story::Doctor.all.map { |doctor| doctor.story.id }
  end

  # The doctor reports; it never writes. A tool that repaired as a side effect
  # of being asked what was wrong would be unusable on the captain's own data.
  test "diagnosing changes nothing" do
    story = healthy_story
    story.opening_scene.destroy!
    story.locations.find_by(name: "The Street").destroy!

    before = Location.count + Scene.count + Character.count + LocationConnection.count
    Story::Doctor.new(story.reload).findings

    assert_equal before, Location.count + Scene.count + Character.count + LocationConnection.count
  end

  # --- the item registry ----------------------------------------------------
  #
  # `Item::Registry` refuses every one of these at the moment it writes, so a
  # world generated since it landed cannot show one. A world here outlives the
  # code that made it -- a seed file, a hand-written row, an older build -- and
  # the first thing that would otherwise notice is the classifier resolving one
  # word two ways, mid-turn.

  test "a story with things lying in its rooms is still healthy" do
    story = healthy_story
    create(:item, :lying, location: story.locations.first, name: "ward stamp")
    create(:item, character: story.characters.first, name: "brass key")

    assert_empty Story::Doctor.new(story).findings
  end

  test "a story whose party is carrying its own copies is still healthy" do
    story = healthy_story
    room = story.locations.first
    create(:item, :lying, location: room, name: "ward stamp")
    played = create(:playthrough, story: story, character: story.protagonist, current_location: room)
    Playthrough::Turn.new(played).carry!(played.items_lying_in(room).sole)

    assert_empty Story::Doctor.new(story).findings
  end

  # A COPY OF NOTHING IS A REPORT AND NOT A DEFECT: the row is a real thing that
  # player really holds, and only its provenance is gone. It is what deleting
  # one of the world's own rows out from under a game in progress leaves behind.
  test "reports a playthrough's own copy that is a copy of nothing" do
    story = healthy_story
    played = create(:playthrough, story: story, character: story.protagonist,
                                  current_location: story.locations.first)
    create(:item, :carried, playthrough: played, name: "ward stamp")

    assert_includes codes(story), :instance_without_a_template
    assert_match(/no longer exists/, finding(story, :instance_without_a_template).message)
  end

  # EVERY GAME HOLDS ITS OWN COPY OF WHAT IS LYING IN THE ROOMS IT HAS WALKED
  # THROUGH, and a database older than the layers holds none of them.
  test "reports a playthrough standing in a room it has no copy of" do
    story = healthy_story
    room = story.locations.first
    played = create(:playthrough, story: story, character: story.protagonist, current_location: room)
    create(:item, :lying, location: room, name: "ward stamp")

    assert_includes codes(story), :playthrough_missing_a_copy
    assert_match(/emptier than the world's/, finding(story, :playthrough_missing_a_copy).message)
  end

  test "reports an item that is neither held nor carried nor lying anywhere" do
    story = healthy_story
    item = create(:item, :lying, location: story.locations.first)
    item.update_columns(location_id: nil, character_id: nil)

    assert_includes codes(story), :items_nowhere
    assert_match(/neither held by anybody nor lying anywhere/, finding(story, :items_nowhere).message)
  end

  # `Item#in_exactly_one_place` refuses to SAVE one, so like `items_nowhere`
  # this can only arrive through raw SQL or a schema older than the rule.
  test "reports an item in both of its places at once" do
    story = healthy_story
    item = create(:item, :lying, location: story.locations.first, name: "ward stamp")
    item.update_columns(character_id: story.protagonist.id)

    assert_includes codes(story), :items_in_several_places
    assert_match(/both offered and already done/, finding(story, :items_in_several_places).message)
    assert_match(/the world's own/, finding(story, :items_in_several_places).message)
  end

  # --- the shared inventory this column closed --------------------------------
  #
  # An item held by the protagonist that a playthrough's turn log records TAKING
  # is that player's, left on the story's one protagonist row by a build of the
  # app in which every play of a world shared one pair of hands.

  test "reports an item the protagonist holds that a playthrough's turn log took" do
    story = healthy_story
    played, item = a_shared_inventory(story)

    assert_includes codes(story), :protagonist_holds_a_taken_item
    finding = finding(story, :protagonist_holds_a_taken_item)
    assert_match(/playthrough ##{played.id}'s turn log records taking it/, finding.message)
    assert_equal :safe, finding.remedy
    assert_equal item, finding.subject
  end

  test "the story's starting inventory is not reported: nobody's turn log took it" do
    story = healthy_story
    create(:playthrough, story: story, character: story.protagonist,
                         current_location: story.locations.first)
    create(:item, character: story.protagonist, name: "Ward Office 12 daybook")

    assert_not_includes codes(story), :protagonist_holds_a_taken_item
  end

  # Every playthrough carries its OWN copy of what the story starts the player
  # with, so a world played four times holds five rows of one name and none of
  # them is a collision -- no closed set ever offers two, because a party sees
  # only its own.
  test "copies of the starting inventory are not two things answering to one name" do
    story = healthy_story
    create(:item, character: story.protagonist, name: "Ward Office 12 daybook")
    3.times do
      create(:playthrough, story: story, character: story.protagonist,
                           current_location: story.locations.first)
    end

    assert_equal 4, Item.in_story(story).where("LOWER(name) = ?", "ward office 12 daybook").count
    assert_not_includes codes(story), :duplicate_items
  end

  test "reports two things in one world answering to one name" do
    story = healthy_story
    create(:item, :lying, location: story.locations.first, name: "ward stamp")
    create(:item, character: story.characters.first, name: "Ward Stamp")

    assert_includes codes(story), :duplicate_items
    assert_match(/ordering accident/, finding(story, :duplicate_items).message)
  end

  test "reports a room holding more than one room may hold" do
    story = healthy_story
    room = story.locations.first
    (Item::Registry::MAX_PER_ROOM + 1).times { |n| create(:item, :lying, location: room, name: "thing #{n}") }

    assert_includes codes(story), :room_over_item_cap
    assert_match(/Your Office/, finding(story, :room_over_item_cap).message)
  end

  test "a room at the cap exactly is not over it" do
    story = healthy_story
    Item::Registry::MAX_PER_ROOM.times { |n| create(:item, :lying, location: story.locations.first, name: "thing #{n}") }

    assert_not_includes codes(story), :room_over_item_cap
  end

  test "reports a world past the ontology it was meant to be bounded by" do
    story = healthy_story
    holder = story.characters.first
    (Item::Registry::MAX_PER_STORY + 1).times { |n| create(:item, character: holder, name: "thing #{n}") }

    assert_includes codes(story), :story_over_item_cap
  end

  # THE CAP IS ON THE ONTOLOGY -- how many distinct things this world contains --
  # so the copies of one starting inventory spend it once, not once per player.
  test "the world cap counts names rather than rows" do
    story = healthy_story
    holder = story.characters.first
    Item::Registry::MAX_PER_STORY.times { |n| create(:item, character: holder, name: "thing #{n}") }
    5.times do
      create(:playthrough, story: story, character: story.protagonist,
                           current_location: story.locations.first)
    end

    assert_operator Item.in_story(story).count, :>, Item::Registry::MAX_PER_STORY
    assert_not_includes codes(story), :story_over_item_cap
  end

  test "reports an item named after somebody in the story" do
    story = healthy_story
    create(:item, :lying, location: story.locations.first, name: story.characters.first.fullname.downcase)

    assert_includes codes(story), :item_named_after_something_else
    assert_match(/character/, finding(story, :item_named_after_something_else).message)
  end

  test "reports an item named after a place in the story" do
    story = healthy_story
    create(:item, :lying, location: story.locations.first, name: "the street")

    assert_includes codes(story), :item_named_after_something_else
    assert_match(/location "The Street"/, finding(story, :item_named_after_something_else).message)
  end

  # None of these stop a story being played -- they are things that will read
  # wrong, not things that raise.
  test "nothing the registry checks makes a story unplayable" do
    story = healthy_story
    create(:item, :lying, location: story.locations.first, name: "the street")
    create(:item, character: story.characters.first, name: "The Street")

    assert Story::Doctor.new(story).playable?
  end
  # --- where the cast is ------------------------------------------------------
  #
  # `Character.present_in(location)` is the closed set `talk` resolves against,
  # so a whereabouts is not decoration: a character with none is somebody the
  # player can never speak to.

  test "reports a character standing nowhere" do
    story = healthy_story
    create(:character, story: story, fullname: "Perrin Lasco")

    assert_includes codes(story), :character_nowhere
    assert_match(/Perrin Lasco is nowhere/, finding(story, :character_nowhere).message)
    assert Story::Doctor.new(story).playable?
  end

  # NOWHERE ON PURPOSE IS NOT REPORTED AT ALL. `The Unrecorded Hour` is about
  # Perrin Lasco having been removed from the world, and the doctor reported him
  # on every single run before `characters.deliberately_absent` existed -- a
  # warning about a world working exactly as written.
  test "a character who is nowhere on purpose is not a finding" do
    story = healthy_story
    create(:character, story: story, fullname: "Perrin Lasco").absent!

    assert_not_includes codes(story), :character_nowhere
    assert_predicate Story::Doctor.new(story), :healthy?
  end

  # NOWHERE ON PURPOSE AND STANDING IN A ROOM: the marker says nobody may be
  # offered this person to talk to and the whereabouts puts them in that room's
  # closed set. Nothing in the app writes it, and the marker is the half that
  # wins -- so it is `safe` and `rake game:repair` puts them back.
  test "reports a character marked absent who is standing somewhere" do
    story = healthy_story
    somewhere = create(:character, story: story, fullname: "Perrin Lasco", location: story.locations.first)
    somewhere.update_column(:deliberately_absent, true)

    assert_includes codes(story), :character_absent_but_somewhere
    assert_equal :safe, finding(story, :character_absent_but_somewhere).remedy
    assert_not_includes codes(story), :character_nowhere
  end

  # `Character#move_to!` clears the marker, which is why no code path in the
  # app can produce the finding above: bringing somebody back is the story's
  # business, and once they are in a room they are not absent from the world.
  test "moving a character who was absent on purpose clears the marker" do
    story = healthy_story
    perrin = create(:character, story: story, fullname: "Perrin Lasco")
    perrin.absent!
    perrin.move_to!(story.locations.first)

    assert_not_predicate perrin, :deliberately_absent?
    assert_predicate Story::Doctor.new(story), :healthy?
  end

  # THE PARTY IS NOT ASKED ABOUT: the protagonist and any companion are wherever
  # the PLAYTHROUGH is, so nowhere is the correct state for them and reporting
  # it would be reporting the design.
  test "the protagonist and companions standing nowhere is not a finding" do
    story = healthy_story
    create(:character, :companion, story: story)

    assert_not_includes codes(story), :character_nowhere
  end

  # A person outlives a building, so a destroyed room nullifies the column
  # rather than the character -- and they land in the same finding.
  test "a character whose room was destroyed reads as nowhere" do
    story = healthy_story
    room = create(:location, story: story, name: "The Vestry Hulk")
    create(:character, story: story, fullname: "Neb Halloran", location: room)
    room.destroy!

    assert_includes codes(story.reload), :character_nowhere
  end

  # Legal, and it plays -- but `Location::Generator` writes the room's
  # description without knowing anybody is in it, so the prose and the records
  # disagree from the moment the room exists.
  test "reports a character standing in a room nobody has written" do
    story = healthy_story
    create(:character, story: story, fullname: "Neb Halloran", location: story.locations.find_by(name: "The Street"))

    assert_includes codes(story), :character_in_a_stub
    assert_match(/nobody has written yet/, finding(story, :character_in_a_stub).message)
  end

  # `Character#location_belongs_to_story` refuses to save one, so this arrives
  # only through raw SQL or a schema older than the validation -- the same shape
  # as `items_nowhere`, and it plays, because `Character.present_in` does not ask
  # whose story a room belongs to.
  test "reports a character standing in another story's room" do
    story = healthy_story
    elsewhere = create(:location, story: create(:story), name: "Somewhere Else Entirely")
    stranger = create(:character, story: story, fullname: "Neb Halloran")
    stranger.update_columns(location_id: elsewhere.id)

    assert_includes codes(story), :character_outside_the_story
  end

  # Not broken -- a seed file may hand-author a crowd -- but the registry will
  # place nobody else there, and the whole cast goes into the classifier's closed
  # enum on every turn. The exact counterpart of `room_over_item_cap`.
  test "reports a room holding more people than the engine would ever place in one" do
    story = healthy_story
    room = story.locations.find_by(name: "Your Office")
    (Character::Registry::MAX_PER_ROOM + 1).times { create(:character, story: story, location: room) }

    assert_includes codes(story), :room_over_cast_cap
    assert_match(/"Your Office" has 4 people standing in it/, finding(story, :room_over_cast_cap).message)
    assert Story::Doctor.new(story).playable?
  end

  test "a room at the cast cap exactly is not over it" do
    story = healthy_story
    room = story.locations.find_by(name: "Your Office")
    Character::Registry::MAX_PER_ROOM.times { create(:character, story: story, location: room) }

    assert_not_includes codes(story), :room_over_cast_cap
  end

  # The counterpart of `story_over_item_cap`: nothing breaks, and no further
  # room in the world will be generated with anybody in it.
  test "reports a world past the cast it was meant to be bounded by" do
    story = healthy_story
    (Character::Registry::MAX_PER_STORY + 1 - story.characters.count).times { create(:character, story: story) }

    assert_includes codes(story), :story_over_cast_cap
    assert Story::Doctor.new(story).playable?
  end

  # THE PREMISE CHECK. Only asked of a story that IS one of the checked-in
  # worlds, and the answer is on record in the file -- so it is `safe` and
  # `Story::Repair` puts them back.
  test "reports a seeded character who is not where the world file puts them" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-salt-assizes.yml"))
    neb = story.characters.find_by(fullname: "Neb Halloran")
    neb.move_to!(story.locations.find_by(name: "The Vestry Hulk"))

    assert_includes codes(story), :character_moved_from_the_seed
    assert_equal :safe, finding(story, :character_moved_from_the_seed).remedy
    assert_match(/the-salt-assizes\.yml puts them in "The Tide Post"/, finding(story, :character_moved_from_the_seed).message)
  end

  test "a story that is not a checked-in world is never asked about a seed file" do
    story = healthy_story
    create(:character, story: story, fullname: "Neb Halloran", location: story.locations.first)

    assert_empty Story::Doctor.new(story).seeded_whereabouts
    assert_not_includes codes(story), :character_moved_from_the_seed
  end

  # THE ONE-TIME PATH for a database seeded before the marker existed -- the
  # captain's own, where Perrin Lasco is nowhere and correct. The file already
  # says `absent: true`, so the answer is on record and the repair is `safe`.
  test "reports a seeded character the file marks absent whose row predates the marker" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    perrin = story.characters.find_by(fullname: "Perrin Lasco")
    perrin.update_column(:deliberately_absent, false)

    assert_includes codes(story), :character_absent_in_the_seed
    assert_equal :safe, finding(story, :character_absent_in_the_seed).remedy
    assert_not_includes codes(story), :character_nowhere
  end

  # The file and the record agreeing is the whole point of the marker, so a
  # file-absent character who IS nowhere is silent on both checks.
  test "a seeded character the file marks absent and who is nowhere is no finding at all" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))

    assert_predicate story.characters.find_by(fullname: "Perrin Lasco"), :absent?
    assert_predicate Story::Doctor.new(story), :healthy?
  end

  # The same finding read from the file's side, and the only one that can see a
  # story seeded before the marker existed: the file says nowhere on purpose and
  # the row is standing in a room.
  test "reports a seeded character the file marks absent who is standing somewhere" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    perrin = story.characters.find_by(fullname: "Perrin Lasco")
    perrin.update_columns(deliberately_absent: false, location_id: story.locations.first.id)

    assert_includes codes(story), :character_moved_from_the_seed
    assert_match(/marks them `absent: true`/, finding(story, :character_moved_from_the_seed).message)
  end

  test "the checked-in worlds are where their own files put them" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      assert_not_includes codes(story), :character_moved_from_the_seed, story.title
    end
  end

  # --- what re-seeding a played world used to leave behind --------------------
  #
  # These three are the shapes the captain's own database holds. The loader
  # cannot make them any more (`WorldSeed::Loader`'s header); a database that
  # already has one needs to be told, which is what these are for.

  test "reports two rooms that are one room to a re-seed" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    story.locations.find_by(name: "The Supply Closet").update!(last_protagonist_visit: story.start_time)
    create(:location, story: story, name: "Supply Closet", detail_level: "stub", teaser: "The second one.")

    assert_includes codes(story), :duplicate_locations
    assert_equal :safe, finding(story, :duplicate_locations).remedy
    assert_match(/declares one, "The Supply Closet"/, finding(story, :duplicate_locations).message)
  end

  test "two rooms both stood in cannot be folded, and says so" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    story.locations.find_by(name: "The Supply Closet").update!(last_protagonist_visit: story.start_time)
    create(:location, story: story, name: "Supply Closet", detail_level: "stub",
                      teaser: "The second one.", last_protagonist_visit: story.start_time)

    assert_equal :manual, finding(story, :duplicate_locations).remedy
    assert_match(/two histories cannot be folded into one/, finding(story, :duplicate_locations).message)
  end

  test "two rooms in a world with no checked-in file are nobody's to fold" do
    story = healthy_story
    create(:location, story: story, name: story.locations.first.name.downcase, detail_level: "stub", teaser: "x")

    assert_equal :manual, finding(story, :duplicate_locations).remedy
    assert_match(/no checked-in file declares any of them/, finding(story, :duplicate_locations).message)
  end

  test "reports two items that are one item to a re-seed" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    stamp = Item.in_story(story).find_by(name: "ward stamp")
    create(:item, name: "Ward Stamp", description: "The second one.", character: nil, location: stamp.location)

    assert_includes codes(story), :duplicate_items
    assert_equal :safe, finding(story, :duplicate_items).remedy
    assert_equal stamp, finding(story, :duplicate_items).subject, "the row the file names is the one that survives"
  end

  # A LEFTOVER A TURN LOG RECORDS TAKING IS SOMEBODY'S, and no fold of it is
  # honest: the row a player picked up is the row their game is about, whatever
  # the file says about the name.
  test "a duplicate item a turn log records taking is theirs, not the file's" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    stamp = Item.in_story(story).templates.find_by(name: "ward stamp")
    leftover = create(:item, name: "Ward Stamp", description: "The second one.", character: nil, location: stamp.location)
    playthrough = create(:playthrough, story: story, current_location: story.opening_location)
    playthrough.update!(current_scene: create(:scene, story: story, location: story.opening_location,
                                                      typed: "take the ward stamp", resolved_action: "take",
                                                      acted_on: leftover))

    assert_equal :manual, finding(story, :duplicate_items).remedy
    assert_match(/a player has handled one of the others/, finding(story, :duplicate_items).message)
  end

  # AND A PLAYTHROUGH'S OWN COPY IS NOT A DUPLICATE AT ALL. Every game holds its
  # own copy of the world's things under the same name, so a world played four
  # times holds five ward stamps and exactly one of them is the world's. No
  # closed set ever offers a party anything but its own -- the copy earns
  # `instance_without_a_template` when nothing says what it copies, and nothing
  # else.
  test "a playthrough's own copy of a name is not a duplicate of the world's row" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-unrecorded-hour.yml"))
    playthrough = create(:playthrough, story: story, current_location: story.opening_location)

    assert_not_includes codes(story), :duplicate_items
    assert_equal 2, Item.in_story(story).by_name("ward stamp").count,
                 "the world's own stamp and this game's copy of it"
    assert_predicate playthrough.items_lying_in(story.opening_location).find_by(name: "ward stamp"), :instance?
  end

  # THE PHANTOM DOORWAY, read off the pair rather than off the count: a mobile
  # room's arity is not the file's on a played world, because realizing it
  # writes stub neighbours. What the file proves is that the doorway it declares
  # is one the mechanic MOVES -- so that pair being on record after a night has
  # run means something wrote it back.
  test "reports the file's own doorway back on record after the world had moved it" do
    story = moved_cartographer
    circle = story.locations.find_by(name: "Sovereign's Circle")
    # Somewhere else for the circle to hang off, so closing the lane's doorway
    # onto it does not strand it -- which is what makes the finding `safe`.
    connect(story.locations.find_by(name: "Larkspur Quarter rooftops"), circle)

    assert_includes codes(story), :mobile_doorway_re_asserted
    assert_equal :safe, finding(story, :mobile_doorway_re_asserted).remedy
    assert_match(/which is the doorway db\/seeds\/worlds\/the-lunar-cartographer\.yml declares for it/,
                 finding(story, :mobile_doorway_re_asserted).message)
  end

  # A doorway whose far side leads nowhere else cannot be closed at all, so the
  # finding says so rather than promising a repair that would refuse.
  test "a re-asserted doorway that cannot be closed without stranding something is by hand" do
    story = moved_cartographer

    assert_equal :manual, finding(story, :mobile_doorway_re_asserted).remedy
    assert_match(/reachable from nowhere/, finding(story, :mobile_doorway_re_asserted).message)
  end

  test "the file's own doorway is no finding until a night has run" do
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-lunar-cartographer.yml"))
    lane = story.locations.find_by(name: "Mournwell Lane")
    connect(lane, create(:location, story: story, name: "The Long Quay", detail_level: "stub", teaser: "Barges."))

    assert_nil story.world_mechanics.sole.last_run_at
    assert_not_includes codes(story), :mobile_doorway_re_asserted
  end

  test "the checked-in worlds have no re-asserted doorway of their own" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      assert_not_includes codes(story), :mobile_doorway_re_asserted, story.title
      assert_not_includes codes(story), :duplicate_locations, story.title
      assert_not_includes codes(story), :duplicate_items, story.title
    end
  end

  # The world that moves, one night on, with the file's own doorway written
  # back over the arrangement the night produced -- which is exactly what a
  # re-seed used to do. Built by hand rather than by running the mechanic, so
  # the shape under test does not depend on which permutation came up.
  def moved_cartographer
    story = WorldSeed::Loader.load_file(WorldSeed::DIRECTORY.join("the-lunar-cartographer.yml"))
    story.world_mechanics.sole.update!(last_run_at: story.start_time + 1.day)

    lane = story.locations.find_by(name: "Mournwell Lane")
    connect(lane, create(:location, story: story, name: "The Long Quay", detail_level: "stub", teaser: "Barges."))
    story
  end
end
