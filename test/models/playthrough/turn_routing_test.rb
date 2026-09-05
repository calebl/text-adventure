require "test_helper"

# WHICH READER ANSWERS A LINE IN THE BROWSER, and what it costs.
#
# The captain's ruling of 2026-09-04, evening: *"support a slash prefix
# autocomplete in the text box, and resolve those and verb-prefixed lines offline
# then fallback to the model."* `Playthrough::TurnTest` is the loop's branches;
# this is the decision in front of them, and the assertion that matters most
# here is a NEGATIVE one -- that no classifier call was made. A FakeAgent records
# every prompt it is handed, so counting them is the whole proof.
#
# The world is one room with a way out, somebody standing in it, something on the
# floor and something in hand, so all five record-resolving verbs have a set to
# resolve against.
class Playthrough::TurnRoutingTest < ActiveSupport::TestCase
  CLASSIFY = ->(intent, target) { { "intent" => intent, "target" => target } }

  def setup
    @story = create(:story)
    @vance = create(:character, story: @story, fullname: "Odile Vance", is_protagonist: true)
    @office = create(:location, story: @story, name: "Ward Office 12")
    @closet = create(:location, story: @story, name: "The Supply Closet")
    create(:location_connection, location: @office, connected_location: @closet,
                                 distance: "adjacent", travel_method: "walking")
    create(:location_connection, location: @closet, connected_location: @office,
                                 distance: "adjacent", travel_method: "walking")

    @rowe = create(:character, story: @story, fullname: "Halkett Rowe", nickname: "Rowe", location: @office)
    @playthrough = create(:playthrough, story: @story, character: @vance, current_location: @office)
    @stamp = create(:item, :lying, playthrough: @playthrough, location: @office, name: "ward stamp")
    @daybook = create(:item, :carried, playthrough: @playthrough, name: "Ward Office 12 daybook")
  end

  # Every BaseAgent the turn builds is this one fake, and the queued responses
  # ARE the model calls the turn is allowed to make, in order. So a test that
  # queues ONLY a narration and passes is a test in which the classifier was
  # never asked.
  def play(command, *responses)
    agent = FakeAgent.new(*responses)
    outcome = BaseAgent.stub(:new, agent) { Playthrough::Turn.new(@playthrough).play(command) }

    [ outcome, agent ]
  end

  # --- the grammar answers, and the model is never asked --------------------

  test "a slashed take resolves offline and costs no classifier call" do
    scene, agent = play("/take ward stamp", "You lift the brass stamp.")

    assert_equal 1, agent.prompts.count, "the only call a resolved take may make is the narration"
    assert_equal "take", scene.resolved_action
    assert_equal @stamp, scene.acted_on
    assert_equal "grammar", scene.resolved_by
    assert_equal @playthrough, @stamp.reload.playthrough
  end

  test "the slash is stripped before the line is recorded" do
    scene, = play("/take ward stamp", "You lift the brass stamp.")

    assert_equal "take ward stamp", scene.typed
  end

  test "a slashed drop resolves offline and costs no classifier call" do
    scene, agent = play("/drop the daybook", "You set the daybook down.")

    assert_equal 1, agent.prompts.count
    assert_equal "drop", scene.resolved_action
    assert_equal @daybook, scene.acted_on
    assert_equal "grammar", scene.resolved_by
    assert_equal @office, @daybook.reload.location
  end

  test "a grammar-resolved move realizes and narrates with no classifier call" do
    @closet.update!(detail_level: "stub", description: nil, lore: nil)

    scene, agent = play("/go to the supply closet",
                        { "description" => "Shelves to the ceiling.", "lore" => "It was a scullery." },
                        { "exits" => [] },
                        { "description" => "You push in among the shelves.", "summary" => "Arrived." })

    assert_equal 3, agent.prompts.count, "two realization calls and the arrival, and no classification"
    assert_equal @closet, @playthrough.reload.current_location
    assert_equal "grammar", scene.resolved_by
    assert_equal @closet, scene.acted_on
  end

  test "a grammar-resolved talk reaches the interaction agent and nothing else" do
    reaction = { "pre_thought" => "Who is that.", "pre_feeling" => "wary",
                 "action" => "He sets down the pen.", "post_feeling" => "steadier",
                 "post_thought" => "Say something." }

    scene, agent = play("/talk to Rowe", reaction, "\"You again,\" he says.")

    assert_equal 2, agent.prompts.count
    assert_equal "talk", scene.resolved_action
    assert_equal @rowe, scene.acted_on
    assert_equal "grammar", scene.resolved_by
  end

  test "a grammar-resolved examine reads the record and narrates" do
    note = create(:item, :lying, :readable, playthrough: @playthrough, location: @office,
                                            name: "folded note", inscription: "Burn this.")

    scene, agent = play("/read folded note", "You unfold it.")

    assert_equal 1, agent.prompts.count
    assert_includes agent.prompts.last, "Burn this."
    assert_equal note, scene.acted_on
    assert_equal "grammar", scene.resolved_by
  end

  # THE CONVERSATION IS NOT FILED EITHER. `BaseAgent#attribute_to!` stamps
  # `messages.scene_id`, and a turn the grammar answered had no classifier
  # exchange at all -- so nothing filed under this turn came from one.
  test "a grammar-resolved turn files no classifier messages under it" do
    scene, = play("/take ward stamp", "You lift the brass stamp.")

    assert_empty Message.where(scene: scene).joins(:chat).where(chats: { purpose: "classifier" })
  end

  # --- the model answers, exactly as it did before --------------------------

  test "an ordinary sentence goes to the classifier untouched" do
    scene, agent = play("what about that stamp then",
                        CLASSIFY.call("take", "ward stamp"), "You lift the brass stamp.")

    assert_equal 2, agent.prompts.count
    assert_includes agent.prompts.first, "what about that stamp then"
    assert_equal "model", scene.resolved_by
    assert_equal @stamp, scene.acted_on
  end

  # THE FALLBACK, AND IT IS THE WHOLE REASON THE MODEL IS STILL HERE. The verb is
  # one of the grammar's own and the noun is not a name it can place, so the line
  # reaches `Playthrough::Classifier` exactly as it did before any of this.
  test "a slashed line whose noun the grammar cannot place falls back to the classifier" do
    scene, agent = play("/take the brass thing on the desk",
                        CLASSIFY.call("take", "ward stamp"), "You lift the brass stamp.")

    assert_equal 2, agent.prompts.count
    assert_equal "model", scene.resolved_by
    assert_equal @stamp, scene.acted_on
  end

  # THE CAPTAIN'S RULING OF 2026-09-05: *"I think we should only auto accept the
  # slash commands."* A leading verb is a coincidence of English -- `take the
  # ward stamp` is the same line the grammar answers behind a slash, and without
  # one it costs a classifier call like everything else a player types.
  test "the same line with no slash goes to the classifier" do
    scene, agent = play("take the ward stamp",
                        CLASSIFY.call("take", "ward stamp"), "You lift the brass stamp.")

    assert_equal 2, agent.prompts.count
    assert_equal "model", scene.resolved_by
    assert_equal @stamp, scene.acted_on
  end

  # THE FOUR LINES THAT MADE THE RULING. Each is ordinary English meaning one
  # thing whose leading word is the command vocabulary for another, and each was
  # measured answering a real record: two walked the player somewhere they were
  # describing, one put down what they were carrying, one took what they meant to
  # read. Every one of them is the classifier's now.
  test "an ordinary line whose first word is a command verb is left to the classifier" do
    [ "move the ward stamp off the desk", "walk the supply closet perimeter",
      "leave the ward office", "take a look at the ward stamp" ].each do |line|
      _scene, agent = play(line, CLASSIFY.call("other", "nothing"), "Nothing much happens.")

      assert_equal 2, agent.prompts.count, "#{line.inspect} must reach the classifier"
      assert_includes agent.prompts.first, line
    end
  end

  test "a slashed line the grammar cannot read at all falls back to the classifier" do
    scene, agent = play("/ponder the stamp",
                        CLASSIFY.call("examine", "ward stamp"), "Brass, worn smooth.")

    assert_equal 2, agent.prompts.count
    assert_equal "model", scene.resolved_by
    # And the classifier was handed the line WITHOUT its slash, because that is
    # what the player meant and what the prompt is written for.
    assert_includes agent.prompts.first, "ponder the stamp"
    assert_not_includes agent.prompts.first, "/ponder"
  end

  # An engine-view verb is `rake game:mechanics`'s instrument and the browser has
  # no engine view, so it is not claimed and reaches the classifier the way it
  # always did -- which is what keeps `stats` and `check the ledger` playable
  # lines in the fiction.
  test "an engine-view verb still reaches the classifier in the browser" do
    scene, agent = play("check the daybook",
                        CLASSIFY.call("examine", "Ward Office 12 daybook"), "You turn the pages.")

    assert_equal 2, agent.prompts.count
    assert_equal "model", scene.resolved_by
  end

  # --- what the two readers still share -------------------------------------

  # A refusal is the classifier's answer, so it stays the classifier's answer:
  # the grammar produces no `also_named` and refuses nothing into the browser.
  test "a line that named two things is still refused, by the model that saw both" do
    apron = create(:item, :lying, playthrough: @playthrough, location: @office, name: "copy-room apron")
    refusal, = play("take the ward stamp and the copy-room apron",
                    { "intent" => "take", "target" => "ward stamp", "also_named" => "copy-room apron" })

    assert_instance_of Playthrough::Refusal, refusal
    assert_equal :named_more_than_one, refusal.kind
    assert_equal @office, @stamp.reload.location, "nothing moved"
    assert_equal @office, apron.reload.location
  end

  # ONE LINE, ONE ACT SURVIVES THE SHORTCUT. The grammar has no `also_named`, so
  # a line joining two things is handed to the classifier -- which has the field
  # that can see the second name, refuses the line, and writes the
  # `Playthrough::Overreach` row. Neither the ruling nor the counter had to be
  # reproduced in the grammar. See `Playthrough::Grammar::JOINING_WORDS`.
  test "a joined line is handed to the classifier, refused there, and counted there" do
    apron = create(:item, :lying, playthrough: @playthrough, location: @office, name: "copy-room apron")

    refusal, agent = play("/take the ward stamp and the apron",
                          { "intent" => "take", "target" => "ward stamp", "also_named" => "copy-room apron" })

    assert_equal 1, agent.prompts.count, "the classifier read it, and no narrator was asked"
    assert_instance_of Playthrough::Refusal, refusal
    assert_equal :named_more_than_one, refusal.kind
    assert_equal 1, Playthrough::Overreach.where(playthrough: @playthrough).count
    assert_equal @office, @stamp.reload.location, "nothing moved"
    assert_equal @office, apron.reload.location
  end


  # A BODY BIG ENOUGH THAT ONE d8 CANNOT END IT, AND THE CONDITION ROWS REBUILT
  # WITH IT. `Playthrough::Vitals` is written at first contact against the
  # maximum the body had THEN, so raising a level under a game already in
  # progress leaves a row below the new ceiling -- a real thing a re-seed does
  # (`hp_above_maximum` is the doctor's finding for the other direction) and the
  # wrong starting state for a test about a fight. Dropping the rows lets the
  # snapshot write them again at the new maximum.
  #
  # It is here because the dice are seeded off ROW IDS (`Roll.seed`), so a test
  # that is not about dying must not be able to end in a death.
  def tough!(*people)
    people.each { |person| person.update!(level: 3) }
    @playthrough.vitals.destroy_all
    Playthrough::Snapshot.new(@playthrough).of_the_room!(@playthrough.current_location)
  end

  # --- a fight in the browser -------------------------------------------------
  #
  # `attack` is in the fixed grammar and NOT in `Playthrough::IntentSchema::INTENTS`
  # (that is a later, measured slice), so a slashed attack resolves offline for
  # no call at all and an unslashed one reaches the classifier like any other
  # line.

  test "a slashed attack resolves offline, strikes, and calls nothing" do
    tough!(@vance, @rowe)

    scene, agent = play("/attack Halkett Rowe")

    assert_empty agent.prompts, "a fight is arithmetic over records"
    assert_nil scene, "an attack writes no Scene of its own -- one closes the fight when it ends"
    assert_equal 1, @playthrough.blows.where(attacker: @vance).count
    assert_equal 1, @playthrough.blows.where(attacker: @rowe).count, "and the foe answered in the same turn"
  end

  # A ROUND IS THE TURN -- the captain's call C5 -- so the world answers a line
  # the player spent doing something else.
  test "a foe answers a turn the player spent reading" do
    tough!(@vance, @rowe)
    @stamp.update!(readable: true, inscription: "WARD 12")
    play("/attack Halkett Rowe")

    assert_difference "Playthrough::Blow.where(attacker: @rowe).count", 1 do
      play("/read the ward stamp", "You read it.")
    end
  end

  # *"A refused line writes nothing"* -- the captain's ruling of 2026-09-04 --
  # and a blow would be something.
  test "a refused line buys the foe no round" do
    tough!(@vance, @rowe)
    play("/attack Halkett Rowe")

    assert_difference "Playthrough::Blow.count", 0 do
      # The grammar cannot place the name, so the line falls through to the
      # classifier -- which resolves it to nothing, and a `take` that resolved
      # to nothing is refused.
      outcome, = play("/take the mayor's chain", CLASSIFY.call("take", "nothing"))
      assert_instance_of Playthrough::Refusal, outcome
    end
  end

  # ONE `Scene` WHEN THE FIGHT ENDS, and it is what `#play` hands back on the
  # turn it ended -- the browser's per-round view is the battle panel, a later
  # slice.
  test "leaving the room ends the fight and the turn answers with the closing scene" do
    tough!(@vance, @rowe)
    play("/attack Halkett Rowe")

    scene, = play("/go to The Supply Closet",
                  { "description" => "You push in among the shelves.", "summary" => "Arrived." })

    assert_equal "attack", @playthrough.reload.current_scene.resolved_action
    assert_predicate @playthrough.current_scene, :engine_authored?
    assert_empty @playthrough.blows.open
    assert_equal @office, @playthrough.current_scene.location, "the fight happened in the room she left"
    assert_not_nil scene
  end

  test "an unslashed attack goes to the classifier like any other line" do
    _, agent = play("attack Halkett Rowe", CLASSIFY.call("other", "nothing"), "You raise your hand and stop.")

    assert_equal 2, agent.prompts.count
    assert_equal 0, @playthrough.blows.count
  end

  # --- a thing thrown, in the browser ---------------------------------------
  #
  # `throw` is in the fixed grammar and NOT in `Playthrough::IntentSchema::INTENTS`
  # either, so a slashed throw resolves two records offline and the only call it
  # makes is the narration -- exactly what a `take` costs.

  test "a slashed throw resolves two records offline and narrates once" do
    scene, agent = play("/throw the daybook at Halkett Rowe", "The daybook goes past his ear.")

    assert_equal 1, agent.prompts.count, "the only call a resolved throw may make is the narration"
    assert_equal "throw", scene.resolved_action
    assert_equal @daybook, scene.acted_on, "the record that moves is the thing thrown"
    assert_equal "grammar", scene.resolved_by
    assert_equal "throw the daybook at Halkett Rowe", scene.typed
    assert_not_predicate scene, :engine_authored?, "the narrator wrote it"
  end

  # WHICHEVER WAY THE DIE WENT IT IS A TURN. A fumble writes the same Scene and
  # costs the same story time; what differs is whether a row moved.
  test "a throw is one turn and one Scene whatever the die did" do
    before = @story.clock

    assert_difference "Scene.count", 1 do
      play("/throw the daybook at The Supply Closet", "It sails through the doorway.")
    end

    assert_operator @story.reload.clock, :>, before
    assert_includes [ @office, @closet, nil ], @daybook.reload.location
  end

  # THE NARRATOR IS TOLD WHAT ALREADY HAPPENED, in the app's own words -- the
  # prompt carries the fact, and the fact says whether the thing left the hands.
  test "the narrator is handed the throw as a fact" do
    _, agent = play("/throw the daybook at Halkett Rowe", "The daybook goes past his ear.")

    assert_match(/Odile Vance/, agent.prompts.first)
    assert_match(/Ward Office 12 daybook/, agent.prompts.first)
    assert_match(/NOTHING WAS THROWN|NO LONGER\s+CARRIED/, agent.prompts.first)
  end

  # AN IMMOVABLE THING IS REFUSED IN FRONT OF THE DISPATCH: no narration, no
  # Scene, no story time, and the counters are untouched because the classifier
  # never ran.
  test "a throw of something immovable is refused and calls nothing" do
    create(:item, :lying, :immovable, playthrough: @playthrough, location: @office, name: "filing press")
    before = @story.clock

    outcome, agent = play("/throw the filing press at Halkett Rowe")

    assert_instance_of Playthrough::Refusal, outcome
    assert_equal :immovable, outcome.kind
    assert_empty agent.prompts, "nothing was narrated, because nothing happened"
    assert_equal before, @story.reload.clock
    assert_equal 0, @playthrough.drifts.count
    assert_equal 0, @playthrough.overreaches.count
  end

  test "an unslashed throw goes to the classifier like any other line" do
    _, agent = play("throw the daybook at Halkett Rowe",
                    CLASSIFY.call("other", "nothing"), "You weigh it in your hand and stop.")

    assert_equal 2, agent.prompts.count
    assert_predicate @daybook.reload, :carried?
  end

  test "a dead playthrough is refused in front of both readers" do
    @vance.update!(level: 1, hit_die: 6, strength: 10, dexterity: 10, will: 10)
    @playthrough.update!(ended_at: @story.clock)

    agent = FakeAgent.new
    refusal = BaseAgent.stub(:new, agent) { Playthrough::Turn.new(@playthrough).play("/take ward stamp") }

    assert_instance_of Playthrough::Refusal, refusal
    assert_predicate refusal, :game_over?
    assert_empty agent.prompts
  end
end
