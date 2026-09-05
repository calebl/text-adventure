require "test_helper"

# The engine with the prose taken out. What matters here is not what anything
# read like -- nothing reads like anything -- it is that after every command the
# DATABASE says what the read-out said, and that a refused command changed
# nothing at all.
#
# TWO PATHS IN, AND THE FILE IS SPLIT ALONG THEM:
#
#   `play`      the offline mode (`model: false`), run with `BaseAgent.new`
#               RAISING. That guarantee is asserted rather than assumed -- no
#               API key is deleted, no network is blocked, nothing is hoped for.
#               If any path through the offline mode ever reaches for a model,
#               every test using this helper fails on the spot.
#   `interpret` the default mode, driven through a FakeAgent standing in for
#               every BaseAgent the command builds. The queued responses ARE the
#               model calls the mode is allowed to make, in order, and running
#               out of them raises -- so a narrator call this mode must not make
#               fails the test loudly instead of passing quietly.
#
# The world is shaped like `the-unrecorded-hour.yml` -- an opening room, a
# realized dead end off it, an unwritten stub, something on each floor and
# something in the protagonist's hands -- and built with factories rather than
# loaded from the seed file, because `SeededWorldsTest` is deliberately the one
# test that reads those.
class Playthrough::MechanicsTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @vance = create(:character, story: @story, fullname: "Odile Vance", is_protagonist: true)

    @office = create(:location, story: @story, name: "Ward Office 12")
    @closet = create(:location, story: @story, name: "The Supply Closet")
    @hallway = create(:location, :stub, story: @story, name: "The Long Hallway")
    connect(@office, @closet)
    connect(@office, @hallway)

    # Rowe is standing in the office, and that is a record on him now rather
    # than something read back out of a scene's cast.
    @rowe = create(:character, story: @story, fullname: "Halkett Rowe", location: @office)

    # The world's opening arrival. What puts Rowe in the room is his own
    # whereabouts (`characters.location_id`, set on the factory above); the
    # scene's cast is a snapshot of that and no longer the source of it.
    @opening = create(:scene, story: @story, location: @office, characters: [ @vance, @rowe ],
                              description: "The gap in the daybook is still under your hand.")
    @playthrough = create(:playthrough, story: @story, character: @vance,
                                        current_location: @office, current_scene: @opening)

    # WHAT IS ON THE FLOOR, IN THIS GAME. `lying_here` writes the world's own
    # row and then takes this playthrough's copy of it, which is what the loop
    # resolves a `take` against -- so it has to run after the playthrough
    # exists. The closet is snapshotted here too rather than on arrival,
    # because a test that walks in wants to assert what is waiting there.
    @stamp = lying_here(@playthrough, @office, name: "ward stamp")
    @index = lying_here(@playthrough, @closet, name: "Perrin's private index")

    # WHAT THE PLAYER HAS IS THE PLAYTHROUGH'S, not the protagonist's: this is
    # `items.playthrough_id`, the closed set `drop` resolves against. Created
    # after the playthrough on purpose -- an item held by the protagonist would
    # be the story's STARTING INVENTORY, which a new playthrough copies rather
    # than carries, and the copy is not the row a test can then follow.
    @daybook = create(:item, :carried, playthrough: @playthrough, name: "Ward Office 12 daybook")
  end

  def connect(from, to)
    create(:location_connection, location: from, connected_location: to,
                                 distance: "adjacent", travel_method: "walking")
    create(:location_connection, location: to, connected_location: from,
                                 distance: "adjacent", travel_method: "walking")
  end

  # One command in the OFFLINE mode, with no model reachable from anywhere
  # inside it.
  def play(command)
    BaseAgent.stub(:new, ->(*) { raise "the offline mechanics mode made a model call" }) do
      Playthrough::Mechanics.new(@playthrough, model: false).run(command)
    end
  end

  # One command in the DEFAULT mode: the classifier reads it and the world
  # generates itself. `responses` are the model calls this command is allowed to
  # make, in order -- a classification, then whatever a move has to generate.
  # The agent comes back so a test can count the prompts and prove no more were
  # asked for.
  def interpret(command, *responses)
    agent = FakeAgent.new(*responses)

    report = BaseAgent.stub(:new, agent) do
      Playthrough::Mechanics.new(@playthrough).run(command)
    end

    [ report, agent ]
  end

  CLASSIFY = ->(intent, target, also = nil) { { "intent" => intent, "target" => target, "also_named" => also }.compact }

  DETAIL = {
    "description" => "Doors on both sides, and the gas turned down to nothing.",
    "lore" => "The east ring's hallways were built for carts that no longer exist."
  }.freeze

  ARRIVAL = {
    "description" => "You step out and the hallway takes the sound of the door away.",
    "summary" => "Vance leaves the office for the long hallway."
  }.freeze

  # --- the offline mode: a scripted walk -------------------------------------

  test "a walk through the world moves the playthrough and the items, and the records say so at every step" do
    report = play("take stamp")
    assert_change report, "took: ward stamp"
    assert_equal @playthrough, @stamp.reload.playthrough
    assert_nil @stamp.location

    report = play("go closet")
    assert_change report, "moved: Ward Office 12 -> The Supply Closet"
    assert_equal @closet, @playthrough.reload.current_location

    # DROPPED WHERE IT WAS DROPPED, not back where it was taken from. This is
    # the whole reason `Item` is in exactly one place rather than carrying a
    # note about where it came from.
    report = play("drop stamp")
    assert_change report, "dropped: ward stamp"
    assert_equal @closet, @stamp.reload.location
    assert_nil @stamp.character

    report = play("take index")
    assert_change report, "took: Perrin's private index"
    assert_equal @playthrough, @index.reload.playthrough

    report = play("go ward office")
    assert_change report, "moved: The Supply Closet -> Ward Office 12"
    assert_equal @office, @playthrough.reload.current_location

    # And the stamp stayed in the closet when she walked out of it. THE OFFICE
    # IS EMPTY FOR HER AND NOT FOR ANYBODY ELSE: her copy of the stamp is in the
    # closet now, and the world's own row is still lying in the office for the
    # next game that walks in.
    assert_equal @closet, @stamp.reload.location
    assert_empty @playthrough.items_lying_in(@office)
    assert_equal [ "ward stamp" ], Item.lying_in(@office).templates.pluck(:name)
    assert_equal [ @daybook, @index ].map(&:id).sort, @playthrough.carried.pluck(:id).sort
  end

  test "the read-out matches the database after every command of the walk" do
    [ "look", "take stamp", "go closet", "drop stamp", "take index", "go ward office", "go hallway" ].each do |command|
      assert_reads_true play(command), command
    end
  end

  test "the offline mode walks into a stub without writing the room, because writing it is a model call" do
    report = play("go hallway")

    assert_equal @hallway, @playthrough.reload.current_location
    assert_predicate @hallway.reload, :stub?
    assert_nil @hallway.description
    assert_includes report.change, "a stub"
  end

  test "the offline mode writes no Scene, so the turn log and the story clock are untouched" do
    scenes = @story.scenes.count
    clock = @story.clock

    [ "take stamp", "go closet", "drop stamp", "go ward office" ].each { |command| play(command) }

    assert_equal scenes, @story.reload.scenes.count
    assert_equal clock, @story.clock
  end

  # --- reading what is written on something ----------------------------------

  # WHAT IS WRITTEN ON A THING IS A RECORD, so it reads out with no model at all.
  # This is not the mode growing a narrator: `Item#inscription` is a column, and
  # printing it is printing a record exactly as the read-out prints an exit.
  test "the offline mode reads out the words on a thing, with no model" do
    @stamp.update!(readable: true, inscription: "WARD 12 — REGISTRY OF AMENDMENTS")

    report = play("read the ward stamp")

    assert_not report.refused?
    assert_not report.changed?
    assert_equal "examine -> ward stamp", report.understood
    assert_includes report.to_s, "WARD 12 — REGISTRY OF AMENDMENTS"
  end

  test "the offline mode reads a thing out of the player's own hands" do
    @daybook.update!(readable: true, inscription: "5.15 — Query 1188 still open. O.V.")

    assert_includes play("read the daybook").to_s, "5.15 — Query 1188 still open. O.V."
  end

  # `examine`, `x` and `look at` are the same verb, and `look` on its own is
  # still the whole read-out.
  test "the offline grammar reads by four names and keeps look for the read-out" do
    @index.update!(readable: true, inscription: "1188/12 — amended.")
    play("go to the closet")

    [ "read the index", "examine the index", "x the index", "look at the index" ].each do |line|
      assert_includes play(line).to_s, "1188/12 — amended.", line
    end

    assert_not_includes play("look").to_s, "1188/12 — amended."
  end

  # THE GATE. A thing with nothing written on it is refused, and the refusal
  # says which of the two facts it is -- nothing generates text for it, ever.
  test "the offline mode refuses to read a thing with nothing written on it" do
    report = play("read the ward stamp")

    assert report.refused?
    assert_not report.changed?
    assert_includes report.refusal, "there is nothing written on the ward stamp"
  end

  # And it will not WRITE the words either: that is one model call, and this mode
  # makes none here. It says what is missing rather than inventing it.
  test "the offline mode says so rather than writing the words a readable thing lacks" do
    @stamp.update!(readable: true, inscription: nil)

    report = play("read the ward stamp")

    assert report.refused?
    assert_includes report.refusal, "the records do not hold the words yet"
    assert_nil @stamp.reload.inscription
  end

  test "reading nothing in particular asks against both sets at once" do
    report = play("read")

    assert report.refused?
    assert_includes report.refusal, "read what?"
    assert_includes report.refusal, "ward stamp"
    assert_includes report.refusal, "Ward Office 12 daybook"
  end

  test "reading something that is not here is refused with what is" do
    report = play("read the lighthouse ledger")

    assert report.refused?
    assert_includes report.refusal, "thing here or in your hands"
  end

  # Reading moves nothing. The records after a read are the records before it.
  test "reading changes no row at all" do
    @index.update!(readable: true, inscription: "1188/12 — amended.")
    play("go to the closet")

    assert_no_changes -> { [ @index.reload.attributes, @playthrough.reload.current_location_id ] } do
      play("read the index")
    end
  end

  # The classifier path reaches the same branch, off the same resolved record.
  test "the classifier mode reads what the classifier resolved" do
    @index.update!(readable: true, inscription: "1188/12 — amended.")
    @playthrough.update!(current_location: @closet)

    report, agent = interpret("what does the index say?", CLASSIFY.call("examine", "Perrin's private index"))

    assert_includes report.to_s, "1188/12 — amended."
    assert_equal 1, agent.prompts.size, "reading a record is not a second model call"
  end

  # --- the offline mode: refusals --------------------------------------------

  test "an exit that does not exist is refused, and nothing moves" do
    report = play("go cellar")

    assert_refusal report, "there is no way out called \"cellar\""
    assert_includes report.refusal, "The Supply Closet"
    assert_equal @office, @playthrough.reload.current_location
  end

  test "taking something that is not lying here is refused, and nothing moves" do
    report = play("take index")

    assert_refusal report, "there is no thing lying here called \"index\""
    refute_predicate @index.reload, :carried?
    assert_equal @closet, @index.location
  end

  test "taking something the player is already carrying is refused" do
    report = play("take daybook")

    assert_refusal report, "there is no thing lying here called \"daybook\""
    assert_equal @playthrough, @daybook.reload.playthrough
  end

  test "dropping something the player is not carrying is refused, and nothing moves" do
    report = play("drop stamp")

    assert_refusal report, "there is no thing you are carrying called \"stamp\""
    assert_equal @office, @stamp.reload.location
    assert_nil @stamp.character
  end

  test "an ambiguous name is refused with what it matched rather than resolved to the first" do
    lying_here(@playthrough, @office, name: "ward stamp pad")

    report = play("take ward")

    assert_refusal report, "matches more than one"
    assert_includes report.refusal, "ward stamp pad"
    refute_predicate @stamp.reload, :carried?
  end

  test "a word that is not in the grammar is refused with the whole grammar" do
    report = play("sing to the filing press")

    assert_refusal report, "I do not understand \"sing\""
    assert_includes report.to_s, "go <exit>"
    assert_equal @office, @playthrough.reload.current_location
  end

  test "a bare verb with nothing after it says what it could have taken" do
    assert_refusal play("go"), "go where?"
    assert_refusal play("take"), "take what?"
    assert_refusal play("drop"), "drop what?"
  end

  # --- the offline mode: resolving a typed name ------------------------------

  test "a name resolves exactly, then by prefix, then by fragment, ignoring case and spacing" do
    assert_change play("go   THE supply CLOSET  "), "-> The Supply Closet"
    assert_change play("go ward"), "-> Ward Office 12"
    assert_change play("go closet"), "-> The Supply Closet"
  end

  # THE TWO DEFECTS THE ENGINE SWEEP WAS BUILT ON, both found by typing at the
  # console and both the same defect: matching ran one way round only, so a
  # leading article was fatal and a typed line that HELD the record's name
  # matched nothing at all. The refusal listed the very thing it was refusing.
  test "a leading article or preposition is not part of the name" do
    assert_change play("drop the daybook"), "dropped: Ward Office 12 daybook"
    assert_change play("go to the Supply Closet"), "-> The Supply Closet"
    assert_change play("go into Ward Office 12"), "-> Ward Office 12"
    assert_change play("take the ward stamp"), "took: ward stamp"
  end

  test "a typed line that holds the whole name resolves to it" do
    assert_change play("take the ward stamp off the desk"), "took: ward stamp"
  end

  # The one direction that needs word boundaries. Without them a two-letter
  # item name would be found inside any long enough sentence, which is the
  # failure a containment test invites when the typing is the longer side.
  test "a short name is not swallowed by a longer word that contains it" do
    lying_here(@playthrough, @office, name: "key")

    assert_refusal play("take the monkey"), "there is no thing lying here"
  end

  # Ambiguity on the first reading must not hide a match on the second: "the
  # copy-room apron" holds BOTH item names, and only one of them is what was
  # typed once the article is off the front.
  test "ambiguity as typed does not hide the match the stripped name finds" do
    lying_here(@playthrough, @office, name: "apron")
    lying_here(@playthrough, @office, name: "copy-room apron")

    assert_change play("take the copy-room apron"), "took: copy-room apron"
  end

  test "an article on its own still resolves to nothing rather than to a guess" do
    assert_refusal play("go the"), "matches more than one"
  end

  test "an exit name typed on its own is a move, so a world with compass exits can be walked" do
    north = create(:location, story: @story, name: "north")
    connect(@office, north)

    report = play("north")

    assert_change report, "moved: Ward Office 12 -> north"
    assert_equal north, @playthrough.reload.current_location
  end


  # --- the default mode: the classifier reads it, the world generates ---------

  # THE POINT OF THE WHOLE MODE. One classification, then the same engine
  # method the browser calls, and nothing else asked of any model.
  test "a take goes through the classifier to the same engine write, and asks for nothing more" do
    report, agent = interpret("pick up that stamp", CLASSIFY.call("take", "ward stamp"))

    assert_equal "take -> ward stamp", report.understood
    assert_includes report.change, "took: ward stamp"
    assert_equal @playthrough, @stamp.reload.playthrough
    assert_nil @stamp.location
    # One prompt: the classification. A narrator call would have been a second,
    # and FakeAgent would have raised on it.
    assert_equal 1, agent.prompts.count
  end

  test "a drop goes through the classifier to the same engine write, and asks for nothing more" do
    report, agent = interpret("put the daybook down", CLASSIFY.call("drop", "Ward Office 12 daybook"))

    assert_equal "drop -> Ward Office 12 daybook", report.understood
    assert_includes report.change, "dropped: Ward Office 12 daybook"
    assert_equal @office, @daybook.reload.location
    assert_nil @daybook.character
    assert_equal 1, agent.prompts.count
  end

  # THE WORLD STILL GENERATES ITSELF. Walking into a room nobody has written
  # writes it, its exits and the arrival -- exactly the calls the browser makes,
  # and no narrator among them.
  test "walking into a stub realizes it and writes the arrival, as the real game does" do
    report, agent = interpret("go out into the hallway",
                              CLASSIFY.call("move", "The Long Hallway"),
                              DETAIL, { "exits" => [] }, ARRIVAL)

    assert_predicate @hallway.reload, :realized?
    assert_equal DETAIL["description"], @hallway.description
    assert_equal @hallway, @playthrough.reload.current_location
    assert_equal ARRIVAL["description"], @playthrough.current_scene.description
    assert_includes report.change, "written for the first time"
    # classify, detail, exits, arrival. Nothing narrated on top.
    assert_equal 4, agent.prompts.count
  end

  # THE ITEM REGISTRY, END TO END AND THROUGH THE CLASSIFIER. Before it, a room
  # the world wrote for itself was always empty, so `take` and `drop` could only
  # be walked in rooms a person had hand-written into a seed file. The registry
  # writes the rows at realization; `Item.lying_in` is the closed set the
  # classifier already resolves against, so nothing downstream changed and the
  # generated thing is takeable on the very next turn.
  test "walking into a stub furnishes it, and what it furnishes can be taken and dropped" do
    furnished = DETAIL.merge(
      "items" => [ { "name" => "gas key", "description" => "A key for the hallway's gas taps, left in the bracket." } ]
    )

    report, = interpret("go out into the hallway",
                        CLASSIFY.call("move", "The Long Hallway"),
                        furnished, { "exits" => [] }, ARRIVAL)
    assert_includes report.change, "written for the first time"

    # TWO ROWS, ONE THING. `Item::Registry` wrote the world's own row when the
    # room was realized and `Item::Snapshot` gave this game its copy on the way
    # in, which is the order `Playthrough::Turn#move_to` makes it happen in.
    template = Item.lying_in(@hallway).templates.sole
    key = @playthrough.items_lying_in(@hallway).sole
    assert_equal "gas key", template.name
    assert_equal template, key.template

    # The read-out shows it, out of the same closed set the classifier reads.
    assert_includes report.state.to_s, "gas key"

    report, agent = interpret("pick up the gas key", CLASSIFY.call("take", "gas key"))
    assert_equal "take -> gas key", report.understood
    assert_includes report.change, "took: gas key"
    assert_predicate key.reload, :carried?
    assert_equal @playthrough, key.playthrough
    assert_equal 1, agent.prompts.count

    # AND THE WORLD STILL HAS ITS OWN. A take moves one game's copy, so the
    # hallway is furnished for the next player exactly as it was generated.
    assert_equal @hallway, template.reload.location
    assert_predicate template, :template?

    report, = interpret("put the gas key down", CLASSIFY.call("drop", "gas key"))
    assert_includes report.change, "dropped: gas key"
    assert_equal @hallway, key.reload.location
    assert_nil key.character
  end

  # The offline mode reads the same records, so a generated room's furniture is
  # takeable there too -- and NO_MODEL is the mode the engine-direct tests run
  # in, so this is the path a scripted sweep walks.
  test "the offline mode takes and drops a generated thing like any other" do
    template = Item::Registry.new(@office).admit!(
      [ { "name" => "gas key", "description" => "A key for the gas taps." } ]
    ).sole

    # The snapshot at the top of the turn is what puts this game's copy on the
    # floor -- the registry wrote a template into a room the party is already
    # standing in, which is the one case arrival cannot cover.
    report = play("take gas key")
    assert_change report, "took: gas key"
    key = @playthrough.carried.find_by(name: "gas key")
    assert_equal template, key.template
    assert_equal @office, template.reload.location

    report = play("drop gas key")
    assert_change report, "dropped: gas key"
    assert_equal @office, key.reload.location
  end

  test "walking back into a realized room generates nothing but the arrival" do
    _report, agent = interpret("into the closet", CLASSIFY.call("move", "The Supply Closet"), ARRIVAL)

    assert_equal @closet, @playthrough.reload.current_location
    assert_equal 2, agent.prompts.count
    assert_equal "A mysterious place filled with wonder and potential adventure", @closet.reload.description
  end

  # The stamps `Playthrough::Turn#play` makes on every branch, so a turn walked
  # here reads afterwards like one walked in the browser -- and a sweep cannot
  # tell them apart. `move` is the only branch in this mode that writes a
  # `Scene` at all, so this is the whole of that obligation.
  test "an arrival records what was typed, what it did, and joins the turn log" do
    before = @playthrough.current_scene

    interpret("into the closet", CLASSIFY.call("move", "The Supply Closet"), ARRIVAL)

    scene = @playthrough.reload.current_scene
    assert_equal "into the closet", scene.typed
    assert_equal "move", scene.resolved_action
    assert_equal @closet, scene.acted_on
    assert_equal before, scene.previous_scene
    assert_includes @playthrough.scene_chain, scene
  end

  # THE PROSE IS THE ONE THING DROPPED. Talking is answered by a character, so
  # it is refused rather than half-played -- and the person it resolved to is
  # still named, because that half is worth seeing.
  test "talking is refused without a character call, and writes no Interaction" do
    report, agent = interpret("ask Rowe what he wants", CLASSIFY.call("talk", "Halkett Rowe"))

    assert_predicate report, :refused?
    assert_equal "talk -> Halkett Rowe", report.understood
    assert_includes report.refusal, "Halkett Rowe"
    assert_includes report.refusal, "prose"
    assert_equal 0, Interaction.count
    assert_equal 1, agent.prompts.count
  end

  test "an examine is refused without a narrator call" do
    report, agent = interpret("look closely at the tube", CLASSIFY.call("examine", "nothing"))

    assert_predicate report, :refused?
    assert_equal "examine -> nothing", report.understood
    assert_includes report.refusal, "prose"
    assert_equal 1, agent.prompts.count
  end

  # DRIFT IS STILL COUNTED, because it is one of the things this mode exists to
  # watch: the classifier reached for a way out that the records do not have.
  test "a reach that resolved to nothing is refused, counted as drift, and changes nothing" do
    report, = interpret("go down to the cellar", CLASSIFY.call("move", "nothing"))

    assert_predicate report, :refused?
    assert_equal "move -> nothing", report.understood
    assert_includes report.refusal, "Playthrough::Drift"
    assert_equal @office, @playthrough.reload.current_location
    assert_equal 1, @playthrough.drifts.count
    assert_equal "move", @playthrough.drifts.sole.action
  end

  # A REFUSAL THAT CONTRADICTED THE READ-OUT UNDER IT. "pickup everything" in a
  # room with three things on the floor resolved to nothing -- a quantifier is
  # not a name -- and the refusal said "Nothing of that name is lying here",
  # directly above a read-out listing all three. The set being empty and the
  # command not landing on anything in it are two different facts.
  test "a reach that found nothing says so without denying what is lying here" do
    report, = interpret("pickup everything", CLASSIFY.call("take", "nothing"))

    assert_predicate report, :refused?
    assert_includes report.refusal, "did not resolve to anything lying here"
    assert_not_includes report.refusal, "Nothing of that name"
    assert_includes report.to_s, @stamp.name, "the read-out still says what is really here"
  end

  test "an empty set is refused by saying it is empty, not that nothing matched" do
    @stamp.update!(location: @closet)

    report, = interpret("pickup everything", CLASSIFY.call("take", "nothing"))

    assert_includes report.refusal, "There is nothing lying here to pick up"
  end

  test "empty hands are refused the same way as an empty floor" do
    @daybook.update!(playthrough: nil, location: @office)

    report, = interpret("drop it all", CLASSIFY.call("drop", "nothing"))

    assert_includes report.refusal, "carrying nothing"
  end

  test "a set with something in it is refused by saying the command did not land on it" do
    report, = interpret("drop the lot", CLASSIFY.call("drop", "nothing"))

    assert_includes report.refusal, "did not resolve to anything you are carrying"
  end

  test "the read-out after a classified command matches the database too" do
    report, = interpret("pick up that stamp", CLASSIFY.call("take", "ward stamp"))
    assert_reads_true report, report.command

    report, = interpret("into the closet", CLASSIFY.call("move", "The Supply Closet"), ARRIVAL)
    assert_reads_true report, report.command
  end

  test "help says what the mode understands, in whichever mode is running" do
    assert_includes Playthrough::Mechanics.new(@playthrough).help.to_s, "Playthrough::Classifier"
    assert_includes Playthrough::Mechanics.new(@playthrough, model: false).help.to_s, "go <exit>"
  end

  # --- talking, in the offline grammar --------------------------------------
  #
  # Talking is prose and this mode writes none, so `talk` here resolves somebody
  # and then refuses. WHETHER it resolves is an engine question, and since
  # presence became a record (`Character.present_in`) it is one that can be
  # answered with no model at all -- which is what lets `rake game:sweep`
  # regression-test who is in a room.

  test "a talk offline resolves somebody the records place here, and then refuses the prose" do
    report = play("talk to Halkett Rowe")

    assert_equal "talk -> Halkett Rowe", report.understood
    assert_predicate report, :refused?
    assert_not report.changed?
    assert_includes report.refusal, "talking is prose"
  end

  # A person answers to two names and both are in the closed enum the classifier
  # offers a model, so both have to resolve here or the offline grammar would
  # refuse a name the classifier accepts.
  test "a talk offline resolves a nickname too" do
    @rowe.update!(nickname: "Sub-Inspector Rowe")

    assert_equal "talk -> Halkett Rowe", play("talk to the Sub-Inspector").understood
  end

  # THE ACCEPTANCE CASE. Somebody the records place in another room is not here,
  # and the refusal names the cast that IS.
  test "a talk to somebody recorded in another room is refused with the cast that is here" do
    create(:character, story: @story, fullname: "Perrin Lasco", location: @closet)

    report = play("talk to Perrin Lasco")

    assert_predicate report, :refused?
    assert_includes report.refusal, "there is no person here"
    assert_includes report.refusal, "Halkett Rowe"
  end

  test "an empty room is refused differently from a name that missed" do
    @rowe.move_to!(@closet)

    assert_includes play("talk").refusal, "There is nobody here."
    assert_includes play("talk to Halkett Rowe").refusal, "there is no person here"
  end

  test "nobody is moved by talking, or by failing to" do
    play("talk to Halkett Rowe")
    play("talk to Perrin Lasco")

    assert_equal @office, @rowe.reload.location
  end

  test "the offline grammar says it understands talking" do
    assert_includes Playthrough::Mechanics.new(@playthrough, model: false).help.to_s, "talk <person>"
  end

  # --- a room born with somebody in it --------------------------------------
  #
  # The captain's ruling, walked end to end: the world writes a room, the room
  # comes out with a person in it, and the very next line the player types can
  # reach them. This is the classifier mode, so the world really generates --
  # `Playthrough::Turn#move_to` whole, `Location::Generator` and
  # `Scene::Generator` both.

  test "walking into an unwritten room that generates a person lists them and lets a talk resolve" do
    peopled = DETAIL.merge("people" => [ {
      "fullname" => "Perrin Lasco", "nickname" => "Perrin",
      "appearance" => "Slight, dark-haired, a copy-room apron over ordinary clothes.",
      "personality" => "Quick, funny, and careful in a way people mistake for nerves.",
      "backstory" => "Perrin Lasco keeps a private index of every amendment that came through the ward.",
      "likes" => "An index that catches something, other people's strong tea",
      "dislikes" => "Being asked to repeat his name, doors that lock from one side",
      "fears" => "Being closed quietly, on a Tuesday"
    } ])

    report, = interpret("out into the long hallway",
                        CLASSIFY.call("move", @hallway.name), peopled, { "exits" => [] }, ARRIVAL)

    lasco = Character.present_in(@hallway).sole
    assert_equal "Perrin Lasco", lasco.fullname
    assert_predicate @hallway.reload, :realized?
    assert_equal [ lasco ], report.state.present
    assert_includes report.state.to_s, "present     Perrin Lasco"

    # AND THE VERY NEXT LINE REACHES THEM. `Character.present_in` is the closed
    # set, so the classifier's cast and the read-out are the same answer.
    talk, = interpret("ask Perrin about the index", CLASSIFY.call("talk", "Perrin Lasco"))

    assert_equal "talk -> Perrin Lasco", talk.understood
    assert_includes talk.refusal, "Perrin Lasco is here"
  end

  # THE ARRIVAL CAST IS WRITTEN FROM THE RECORDS, not the other way round: the
  # person is created and placed before `Scene::Generator` reads who is here.
  test "the arrival scene records the person the room was born with" do
    peopled = DETAIL.merge("people" => [ {
      "fullname" => "Perrin Lasco", "nickname" => "Perrin",
      "appearance" => "Slight and dark-haired.", "personality" => "Quick and careful.",
      "backstory" => "Perrin Lasco kept an index nobody asked for.",
      "likes" => "Strong tea", "dislikes" => "Being asked twice", "fears" => "A quiet Tuesday"
    } ])

    interpret("out into the long hallway", CLASSIFY.call("move", @hallway.name), peopled, { "exits" => [] }, ARRIVAL)

    arrival = @hallway.scenes.order(:id).last
    assert_equal [ "Odile Vance", "Perrin Lasco" ], arrival.characters.order(:id).pluck(:fullname)
  end

  # --- the closed sets ------------------------------------------------------

  test "the read-out offers exactly what the classifier would offer a model" do
    classifier = Playthrough::Classifier.new(@playthrough)
    state = Playthrough::Mechanics.new(@playthrough).state

    assert_equal classifier.exits_here, state.exits
    assert_equal classifier.items_here, state.items_here
    assert_equal classifier.items_carried, state.carried
    assert_equal classifier.characters_here, state.present
  end

  test "a playthrough with no protagonist cannot carry anything, and says so" do
    @playthrough.update!(character: nil)

    assert_refusal play("take stamp"), "no protagonist"
    refute_predicate @stamp.reload, :carried?
  end

  test "a playthrough standing nowhere has no room to put anything down in" do
    @playthrough.update!(current_location: nil)
    report = play("drop daybook")

    assert_refusal report, "standing nowhere"
    assert_equal @playthrough, @daybook.reload.playthrough
    assert_includes report.to_s, "nowhere"
  end

  private

  def assert_change(report, expected)
    refute_predicate report, :refused?, "expected a change, got: #{report.refusal}"
    assert_includes report.change, expected
    assert_reads_true report, report.command
  end

  def assert_refusal(report, expected)
    assert_predicate report, :refused?, "expected a refusal, got: #{report.change}"
    assert_includes report.refusal, expected
    assert_nil report.change, "a refused command must not report a change"
    assert_reads_true report, report.command
  end

  # THE ACCEPTANCE TEST, applied to every command in this file: what was printed
  # is what the database holds, read back independently of the class that
  # printed it.
  def assert_reads_true(report, command)
    @playthrough.reload
    state = report.state
    here = @playthrough.current_location
    who = @playthrough.character
    where = "after #{command.inspect}"

    # `nil` on either side is a real state -- a playthrough can stand nowhere and
    # can have no protagonist -- and both are empty sets rather than "everything
    # whose column is null", which is what an unguarded scope would answer.
    if here.nil?
      assert_nil state.location, where
    else
      assert_equal here, state.location, where
    end

    assert_equal here ? here.exits.order(:id).to_a : [], state.exits, where
    # THIS GAME'S FLOOR, not the world's. `Item.lying_in` reaches both layers,
    # and the read-out prints the closed set `take` resolves against, which is
    # this playthrough's own copies (`Playthrough#items_lying_in`).
    assert_equal @playthrough.items_lying_in(here).to_a, state.items_here, where
    assert_equal @playthrough.carried.to_a, state.carried, where

    state.items_here.each { |item| assert_equal here, item.reload.location, where }
    state.carried.each { |item| assert_predicate item.reload, :carried?, where }
    state.carried.each { |item| assert_equal @playthrough, item.playthrough, where }

    # And the printed block names them, so a read-out cannot be right in the
    # records and wrong on the screen.
    (state.items_here + state.carried).each { |item| assert_includes report.to_s, item.name, where }
    state.exits.each { |exit| assert_includes report.to_s, exit.name, where }
  end
  # --- a line that named more than one thing ---------------------------------

  # ONE LINE IS ONE ACT, and this mode used to DO the first of the two and add a
  # note about the second: `also named: copy-room apron -- one line is one act,
  # so this turn did not touch it`. That was the honest report of a half-played
  # turn. On the captain's ruling of 2026-09-04 there is no half-played turn --
  # the line is refused whole and the player is asked to pick one, in the same
  # words the browser uses (`Playthrough::Refusal`).
  test "a line that names two things is refused whole and moves neither" do
    apron = lying_here(@playthrough, @office, name: "copy-room apron")

    report, = interpret("pickup the ward stamp and the apron",
                        CLASSIFY.call("take", @stamp.name, apron.name))

    assert_predicate report, :refused?
    assert_not_predicate report, :changed?
    refute_predicate @stamp.reload, :carried?, "the first thing is not taken either"
    assert_equal @office, @stamp.location
    refute_predicate apron.reload, :carried?
    assert_equal @office, apron.location

    assert_includes report.refusal, "two things at once"
    assert_includes report.refusal, "take ward stamp"
    assert_includes report.refusal, "take copy-room apron"
    assert_includes report.refusal, "One line is one act"
    assert_includes report.refusal, "Playthrough::Overreach"

    # The reading names BOTH, or `understood: take -> ward stamp` printed above
    # a refusal would read as though the stamp had been taken.
    assert_equal "take -> ward stamp (and copy-room apron)", report.understood
  end

  # The second name goes through the same closed set as the action, so a talk's
  # is another person and never an item -- and a talk this mode would have
  # refused for being prose is refused for the ruling instead, one step earlier.
  test "two people named on one line is refused before the prose refusal" do
    lasco = create(:character, story: @story, fullname: "Perrin Lasco", location: @office)

    report, = interpret("ask Rowe and Lasco where the file went",
                        CLASSIFY.call("talk", @rowe.fullname, lasco.fullname))

    assert_predicate report, :refused?
    assert_includes report.refusal, "talk to Halkett Rowe"
    assert_includes report.refusal, "talk to Perrin Lasco"
    assert_not_includes report.refusal, "talking is prose"
  end

  # THE REFUSAL DOES NOT REPEAT THE READ-OUT, which is printed under every
  # report in this mode. The browser has no read-out and gets the lists; here
  # they would be said twice and could contradict what is printed below.
  test "the refusal leaves the lists to the read-out under it" do
    report, = interpret("go down to the cellar", CLASSIFY.call("move", "nothing"))

    assert_includes report.refusal, "did not resolve to one of the ways out"
    assert_not_includes report.refusal, "The ways out are:"
    assert_includes report.to_s, @closet.name, "the read-out is where the records are printed"
  end

  # A READ IS AN ACT LIKE ANY OTHER, so a line naming two readable things is
  # refused before this mode recites either of them.
  test "a read that names two things is refused before it recites either" do
    note = lying_here(@playthrough, @office, name: "folded note",
                                 readable: true, inscription: "Midnight. The Bell.")

    report, = interpret("read the note and the daybook",
                        CLASSIFY.call("examine", note.name, @daybook.name))

    assert_predicate report, :refused?
    assert_includes report.refusal, "read folded note"
    assert_includes report.refusal, "read Ward Office 12 daybook"
    assert_includes report.refusal, "Playthrough::Overreach"
    assert_not_includes report.to_s, "reads:", "neither one was recited"
  end

  # And a look that landed on nothing is not refused for the ruling -- it is
  # refused for being prose, which is this mode's own rule and a different
  # sentence.
  test "a look that resolved to nothing is refused as prose and not as a reach" do
    report, = interpret("look at the ceiling", CLASSIFY.call("examine", "nothing"))

    assert_predicate report, :refused?
    assert_includes report.refusal, "answered in prose"
    assert_not_includes report.refusal, "Playthrough::Drift"
    assert_equal 0, @playthrough.drifts.count
  end

  test "a line that names one thing is played" do
    report, = interpret("take the stamp", CLASSIFY.call("take", @stamp.name))

    assert_predicate report, :changed?
    assert_not_predicate report, :refused?
    assert_equal @playthrough, @stamp.reload.playthrough
  end

  # The offline grammar has no way to name two things, and does not pretend to:
  # `also_named` is the classifier's answer and there is no classifier here.
  test "the offline grammar names one thing and plays it" do
    report = play("take stamp")

    assert_predicate report, :changed?
    assert_not_predicate report, :refused?
  end

  # --- the body, and the engine-view commands ------------------------------
  #
  # `vitals`, `harm <n>` and `mend <n>` are the engine's own instruments rather
  # than things a player does in the fiction, so they are read by the fixed
  # grammar IN BOTH MODES and make no model call at all. The walk of the ruling
  # itself is `lib/engine_sweep/scripts/death-ends-a-playthrough.yml`; these pin
  # the two things a script cannot see -- that the classifier is never reached,
  # and what the read-out says.

  test "the read-out carries the player's condition" do
    assert_includes play("look").state.to_s, "condition   unhurt"
  end

  test "harm goes through the engine's own writer and says what it did" do
    report = play("harm 3")

    assert_predicate report, :changed?
    assert_equal "harm -> 3 hit points", report.understood
    assert_includes report.change, "Odile Vance unhurt -> "
    assert_equal @vance.max_hp - 3, @playthrough.vitals_for(@vance).hp
  end

  test "mend is the mirror and stops at the maximum" do
    play("harm 2")
    report = play("mend 99")

    assert_predicate report, :changed?
    assert_equal @vance.max_hp, @playthrough.vitals_for(@vance).hp
    assert_includes report.change, "-> unhurt"
  end

  test "harm without a number is refused with the shape it wanted" do
    report = play("harm")

    assert_predicate report, :refused?
    assert_match(/takes a whole number/, report.refusal)
  end

  test "harm of something that is not a number is refused rather than read as zero" do
    report = play("harm a lot")

    assert_predicate report, :refused?
    assert_not_predicate report, :changed?
  end

  test "harm of zero is refused rather than quietly doing nothing" do
    assert_predicate play("harm 0"), :refused?
  end

  # WITH A MODEL AVAILABLE THEY STILL MAKE NO CALL. `Playthrough::IntentSchema`
  # has no word for any of them, so classifying one could only ever come back
  # `other` -- and it would cost a model call to be told so. `#interpret` with
  # NO allowed responses is what asserts it: `FakeAgent` runs out if anything
  # asks.
  test "the engine-view commands are not classified even when a model is there" do
    report, agent = interpret("harm 2")

    assert_predicate report, :changed?
    assert_equal @vance.max_hp - 2, @playthrough.vitals_for(@vance).hp
    assert_empty agent.prompts
  end

  test "vitals reads and changes nothing, in either mode" do
    report, agent = interpret("vitals")

    assert_not_predicate report, :changed?
    assert_not_predicate report, :refused?
    assert_empty agent.prompts
  end

  # --- which reader answered ------------------------------------------------

  # THE MODE AND THE BROWSER READ A LINE THE SAME WAY, which is the whole reason
  # `Playthrough::Grammar` is a class and not this file's private half. The
  # captain's ruling of 2026-09-05: *"I think we should only auto accept the
  # slash commands."* So a SLASHED line is answered offline in this mode too.
  test "a slashed line the grammar resolves costs this mode no model call" do
    report, agent = interpret("/take the ward stamp")

    assert_equal "take -> ward stamp", report.understood
    assert_equal "grammar", report.resolved_by
    assert_includes report.change, "took: ward stamp"
    assert_empty agent.prompts
  end

  # AND AN UNSLASHED LINE IS UNTOUCHED, whatever it begins with. This is the
  # captain's objection of 2026-09-05 as a test -- `take` is one of the grammar's
  # own verbs and the line still costs a classifier call, because a leading verb
  # is a coincidence of English and not a player asking for the command language.
  test "the same line without a slash still goes to the classifier" do
    report, agent = interpret("take the ward stamp", CLASSIFY.call("take", "ward stamp"))

    assert_equal "model", report.resolved_by
    assert_equal 1, agent.prompts.count
    assert_includes report.change, "took: ward stamp"
  end

  test "an engine-view verb is answered by the engine and named as such" do
    report, agent = interpret("stats")

    assert_equal "engine_view", report.resolved_by
    assert_empty agent.prompts
  end

  # The read-out prints which reader answered, under the reading itself, because
  # "it did not understand me" and "the wrong reader read it" are different bugs.
  test "the read-out says which reader answered" do
    report, = interpret("/take the ward stamp")

    assert_includes report.to_s, "read by:    grammar"
  end

  # A move is the one branch this mode writes a `Scene` from, so it is the one
  # place `scenes.resolved_by` can be checked from here at all.
  test "a move stamps the scene with the reader that resolved it" do
    report, agent = interpret("/go to The Long Hallway", DETAIL, { "exits" => [] }, ARRIVAL)
    scene = @playthrough.reload.current_scene

    assert_equal "grammar", report.resolved_by
    assert_equal "grammar", scene.resolved_by
    assert_equal "move", scene.resolved_action
    # The slash comes off before the line is recorded, here exactly as it does
    # in the browser: `Scene#typed` is what the engine read, and every corpus
    # that reads it goes on seeing ordinary English.
    assert_equal "go to The Long Hallway", scene.typed
    assert_equal 3, agent.prompts.count, "two realization calls and the arrival, and no classification"
  end

  # `help` was always read here rather than sent to a model, and the classifier
  # mode has its own help. Adding three verbs beside it must not have changed
  # which one either mode prints.
  test "help still prints the mode's own list" do
    assert_includes play("help").note, Playthrough::Grammar::HELP.first
    assert_includes interpret("help").first.note, Playthrough::Mechanics::CLASSIFIER_HELP.first
  end

  test "there is nothing to harm on a protagonist with no stat block" do
    @vance.update!(level: nil, hit_die: nil)
    report = play("harm 2")

    assert_predicate report, :refused?
    assert_match(/no stat block/, report.refusal)
  end

  # --- the sheet, and the check kernel --------------------------------------
  #
  # `stats` reads and `check <ability> [penalty]` throws one d20 and WRITES
  # NOTHING, which is what makes it the one verb here safe to type into a real
  # game as often as you like. Both are engine-view commands, so neither costs
  # a model call in either mode. The walk is
  # `lib/engine_sweep/scripts/a-check-against-an-ability.yml`; these pin what a
  # script cannot see.

  test "the read-out carries the world's own numbers for the player" do
    @vance.update!(level: 1, hit_die: 6, strength: 9, dexterity: 11, will: 15)

    read_out = play("stats").state.to_s

    assert_includes read_out, "sheet       level 1, d6, strength 9 dexterity 11 will 15"
  end

  test "a check prints the roll and changes nothing" do
    @vance.update!(strength: 12)

    report = play("check strength")

    assert_not_predicate report, :changed?
    assert_not_predicate report, :refused?
    assert_equal "check -> strength", report.understood
    assert_match(/\Acheck strength -> d20\(\d+\) <= 12 (PASS|FAIL)\z/, report.note.sole)
  end

  # The die is `Playthrough::Turn#check`'s, which is seeded -- so the read-out
  # and the engine cannot disagree about the roll, and a sweep can assert it.
  test "the roll it prints is the roll the engine makes" do
    @vance.update!(strength: 12)
    wanted = Playthrough::Turn.new(@playthrough).check(@vance, :strength)

    assert_match(/d20\(#{wanted.die}\)/, play("check strength").note.sole)
  end

  test "a penalty is taken off the target and named in the reading" do
    @vance.update!(dexterity: 14)

    report = play("check dexterity 4")

    assert_equal "check -> dexterity (penalty 4)", report.understood
    assert_match(/<= 10 /, report.note.sole)
  end

  # An unambiguous prefix, because a player at a prompt is not a JSON enum --
  # and NOT a fragment, because a three-word list would let `check ill` mean
  # `will`.
  test "an ability may be named by an unambiguous prefix and not by a fragment" do
    assert_equal "check -> dexterity", play("check dex").understood
    assert_predicate play("check ill"), :refused?
  end

  test "a check with no ability is refused with the three there are" do
    report = play("check")

    assert_predicate report, :refused?
    assert_match(/strength, dexterity, will/, report.refusal)
  end

  test "a penalty that is not a number is refused rather than read as zero" do
    report = play("check will lots")

    assert_predicate report, :refused?
    assert_match(/a penalty is a whole number/, report.refusal)
  end

  # A REFUSAL AND NOT A ROLL: the pass rate at a target of zero or less is zero
  # for ever, so the engine says the thing cannot be done.
  test "a check it cannot win is refused instead of rolled" do
    @vance.update!(strength: 6)

    report = play("check strength 6")

    assert_predicate report, :refused?
    assert_match(/cannot do it at all/, report.refusal)
    assert_match(/No die was thrown/, report.refusal)
  end

  test "there is nothing to check on a protagonist with no abilities" do
    @vance.update!(strength: nil, dexterity: nil, will: nil)

    report = play("check will")

    assert_predicate report, :refused?
    assert_match(/no abilities/, report.refusal)
  end

  test "stats and check are not classified even when a model is there" do
    _, reading = interpret("stats")
    assert_empty reading.prompts

    @vance.update!(strength: 12)
    report, agent = interpret("check strength")

    assert_empty agent.prompts
    assert_match(/check strength -> d20/, report.note.sole)
  end

  # `check` IS THE ONE ENGINE-VIEW WORD A PLAYER PLAUSIBLY MEANS IN THE FICTION.
  # *"check the ledger"* is ordinary English, so with a model available it goes
  # to the classifier like any other line rather than being swallowed here --
  # otherwise the instrument would have cost the mode a verb.
  test "check followed by something that is not an ability goes to the classifier" do
    report, agent = interpret("check the daybook", CLASSIFY.call("examine", "nothing"))

    assert_equal 1, agent.prompts.size
    assert_match(/examine/, report.understood)
  end

  # With no model there is nothing to hand it to, so the fixed grammar answers.
  test "offline, check of something that is not an ability is refused by the grammar" do
    report = play("check the daybook")

    assert_predicate report, :refused?
    assert_match(/not one of the three abilities/, report.refusal)
  end
end
