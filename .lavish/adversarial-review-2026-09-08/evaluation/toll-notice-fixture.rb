# Offline presentation fixture. Run with an isolated DATABASE_URL in test:
#   PARALLEL_WORKERS=1 bundle exec ruby -Itest <this file>
# All database writes roll back. The HTML is the actual Rails play page and
# application layout; the arrival response is a fixed FakeAgent, not live prose.
require "test_helper"

include FactoryBot::Syntax::Methods

output = File.dirname(__FILE__)
ActiveRecord::Base.transaction(requires_new: true) do
  story = create(:story, title: "The Counting House", start_time: Time.utc(2026, 9, 9, 9),
                        preface: "You are Iri Calder. Beyond the market, floodwater runs through the abandoned counting house.")
  origin = create(:location, :unpeopled, story: story, name: "Market")
  destination = create(:location, :unpeopled, :flooded, story: story, name: "Counting House")
  hero = create(:character, :protagonist, :without_abilities, story: story,
                fullname: "Iri Calder", nickname: "Iri", age: 29, sex: "female", level: 3, hit_die: 8)
  game = create(:playthrough, story: story, character: hero, current_location: origin)
  create(:location_connection, :short_distance, location: origin, connected_location: destination)
  answer = {
    "description" => "The counting house opens before you.",
    "summary" => "The crossing costs the player 3 hit points."
  }
  agent = FakeAgent.new(answer)
  scene = Roll.stub(:die, 3) do
    BaseAgent.stub(:new, agent) { Playthrough::Turn.new(game).play("/move Counting House") }
  end
  html = Playthrough::Debug.stub(:enabled?, false) do
    ApplicationController.render(template: "playthroughs/show", layout: "application", assigns: { playthrough: game })
  end
  document = Nokogiri::HTML(html)
  toll = game.tolls.sole
  raise "unexpected toll" unless toll.damage == 3 && toll.scene == scene
  raise "notice missing" unless document.css(".log .notice").map(&:text) == [toll.to_s]
  raise "debug visible" if document.at_css(".machinery")
  raise "summary visible" if html.include?(answer.fetch("summary"))
  raise "unexpected model calls" unless agent.prompts.length == 1

  File.write(File.join(output, "toll-notice-fixture.html"), html)
  File.write(File.join(output, "toll-notice-fixture.json"), JSON.pretty_generate({
    fixture: "Deterministic offline Rails-rendered play page, not a live browser session or live model output",
    render: "playthroughs/show with application layout and existing inline CSS",
    debug: false,
    database: "isolated test database; all fixture writes rolled back",
    action: "/move Counting House",
    description: scene.description,
    hidden_summary: scene.summary,
    notice: toll.to_s,
    damage: toll.damage,
    hp_after: toll.hp_after,
    saved: toll.saved?,
    model: "FakeAgent fixed response; no provider calls",
    viewport: { width: 1100, height: 850 }
  }) + "\n")
  puts toll.to_s
  raise ActiveRecord::Rollback
end
