require "json"
require "digest"
require "factory_bot_rails"
require ENV.fetch("EVAL_BUDGET_HELPER")
FactoryBot.find_definitions if FactoryBot.factories.count.zero?
$stdout.sync = true
ReviewEvalBudget.assert_isolated_database!
preflight = ENV["EVAL_PREFLIGHT"] == "1"
ReviewEvalBudget.install! unless preflight
cases = [
  [ "apothecary", "Apothecary Store", "An unattended shelf holds a sealed healing draught and a flask of clean drinking water, ready to take." ],
  [ "tools", "Repair Shed", "An unattended workbench holds a portable iron crowbar and a tinderbox, ready to take." ],
  [ "paper", "Writing Desk", "An unattended desk holds a loose folded paper note and a small smooth stone paperweight, ready to take." ]
]
output = ENV.fetch("OUT")
raise "Existing output" if File.exist?(output)
result = { source: ENV.fetch("EVAL_SOURCE_SHA"), preflight: preflight, corpus: Digest::SHA256.hexdigest(JSON.generate(cases)),
  harness_sha256: Digest::SHA256.file(__FILE__).hexdigest, results: [] }
(preflight ? 1 : 4).times do |rep|
  cases.each do |id, name, teaser|
    universe = FactoryBot.create(:universe, :modern,
      physics: "Ordinary physics except that prepared healing draughts restore wounds when consumed.",
      technology: "Hand tools, paper, glass flasks and carts.", weapons: "Ordinary knives.", religion: "Household traditions.")
    story = FactoryBot.create(:story, universe: universe, title: "The Market Stores", summary: "A traveler explores the market's unattended storerooms.", start_time: Time.utc(2026, 1, 1, 12))
    room = FactoryBot.create(:location, :stub, story: story, name: name, teaser: teaser, population: "nobody")
    Location::ExitsSchema::MAX_EXITS.times do |n|
      neighbor = FactoryBot.create(:location, story: story, name: "Passage #{n + 1}", population: "nobody")
      FactoryBot.create(:location_connection, location: room, connected_location: neighbor, distance: "adjacent")
      FactoryBot.create(:location_connection, location: neighbor, connected_location: room, distance: "adjacent")
    end
    generator = Location::Generator.new(room)
    inputs = { prompt: generator.detail_prompt, schema: generator.detail_schema.new.to_json_schema }
    ReviewEvalBudget.calls = []
    ReviewEvalBudget.label = "physical-generation:#{ENV.fetch('EVAL_ARM')}:#{id}:#{rep + 1}"
    failure = nil
    begin
      generator.realize! unless preflight
    rescue StandardError, ReviewEvalBudget::Halt => error
      failure = error
    end
    result[:results] << { case: id, rep: rep + 1, inputs: inputs,
      description: room.reload.description, items: room.items.templates.order(:id).map { |item| item.attributes.slice("name", "description", "use_kind", "combustible", "disposition") },
      calls: ReviewEvalBudget.calls, error: failure&.class&.name }
    File.write(output, JSON.pretty_generate(result))
    puts "#{id} #{rep + 1}: #{failure&.class || (preflight ? 'preflight' : 'realized')}"
    raise failure if failure
  end
end
