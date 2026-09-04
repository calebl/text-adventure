require "test_helper"

# The classifier is one model call, and everything either side of it is the
# part worth testing: what candidates the model is offered, and what its answer
# resolves back to. Both directions have to agree -- a name the prompt did not
# offer cannot resolve, and a name that resolves to nothing has to leave the
# loop free to narrate a failure instead of moving the player somewhere.
#
# Never a live model: FakeAgent stands in at the BaseAgent boundary.
class Playthrough::ClassifierTest < ActiveSupport::TestCase
  include SchemaAssertions

  def setup
    @story = create(:story)
    @protagonist = create(:character, story: @story, fullname: "Iri Calder", is_protagonist: true)
    @here = create(:location, story: @story, name: "Ashgate Market")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @here)
  end

  def classify(answer, command: "go on then")
    agent = FakeAgent.new(answer)
    intent = BaseAgent.stub(:new, agent) do
      Playthrough::Classifier.new(@playthrough).classify(command)
    end

    [ intent, agent ]
  end

  def connect(name, distance: "adjacent", travel_method: "walking", **attributes)
    neighbour = create(:location, story: @story, name: name, **attributes)
    create(:location_connection, location: @here, connected_location: neighbour,
                                 distance: distance, travel_method: travel_method)
    neighbour
  end

  # --- resolving a move ----------------------------------------------------

  test "a move resolves to the exit record the player named" do
    stair = connect("The Sunken Stair")

    intent, = classify({ "intent" => "move", "target" => "The Sunken Stair" })

    assert intent.move?
    assert_equal stair, intent.destination
    assert_nil intent.speaker
  end

  test "an exit is resolved by name regardless of case" do
    stair = connect("The Sunken Stair")

    intent, = classify({ "intent" => "move", "target" => "the sunken stair" })

    assert_equal stair, intent.destination
  end

  # A stub is exactly what the player is meant to be able to walk into: it is
  # only realized because they chose it.
  test "a stub exit is a legitimate destination" do
    vestibule = connect("Drowned Vestibule", detail_level: "stub", description: nil, lore: nil)

    intent, = classify({ "intent" => "move", "target" => "Drowned Vestibule" })

    assert_equal vestibule, intent.destination
    assert_predicate vestibule, :stub?
  end

  # The point of the closed enum. If a name does get through that resolves to
  # nothing, the loop must fall through to narration rather than guess.
  test "a move nobody can make resolves to no destination" do
    connect("The Sunken Stair")

    intent, = classify({ "intent" => "move", "target" => "nothing" })

    assert intent.move?
    assert_nil intent.destination
  end

  test "a place that is not an exit from here resolves to no destination" do
    create(:location, story: @story, name: "Somewhere Else Entirely")

    intent, = classify({ "intent" => "move", "target" => "Somewhere Else Entirely" })

    assert_nil intent.destination
  end

  # --- resolving a talk ----------------------------------------------------

  test "a talk resolves to the character standing here" do
    maren = stands_here("Maren Vosk", nickname: "Maren")

    intent, = classify({ "intent" => "talk", "target" => "Maren Vosk" })

    assert intent.talk?
    assert_equal maren, intent.speaker
    assert_nil intent.destination
  end

  # A player types the name they were shown, and an arrival paragraph calls
  # people by their nickname as often as their full name.
  test "a talk resolves by nickname too" do
    maren = stands_here("Maren Vosk", nickname: "Maren")

    intent, = classify({ "intent" => "talk", "target" => "Maren" })

    assert_equal maren, intent.speaker
  end

  test "a talk with nobody here resolves to no speaker" do
    intent, = classify({ "intent" => "talk", "target" => "nothing" })

    assert intent.talk?
    assert_nil intent.speaker
  end

  # --- the other three -----------------------------------------------------

  test "an action never resolves against a set that is not its own" do
    connect("The Sunken Stair")
    stands_here("Maren Vosk")

    %w[examine take other].each do |action|
      intent, = classify({ "intent" => action, "target" => "The Sunken Stair" })

      assert_equal action.to_sym, intent.action
      assert_nil intent.destination
      assert_nil intent.speaker
      assert_nil intent.item
    end
  end

  # --- looking at something -------------------------------------------------

  # `examine` IS THE ONLY ACTION THAT READS BOTH ITEM SETS. Looking at a thing
  # does not move it, so neither the floor nor the hands is the wrong one -- and
  # `Playthrough::Turn#read_item` is what is on the other side of the seam.
  test "an examine resolves to a thing lying here" do
    note = lying_here(@playthrough, @here, name: "folded note")

    intent, = classify({ "intent" => "examine", "target" => "folded note" })

    assert intent.examine?
    assert_equal note, intent.item
    assert_nil intent.destination
    assert_nil intent.speaker
  end

  test "an examine resolves to a thing the party is carrying" do
    daybook = create(:item, :carried, playthrough: @playthrough, name: "the daybook")

    intent, = classify({ "intent" => "examine", "target" => "the daybook" })

    assert_equal daybook, intent.item
  end

  # The floor first, because that is the order the prompt lists the two sets in
  # and the order `Playthrough::Moment` states them to the narrator. With two
  # things of one name it resolves the nearer one, stably.
  test "two things of one name resolve to the one lying here" do
    here = lying_here(@playthrough, @here, name: "folded note")
    create(:item, :carried, playthrough: @playthrough, name: "folded note")

    intent, = classify({ "intent" => "examine", "target" => "folded note" })

    assert_equal here, intent.item
  end

  test "both item sets are offered to an examine, and each name once" do
    lying_here(@playthrough, @here, name: "folded note")
    create(:item, :carried, playthrough: @playthrough, name: "the daybook")

    _intent, agent = classify({ "intent" => "examine", "target" => "folded note" })

    enum = agent.schemas.last.new.to_json_schema.dig(:schema, :properties, :target, :enum)
    assert_equal [ "folded note", "the daybook", "nothing" ], enum
  end

  # A model that answers outside its own enum is the failure BaseAgent exists to
  # distrust. Treating it as `other` narrates the turn, which is the safe
  # outcome; treating it as a move would send the player somewhere on a typo.
  test "an intent outside the fixed set becomes other" do
    intent, = classify({ "intent" => "wander vaguely", "target" => "nothing" })

    assert_equal :other, intent.action
  end

  # --- the candidates the model is offered ---------------------------------

  test "the target enum is exactly the exits and the people here" do
    connect("The Sunken Stair")
    stands_here("Maren Vosk", nickname: "Maren")

    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    enum = agent.schemas.last.new.to_json_schema.dig(:schema, :properties, :target, :enum)
    assert_equal [ "The Sunken Stair", "Maren Vosk", "Maren", "nothing" ], enum
  end

  test "the prompt names the room, its exits and who is in it" do
    connect("The Sunken Stair", distance: "adjacent", travel_method: "taking stairs")
    stands_here("Maren Vosk", nickname: "Maren")

    _intent, agent = classify({ "intent" => "other", "target" => "nothing" }, command: "look around")
    prompt = agent.prompts.first

    assert_match(/Ashgate Market/, prompt)
    assert_match(/- The Sunken Stair \(adjacent, taking stairs\)/, prompt)
    assert_match(/- Maren Vosk \(Maren\)/, prompt)
    assert_match(/look around/, prompt)
  end

  # The player is not somebody to talk to, and offering them as a candidate is
  # how "talk to myself" becomes a resolvable move.
  test "the protagonist is not offered as somebody to talk to" do
    stands_here("Maren Vosk")

    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    assert_no_match(/Iri Calder/, agent.prompts.first)
  end

  # Not decoration: a room with no way out and nobody in it is a real state
  # (`Location::Generator` can leave a room short of its exits), and the prompt
  # has to say so rather than showing the model two empty headings.
  test "an empty room says so in words" do
    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })
    prompt = agent.prompts.first

    assert_match(/cannot go anywhere/, prompt)
    assert_match(/no one here to talk to/, prompt)
  end

  test "the instructions tell the model not to narrate" do
    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    assert_match(/do not narrate/i, agent.instructions)
  end

  # --- who counts as present ------------------------------------------------

  # One list, decided in one place. Scene::Generator writes the cast onto the
  # arrival scene; this reads that same answer back, so the classifier accepts
  # exactly the people the arrival paragraph introduced.
  # "pickup everything" used to resolve to nothing, which refused the turn and
  # wrote a Playthrough::Drift row -- and drift is the count of the player
  # reaching for what the records DO NOT HAVE. Everything named existed; `all`
  # is a quantifier and not a missing name. `take all`, `get everything` and
  # `drop all` are ordinary text-adventure verbs, so this was a standing stream
  # of drift rows with no drift in them.
  test "the instructions tell the model that a collective word names the list" do
    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    assert_includes agent.instructions, "means ALL of them"
    assert_includes agent.instructions, "is not `nothing`"
    assert_includes agent.instructions, "also_named"
  end

  # And when it answers that way, the turn lands in the path that exists: two
  # names resolved out of one list, counted as an overreach and NOT as drift.
  # What the loop then DOES with it changed on 2026-09-04 -- the line is refused
  # whole rather than half-played -- and the count did not; see
  # `Playthrough::Overreach`.
  test "a collective word answered as the first thing is an overreach and not drift" do
    index = lying_here(@playthrough, @here, name: "Perrin's private index")
    lying_here(@playthrough, @here, name: "copy-room apron")

    assert_difference "Playthrough::Overreach.count", 1 do
      assert_no_difference "Playthrough::Drift.count" do
        intent, = classify({ "intent" => "take", "target" => index.name, "also_named" => "copy-room apron" },
                           command: "pickup everything")

        assert_equal index, intent.item
      end
    end
  end

  # The other direction of the same guarantee. A collective read against the
  # wrong list would resolve to nothing and be counted as drift again, so which
  # set each action reads is the part worth pinning: `drop everything` and `put
  # down everything` both answer out of the player's hands, never the floor.
  test "a collective drop resolves out of the player's hands and is an overreach" do
    lying_here(@playthrough, @here, name: "copy-room apron")
    sextant = create(:item, :carried, playthrough: @playthrough, name: "brass sextant")
    create(:item, :carried, playthrough: @playthrough, name: "chart tube")

    [ "drop everything", "put down everything" ].each do |command|
      assert_difference "Playthrough::Overreach.count", 1 do
        assert_no_difference "Playthrough::Drift.count" do
          intent, = classify({ "intent" => "drop", "target" => sextant.name, "also_named" => "chart tube" },
                             command: command)

          assert_equal sextant, intent.item
          assert_equal "chart tube", intent.also_named.name
        end
      end
    end

    assert_equal "drop", Playthrough::Overreach.last.action
  end

  test "the cast is Scene::Generator's answer, minus the player" do
    maren = stands_here("Maren Vosk")
    companion = create(:character, story: @story, fullname: "Dell Roy", is_companion: true)

    cast = Playthrough::Classifier.new(@playthrough).characters_here

    assert_equal [ maren, companion ].sort_by(&:id), cast.sort_by(&:id)
    assert_not_includes cast, @protagonist
  end

  test "a playthrough that is nowhere offers nothing to aim at" do
    adrift = create(:playthrough, story: @story, character: @protagonist)

    classifier = Playthrough::Classifier.new(adrift)

    assert_empty classifier.exits_here
    assert_empty classifier.characters_here
  end

  # --- resolving a take -----------------------------------------------------

  test "a take resolves to the item record lying in this room" do
    key = lying_here(@playthrough, @here, name: "Brass Key")

    intent, = classify({ "intent" => "take", "target" => "Brass Key" })

    assert intent.take?
    assert_equal key, intent.item
    assert_nil intent.destination
    assert_nil intent.speaker
  end

  test "an item is resolved by name regardless of case" do
    key = lying_here(@playthrough, @here, name: "Brass Key")

    intent, = classify({ "intent" => "take", "target" => "brass key" })

    assert_equal key, intent.item
  end

  test "what is lying here is offered by name" do
    lying_here(@playthrough, @here, name: "Brass Key")

    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    assert_match(/## What Is Lying Here\n- Brass Key/, agent.prompts.first)
  end

  test "an empty floor says so in words" do
    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    assert_match(/nothing here to pick up/, agent.prompts.first)
  end

  # THE CLOSED SET. An item somebody is holding is not takeable, so it is not
  # offered and cannot be resolved -- taking something off a person is a
  # different act with somebody on the other side of it.
  test "an item in somebody else's hands is not offered and does not resolve" do
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    create(:item, character: landlord, name: "Iron Ledger")

    intent, agent = classify({ "intent" => "take", "target" => "Iron Ledger" })

    assert_no_match(/Iron Ledger/, agent.prompts.first)
    assert_nil intent.item
  end

  test "an item lying in another room is not offered" do
    elsewhere = create(:location, story: @story, name: "The Bell of Saint Aravel")
    lying_here(@playthrough, elsewhere, name: "Iron Ledger")

    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    assert_no_match(/Iron Ledger/, agent.prompts.first)
  end

  # A name the app never offered cannot become an item, whatever comes back.
  # The enum makes this unreachable in production; the test is here because the
  # resolution is the seam that decides what the player is carrying.
  test "a name that was never offered resolves to no item at all" do
    lying_here(@playthrough, @here, name: "Brass Key")

    intent, = classify({ "intent" => "take", "target" => "Skeleton Key" })

    assert_nil intent.item
    assert intent.take?
  end

  test "the item names are in the schema's closed enum alongside exits and cast" do
    connect("The Sunken Stair")
    stands_here("Maren Vosk")
    lying_here(@playthrough, @here, name: "Brass Key")

    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })
    enum = json_schema_body(agent.schemas.first)["properties"]["target"]["enum"]

    assert_includes enum, "Brass Key"
    assert_includes enum, "The Sunken Stair"
    assert_includes enum, "Maren Vosk"
  end

  # --- resolving a drop -----------------------------------------------------

  # THE OTHER HALF OF THE SAME GUARANTEE. Taking is app-owned and dropping has
  # to be too, or the records go stale the first time a player puts something
  # down.

  test "a drop resolves to the item record the player is carrying" do
    key = create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    intent, = classify({ "intent" => "drop", "target" => "Brass Key" })

    assert intent.drop?
    assert_equal key, intent.item
    assert_nil intent.destination
  end

  test "what the player is carrying is offered by name" do
    create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    assert_match(/## What The Player Is Carrying\n- Brass Key/, agent.prompts.first)
  end

  test "empty hands say so in words" do
    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    assert_match(/carrying nothing at all/, agent.prompts.first)
  end

  # A player cannot drop what the records do not say they hold, however
  # confidently some earlier narration said they picked it up.
  test "an item the player does not hold is not offered to drop and does not resolve" do
    landlord = create(:character, story: @story, fullname: "Grenn Ollivar")
    create(:item, character: landlord, name: "Iron Ledger")

    intent, agent = classify({ "intent" => "drop", "target" => "Iron Ledger" })

    assert_no_match(/Iron Ledger/, agent.prompts.first)
    assert_nil intent.item
  end

  test "an item lying on the floor is not something the player can drop" do
    lying_here(@playthrough, @here, name: "Brass Key")

    intent, = classify({ "intent" => "drop", "target" => "Brass Key" })

    assert_nil intent.item, "the key is on the floor, not in the player's hands"
  end

  # The two closed sets are disjoint by construction -- an item is in exactly
  # one place -- so the same name in both lists means two different rows, and
  # each action resolves against its own list.
  test "take and drop resolve against their own lists" do
    floor = lying_here(@playthrough, @here, name: "Brass Key")
    carried = create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    taken, = classify({ "intent" => "take", "target" => "Brass Key" })
    dropped, = classify({ "intent" => "drop", "target" => "Brass Key" })

    assert_equal floor, taken.item
    assert_equal carried, dropped.item
  end

  test "a playthrough with nobody to carry anything offers nothing to drop" do
    nobody = create(:playthrough, story: @story, current_location: @here)

    assert_empty Playthrough::Classifier.new(nobody).items_carried
  end

  # --- counting drift -------------------------------------------------------

  test "a move that resolved to nothing is counted, with what was on offer" do
    connect("The Sunken Stair")

    assert_difference "Playthrough::Drift.count", 1 do
      classify({ "intent" => "move", "target" => "nothing" }, command: "go through the cellar door")
    end

    drift = Playthrough::Drift.last

    assert_equal "move", drift.action
    assert_equal "go through the cellar door", drift.command
    assert_equal [ "The Sunken Stair" ], drift.offered_names
    assert_equal @here, drift.location
    assert_equal @playthrough, drift.playthrough
  end

  # The narration the player had just read is the evidence, and the reason the
  # scene is on the row at all.
  test "the drift points at the narration the player had just read" do
    read = create(:scene, story: @story, location: @here,
                          description: "A cellar door stands open in the far wall.")
    @playthrough.update!(current_scene: read)

    classify({ "intent" => "move", "target" => "nothing" }, command: "go through the cellar door")

    assert_equal read, Playthrough::Drift.last.scene
  end

  test "a talk that resolved to nobody is counted, offering the cast that was here" do
    stands_here("Maren Vosk")

    assert_difference "Playthrough::Drift.count", 1 do
      classify({ "intent" => "talk", "target" => "nothing" }, command: "talk to the ghost")
    end

    drift = Playthrough::Drift.last

    assert_equal "talk", drift.action
    assert_includes drift.offered_names, "Maren Vosk"
  end

  test "a take that resolved to nothing is counted, offering what was lying here" do
    lying_here(@playthrough, @here, name: "Brass Key")

    assert_difference "Playthrough::Drift.count", 1 do
      classify({ "intent" => "take", "target" => "nothing" }, command: "pick up the silver locket")
    end

    drift = Playthrough::Drift.last

    assert_equal "take", drift.action
    assert_equal [ "Brass Key" ], drift.offered_names
  end

  test "a drop that resolved to nothing is counted, offering what the player holds" do
    create(:item, :carried, playthrough: @playthrough, name: "Brass Key")

    assert_difference "Playthrough::Drift.count", 1 do
      classify({ "intent" => "drop", "target" => "nothing" }, command: "put down the lantern")
    end

    drift = Playthrough::Drift.last

    assert_equal "drop", drift.action
    assert_equal [ "Brass Key" ], drift.offered_names
  end

  # A turn that resolved is not drift, and neither is an intent that never
  # reaches for a record.
  test "a resolved move counts no drift" do
    connect("The Sunken Stair")

    assert_no_difference "Playthrough::Drift.count" do
      classify({ "intent" => "move", "target" => "The Sunken Stair" })
    end
  end

  # DRIFT IS THE FOUR ACTIONS THAT REACH FOR SOMETHING THE APP WOULD MOVE, and
  # `examine` is deliberately not one of them even now that it resolves a
  # record. Looking at the ceiling is an ordinary turn in a room with nothing on
  # the floor; counting it would make the drift number a number about how people
  # look around rather than about what the world does not have.
  test "examine and other reach for no record, so they cannot miss one" do
    lying_here(@playthrough, @here, name: "folded note")

    assert_no_difference "Playthrough::Drift.count" do
      classify({ "intent" => "examine", "target" => "nothing" })
      classify({ "intent" => "other", "target" => "nothing" })
    end
  end

  # An unresolved reach still returns a whole intent: the drift row and the
  # refusal are two different things the loop does with the same answer, and the
  # answer is the same either way.
  test "counting drift does not change what the loop is told" do
    intent, = classify({ "intent" => "move", "target" => "nothing" }, command: "go north")

    assert intent.move?
    assert_nil intent.destination
    assert_predicate intent, :reached_for_nothing?
  end

  # --- what the engine will not play ----------------------------------------

  # THE CAPTAIN'S RULING OF 2026-09-04, as a predicate on the answer. The
  # classifier decides which lines are refused; `Playthrough::Refusal` says it,
  # and `Playthrough::Turn` and `Playthrough::Mechanics` both read this one
  # method rather than each working it out again.
  test "the three refusable shapes are refused and nothing else is" do
    index = lying_here(@playthrough, @here, name: "Perrin's private index")
    apron = lying_here(@playthrough, @here, name: "copy-room apron")

    two, = classify({ "intent" => "take", "target" => index.name, "also_named" => apron.name })
    assert_predicate two, :refused?

    missed, = classify({ "intent" => "take", "target" => "nothing" })
    assert_predicate missed, :refused?

    unreadable, = classify({ "intent" => "steal", "target" => index.name, "also_named" => "nothing" })
    assert_predicate unreadable, :refused?

    played, = classify({ "intent" => "take", "target" => index.name, "also_named" => "nothing" })
    assert_not_predicate played, :refused?
  end

  # A COHERENT LINE THAT REACHES FOR NO RECORD IS NOT UNDETERMINABLE, and this
  # is the boundary the ruling has to stop at: "look at the sky", "wait", a
  # remark to nobody. The classifier placed them, they resolve to no record by
  # design, and refusing them would refuse everything that is not one of the
  # four acts.
  test "examine and other are not refused" do
    %w[examine other].each do |intent|
      answered, = classify({ "intent" => intent, "target" => "nothing" })

      assert_not_predicate answered, :refused?, "#{intent} is prose, not an unreadable line"
      assert_not_predicate answered, :unreadable?
    end
  end

  # AN ANSWER OUTSIDE THE TABLE THAT STILL NAMED A RECORD is kept as unreadable
  # rather than coerced. The coercion read it as `other`, dropped the record it
  # named and narrated the raw line -- so a provider ignoring a closed enum
  # looked exactly like a player musing about the weather.
  test "an intent outside the table that named a record is unreadable" do
    index = lying_here(@playthrough, @here, name: "Perrin's private index")

    intent, = classify({ "intent" => "steal", "target" => index.name, "also_named" => "nothing" })

    assert_predicate intent, :unreadable?
    assert_equal "steal", intent.unknown_action
    assert_equal :other, intent.action
    assert_nil intent.item, "nothing was resolved: there is no branch to send it down"
  end

  # And one that named NOTHING loses nothing by being read as `other`, because
  # there is no record to drop -- so it still is.
  test "an intent outside the table that named nothing is read as other" do
    intent, = classify({ "intent" => "sing", "target" => "nothing", "also_named" => "nothing" })

    assert_equal :other, intent.action
    assert_not_predicate intent, :unreadable?
    assert_not_predicate intent, :refused?
  end

  # Neither counter fires: an unreadable answer is a defect on our side, not a
  # reach on the player's, and adding it to either number would corrupt both.
  test "an unreadable answer is counted as neither drift nor overreach" do
    index = lying_here(@playthrough, @here, name: "Perrin's private index")

    assert_no_difference [ "Playthrough::Drift.count", "Playthrough::Overreach.count" ] do
      classify({ "intent" => "steal", "target" => index.name, "also_named" => "nothing" })
    end
  end

  # --- the closed set an action reads against -------------------------------

  # THE INVERSE OF THE CANDIDATE LIST, asked for by action. Both refusal paths
  # need it to say what WOULD have worked, and a second copy of the table is how
  # the two ways into the records start disagreeing about what is reachable.
  test "offered_for hands back the same four sets the prompt was built from" do
    stair = connect("The Sunken Stair")
    rowe = stands_here("Halkett Rowe")
    lying = lying_here(@playthrough, @here, name: "ward stamp")
    held = create(:item, :carried, playthrough: @playthrough, name: "daybook")
    classifier = Playthrough::Classifier.new(@playthrough)

    assert_equal [ stair ], classifier.offered_for(:move)
    assert_equal [ rowe ], classifier.offered_for(:talk)
    assert_equal [ lying ], classifier.offered_for(:take)
    assert_equal [ held ], classifier.offered_for(:drop)
    # A look reads BOTH item sets, in the order `#build_intent` resolves against.
    assert_equal [ lying, held ], classifier.offered_for(:examine)
    assert_empty classifier.offered_for(:other)
    assert_empty classifier.offered_for(nil)
  end

  # One definition of the name a record answers to, because the read-out, the
  # refusals and the counter rows must not name the same person three ways.
  test "label_for gives a person their fullname and everything else its name" do
    assert_equal "Halkett Rowe", Playthrough::Classifier.label_for(stands_here("Halkett Rowe", nickname: "Rowe"))
    assert_equal "Ashgate Market", Playthrough::Classifier.label_for(@here)
    assert_nil Playthrough::Classifier.label_for(nil)
  end

  # --- a line that named more than one thing --------------------------------

  # ONE LINE IS ONE ACT. "take the index and the apron" has an answer the loop
  # cannot make, and what used to happen is that the second half went nowhere
  # at all: no write, no refusal, and no drift row either, because the reach
  # resolved. `also_named` is that half kept -- and since the ruling of
  # 2026-09-04 it is also what makes the line refusable, so this is the field
  # the whole refusal hangs on. Resolution is unchanged: it is still one more
  # name out of the same closed set, through the same matcher.

  test "a second thing named in the same line is resolved, and is not the target" do
    index = lying_here(@playthrough, @here, name: "Perrin's private index")
    apron = lying_here(@playthrough, @here, name: "copy-room apron")

    intent, = classify({ "intent" => "take", "target" => "Perrin's private index", "also_named" => "copy-room apron" },
                       command: "pickup the index and the apron")

    assert_equal index, intent.item, "the turn still acts on the first thing"
    assert_equal apron, intent.also_named
    assert_predicate intent, :named_more_than_one?
  end

  test "the second name resolves against the same closed set as the action" do
    lying_here(@playthrough, @here, name: "Perrin's private index")
    carried = create(:item, :carried, playthrough: @playthrough, name: "Ward Office 12 daybook")

    intent, = classify({ "intent" => "take", "target" => "Perrin's private index", "also_named" => carried.name })

    assert_nil intent.also_named, "a take resolves against the floor, so what is in hand is not on its list"
    assert_not_predicate intent, :named_more_than_one?
  end

  # ONE RECORD ANSWERS TO MORE THAN ONE NAME. `#find_character` matches a
  # fullname OR a nickname, so "Halkett Rowe" and "Rowe" are two strings for one
  # person -- and comparing the STRINGS counted them as two things, wrote an
  # overreach row naming him on both sides, and told the player a turn had left
  # him undone while he was the one it acted on.
  test "a fullname and a nickname for one person are one thing, not two" do
    rowe = stands_here("Halkett Rowe", nickname: "Rowe")

    assert_no_difference "Playthrough::Overreach.count" do
      intent, = classify({ "intent" => "talk", "target" => "Halkett Rowe", "also_named" => "Rowe" },
                         command: "ask Rowe about the file")

      assert_equal rowe, intent.speaker
      assert_nil intent.also_named
      assert_not_predicate intent, :named_more_than_one?
    end
  end

  test "the nickname as the target and the fullname as the second is the same one thing" do
    rowe = stands_here("Halkett Rowe", nickname: "Rowe")

    intent, = classify({ "intent" => "talk", "target" => "Rowe", "also_named" => "Halkett Rowe" })

    assert_equal rowe, intent.speaker
    assert_nil intent.also_named
  end

  # Two items of the same name in one room resolve to the same first record, so
  # they are one thing to a player typing the name -- the same rule, arrived at
  # from the other direction. See Playthrough::Classifier#find_item.
  test "two identical names in one room are one thing" do
    lying_here(@playthrough, @here, name: "ward stamp")
    lying_here(@playthrough, @here, name: "ward stamp")

    assert_no_difference "Playthrough::Overreach.count" do
      intent, = classify({ "intent" => "take", "target" => "ward stamp", "also_named" => "ward stamp" })

      assert_nil intent.also_named
    end
  end

  # And a genuinely different person still counts, so the fix above did not buy
  # its correctness by never counting anything.
  test "two different people named in one line are still two things" do
    rowe = stands_here("Halkett Rowe", nickname: "Rowe")
    lasco = stands_here("Perrin Lasco")

    assert_difference "Playthrough::Overreach.count", 1 do
      intent, = classify({ "intent" => "talk", "target" => "Rowe", "also_named" => "Perrin Lasco" })

      assert_equal rowe, intent.speaker
      assert_equal lasco, intent.also_named
    end
  end

  test "`nothing`, a blank and the target repeated all mean one thing was named" do
    stair = connect("The Sunken Stair")

    [ "nothing", "", nil, "The Sunken Stair", "the sunken stair" ].each do |also|
      intent, = classify({ "intent" => "move", "target" => "The Sunken Stair", "also_named" => also })

      assert_equal stair, intent.destination
      assert_nil intent.also_named, "#{also.inspect} is not a second thing"
      assert_not_predicate intent, :named_more_than_one?
    end
  end

  # A reach that found nothing is DRIFT, and drift is a different fact about
  # the world: the player named something that is not there, rather than more
  # than the turn can do. The two never collapse into one count.
  test "a reach that resolved to nothing is drift and not an overreach" do
    lying_here(@playthrough, @here, name: "copy-room apron")

    intent, = classify({ "intent" => "take", "target" => "nothing", "also_named" => "copy-room apron" },
                       command: "take the cellar key and the apron")

    assert_predicate intent, :reached_for_nothing?
    assert_not_predicate intent, :named_more_than_one?
  end

  # The count. Written here because this is the only place that knows both
  # halves -- what the turn is about to do, and the thing the same line named
  # that it will not.
  test "a line that named two things is counted, with both halves on the row" do
    index = lying_here(@playthrough, @here, name: "Perrin's private index")
    apron = lying_here(@playthrough, @here, name: "copy-room apron")
    scene = create(:scene, story: @story, location: @here)
    @playthrough.update!(current_scene: scene)

    assert_difference "Playthrough::Overreach.count", 1 do
      classify({ "intent" => "take", "target" => index.name, "also_named" => apron.name },
               command: "pickup the index and the apron")
    end

    row = Playthrough::Overreach.last
    assert_equal "take", row.action
    assert_equal "pickup the index and the apron", row.command
    assert_equal index.name, row.acted
    assert_equal apron.name, row.unacted
    assert_equal @here, row.location
    assert_equal scene, row.scene, "the narration the player had just read"
  end

  test "a line that named one thing is counted as nothing" do
    index = lying_here(@playthrough, @here, name: "Perrin's private index")

    assert_no_difference "Playthrough::Overreach.count" do
      classify({ "intent" => "take", "target" => index.name, "also_named" => "nothing" })
    end
  end

  # The two counts are different facts about the world and never one number.
  test "a reach that found nothing is counted as drift and not as an overreach" do
    lying_here(@playthrough, @here, name: "copy-room apron")

    assert_difference "Playthrough::Drift.count", 1 do
      assert_no_difference "Playthrough::Overreach.count" do
        classify({ "intent" => "take", "target" => "nothing", "also_named" => "copy-room apron" },
                 command: "take the cellar key and the apron")
      end
    end
  end

  test "a person is counted by the name a player would have typed" do
    rowe = stands_here("Halkett Rowe")
    lasco = stands_here("Perrin Lasco")

    classify({ "intent" => "talk", "target" => rowe.fullname, "also_named" => lasco.fullname },
             command: "ask Rowe and Lasco where the file went")

    row = Playthrough::Overreach.last
    assert_equal rowe.fullname, row.acted
    assert_equal lasco.fullname, row.unacted
  end

  test "the second name is drawn from the same closed enum as the target" do
    connect("The Sunken Stair")
    lying_here(@playthrough, @here, name: "Brass Key")

    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })
    properties = json_schema_body(agent.schemas.first)["properties"]

    assert_equal properties["target"]["enum"], properties["also_named"]["enum"]
    assert_includes properties["also_named"]["enum"], "Brass Key"
    assert_includes properties["also_named"]["enum"], Playthrough::IntentSchema::NOTHING
  end

  # One word from a fixed table and one name from a closed enum: nothing here
  # for sampling to improve, and one thing for it to ruin.
  test "the classifier asks at temperature zero" do
    _intent, agent = classify({ "intent" => "other", "target" => "nothing" })

    assert_equal 0.0, agent.temperature
    assert_equal 0.0, Playthrough::Classifier::TEMPERATURE
  end

  private

  # Somebody the game knows is standing here: the records place them in this
  # room, which is how `Character.present_in` -- and so `Scene::Generator` --
  # answers the question. It used to mean "recorded in the last scene played
  # here", which is exactly what the whereabouts column replaced.
  def stands_here(fullname, **attributes)
    create(:character, story: @story, fullname: fullname, location: @here, **attributes)
  end
end
