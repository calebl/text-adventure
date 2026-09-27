# `Playthrough::Moment`: what the narrator and a character pass are told about
# the moment the player is standing in, at moments the game itself reached.
module EngineVectors::Moment
  SOURCES = [ "app/models/playthrough/moment.rb", "app/models/playthrough/ledger.rb", "app/models/playthrough/memory.rb",
              "app/models/location/plan.rb", "app/models/playthrough.rb", "app/models/playthrough/vitals.rb",
              "app/models/playthrough/blow.rb", "app/models/playthrough/toll.rb", "app/models/playthrough/arc.rb" ].freeze
  NOTES = "Each case is one moment of a sweep script (`script`, stopped after step `step`, whose line was " \
          "`typed`), played offline through the engine; `records` is every row the database then holds " \
          "(see lib/engine_vectors/records.rb) and `playthrough` the id of the game being played. " \
          "`narration` is #narration_context and `narration_bare` #narration_context(plan: false, arc: " \
          "false). `handled` reads the moment with Moment::Handled marking the first carried thing as " \
          "taken and the first thing on the floor as dropped, each where there is one; `endings` reads it " \
          "with each of the story's Quest::Outcome rows as `ending:`. `characters` is every person in the " \
          "room but the player, in cast order: #character_context(character, replayed: `replayed`) and " \
          "#personal_facts.".freeze

  REPLAYED = 2

  # [script, step indexes], each stop chosen for what it puts in front of the
  # narrator: blows, tolls, somebody else's act, a body's condition, a floor
  # plan, an arc's next beat and its end, a thing just read.
  STOPS = [
    [ "a-fight-the-player-wins", [ 0, 3, 11, 23, 24 ] ],
    [ "somebody-walks-out-on-their-own", [ 2 ] ],
    [ "a-one-way-hazard-on-a-door", [ 1, 7 ] ],
    [ "the-unrecorded-hour-two-bodies", [ 6 ] ],
    [ "a-building-with-two-floors", [ 1, 8 ] ],
    [ "a-cellar-below-the-way-in", [ 3 ] ],
    [ "the-salt-assizes-to-an-ending", [ 0, 3, 4 ] ],
    [ "npc-experience-survives-small-talk", [ 0 ] ],
    [ "an-ending-with-words", [ 7 ] ]
  ].freeze

  def self.constants_table
    { "replayed" => REPLAYED, "conclusions" => Playthrough::Moment::CONCLUSIONS,
      "conclusions_budget" => Playthrough::Moment::CONCLUSIONS_BUDGET, "memories_budget" => Playthrough::Moment::MEMORIES_BUDGET,
      "recap_budget" => Playthrough::RECAP_BUDGET, "recap_scenes" => Playthrough::RECAP_SCENES }
  end

  def self.cases
    STOPS.flat_map do |script, stops|
      EngineVectors::Walked.each_stop(script, stops) do |game, index, step|
        input = { "script" => script, "step" => index, "typed" => step.typed, "playthrough" => game.id,
                  "replayed" => REPLAYED, "records" => EngineVectors::Records.dump }
        EngineVectors.case_for("#{script} #{index}", input, read(game))
      end
    end
  end

  def self.read(game)
    moment = Playthrough::Moment.new(game)
    location = game.current_location
    {
      "narration" => moment.narration_context,
      "narration_bare" => moment.narration_context(plan: false, arc: false),
      "handled" => handled(game).map do |item, direction|
        { "item" => item.id, "direction" => direction.to_s,
          "narration" => Playthrough::Moment.new(game, handled: Playthrough::Moment::Handled.new(item: item, direction: direction)).narration_context }
      end,
      "endings" => Quest::Outcome.joins(:quest).where(quests: { story_id: game.story_id }).order(:id).map do |outcome|
        { "outcome" => outcome.id, "narration" => Playthrough::Moment.new(game, ending: outcome).narration_context }
      end,
      "characters" => (location ? game.cast_in(location) - [ game.character ].compact : []).map do |character|
        { "character" => character.id, "context" => moment.character_context(character, replayed: REPLAYED),
          "personal_facts" => moment.personal_facts(character) }
      end
    }
  end

  def self.handled(game)
    taken = game.carried.first
    dropped = game.current_location && game.items_lying_in(game.current_location).first
    [ ([ taken, :taken ] if taken), ([ dropped, :dropped ] if dropped) ].compact
  end
end
