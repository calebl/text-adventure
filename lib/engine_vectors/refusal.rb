# `Playthrough::Refusal`: what the engine says when it will not play a line,
# from each of its entry points.
module EngineVectors::Refusal
  SOURCES = [ "app/models/playthrough/refusal.rb", "app/models/playthrough/classifier.rb",
              "app/models/playthrough/end_notice.rb", "app/models/playthrough/death_notice.rb",
              "app/models/item.rb" ].freeze
  NOTES = "Each case stands in the room named `world` (a world in `worlds`). `entry` is the class " \
          "method called. `for`: Refusal.for(intent, typed:, offered:), `intent` written as " \
          "lib/engine_vectors/room.rb writes one and `offered` a list of record ids. `unplayable`: " \
          "Refusal.unplayable(intent, playthrough: the room's, typed:). `dead`: Refusal.dead(typed:, " \
          "character:), `character` an id or null. `over`: Refusal.over(playthrough:, typed:) after the " \
          "game ended one way -- `concluded` (it reached a default ending), `died` (the " \
          "protagonist's hit points are 0) or `unrecorded` (neither: `ended_at` alone). `new`: Refusal.new(kind:, typed:, fact:), which answers " \
          "{error} for a kind outside `kinds`. The output is {kind, fact, offer, reason, text, " \
          "game_over} with nulls left out, or null for no refusal.".freeze

  WORLDS = %w[refusal office castless nowhere empty].freeze

  SLOTS = { "move" => "destination", "talk" => "speaker", "attack" => "speaker", "take" => "item", "drop" => "item",
            "examine" => "item", "throw" => "item" }.freeze

  def self.constants_table
    { "worlds" => EngineVectors::Rooms::WORLDS.slice(*WORLDS).to_a, "kinds" => Playthrough::Refusal::KINDS.map(&:to_s),
      "unchanged" => Playthrough::Refusal::UNCHANGED }
  end

  def self.cases
    tested + swept + unplayable + endings
  end

  # `test/models/playthrough/refusal_test.rb`, case for case.
  def self.tested
    ids = EngineVectors::Rooms::WORLDS.fetch("refusal")
    there = ids["exits"][0]["id"]
    here = ids["here"]["id"]
    rowe = ids["protagonist"]["id"]
    lasco = ids["cast"][0]["id"]
    index, apron, press, bolted = ids["lying"].map { |item| item["id"] }
    daybook = ids["carried"][0]["id"]
    [
      [ { "action" => "move", "destination" => there }, "go to the closet", [] ],
      [ { "action" => "talk", "speaker" => lasco }, "ask Rowe about the file", [] ],
      [ { "action" => "take", "item" => index }, "take the index", [] ],
      [ { "action" => "drop", "item" => index }, "drop the index", [] ],
      [ { "action" => "throw", "item" => press, "at" => rowe }, "throw the press at Rowe", [] ],
      [ { "action" => "take", "item" => press }, "take the filing press", [] ],
      [ { "action" => "throw", "item" => daybook, "at" => lasco }, "throw the daybook at Rowe", [] ],
      [ { "action" => "throw", "item" => index, "at" => there }, "throw the index at the closet", [] ],
      [ { "action" => "other" }, "look at the sky", [] ],
      [ { "action" => "examine" }, "wait", [] ],
      [ { "action" => "take", "item" => index, "also_named" => apron }, "pick up the index and the apron", [] ],
      [ { "action" => "move", "destination" => there, "also_named" => here }, "something", [] ],
      [ { "action" => "talk", "speaker" => rowe, "also_named" => lasco }, "something", [] ],
      [ { "action" => "drop", "item" => index, "also_named" => apron }, "something", [] ],
      [ { "action" => "examine", "item" => index, "also_named" => apron }, "something", [] ],
      [ { "action" => "attack", "speaker" => rowe, "also_named" => lasco }, "something", [] ],
      [ { "action" => "examine" }, "look at the sky", [ index ] ],
      [ { "action" => "take", "item" => index, "also_named" => apron }, "something", [ index, apron ] ],
      [ { "action" => "take" }, "something", [] ],
      [ { "action" => "talk" }, "something", [] ],
      [ { "action" => "move" }, "something", [] ],
      [ { "action" => "drop" }, "something", [] ],
      [ { "action" => "attack" }, "attack the core", [] ],
      [ { "action" => "throw", "item" => bolted, "at" => rowe }, "throw the press at Rowe", [] ],
      [ { "action" => "take" }, "something", [ index, apron ] ],
      [ { "action" => "move" }, "something", [ there ] ],
      [ { "action" => "talk" }, "something", [ rowe ] ],
      [ { "action" => "drop" }, "something", [ apron ] ],
      [ { "action" => "attack" }, "something", [ rowe ] ],
      [ { "action" => "attack" }, "something", [ rowe, lasco ] ],
      [ { "action" => "other", "unknown_action" => "steal" }, "something", [] ]
    ].each_with_index.map do |(intent, typed, offered), n|
      input = { "world" => "refusal", "entry" => "for", "intent" => intent, "typed" => typed, "offered" => offered }
      EngineVectors.case_for("tested #{n}", input, EngineVectors.rolled_back { refuse(input) })
    end
  end

  # Every action with its record, with none, and with a second one; offered
  # nothing, one record and every record of its set; and a throw's missing
  # halves.
  def self.swept
    %w[refusal office empty].flat_map do |world|
      EngineVectors.rolled_back do
        room = EngineVectors::Rooms.build!(world)
        classifier = room.classifier
        actions = Playthrough::IntentSchema::INTENTS.reject { |action| action == "use" }
        actions.flat_map do |action|
          set = classifier.offered_for(action).map(&:id)
          slot = SLOTS[action]
          intents = [ { "action" => action } ]
          if slot
            aims = (classifier.characters_here + classifier.exits_here).map(&:id)
            set = (classifier.items_carried + classifier.items_here).map(&:id) if action == "throw"
            set.each do |id|
              intents << { "action" => action, slot => id }
              intents << { "action" => action, slot => id, "at" => aims.first }.compact if action == "throw"
              set.each { |other| intents << { "action" => action, slot => id, "also_named" => other } unless other == id || action == "throw" }
            end
          end
          intents.product([ [], set.first(1), set ].uniq).map do |intent, offered|
            input = { "world" => world, "entry" => "for", "intent" => intent, "typed" => "a line", "offered" => offered }
            EngineVectors.case_for("swept #{world} #{intent.to_a.flatten.join(" ")} offered #{offered.size}", input, refuse(input, room))
          end
        end
      end
    end
  end

  def self.unplayable
    %w[office castless nowhere].flat_map do |world|
      EngineVectors.rolled_back do
        room = EngineVectors::Rooms.build!(world)
        item = room.playthrough.carried.first&.id
        exit = room.classifier.exits_here.first&.id
        Playthrough::IntentSchema::INTENTS.map do |action|
          slot = SLOTS[action]
          intent = { "action" => action, (slot == "destination" ? slot : "item") => (slot == "destination" ? exit : item) }.compact
          intent = { "action" => action } unless slot
          input = { "world" => world, "entry" => "unplayable", "intent" => intent, "typed" => "#{action} it" }
          EngineVectors.case_for("unplayable #{world} #{action}", input, refuse(input, room))
        end
      end
    end
  end

  def self.endings
    rowe = EngineVectors::Rooms::WORLDS.fetch("refusal")["protagonist"]["id"]
    dead = [ nil, rowe ].map do |character|
      input = { "world" => "refusal", "entry" => "dead", "typed" => "go north", "character" => character }
      EngineVectors.case_for("dead #{character.inspect}", input, EngineVectors.rolled_back { refuse(input) })
    end
    over = %w[concluded died unrecorded].map do |ending|
      input = { "world" => "refusal", "entry" => "over", "typed" => "go north", "ending" => ending }
      EngineVectors.case_for("over #{ending}", input, EngineVectors.rolled_back { refuse(input) })
    end
    invented = { "world" => "refusal", "entry" => "new", "kind" => "invented", "typed" => "x", "fact" => "y" }
    dead + over + [ EngineVectors.case_for("new invented", invented, EngineVectors.rolled_back { refuse(invented) }) ]
  end

  def self.refuse(input, room = EngineVectors::Rooms.build!(input["world"]))
    refusal = case input["entry"]
    when "for"
      Playthrough::Refusal.for(intent(room, input["intent"]), typed: input["typed"], offered: input["offered"].map { |id| room[id] })
    when "unplayable"
      Playthrough::Refusal.unplayable(intent(room, input["intent"]), playthrough: room.playthrough, typed: input["typed"])
    when "dead"
      Playthrough::Refusal.dead(typed: input["typed"], character: input["character"] && room[input["character"]])
    when "new"
      begin
        Playthrough::Refusal.new(kind: input["kind"].to_sym, typed: input["typed"], fact: input["fact"])
      rescue ArgumentError => e
        return { "error" => e.message }
      end
    when "over"
      end!(room.playthrough, input["ending"])
      Playthrough::Refusal.over(playthrough: room.playthrough, typed: input["typed"])
    end
    EngineVectors::Room.refusal(refusal)
  end

  def self.intent(room, spec)
    records = spec.slice("destination", "speaker", "item", "at", "also_named").to_h { |slot, id| [ slot.to_sym, room[id] ] }
    Playthrough::Classifier::Intent.new(action: spec["action"].to_sym, unknown_action: spec["unknown_action"], **records)
  end

  def self.end!(playthrough, ending)
    if ending == "concluded"
      quest = Quest.create!(id: playthrough.id, story: playthrough.story, title: "The Long Way Down",
                            premise: "Somebody was taken below.", status: "open", contributes: true, origin: "seeded")
      outcome = Quest::Outcome.create!(id: playthrough.id, quest: quest, name: "rescued", summary: "They came back.",
                                       is_default: true)
      Playthrough::Ending.create!(playthrough: playthrough, quest_outcome: outcome, reached_at: playthrough.story_now)
    elsif ending == "died"
      # A body with no stat block has no hit points to be at zero, so the world's
      # protagonist is given one before it is killed.
      playthrough.character.update!(level: 1, hit_die: 8)
      Playthrough::Vitals.find_or_initialize_by(playthrough: playthrough, character: playthrough.character)
                         .update!(hp_current: 0)
    end
    playthrough.end!
  end
end
