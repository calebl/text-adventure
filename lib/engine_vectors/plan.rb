# `Location::Plan`: what a room's own walls, doors and stairs say to a prompt.
module EngineVectors::Plan
  SOURCES = [ "app/models/location/plan.rb", "app/models/location/box.rb", "app/models/location/interior.rb" ].freeze
  NOTES = "Each case is one story's rows (`records`, every row the database holds; see " \
          "lib/engine_vectors/records.rb): a sweep script's world loaded from its seed file (`script`), or " \
          "a place laid out by Interior.lay_out! (`layout`: story id, place id, footprint and `below`, as " \
          "in interior.json). The output has one entry per location of the story in id order: {location, " \
          "plan}, `plan` null where Location::Plan.for answers nil, otherwise {to_h, sentences, prompt} -- " \
          "#to_h, #sentences and #to_prompt.".freeze

  SCRIPTS = %w[a-building-with-two-floors a-cellar-below-the-way-in an-ending-with-words the-salt-assizes-grammar].freeze
  LAYOUTS = [
    { "story_id" => 9_401, "place_id" => 940_100, "footprint" => [ 18, 12 ], "below" => 1 },
    { "story_id" => 9_402, "place_id" => 940_200, "footprint" => [ 4, 20 ], "below" => 2 },
    { "story_id" => 9_403, "place_id" => 940_300, "footprint" => [ 3, 3 ], "below" => 0 },
    { "story_id" => 9_404, "place_id" => 940_400, "footprint" => [ 15, 15 ], "below" => nil }
  ].freeze

  def self.constants_table = { "way_out" => Location::Plan::WAY_OUT }

  def self.cases
    walked = SCRIPTS.flat_map do |script|
      EngineVectors::Walked.each_stop(script, [ 0 ]) do |game|
        EngineVectors.case_for(script, { "script" => script, "records" => EngineVectors::Records.dump }, read(game.story))
      end
    end
    laid_out = LAYOUTS.map do |layout|
      EngineVectors::Records.frozen do
        story = EngineVectors::World.story!(layout["story_id"])
        width, depth = layout["footprint"]
        place = EngineVectors::World.location!(story, id: layout["place_id"], name: "The Hall", width: width, depth: depth)
        Location::Interior.lay_out!(place, below: layout["below"])
        EngineVectors.case_for("layout #{layout["story_id"]}", { "layout" => layout, "records" => EngineVectors::Records.dump },
                               read(story.reload))
      end
    end
    walked + laid_out
  end

  def self.read(story)
    story.locations.order(:id).map do |location|
      plan = Location::Plan.for(location)
      { "location" => location.id,
        "plan" => plan && { "to_h" => plan.to_h, "sentences" => plan.sentences, "prompt" => plan.to_prompt } }
    end
  end
end
