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

  # --- which reader answered a turn -----------------------------------------

  # NIL IS NOT A FINDING and must not become one. The column is nullable by
  # history: an opening arrival was read by nobody and every turn played before
  # `scenes.resolved_by` existed is stamped by `Update::Steps::StampResolvedBy`,
  # not reported one at a time here.
  test "a turn with no reader on record is not a finding" do
    story = healthy_story
    create(:scene, story: story, location: story.locations.first, story_timestamp: story.start_time,
                   typed: "take the stamp", resolved_action: "take", resolved_by: nil)

    assert_not_includes codes(story), :scene_with_an_unknown_reader
  end

  test "both readers that write a turn are accepted" do
    story = healthy_story
    Scene::TURN_READERS.each do |reader|
      create(:scene, story: story, location: story.locations.first, story_timestamp: story.start_time,
                     typed: "take the stamp", resolved_action: "take", resolved_by: reader)
    end

    assert_not_includes codes(story), :scene_with_an_unknown_reader
  end

  # A world here outlives the code that made it, so the check is about a row
  # this app did not save: `Scene`'s own validation refuses one on the way in.
  # `engine_view` is the reachable case -- it is in the column's closed list and
  # no engine-view command writes a `Scene` at all.
  test "a turn claiming a reader that writes no turns is named" do
    story = healthy_story
    scene = create(:scene, story: story, location: story.locations.first, story_timestamp: story.start_time,
                           typed: "harm 5", resolved_action: "other")
    scene.update_column(:resolved_by, "engine_view")

    assert_includes codes(story), :scene_with_an_unknown_reader
    finding = Story::Doctor.new(story).findings.find { |row| row.code == :scene_with_an_unknown_reader }

    assert_equal :manual, finding.remedy
    assert_includes finding.message, "engine_view"
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

  # --- a copy that lags the world's own row ---------------------------------

  # A SEED FILE EDITED AFTER SOMEBODY PLAYED. A re-seed puts the words on the
  # world's own row and, correctly, stops there -- so the copy made before the
  # edit goes on reading blank. See `Item::TemplateRefresh`.
  def lagging_story
    story = healthy_story
    room = story.locations.first
    played = create(:playthrough, story: story, character: story.protagonist, current_location: room)
    template = create(:item, :lying, location: room, name: "assize tide-slate")
    copy = create(:item, :lying, location: room, playthrough: played, template: template,
                                 name: template.name, description: template.description)
    template.update!(readable: true, inscription: "Three hours forty after noon.")

    [ story, played, copy.reload ]
  end

  test "reports a playthrough's untouched copy carrying what the world used to say" do
    story, played, = lagging_story

    assert_includes codes(story), :copy_lags_its_template
    assert_equal played, finding(story, :copy_lags_its_template).subject
    assert_equal :safe, finding(story, :copy_lags_its_template).remedy
    assert_match(/what the world used to say/, finding(story, :copy_lags_its_template).message)
  end

  # A copy some turn took or put down is that player's, and nothing on record
  # says whether its text is stale or is what they have. Reported, not repaired.
  test "a lagging copy a turn has acted on is reported and never called safe" do
    story, _played, copy = lagging_story
    create(:scene, story: story, location: copy.location, resolved_action: "take", acted_on: copy)

    assert_not_includes codes(story), :copy_lags_its_template
    assert_includes codes(story), :touched_copy_lags_its_template
    assert_equal :manual, finding(story, :touched_copy_lags_its_template).remedy
  end

  test "a copy that says what its template says is silent" do
    story = healthy_story
    room = story.locations.first
    played = create(:playthrough, story: story, character: story.protagonist, current_location: room)
    template = create(:item, :lying, :readable, location: room)
    create(:item, :lying, location: room, playthrough: played, template: template, name: template.name,
                          description: template.description, readable: true, inscription: template.inscription)

    assert_not_includes codes(story), :copy_lags_its_template
    assert_not_includes codes(story), :touched_copy_lags_its_template
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

  # --- the bodies, and the conditions --------------------------------------

  test "somebody with no stat block is reported, and repairably" do
    story = create(:story)
    nobody = create(:character, :without_a_stat_block, story: story)

    finding = Story::Doctor.new(story).findings.find { |row| row.code == :character_without_a_stat_block }

    assert_not_nil finding
    assert_equal :safe, finding.remedy
    assert_equal nobody, finding.subject
    assert_match(/no stat block/, finding.message)
  end

  test "a character with a whole stat block is no finding" do
    story = create(:story)
    create(:character, story: story, level: 1, hit_die: 8)

    assert_not_includes codes(story), :character_without_a_stat_block
  end

  # THE SHAPE A LEGITIMATE FILE EDIT LEAVES: a re-seed lowers somebody's hit die
  # under a game already in progress, and that game's row is now above its new
  # maximum. `Playthrough::Vitals` refuses to SAVE one, so it is written past
  # the validation the way the database really gets one.
  test "a condition above the maximum its stat block allows is reported" do
    story = create(:story)
    room = create(:location, story: story)
    rowe = create(:character, story: story, location: room, level: 1, hit_die: 10)
    game = create(:playthrough, story: story, character: create(:character, :protagonist, story: story),
                                current_location: room)
    row = Playthrough::Vitals.instantiate!(game, rowe)
    rowe.update!(hit_die: 6)

    finding = Story::Doctor.new(story).findings.find { |candidate| candidate.code == :hp_above_maximum }

    assert_not_nil finding
    assert_equal :safe, finding.remedy
    assert_equal row, finding.subject
  end

  test "a condition for somebody the world no longer has is reported and manual" do
    story = create(:story)
    room = create(:location, story: story)
    rowe = create(:character, story: story, location: room, level: 1, hit_die: 8)
    game = create(:playthrough, story: story, character: create(:character, :protagonist, story: story),
                                current_location: room)
    row = Playthrough::Vitals.instantiate!(game, rowe)
    # A foreign key stops this happening today, and `dependent: :destroy` takes
    # the row with the person before the key is ever consulted. It is written
    # here the way an older database really holds one -- with the constraint
    # deferred -- because the doctor's whole premise is a world that outlives
    # the schema, and this is the shape a build without either would leave.
    ActiveRecord::Base.connection.disable_referential_integrity do
      Character.where(id: rowe.id).delete_all
    end

    finding = Story::Doctor.new(story).findings.find { |candidate| candidate.code == :vitals_without_a_template }

    assert_not_nil finding
    assert_equal :manual, finding.remedy
    assert_equal row.id, finding.subject.id
  end

  # NOTHING IN THE APP CAN WRITE ONE: the snapshot writes at first contact and
  # nowhere else, so a row for somebody two rooms away is a row about an
  # encounter that never happened.
  test "a condition for somebody that game has never met is reported and repairable" do
    story = create(:story)
    room = create(:location, story: story)
    elsewhere = create(:location, story: story)
    stranger = create(:character, story: story, location: elsewhere, level: 1, hit_die: 8)
    game = create(:playthrough, story: story, character: create(:character, :protagonist, story: story),
                                current_location: room)
    row = Playthrough::Vitals.create!(playthrough: game, character: stranger, hp_current: 8)

    finding = Story::Doctor.new(story).findings.find { |candidate| candidate.code == :vitals_for_an_unmet_character }

    assert_not_nil finding
    assert_equal :safe, finding.remedy
    assert_equal row, finding.subject
  end

  # THE PARTY IS NEVER ONE OF THOSE: the protagonist and any companion are
  # wherever the playthrough is rather than in a room, which is the same
  # exception `cast_unmoved` makes.
  test "the party's own condition is never reported as an unmet character" do
    story = create(:story)
    room = create(:location, story: story)
    vance = create(:character, :protagonist, story: story, level: 1, hit_die: 6)
    create(:playthrough, story: story, character: vance, current_location: room)

    assert_not_includes codes(story), :vitals_for_an_unmet_character
  end

  test "a game with no condition for its own protagonist is reported and repairable" do
    story = create(:story)
    room = create(:location, story: story)
    vance = create(:character, :protagonist, story: story, level: 1, hit_die: 6)
    game = create(:playthrough, story: story, character: vance, current_location: room)
    game.vitals.destroy_all

    finding = Story::Doctor.new(story).findings.find { |row| row.code == :protagonist_without_vitals }

    assert_not_nil finding
    assert_equal :safe, finding.remedy
    assert_equal game, finding.subject
  end

  # Said once about the person rather than once per game of them: a protagonist
  # with no stat block is `character_without_a_stat_block`, and there is nothing
  # to write a condition from.
  test "a protagonist with no stat block earns no missing-condition finding" do
    story = create(:story)
    room = create(:location, story: story)
    vance = create(:character, :protagonist, :without_a_stat_block, story: story)
    create(:playthrough, story: story, character: vance, current_location: room)

    assert_not_includes codes(story), :protagonist_without_vitals
    assert_includes codes(story), :character_without_a_stat_block
  end

  test "the checked-in worlds give everybody a body" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      assert_not_includes codes(story), :character_without_a_stat_block, story.title
    end
  end

  # --- the three abilities ---------------------------------------------------
  #
  # Reported SEPARATELY from the stat block, because `Character#abilities?` is a
  # separate predicate for a stated reason: `#stat_block?` gates `#max_hp` and
  # through it every condition row in the database.

  test "somebody with no abilities is reported, and repairably" do
    story = create(:story)
    nobody = create(:character, :without_abilities, story: story)

    finding = Story::Doctor.new(story).findings.find { |row| row.code == :character_without_abilities }

    assert_not_nil finding
    assert_equal :safe, finding.remedy
    assert_equal nobody, finding.subject
    assert_match(/no abilities/, finding.message)
  end

  # A body with no abilities is ONE finding and not two: the sheet is whole on
  # one side and empty on the other, and saying both would say the same gap twice.
  test "a body with no abilities earns the ability finding and not the stat block one" do
    story = create(:story)
    create(:character, :without_abilities, story: story, level: 1, hit_die: 8)

    assert_includes codes(story), :character_without_abilities
    assert_not_includes codes(story), :character_without_a_stat_block
  end

  test "a character with all three abilities is no finding" do
    story = create(:story)
    create(:character, story: story, strength: 12, dexterity: 10, will: 14)

    assert_not_includes codes(story), :character_without_abilities
  end

  # A PARTIAL SET, which `Character#abilities_are_whole` refuses to save -- so it
  # is written past the validation the way the database really gets one.
  test "a partial set of abilities is reported and says how much of it there is" do
    story = create(:story)
    somebody = create(:character, story: story)
    Character.where(id: somebody.id).update_all(dexterity: nil, will: nil)

    finding = Story::Doctor.new(story).findings.find { |row| row.code == :character_without_abilities }

    assert_not_nil finding
    assert_match(/only 1 of 3 abilities \(strength\)/, finding.message)
  end

  # A NUMBER 3d6 COULD NEVER HAVE COME UP. `Character` refuses one, so this
  # arrived through raw SQL -- and there is no record of the intended value,
  # which is what makes re-rolling the set the only honest answer.
  test "an ability outside the range 3d6 rolls is reported" do
    story = create(:story)
    somebody = create(:character, story: story)
    Character.where(id: somebody.id).update_all(strength: 25)

    finding = Story::Doctor.new(story).findings.find { |row| row.code == :ability_out_of_range }

    assert_not_nil finding
    assert_equal :safe, finding.remedy
    assert_equal somebody, finding.subject
    assert_match(/strength 25/, finding.message)
  end

  test "the checked-in worlds give everybody three abilities in range" do
    WorldSeed::Loader.load_all(io: nil).each do |story|
      assert_not_includes codes(story), :character_without_abilities, story.title
      assert_not_includes codes(story), :ability_out_of_range, story.title
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

  # --- a world that contains an enemy ---------------------------------------
  #
  # Three shapes, and all three are about WORLD data: `characters.hostile`,
  # `races.monstrous` and `locations.danger` are on `hit_die`'s side of the
  # layer split, so a wrong one is a world somebody has to edit rather than a
  # game that has gone astray.

  test "a world with a healthy monster in it is healthy" do
    story = healthy_story
    room = story.locations.realized.first
    create(:character, :monster, story: story, location: room, fullname: "Marek Sollen")

    doctor = Story::Doctor.new(story)

    assert_predicate doctor, :healthy?, doctor.findings.map(&:message).join("\n")
  end

  test "a foe with no body is reported as a foe with no body" do
    story = healthy_story
    room = story.locations.realized.first
    create(:character, :monster_without_a_stat_block, story: story, location: room, fullname: "The Sump")

    assert_includes codes(story), :hostile_without_a_stat_block
    assert_equal :safe, finding(story, :hostile_without_a_stat_block).remedy
    assert_match(/nothing in this world can fight them/, finding(story, :hostile_without_a_stat_block).message)
  end

  # ONE ROW, ONE FINDING. `character_without_a_stat_block` steps aside for the
  # louder statement rather than reporting the same nil twice.
  test "a foe with no body is not also reported as a person with no body" do
    story = healthy_story
    room = story.locations.realized.first
    create(:character, :monster_without_a_stat_block, story: story, location: room, fullname: "The Sump")

    assert_not_includes codes(story), :character_without_a_stat_block
  end

  test "an ordinary person with no body is still reported the ordinary way" do
    story = healthy_story
    create(:character, :without_a_stat_block, story: story, fullname: "Grenn Ollivar")

    assert_includes codes(story), :character_without_a_stat_block
    assert_not_includes codes(story), :hostile_without_a_stat_block
  end

  test "a monstrous race this world has nobody of is reported and cannot be repaired" do
    story = healthy_story
    create(:race, :monstrous, universe: story.universe, name: "Nocturna-Blighted")

    assert_includes codes(story), :monstrous_race_with_no_monsters
    assert_equal :manual, finding(story, :monstrous_race_with_no_monsters).remedy
    assert_not_includes Story::Repair.new(story, generate: true).plan.map(&:code), :monstrous_race_with_no_monsters
  end

  test "a monstrous race with a monster of it is quiet" do
    story = healthy_story
    race = create(:race, :monstrous, universe: story.universe, name: "Nocturna-Blighted")
    create(:character, story: story, race: race, hostile: true, location: story.locations.realized.first,
                       fullname: "Marek Sollen")

    assert_not_includes codes(story), :monstrous_race_with_no_monsters
  end

  # `Location` refuses a key outside `DANGERS`, so this row arrived through raw
  # SQL or a schema older than the validation -- which is exactly the state the
  # doctor exists to name.
  test "a room with a danger the engine has no table for is reported and cannot be repaired" do
    story = healthy_story
    room = story.locations.realized.first
    room.update_column(:danger, "a bit worrying")

    assert_includes codes(story), :location_with_an_unknown_danger
    assert_equal :manual, finding(story, :location_with_an_unknown_danger).remedy
    assert_match(/a bit worrying/, finding(story, :location_with_an_unknown_danger).message)
  end

  test "every danger the table has is quiet" do
    Location::DANGERS.each_key do |danger|
      story = healthy_story
      story.locations.realized.first.update!(danger: danger)

      assert_not_includes codes(story), :location_with_an_unknown_danger, danger
    end
  end
end
